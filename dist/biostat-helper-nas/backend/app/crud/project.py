import json
import re
from datetime import datetime, timedelta
from typing import List, Optional, Tuple

from sqlalchemy import false, func, or_
from sqlalchemy.orm import Session

from app.core.project_types import normalize_project_type
from app.models.models import (
    Project,
    ProjectAgentMessage,
    ProjectMember,
    ProjectMeeting,
    ProjectPhase,
    ProjectTimelineImport,
    ProjectTimelineItem,
    ProjectTodo,
    ProjectTodoChecklistItem,
)
from app.schemas.project import (
    ChecklistItemCreate,
    ChecklistItemUpdate,
    MeetingCreate,
    MeetingUpdate,
    ProjectCreate,
    ProjectPhaseCreate,
    ProjectPhaseUpdate,
    ProjectUpdate,
    ProjectAgentPlan,
    ProjectMemberCreate,
    ProjectMemberUpdate,
    TimelineItemUpdate,
    TodoCreate,
    TodoUpdate,
)
from app.services.project_workflow import (
    STANDARD_PHASE_ORDER,
    STANDARD_WORKFLOW,
    build_workflow_blueprint,
)


# GTD status predicates. These replace bare string comparisons for status
# classification so new GTD statuses and the legacy clinical pipeline statuses
# stay consistent in one place.
GTD_ACTIVE = {"next", "open", "in_progress", "blocked", "waiting"}
GTD_DONE = {"done"}
GTD_CLOSED = {"done", "cancelled", "archived"}
# Parked GTD buckets with no concrete next action (waiting has its own list).
GTD_SOMEDAY = {"someday", "reference"}
GTD_INBOX = {"inbox"}


DEFAULT_PHASE_CHECKLISTS = {
    "项目启动": [
        "确认当前方案版本和关键里程碑",
        "确认统计、编程、DM、医学和运营责任人",
        "建立项目目录、命名规范和会议节奏",
    ],
    "SAP与TFL": [
        "核对SAP与TFL使用同一套终点、分析集和统计方法",
        "分别核对SAP正文与TFL shell的审阅状态",
        "分别确认SAP与TFL定稿版本并关闭交叉不一致",
    ],
    "数据管理DM": [
        "确认CRF字段支持主要终点和关键协变量",
        "核对Edit Check和Query闭环状态",
        "确认外部数据、医学编码和SAE一致性状态",
    ],
    "CDISC与数据集": [
        "确认SDTM/ADaM规格版本",
        "核对分析标志、访视窗口和派生规则",
        "完成主程序与QC结果差异关闭",
    ],
    "统计编程与输出": [
        "核对TFL shell标题、脚注、分母和小数位",
        "核对关键表格数字和分析集",
        "完成输出审阅记录",
    ],
    "盲态审阅": [
        "确认重要方案偏离列表",
        "确认分析集归属和盲态数据问题",
        "记录盲态决策和审批",
    ],
    "锁库与揭盲": [
        "确认所有关键Query关闭",
        "确认数据快照和随机化揭盲流程",
        "确认最终分析输入冻结",
    ],
    "SAR统计分析报告": [
        "核对SAR分析集、终点和统计方法与SAP一致",
        "核对SAR结果数字、表图出处和TFL一致",
        "完成SAR独立QC、审阅意见关闭和签发归档",
    ],
    "CSR与提交": [
        "核对CSR文本与TFL一致",
        "核对define.xml、ADRG/SDRG和验证Issue解释",
        "确认审评追溯材料完整",
    ],
}


def default_checklist_for_todo(phase: Optional[str], title: str) -> List[str]:
    items = list(DEFAULT_PHASE_CHECKLISTS.get(phase or "", []))
    title_keywords = {
        "SAP": ["确认SAP定稿状态", "确认SAP与方案差异已记录"],
        "TFL": ["确认shell版本", "确认表图列表与SAP一致"],
        "CRF": ["确认字段名、单位、访视窗口和缺失编码", "确认关键字段有Edit Check"],
        "SDTM": ["确认Trial Design域", "确认受控术语版本"],
        "ADaM": ["确认ADSL关键变量", "确认PARAM/PARAMCD和分析标志"],
        "SAR": ["确认SAR版本号和签发状态", "确认SAR与CSR统计描述一致"],
        "CSR": ["确认关键结论有表图出处", "确认探索性结果措辞"],
    }
    for keyword, keyword_items in title_keywords.items():
        if keyword in title:
            items.extend(keyword_items)
    unique_items = []
    for item in items:
        if item not in unique_items:
            unique_items.append(item)
    return unique_items[:5]


def normalize_todo_phase(phase: Optional[str]) -> str:
    if not phase or phase == "额外待办":
        return "流程待办"
    if phase in {"方案与SAP", "TFL与统计输出"}:
        return "SAP与TFL"
    return phase


def phase_sort_rank(phase: Optional[str]) -> int:
    normalized = normalize_todo_phase(phase)
    if normalized in STANDARD_PHASE_ORDER:
        return STANDARD_PHASE_ORDER.index(normalized)
    if normalized == "流程待办":
        return len(STANDARD_PHASE_ORDER)
    return len(STANDARD_PHASE_ORDER) + 1


def _phase_sort_name(phase: Optional[str]) -> str:
    normalized = normalize_todo_phase(phase)
    if normalized in STANDARD_PHASE_ORDER or normalized == "流程待办":
        return ""
    return normalized


def _todo_sort_order(todo: ProjectTodo) -> int:
    return todo.sort_order if todo.sort_order and todo.sort_order > 0 else 100000


def _todo_sort_key(todo: ProjectTodo):
    return (
        phase_sort_rank(todo.phase),
        _phase_sort_name(todo.phase),
        _todo_sort_order(todo),
        todo.due_at is None,
        todo.due_at or datetime.max,
        todo.id,
    )


def _next_phase_sort_order(db: Session, project_id: int) -> int:
    max_order = (
        db.query(func.max(ProjectPhase.sort_order))
        .filter(ProjectPhase.project_id == project_id)
        .scalar()
        or 0
    )
    return max_order + 1


def _find_phase(db: Session, project_id: int, name: str) -> Optional[ProjectPhase]:
    normalized = normalize_todo_phase(name)
    return (
        db.query(ProjectPhase)
        .filter(ProjectPhase.project_id == project_id, ProjectPhase.name == normalized)
        .first()
    )


def _ensure_phase(db: Session, project_id: int, name: Optional[str], sort_order: Optional[int] = None) -> ProjectPhase:
    normalized = normalize_todo_phase(name)
    phase = _find_phase(db, project_id, normalized)
    if phase:
        return phase
    phase = ProjectPhase(
        project_id=project_id,
        name=normalized,
        sort_order=sort_order or _next_phase_sort_order(db, project_id),
    )
    db.add(phase)
    db.flush()
    return phase


def _ensure_standard_phases(
    db: Session,
    project_id: int,
    phase_names: Optional[List[str]] = None,
) -> None:
    for index, phase_name in enumerate(phase_names or STANDARD_PHASE_ORDER, start=1):
        phase = _find_phase(db, project_id, phase_name)
        if phase:
            if not phase.sort_order or phase.sort_order <= 0:
                phase.sort_order = index
            continue
        db.query(ProjectPhase).filter(
            ProjectPhase.project_id == project_id,
            ProjectPhase.sort_order >= index,
        ).update(
            {ProjectPhase.sort_order: ProjectPhase.sort_order + 1},
            synchronize_session=False,
        )
        db.add(
            ProjectPhase(
                project_id=project_id,
                name=phase_name,
                sort_order=index,
            )
        )
        db.flush()


def _ensure_phases_from_todos(db: Session, project_id: int) -> None:
    todo_phases = db.query(ProjectTodo.phase).filter(ProjectTodo.project_id == project_id).distinct().all()
    changed = False
    for (phase,) in todo_phases:
        normalized = normalize_todo_phase(phase)
        if not _find_phase(db, project_id, normalized):
            _ensure_phase(db, project_id, normalized)
            changed = True
    if changed:
        db.commit()


def _add_checklist_items(db: Session, todo_id: int, items: List[ChecklistItemCreate | str]) -> None:
    for index, item in enumerate(items, start=1):
        if isinstance(item, str):
            title = item
            is_done = False
            due_at = None
            meeting_id = None
            sort_order = index
        else:
            title = item.title
            is_done = item.is_done
            due_at = item.due_at
            meeting_id = item.meeting_id
            sort_order = item.sort_order or index
        db.add(ProjectTodoChecklistItem(
            todo_id=todo_id,
            title=title,
            is_done=is_done,
            due_at=due_at,
            meeting_id=meeting_id,
            sort_order=sort_order,
        ))


def _ensure_default_checklist(db: Session, todo: ProjectTodo) -> None:
    existing = (
        db.query(func.count(ProjectTodoChecklistItem.id))
        .filter(ProjectTodoChecklistItem.todo_id == todo.id)
        .scalar()
        or 0
    )
    if existing:
        return
    items = default_checklist_for_todo(todo.phase, todo.title)
    _add_checklist_items(db, todo.id, items)


def _sync_todo_from_checklist(db: Session, todo: ProjectTodo) -> None:
    """Reconcile a workflow todo's status against its checklist completion.

    Only workflow-driven statuses (next/open/in_progress/done) are touched so
    GTD-deferred statuses (waiting/someday/reference) and blocked are never
    silently overwritten by checklist edits."""
    if todo.status not in {"next", "open", "in_progress", "done"}:
        return
    items = db.query(ProjectTodoChecklistItem).filter(ProjectTodoChecklistItem.todo_id == todo.id).all()
    if not items:
        return
    done_count = sum(1 for item in items if item.is_done)
    was_done = todo.status in GTD_DONE
    if done_count == len(items):
        # All checklist steps finished => the task is done. This is the core
        # antidote to "I finished the task but forgot to update the status".
        todo.status = "done"
        todo.completed_at = todo.completed_at or datetime.now()
        if not was_done:
            # First transition into done arms the next recurring occurrence.
            _spawn_next_recurrence(db, todo)
    elif done_count == 0:
        todo.status = "next"
        if was_done:
            todo.completed_at = None
    else:
        todo.status = "in_progress"
        if was_done:
            todo.completed_at = None


def _sync_checklist_from_todo(db: Session, todo: ProjectTodo) -> None:
    if todo.status != "done":
        return
    todo.completed_at = todo.completed_at or datetime.now()
    db.query(ProjectTodoChecklistItem).filter(ProjectTodoChecklistItem.todo_id == todo.id).update(
        {"is_done": True},
        synchronize_session=False,
    )


def _stamp_terminal_status(todo: ProjectTodo, old_status: Optional[str] = None) -> None:
    """Stamp completed_at/cancelled_at on terminal transitions and clear them
    when a task is reopened, so GTD review can rely on real timestamps."""
    now = datetime.now()
    if todo.status == "done" and old_status != "done":
        todo.completed_at = now
    elif todo.status == "cancelled" and old_status != "cancelled":
        todo.cancelled_at = now
    elif todo.status not in GTD_CLOSED:
        # Reopened from a terminal status clears the old terminal timestamp.
        if old_status == "done":
            todo.completed_at = None
        if old_status == "cancelled":
            todo.cancelled_at = None


def _spawn_next_recurrence(db: Session, todo: ProjectTodo) -> Optional[ProjectTodo]:
    """Spawn the next occurrence of a recurring task when it is completed.

    Only called on a transition *into* done (guarded at each completion site so
    re-opening and re-checking an already-done task never double-spawns). The
    clone is created in 'next' with the same schedule and fields but a fresh,
    un-checked checklist, so finishing one occurrence arms the next without
    re-running any completion logic against the original task."""
    spec = (todo.recurrence or "").strip()
    if todo.status != "done" or not spec or not todo.due_at:
        return None
    from app.services.recurrence import next_due

    next_dt = next_due(todo.due_at, spec)
    if next_dt is None:
        return None
    _ensure_phase(db, todo.project_id, todo.phase)
    clone = ProjectTodo(
        project_id=todo.project_id,
        title=todo.title,
        description=todo.description,
        todo_type=todo.todo_type,
        phase=todo.phase,
        status="next",
        priority=todo.priority,
        due_at=next_dt,
        sort_order=todo.sort_order,
        source_text=todo.source_text,
        contexts=todo.contexts,
        tags=todo.tags,
        area=todo.area,
        energy_level=todo.energy_level,
        time_estimate=todo.time_estimate,
        recurrence=spec,
        is_focused_today=False,
    )
    db.add(clone)
    db.flush()
    items = (
        db.query(ProjectTodoChecklistItem)
        .filter(ProjectTodoChecklistItem.todo_id == todo.id)
        .all()
    )
    for item in items:
        db.add(
            ProjectTodoChecklistItem(
                todo_id=clone.id,
                title=item.title,
                is_done=False,
                due_at=item.due_at,
                meeting_id=item.meeting_id,
                sort_order=item.sort_order,
            )
        )
    db.flush()
    return clone


def _refresh_project_status(db: Session, project_id: int) -> None:
    todos = db.query(ProjectTodo).filter(ProjectTodo.project_id == project_id).all()
    project = db.query(Project).filter(Project.id == project_id).first()
    if not project:
        return
    if todos and all(todo.status in GTD_DONE for todo in todos):
        project.status = "completed"
    elif project.status == "completed":
        project.status = "active"


def _project_counts(db: Session, project: Project) -> Project:
    project.todo_count = db.query(func.count(ProjectTodo.id)).filter(ProjectTodo.project_id == project.id).scalar() or 0
    project.done_todo_count = (
        db.query(func.count(ProjectTodo.id))
        .filter(ProjectTodo.project_id == project.id, ProjectTodo.status.in_(GTD_DONE))
        .scalar()
        or 0
    )
    project.in_progress_todo_count = (
        db.query(func.count(ProjectTodo.id))
        .filter(ProjectTodo.project_id == project.id, ProjectTodo.status.in_(["in_progress", "blocked"]))
        .scalar()
        or 0
    )
    project.open_todo_count = (
        db.query(func.count(ProjectTodo.id))
        .filter(ProjectTodo.project_id == project.id, ProjectTodo.status.in_(GTD_ACTIVE))
        .scalar()
        or 0
    )
    project.meeting_count = db.query(func.count(ProjectMeeting.id)).filter(ProjectMeeting.project_id == project.id).scalar() or 0
    project.progress_percent = round((project.done_todo_count / project.todo_count) * 100, 1) if project.todo_count else 0
    if project.todo_count and project.done_todo_count == project.todo_count:
        project.status = "completed"
    elif project.status == "completed":
        project.status = "active"
    return project


def get_project(db: Session, project_id: int) -> Optional[Project]:
    project = db.query(Project).filter(Project.id == project_id).first()
    return _project_counts(db, project) if project else None


def _projects_for_user(db: Session, user):
    # Contacts and todo assignees are not project-sharing grants. Unowned
    # legacy projects remain admin-only rather than becoming public records.
    query = db.query(Project)
    user_id = getattr(user, "id", None)
    if user_id is None or not getattr(user, "is_active", True):
        return query.filter(false())
    if getattr(user, "is_admin", False):
        return query
    return query.filter(Project.owner_id == user_id)


def get_project_for_user(db: Session, project_id: int, user) -> Optional[Project]:
    project = _projects_for_user(db, user).filter(Project.id == project_id).first()
    return _project_counts(db, project) if project else None


def get_project_child_for_user(db: Session, model, child_id: int, user):
    project_ids = _projects_for_user(db, user).with_entities(Project.id)
    query = db.query(model).filter(model.id == child_id)
    if model is ProjectTodoChecklistItem:
        query = query.join(ProjectTodo, ProjectTodo.id == model.todo_id)
        return query.filter(ProjectTodo.project_id.in_(project_ids)).first()
    if model not in (
        ProjectMember, ProjectPhase, ProjectTodo, ProjectMeeting,
        ProjectTimelineImport, ProjectTimelineItem,
    ):
        raise ValueError("Unsupported project child model")
    return query.filter(model.project_id.in_(project_ids)).first()


def get_projects(db: Session, skip: int = 0, limit: int = 100, search: Optional[str] = None) -> Tuple[List[Project], int]:
    return _list_projects(db, db.query(Project), skip, limit, search)


def get_projects_for_user(
    db: Session, user, skip: int = 0, limit: int = 100, search: Optional[str] = None,
) -> Tuple[List[Project], int]:
    return _list_projects(db, _projects_for_user(db, user), skip, limit, search)


def _list_projects(db: Session, query, skip: int, limit: int, search: Optional[str]):
    query = query.filter(Project.is_inbox == False)  # GTD inbox is a hidden pseudo-project
    if search:
        query = query.filter(
            or_(
                Project.name.ilike(f"%{search}%"),
                Project.sponsor.ilike(f"%{search}%"),
                Project.protocol_no.ilike(f"%{search}%"),
                Project.indication.ilike(f"%{search}%"),
                Project.project_type.ilike(f"%{search}%"),
            )
        )
    total = query.count()
    projects = query.order_by(Project.updated_at.desc()).offset(skip).limit(limit).all()
    return [_project_counts(db, project) for project in projects], total


def create_project(
    db: Session,
    project: ProjectCreate,
    owner_id: Optional[int] = None,
    workflow_blueprint: Optional[List[dict]] = None,
) -> Project:
    data = project.model_dump(exclude={"create_standard_workflow"})
    data["project_type"] = normalize_project_type(data.get("project_type"))
    data["is_cdisc"] = bool(data.get("is_cdisc"))
    db_project = Project(**data, owner_id=owner_id)
    db.add(db_project)
    db.flush()

    if project.create_standard_workflow:
        seed_standard_workflow(
            db,
            db_project.id,
            commit=False,
            workflow_blueprint=workflow_blueprint,
        )

    db.commit()
    db.refresh(db_project)
    return get_project(db, db_project.id)


def update_project(db: Session, project_id: int, project_update: ProjectUpdate) -> Optional[Project]:
    project = db.query(Project).filter(Project.id == project_id).first()
    if not project:
        return None
    changes = project_update.model_dump(exclude_unset=True)
    if "project_type" in changes:
        changes["project_type"] = normalize_project_type(changes["project_type"])
    if "is_cdisc" in changes:
        changes["is_cdisc"] = bool(changes["is_cdisc"])
    for field, value in changes.items():
        setattr(project, field, value)
    db.commit()
    db.refresh(project)
    return get_project(db, project.id)


def delete_project(db: Session, project_id: int) -> bool:
    project = db.query(Project).filter(Project.id == project_id).first()
    if not project:
        return False
    timeline_import_ids = [
        import_id for (import_id,) in db.query(ProjectTimelineImport.id)
        .filter(ProjectTimelineImport.project_id == project_id)
        .all()
    ]
    # Timeline items reference todos/checklists, so remove them before the
    # project work records to keep PostgreSQL foreign-key checks satisfied.
    if timeline_import_ids:
        db.query(ProjectTimelineItem).filter(
            ProjectTimelineItem.timeline_import_id.in_(timeline_import_ids)
        ).delete(synchronize_session=False)
    db.query(ProjectTimelineImport).filter(
        ProjectTimelineImport.project_id == project_id
    ).delete(synchronize_session=False)
    db.query(ProjectMember).filter(ProjectMember.project_id == project_id).delete(
        synchronize_session=False
    )
    todo_ids = [todo_id for (todo_id,) in db.query(ProjectTodo.id).filter(ProjectTodo.project_id == project_id).all()]
    if todo_ids:
        db.query(ProjectTodoChecklistItem).filter(ProjectTodoChecklistItem.todo_id.in_(todo_ids)).delete(synchronize_session=False)
    db.query(ProjectTodo).filter(ProjectTodo.project_id == project_id).delete(synchronize_session=False)
    db.query(ProjectMeeting).filter(ProjectMeeting.project_id == project_id).delete(synchronize_session=False)
    db.query(ProjectPhase).filter(ProjectPhase.project_id == project_id).delete(synchronize_session=False)
    db.query(ProjectAgentMessage).filter(ProjectAgentMessage.project_id == project_id).delete(synchronize_session=False)
    db.delete(project)
    db.commit()
    return True


def get_project_phases(db: Session, project_id: int) -> Tuple[List[ProjectPhase], int]:
    _ensure_phases_from_todos(db, project_id)
    phases = (
        db.query(ProjectPhase)
        .filter(ProjectPhase.project_id == project_id)
        .order_by(ProjectPhase.sort_order.asc(), ProjectPhase.id.asc())
        .all()
    )
    return phases, len(phases)


def create_project_phase(db: Session, project_id: int, phase: ProjectPhaseCreate) -> ProjectPhase:
    stripped_name = phase.name.strip()
    if not stripped_name:
        raise ValueError("阶段名称不能为空")
    name = normalize_todo_phase(stripped_name)
    if _find_phase(db, project_id, name):
        raise ValueError("阶段已存在")
    db_phase = ProjectPhase(
        project_id=project_id,
        name=name,
        sort_order=phase.sort_order or _next_phase_sort_order(db, project_id),
    )
    db.add(db_phase)
    db.commit()
    db.refresh(db_phase)
    return db_phase


def update_project_phase(db: Session, phase_id: int, phase_update: ProjectPhaseUpdate) -> Optional[ProjectPhase]:
    phase = db.query(ProjectPhase).filter(ProjectPhase.id == phase_id).first()
    if not phase:
        return None
    old_name = phase.name
    if phase_update.name is not None:
        stripped_name = phase_update.name.strip()
        if not stripped_name:
            raise ValueError("阶段名称不能为空")
        new_name = normalize_todo_phase(stripped_name)
        existing = _find_phase(db, phase.project_id, new_name)
        if existing and existing.id != phase.id:
            raise ValueError("阶段已存在")
        phase.name = new_name
        db.query(ProjectTodo).filter(
            ProjectTodo.project_id == phase.project_id,
            ProjectTodo.phase == old_name,
        ).update({"phase": new_name}, synchronize_session=False)
        if old_name == "额外待办":
            db.query(ProjectTodo).filter(
                ProjectTodo.project_id == phase.project_id,
                ProjectTodo.phase == "额外待办",
            ).update({"phase": new_name}, synchronize_session=False)
    if phase_update.sort_order is not None:
        phase.sort_order = phase_update.sort_order
    db.commit()
    db.refresh(phase)
    return phase


def reorder_project_phases(db: Session, project_id: int, phase_ids: List[int]) -> List[ProjectPhase]:
    phases = (
        db.query(ProjectPhase)
        .filter(ProjectPhase.project_id == project_id)
        .order_by(ProjectPhase.sort_order.asc(), ProjectPhase.id.asc())
        .all()
    )
    phase_by_id = {phase.id: phase for phase in phases}
    ordered = [phase_by_id[phase_id] for phase_id in phase_ids if phase_id in phase_by_id]
    ordered_ids = {phase.id for phase in ordered}
    remaining = [phase for phase in phases if phase.id not in ordered_ids]
    for index, phase in enumerate([*ordered, *remaining], start=1):
        phase.sort_order = index
    db.commit()
    return sorted(phases, key=lambda item: (item.sort_order or 100000, item.id))


def delete_project_phase(db: Session, phase_id: int) -> bool:
    phase = db.query(ProjectPhase).filter(ProjectPhase.id == phase_id).first()
    if not phase:
        return False
    normalized = normalize_todo_phase(phase.name)
    matching_todos = [
        todo
        for todo in db.query(ProjectTodo).filter(ProjectTodo.project_id == phase.project_id).all()
        if normalize_todo_phase(todo.phase) == normalized
    ]
    if normalized == "流程待办" and matching_todos:
        raise ValueError("流程待办阶段仍有待办，不能删除")
    if normalized != "流程待办":
        fallback = _ensure_phase(db, phase.project_id, "流程待办")
        next_order = _next_todo_sort_order(db, phase.project_id, fallback.name)
        for offset, todo in enumerate(matching_todos):
            todo.phase = fallback.name
            todo.sort_order = next_order + offset
    db.delete(phase)
    db.commit()
    return True


def seed_standard_workflow(
    db: Session,
    project_id: int,
    commit: bool = True,
    workflow_blueprint: Optional[List[dict]] = None,
) -> int:
    project = db.query(Project).filter(Project.id == project_id).first()
    if not project:
        raise ValueError("项目不存在")
    blueprint = workflow_blueprint or build_workflow_blueprint(
        project.project_type,
        project.is_cdisc,
    )
    phase_names = [str(phase.get("name") or "").strip() for phase in blueprint]
    phase_names = [name for name in phase_names if name]
    _ensure_standard_phases(db, project_id, phase_names)
    existing_keys = {
        (normalize_todo_phase(phase), title)
        for phase, title in db.query(ProjectTodo.phase, ProjectTodo.title)
        .filter(ProjectTodo.project_id == project_id, ProjectTodo.todo_type == "standard")
        .all()
    }

    created = 0
    for phase_item in blueprint:
        phase = normalize_todo_phase(phase_item.get("name"))
        for todo_item in phase_item.get("todos") or []:
            title = str(todo_item.get("title") or "").strip()
            if not title:
                continue
            key = (phase, title)
            if key in existing_keys:
                continue
            todo = ProjectTodo(
                project_id=project_id,
                title=title,
                description=todo_item.get("description"),
                todo_type="standard",
                phase=phase,
                status="next",
                priority=todo_item.get("priority") or "normal",
                sort_order=_next_todo_sort_order(db, project_id, phase),
            )
            db.add(todo)
            db.flush()
            checklist = todo_item.get("checklist_items") or default_checklist_for_todo(
                phase,
                title,
            )
            _add_checklist_items(db, todo.id, checklist)
            created += 1
            existing_keys.add(key)
    if commit:
        db.commit()
    return created


def _title_matches(candidate: str, existing: str) -> bool:
    candidate = re.sub(r"\s+", "", (candidate or "").lower())
    existing = re.sub(r"\s+", "", (existing or "").lower())
    return bool(candidate and existing and (candidate in existing or existing in candidate))


def create_project_from_intake(
    db: Session,
    draft,
    source_text: str,
    owner_id: Optional[int] = None,
    model_used: Optional[str] = None,
    fallback_used: bool = False,
    workflow_blueprint: Optional[List[dict]] = None,
):
    """Create a project and apply an AI intake result in one transaction."""
    data = {
        "name": draft.name.strip() or "未命名项目",
        "sponsor": draft.sponsor,
        "protocol_no": draft.protocol_no,
        "phase": draft.phase,
        "current_workflow_phase": normalize_todo_phase(draft.current_phase) if draft.current_phase else None,
        "project_type": normalize_project_type(draft.project_type),
        "is_cdisc": bool(draft.is_cdisc),
        "indication": draft.indication,
        "description": draft.description or source_text[:2000],
        "status": draft.status,
    }
    db_project = Project(**data, owner_id=owner_id)
    db.add(db_project)
    db.flush()

    for index, member in enumerate(getattr(draft, "members", []) or [], start=1):
        member_data = member.model_dump() if hasattr(member, "model_dump") else dict(member)
        member_data["source_text"] = source_text
        member_data["sort_order"] = member_data.get("sort_order") or index
        db.add(ProjectMember(project_id=db_project.id, **member_data))

    if draft.create_standard_workflow:
        seed_standard_workflow(
            db,
            db_project.id,
            commit=False,
            workflow_blueprint=workflow_blueprint,
        )

    todos = db.query(ProjectTodo).filter(ProjectTodo.project_id == db_project.id).all()
    completed_count = 0
    in_progress_count = 0
    created_count = 0

    def find_todo(title: str):
        for todo in todos:
            if _title_matches(title, todo.title):
                return todo
        return None

    for title in draft.completed_todo_titles:
        todo = find_todo(title)
        if todo is None:
            todo = ProjectTodo(
                project_id=db_project.id,
                title=title.strip()[:300],
                todo_type="extra",
                phase=normalize_todo_phase(draft.current_phase),
                status="done",
                priority="normal",
                sort_order=_next_todo_sort_order(db, db_project.id, draft.current_phase),
                source_text=source_text,
            )
            db.add(todo)
            db.flush()
            todos.append(todo)
            created_count += 1
        if todo.status != "done":
            todo.status = "done"
        _sync_checklist_from_todo(db, todo)
        completed_count += 1

    for title in draft.in_progress_todo_titles:
        todo = find_todo(title)
        if todo is None:
            todo = ProjectTodo(
                project_id=db_project.id,
                title=title.strip()[:300],
                todo_type="extra",
                phase=normalize_todo_phase(draft.current_phase),
                status="in_progress",
                priority="normal",
                sort_order=_next_todo_sort_order(db, db_project.id, draft.current_phase),
                source_text=source_text,
            )
            db.add(todo)
            db.flush()
            todos.append(todo)
            created_count += 1
        elif todo.status != "done":
            todo.status = "in_progress"
        in_progress_count += 1

    for item in draft.todos:
        title = item.title.strip()
        if not title:
            continue
        existing = find_todo(title)
        if existing:
            if item.description is not None:
                existing.description = item.description
            if item.status not in {"open", "next"} or existing.status in {"open", "next"}:
                existing.status = item.status
            if item.priority != "normal" or existing.priority == "normal":
                existing.priority = item.priority
            if item.start_at is not None:
                existing.start_at = item.start_at.replace(tzinfo=None)
            if item.due_at is not None:
                existing.due_at = item.due_at.replace(tzinfo=None)
            continue
        phase = normalize_todo_phase(item.phase or draft.current_phase)
        created = ProjectTodo(
            project_id=db_project.id,
            title=title,
            description=item.description,
            todo_type=item.todo_type,
            phase=phase,
            status=item.status,
            priority=item.priority,
            start_at=item.start_at.replace(tzinfo=None) if item.start_at else None,
            due_at=item.due_at.replace(tzinfo=None) if item.due_at else None,
            sort_order=_next_todo_sort_order(db, db_project.id, phase),
            source_text=source_text,
        )
        db.add(created)
        db.flush()
        # Intake creates task records only. Checklist items remain a manual
        # project-workbench action, matching the normal new-todo workflow.
        todos.append(created)
        created_count += 1
        if created.status == "done":
            completed_count += 1
        elif created.status in {"in_progress", "blocked"}:
            in_progress_count += 1

    if draft.current_phase:
        _ensure_phase(db, db_project.id, draft.current_phase)
        db_project.current_workflow_phase = normalize_todo_phase(draft.current_phase)
        active = [
            todo for todo in todos
            if normalize_todo_phase(todo.phase) == normalize_todo_phase(draft.current_phase)
            and todo.status in {"open", "next"}
        ]
        active.sort(key=_todo_sort_key)
        if active and not any(todo.status == "in_progress" for todo in todos if normalize_todo_phase(todo.phase) == normalize_todo_phase(draft.current_phase)):
            active[0].status = "in_progress"
            in_progress_count += 1

    _refresh_project_status(db, db_project.id)
    db.commit()
    db.refresh(db_project)
    return {
        "project": get_project(db, db_project.id),
        "completed_todo_count": completed_count,
        "in_progress_todo_count": in_progress_count,
        "created_todo_count": created_count,
        "model_used": model_used or "",
        "fallback_used": fallback_used,
    }


def get_todos(
    db: Session,
    project_id: int,
    todo_type: Optional[str] = None,
    status: Optional[str] = None,
) -> Tuple[List[ProjectTodo], int]:
    query = db.query(ProjectTodo).filter(ProjectTodo.project_id == project_id)
    if todo_type:
        query = query.filter(ProjectTodo.todo_type == todo_type)
    if status:
        query = query.filter(ProjectTodo.status == status)
    total = query.count()
    items = query.order_by(ProjectTodo.id.asc()).all()
    items.sort(key=_todo_sort_key)
    return items, total


def _next_todo_sort_order(db: Session, project_id: int, phase: Optional[str]) -> int:
    normalized_phase = normalize_todo_phase(phase)
    max_order = 0
    existing = db.query(ProjectTodo).filter(ProjectTodo.project_id == project_id).all()
    for item in existing:
        if normalize_todo_phase(item.phase) == normalized_phase and item.sort_order and item.sort_order > max_order:
            max_order = item.sort_order
    return max_order + 1


def _normalize_todo_json_fields(data: dict) -> dict:
    """Serialize GTD list fields to JSON strings for Text columns."""
    for field in ("contexts", "tags"):
        if data.get(field) is not None:
            data[field] = json.dumps(data[field], ensure_ascii=False)
    return data


def inbox_project(db: Session, owner_id: Optional[int]) -> Project:
    """Get-or-create the hidden GTD inbox pseudo-project for a user.

    The inbox is a real Project row (so the whole FK graph, timeline matching,
    sorting and cascade deletion work unchanged) but is flagged is_inbox=True so
    it is hidden from the project library and excluded from every count."""
    inbox = (
        db.query(Project)
        .filter(Project.is_inbox == True, Project.owner_id == owner_id)  # noqa: E712
        .first()
    )
    if inbox:
        return inbox
    inbox = Project(
        name="收件箱",
        sponsor="GTD",
        description="GTD 收件箱：快速捕获，稍后统一处理。",
        status="active",
        is_inbox=True,
        owner_id=owner_id,
    )
    db.add(inbox)
    db.flush()
    if not _find_phase(db, inbox.id, "收件箱"):
        db.add(ProjectPhase(project_id=inbox.id, name="收件箱", sort_order=1))
    db.commit()
    db.refresh(inbox)
    return inbox


def create_todo(db: Session, project_id: int, todo: TodoCreate) -> ProjectTodo:
    _validate_todo_meetings(db, project_id, todo)
    data = todo.model_dump(exclude={"checklist_items"})
    _ensure_phase(db, project_id, data.get("phase"))
    if not data.get("sort_order"):
        data["sort_order"] = _next_todo_sort_order(db, project_id, data.get("phase"))
    data = _normalize_todo_json_fields(data)
    db_todo = ProjectTodo(project_id=project_id, **data)
    db.add(db_todo)
    db.flush()
    _stamp_terminal_status(db_todo)
    checklist_items = todo.checklist_items or []
    if checklist_items:
        _add_checklist_items(db, db_todo.id, checklist_items)
    _sync_todo_from_checklist(db, db_todo)
    _refresh_project_status(db, project_id)
    db.commit()
    db.refresh(db_todo)
    return db_todo


def update_todo(db: Session, todo_id: int, todo_update: TodoUpdate) -> Optional[ProjectTodo]:
    todo = db.query(ProjectTodo).filter(ProjectTodo.id == todo_id).first()
    if not todo:
        return None
    _validate_todo_meetings(db, todo.project_id, todo_update)
    update_data = todo_update.model_dump(exclude_unset=True)
    if "phase" in update_data:
        _ensure_phase(db, todo.project_id, update_data.get("phase"))
    old_status = todo.status
    _normalize_todo_json_fields(update_data)
    for field, value in update_data.items():
        setattr(todo, field, value)
    if todo.status != old_status:
        _stamp_terminal_status(todo, old_status)
        if todo.status == "done" and old_status != "done":
            # First transition into done arms the next recurring occurrence.
            _spawn_next_recurrence(db, todo)
    _sync_checklist_from_todo(db, todo)
    _refresh_project_status(db, todo.project_id)
    db.commit()
    db.refresh(todo)
    return todo


def reorder_todos(db: Session, project_id: int, phase: str, todo_ids: List[int]) -> List[ProjectTodo]:
    normalized_phase = normalize_todo_phase(phase)
    _ensure_phase(db, project_id, normalized_phase)
    todos = db.query(ProjectTodo).filter(ProjectTodo.project_id == project_id).all()
    phase_todos = [todo for todo in todos if normalize_todo_phase(todo.phase) == normalized_phase]
    todo_by_id = {todo.id: todo for todo in phase_todos}
    ordered = [todo_by_id[todo_id] for todo_id in todo_ids if todo_id in todo_by_id]
    ordered_ids = {todo.id for todo in ordered}
    remaining = [todo for todo in sorted(phase_todos, key=_todo_sort_key) if todo.id not in ordered_ids]
    for index, todo in enumerate([*ordered, *remaining], start=1):
        todo.phase = normalized_phase
        todo.sort_order = index
    db.commit()
    return sorted(phase_todos, key=_todo_sort_key)


def delete_todo(db: Session, todo_id: int) -> bool:
    todo = db.query(ProjectTodo).filter(ProjectTodo.id == todo_id).first()
    if not todo:
        return False
    project_id = todo.project_id
    # Keep imported Timeline history, but remove references to records that
    # are about to be deleted so PostgreSQL foreign-key checks remain valid.
    db.query(ProjectTimelineItem).filter(
        ProjectTimelineItem.project_id == project_id,
        ProjectTimelineItem.matched_todo_id == todo_id,
    ).update(
        {
            "target_type": "none",
            "matched_todo_id": None,
            "matched_checklist_item_id": None,
            "warning": "原绑定的项目任务已删除，请重新选择绑定目标",
        },
        synchronize_session=False,
    )
    db.query(ProjectTodoChecklistItem).filter(ProjectTodoChecklistItem.todo_id == todo_id).delete(synchronize_session=False)
    db.delete(todo)
    _refresh_project_status(db, project_id)
    db.commit()
    return True


def create_checklist_item(db: Session, todo_id: int, item: ChecklistItemCreate) -> Optional[ProjectTodoChecklistItem]:
    todo = db.query(ProjectTodo).filter(ProjectTodo.id == todo_id).first()
    if not todo:
        return None
    if item.meeting_id is not None and not _meeting_belongs_to_project(db, item.meeting_id, todo.project_id):
        return None
    db_item = ProjectTodoChecklistItem(todo_id=todo_id, **item.model_dump())
    db.add(db_item)
    db.flush()
    _sync_todo_from_checklist(db, todo)
    _refresh_project_status(db, todo.project_id)
    db.commit()
    db.refresh(db_item)
    return db_item


def update_checklist_item(
    db: Session,
    item_id: int,
    item_update: ChecklistItemUpdate,
) -> Optional[ProjectTodoChecklistItem]:
    item = db.query(ProjectTodoChecklistItem).filter(ProjectTodoChecklistItem.id == item_id).first()
    if not item:
        return None
    update_data = item_update.model_dump(exclude_unset=True)
    todo = db.query(ProjectTodo).filter(ProjectTodo.id == item.todo_id).first()
    if (
        todo
        and update_data.get("meeting_id") is not None
        and not _meeting_belongs_to_project(db, update_data["meeting_id"], todo.project_id)
    ):
        return None
    for field, value in update_data.items():
        setattr(item, field, value)
    if todo:
        _sync_todo_from_checklist(db, todo)
        _refresh_project_status(db, todo.project_id)
    db.commit()
    db.refresh(item)
    return item


def delete_checklist_item(db: Session, item_id: int) -> bool:
    item = db.query(ProjectTodoChecklistItem).filter(ProjectTodoChecklistItem.id == item_id).first()
    if not item:
        return False
    todo = db.query(ProjectTodo).filter(ProjectTodo.id == item.todo_id).first()
    if todo:
        db.query(ProjectTimelineItem).filter(
            ProjectTimelineItem.project_id == todo.project_id,
            ProjectTimelineItem.matched_checklist_item_id == item_id,
        ).update(
            {
                "target_type": "none",
                "matched_todo_id": None,
                "matched_checklist_item_id": None,
                "warning": "原绑定的清单项已删除，请重新选择绑定目标",
            },
            synchronize_session=False,
        )
    db.delete(item)
    if todo:
        _sync_todo_from_checklist(db, todo)
        _refresh_project_status(db, todo.project_id)
    db.commit()
    return True


def get_meetings(db: Session, project_id: int) -> Tuple[List[ProjectMeeting], int]:
    query = db.query(ProjectMeeting).filter(ProjectMeeting.project_id == project_id)
    total = query.count()
    items = query.order_by(ProjectMeeting.starts_at.asc().nulls_last(), ProjectMeeting.id.desc()).all()
    return items, total


def _meeting_belongs_to_project(db: Session, meeting_id: int, project_id: int) -> bool:
    return (
        db.query(func.count(ProjectMeeting.id))
        .filter(ProjectMeeting.id == meeting_id, ProjectMeeting.project_id == project_id)
        .scalar()
        or 0
    ) > 0


def _validate_todo_meetings(db: Session, project_id: int, todo) -> None:
    meeting_ids = [todo.meeting_id]
    meeting_ids.extend(item.meeting_id for item in getattr(todo, "checklist_items", []))
    for meeting_id in meeting_ids:
        if meeting_id is not None and not _meeting_belongs_to_project(db, meeting_id, project_id):
            raise ValueError("会议不存在或不属于当前项目")


def create_meeting(db: Session, project_id: int, meeting: MeetingCreate) -> ProjectMeeting:
    db_meeting = ProjectMeeting(project_id=project_id, **meeting.model_dump())
    db.add(db_meeting)
    db.commit()
    db.refresh(db_meeting)
    return db_meeting


def update_meeting(db: Session, meeting_id: int, meeting_update: MeetingUpdate) -> Optional[ProjectMeeting]:
    meeting = db.query(ProjectMeeting).filter(ProjectMeeting.id == meeting_id).first()
    if not meeting:
        return None
    for field, value in meeting_update.model_dump(exclude_unset=True).items():
        setattr(meeting, field, value)
    db.commit()
    db.refresh(meeting)
    return meeting


def delete_meeting(db: Session, meeting_id: int) -> bool:
    meeting = db.query(ProjectMeeting).filter(ProjectMeeting.id == meeting_id).first()
    if not meeting:
        return False
    db.query(ProjectTodo).filter(ProjectTodo.meeting_id == meeting_id).update({"meeting_id": None}, synchronize_session=False)
    db.query(ProjectTodoChecklistItem).filter(ProjectTodoChecklistItem.meeting_id == meeting_id).update(
        {"meeting_id": None},
        synchronize_session=False,
    )
    db.delete(meeting)
    db.commit()
    return True


def get_project_members(db: Session, project_id: int) -> Tuple[List[ProjectMember], int]:
    query = db.query(ProjectMember).filter(ProjectMember.project_id == project_id)
    items = query.order_by(ProjectMember.sort_order.asc(), ProjectMember.id.asc()).all()
    return items, len(items)


def build_timeline_context(db: Session, project_id: int) -> dict:
    """Return the small, ID-bearing project context used by Timeline AI matching."""
    phases = (
        db.query(ProjectPhase)
        .filter(ProjectPhase.project_id == project_id)
        .order_by(ProjectPhase.sort_order.asc(), ProjectPhase.id.asc())
        .all()
    )
    todos, _ = get_todos(db, project_id)
    return {
        "phases": [
            {"id": phase.id, "name": phase.name}
            for phase in phases
        ],
        "todos": [
            {
                "id": todo.id,
                "phase": normalize_todo_phase(todo.phase),
                "title": todo.title,
                "checklist_items": [
                    {"id": item.id, "title": item.title}
                    for item in todo.checklist_items
                ],
            }
            for todo in todos[:500]
        ],
    }


def create_project_member(
    db: Session,
    project_id: int,
    member: ProjectMemberCreate,
) -> ProjectMember:
    data = member.model_dump()
    if not data.get("sort_order"):
        max_order = db.query(func.max(ProjectMember.sort_order)).filter(
            ProjectMember.project_id == project_id
        ).scalar() or 0
        data["sort_order"] = max_order + 1
    item = ProjectMember(project_id=project_id, **data)
    db.add(item)
    db.commit()
    db.refresh(item)
    return item


def update_project_member(
    db: Session,
    member_id: int,
    member_update: ProjectMemberUpdate,
) -> Optional[ProjectMember]:
    item = db.query(ProjectMember).filter(ProjectMember.id == member_id).first()
    if not item:
        return None
    for field, value in member_update.model_dump(exclude_unset=True).items():
        setattr(item, field, value)
    db.commit()
    db.refresh(item)
    return item


def delete_project_member(db: Session, member_id: int) -> bool:
    item = db.query(ProjectMember).filter(ProjectMember.id == member_id).first()
    if not item:
        return False
    db.delete(item)
    db.commit()
    return True


def _timeline_text(value) -> str:
    return re.sub(r"\s+", "", str(value or "")).lower()


def _timeline_match(
    db: Session,
    project_id: int,
    item_data: dict,
) -> tuple[Optional[ProjectTodo], Optional[ProjectTodoChecklistItem], float, Optional[str]]:
    target_type = item_data.get("target_type") or "none"
    todo_id = item_data.get("matched_todo_id")
    checklist_id = item_data.get("matched_checklist_item_id")
    todo_query = db.query(ProjectTodo).filter(ProjectTodo.project_id == project_id)
    todos = todo_query.all()
    todo_by_id = {todo.id: todo for todo in todos}
    if todo_id in todo_by_id and target_type in {"todo", "none"}:
        return todo_by_id[todo_id], None, 1.0, None
    checklist_query = (
        db.query(ProjectTodoChecklistItem)
        .join(ProjectTodo, ProjectTodo.id == ProjectTodoChecklistItem.todo_id)
        .filter(ProjectTodo.project_id == project_id)
    )
    checklists = checklist_query.all()
    checklist_by_id = {item.id: item for item in checklists}
    if checklist_id in checklist_by_id and target_type in {"checklist", "none"}:
        return None, checklist_by_id[checklist_id], 1.0, None

    title = _timeline_text(item_data.get("title"))
    phase = _timeline_text(item_data.get("phase"))
    if not title:
        return None, None, 0.0, "缺少事项标题，未绑定项目待办"

    candidates = []
    for todo in todos:
        candidate = _timeline_text(todo.title)
        score = 0.0
        if title == candidate:
            score = 0.98
        elif title in candidate or candidate in title:
            score = 0.82
        else:
            left = set(re.findall(r"[a-z0-9]+|[\u4e00-\u9fff]", title))
            right = set(re.findall(r"[a-z0-9]+|[\u4e00-\u9fff]", candidate))
            overlap = len(left & right) / max(len(left), 1)
            score = overlap * 0.7
        if phase and phase == _timeline_text(todo.phase):
            score += 0.12
        if score:
            candidates.append((score, todo, None))
        for checklist in todo.checklist_items:
            check_title = _timeline_text(checklist.title)
            check_score = 0.0
            if title == check_title:
                check_score = 0.98
            elif title in check_title or check_title in title:
                check_score = 0.82
            if check_score:
                candidates.append((check_score + (0.12 if phase and phase == _timeline_text(todo.phase) else 0), todo, checklist))
    if not candidates:
        return None, None, 0.0, "未找到匹配的项目待办或清单项"
    candidates.sort(key=lambda value: value[0], reverse=True)
    best_score, todo, checklist = candidates[0]
    if best_score < 0.62:
        return None, None, best_score, "匹配置信度较低，请人工选择绑定目标"
    return (None, checklist, min(best_score, 1.0), None) if checklist else (todo, None, min(best_score, 1.0), None)


def _apply_timeline_dates(
    todo: Optional[ProjectTodo],
    checklist: Optional[ProjectTodoChecklistItem],
    item_data: dict,
) -> None:
    if todo:
        if item_data.get("start_at") is not None:
            todo.start_at = item_data["start_at"]
        if item_data.get("due_at") is not None:
            todo.due_at = item_data["due_at"]
    if checklist:
        if item_data.get("due_at") is not None:
            checklist.due_at = item_data["due_at"]


def create_timeline_import(
    db: Session,
    project_id: int,
    *,
    source_type: str,
    file_name: Optional[str],
    source_text: Optional[str],
    raw_rows: List[dict],
    parsed_items: List[dict],
    model_used: str,
    fallback_used: bool,
    error_message: Optional[str] = None,
) -> ProjectTimelineImport:
    timeline = ProjectTimelineImport(
        project_id=project_id,
        file_name=file_name,
        source_type=source_type,
        source_text=source_text,
        raw_json=json.dumps(raw_rows, ensure_ascii=False, default=str),
        model_used=model_used,
        fallback_used=fallback_used,
        status="parsed" if parsed_items else "empty",
        error_message=error_message,
    )
    db.add(timeline)
    db.flush()
    for index, raw_item in enumerate(parsed_items, start=1):
        item = dict(raw_item)
        todo, checklist, confidence, warning = _timeline_match(db, project_id, item)
        target_type = "checklist" if checklist else ("todo" if todo else "none")
        item["target_type"] = target_type
        item["matched_todo_id"] = todo.id if todo else (checklist.todo_id if checklist else None)
        item["matched_checklist_item_id"] = checklist.id if checklist else None
        item["confidence"] = item.get("confidence") if item.get("confidence") is not None else confidence
        item["warning"] = item.get("warning") or warning
        db_item = ProjectTimelineItem(
            timeline_import_id=timeline.id,
            project_id=project_id,
            row_number=item.get("row_number") or index,
            external_id=item.get("external_id"),
            title=item.get("title") or "未命名事项",
            description=item.get("description"),
            phase=normalize_todo_phase(item.get("phase")),
            start_at=item.get("start_at"),
            due_at=item.get("due_at"),
            status=item.get("status"),
            target_type=target_type,
            matched_todo_id=item["matched_todo_id"],
            matched_checklist_item_id=item["matched_checklist_item_id"],
            confidence=item["confidence"],
            warning=item["warning"],
            raw_json=json.dumps(raw_item, ensure_ascii=False, default=str),
        )
        db.add(db_item)
        _apply_timeline_dates(todo, checklist, item)
    db.commit()
    db.refresh(timeline)
    return timeline


def get_timeline_imports(db: Session, project_id: int) -> Tuple[List[ProjectTimelineImport], int]:
    query = db.query(ProjectTimelineImport).filter(ProjectTimelineImport.project_id == project_id)
    items = query.order_by(ProjectTimelineImport.created_at.desc(), ProjectTimelineImport.id.desc()).all()
    return items, len(items)


def get_timeline_import(db: Session, timeline_id: int) -> Optional[ProjectTimelineImport]:
    return db.query(ProjectTimelineImport).filter(ProjectTimelineImport.id == timeline_id).first()


def update_timeline_item(
    db: Session,
    item_id: int,
    item_update: TimelineItemUpdate,
) -> Optional[ProjectTimelineItem]:
    item = db.query(ProjectTimelineItem).filter(ProjectTimelineItem.id == item_id).first()
    if not item:
        return None
    data = item_update.model_dump(exclude_unset=True)
    # A manual binding replaces the complete target state. Never keep an old
    # ID when the UI selects a different target or explicitly unbinds it.
    target_changed = any(
        field in data
        for field in ("matched_todo_id", "matched_checklist_item_id", "target_type")
    )
    if target_changed:
        target_type = data.pop("target_type", item.target_type or "none")
        todo_id = data.pop("matched_todo_id", None)
        checklist_id = data.pop("matched_checklist_item_id", None)
        if target_type == "todo":
            if not todo_id:
                raise ValueError("绑定到任务时必须选择一个项目任务")
            item.target_type = target_type
            item.matched_todo_id = todo_id
            item.matched_checklist_item_id = None
        elif target_type == "checklist":
            if not checklist_id:
                raise ValueError("绑定到清单时必须选择一个清单事项")
            item.target_type = target_type
            item.matched_todo_id = None
            item.matched_checklist_item_id = checklist_id
        else:
            item.target_type = "none"
            item.matched_todo_id = None
            item.matched_checklist_item_id = None
    for field, value in data.items():
        setattr(item, field, value)
    todo = db.query(ProjectTodo).filter(
        ProjectTodo.id == item.matched_todo_id,
        ProjectTodo.project_id == item.project_id,
    ).first() if item.matched_todo_id else None
    checklist = (
        db.query(ProjectTodoChecklistItem)
        .join(ProjectTodo, ProjectTodo.id == ProjectTodoChecklistItem.todo_id)
        .filter(
            ProjectTodoChecklistItem.id == item.matched_checklist_item_id,
            ProjectTodo.project_id == item.project_id,
        )
        .first()
        if item.matched_checklist_item_id else None
    )
    if item.target_type == "todo" and item.matched_todo_id and todo is None:
        raise ValueError("选择的待办不属于当前项目")
    if item.target_type == "checklist" and item.matched_checklist_item_id and checklist is None:
        raise ValueError("选择的清单项不属于当前项目")
    _apply_timeline_dates(todo, checklist, {
        "start_at": item.start_at,
        "due_at": item.due_at,
        "phase": item.phase,
    })
    db.commit()
    db.refresh(item)
    return item


def delete_timeline_import(db: Session, timeline_id: int) -> bool:
    item = get_timeline_import(db, timeline_id)
    if not item:
        return False
    db.delete(item)
    db.commit()
    return True


def _extract_url(text: str) -> Optional[str]:
    match = re.search(r"https?://[^\s，,；;]+", text)
    return match.group(0) if match else None


def _parse_due_at(text: str) -> Optional[datetime]:
    now = datetime.now()
    date_value = None
    if "明天" in text:
        date_value = now + timedelta(days=1)
    elif "后天" in text:
        date_value = now + timedelta(days=2)
    elif "今天" in text:
        date_value = now

    weekday_map = {
        "一": 0, "二": 1, "三": 2, "四": 3, "五": 4, "六": 5, "日": 6, "天": 6,
    }
    week_match = re.search(r"(下周|下星期|本周|这周|周|星期)([一二三四五六日天])", text)
    if week_match:
        prefix, weekday = week_match.groups()
        target = weekday_map[weekday]
        days = (target - now.weekday()) % 7
        if prefix in ("下周", "下星期"):
            days += 7 if days == 0 else 7
        elif days == 0 and "今天" not in text:
            days = 7
        date_value = now + timedelta(days=days)

    iso_match = re.search(r"(\d{4})[-/年](\d{1,2})[-/月](\d{1,2})", text)
    if iso_match:
        year, month, day = [int(part) for part in iso_match.groups()]
        date_value = datetime(year, month, day)

    month_day_match = re.search(r"(\d{1,2})[月/-](\d{1,2})[日号]?", text)
    if month_day_match and not iso_match:
        month, day = [int(part) for part in month_day_match.groups()]
        date_value = datetime(now.year, month, day)
        if date_value.date() < now.date():
            date_value = datetime(now.year + 1, month, day)

    time_match = re.search(r"(凌晨|早上|上午|中午|下午|晚上|晚间)?\s*(\d{1,2})(?::|：|点)(\d{1,2})?(半)?(?:分)?", text)
    hour = 23 if date_value else None
    minute = 59 if date_value else None
    if time_match:
        period, hour_text, minute_text, half_text = time_match.groups()
        hour = int(hour_text)
        minute = 30 if half_text else int(minute_text or 0)
        if period in ("下午", "晚上", "晚间") and hour < 12:
            hour += 12
        if period == "中午" and hour < 11:
            hour += 12
        if date_value is None:
            date_value = now
            candidate = date_value.replace(hour=hour, minute=minute, second=0, microsecond=0)
            if candidate < now:
                candidate += timedelta(days=1)
            return candidate

    if date_value:
        return date_value.replace(hour=hour or 23, minute=minute or 59, second=0, microsecond=0)

    return None


def _parse_end_at(text: str, starts_at: Optional[datetime]) -> Optional[datetime]:
    if not starts_at:
        return None
    range_match = re.search(r"(?:-|~|至|到)\s*(凌晨|早上|上午|中午|下午|晚上|晚间)?\s*(\d{1,2})(?::|：|点)(\d{1,2})?(半)?(?:分)?", text)
    if not range_match:
        return starts_at + timedelta(hours=1)
    period, hour_text, minute_text, half_text = range_match.groups()
    hour = int(hour_text)
    minute = 30 if half_text else int(minute_text or 0)
    if period in ("下午", "晚上", "晚间") and hour < 12:
        hour += 12
    if period == "中午" and hour < 11:
        hour += 12
    end_at = starts_at.replace(hour=hour, minute=minute, second=0, microsecond=0)
    if end_at <= starts_at:
        end_at += timedelta(days=1)
    return end_at


def parse_text_fallback(text: str) -> dict:
    url = _extract_url(text)
    is_meeting = bool(url) or any(keyword in text for keyword in ["会议", "例会", "会", "腾讯会议", "飞书", "Zoom", "Teams"])
    due_at = _parse_due_at(text)

    if is_meeting:
        title = "项目会议"
        title_match = re.search(r"([^。；;\n]{2,40}(?:会议|例会|讨论|同步会))", text)
        if title_match:
            title = title_match.group(1).strip()
        ends_at = _parse_end_at(text, due_at)
        return {
            "intent": "meeting",
            "meetings": [{
                "title": title,
                "agenda": text.strip(),
                "meeting_url": url,
                "starts_at": due_at.isoformat() if due_at else None,
                "ends_at": ends_at.isoformat() if ends_at else None,
                "source_text": text,
            }],
            "todos": [],
        }

    title = text.strip()
    todo_match = re.search(r"(?:需要|要|记得|请|完成|跟进)?(.{2,80})", text.strip())
    if todo_match:
        title = todo_match.group(1).strip(" ，,。；;")
    return {
        "intent": "todo",
        "meetings": [],
        "todos": [{
            "title": title or "项目待办",
            "description": text.strip(),
            "todo_type": "extra",
            "priority": "normal",
            "status": "next",
            "start_at": None,
            "due_at": due_at.isoformat() if due_at else None,
            "source_text": text,
        }],
    }


def build_agent_context(db: Session, project_id: int) -> dict:
    project = db.query(Project).filter(Project.id == project_id).first()
    phases = (
        db.query(ProjectPhase)
        .filter(ProjectPhase.project_id == project_id)
        .order_by(ProjectPhase.sort_order.asc(), ProjectPhase.id.asc())
        .all()
    )
    todos, _ = get_todos(db, project_id)
    meetings, _ = get_meetings(db, project_id)
    history = get_agent_messages(db, project_id, limit=12)[0]
    return {
        "project": {
            "id": project.id,
            "name": project.name,
            "protocol_no": project.protocol_no,
            "phase": project.phase,
            "current_workflow_phase": project.current_workflow_phase,
            "project_type": project.project_type,
            "is_cdisc": project.is_cdisc,
            "indication": project.indication,
            "status": project.status,
        },
        "phases": [
            {"id": phase.id, "name": phase.name, "sort_order": phase.sort_order}
            for phase in phases
        ],
        "todos": [
            {
                "id": todo.id,
                "title": todo.title,
                "phase": normalize_todo_phase(todo.phase),
                "status": todo.status,
                "priority": todo.priority,
                "start_at": todo.start_at.isoformat() if todo.start_at else None,
                "due_at": todo.due_at.isoformat() if todo.due_at else None,
                "checklist_items": [
                    {
                        "id": item.id,
                        "title": item.title,
                        "is_done": item.is_done,
                        "due_at": item.due_at.isoformat() if item.due_at else None,
                    }
                    for item in todo.checklist_items
                ],
            }
            for todo in todos
        ],
        "meetings": [
            {
                "id": meeting.id,
                "title": meeting.title,
                "starts_at": meeting.starts_at.isoformat() if meeting.starts_at else None,
                "ends_at": meeting.ends_at.isoformat() if meeting.ends_at else None,
                "todo_ids": [todo.id for todo in meeting.todos],
            }
            for meeting in meetings
        ],
        "recent_conversation": [
            {"role": message.role, "content": message.content}
            for message in history
        ],
    }


def get_agent_messages(
    db: Session,
    project_id: int,
    limit: int = 100,
) -> Tuple[List[ProjectAgentMessage], int]:
    query = db.query(ProjectAgentMessage).filter(
        ProjectAgentMessage.project_id == project_id
    )
    total = query.count()
    latest = (
        query.order_by(ProjectAgentMessage.id.desc())
        .limit(limit)
        .all()
    )
    return list(reversed(latest)), total


def apply_agent_plan(
    db: Session,
    project_id: int,
    plan: ProjectAgentPlan,
    source_text: str,
    user_id: Optional[int] = None,
    model_used: Optional[str] = None,
    fallback_used: bool = False,
) -> dict:
    """Apply a validated agent plan in one transaction."""
    project = db.query(Project).filter(Project.id == project_id).first()
    if not project:
        raise ValueError("项目不存在")

    todos = db.query(ProjectTodo).filter(ProjectTodo.project_id == project_id).all()
    todo_by_id = {todo.id: todo for todo in todos}
    checklist_items = (
        db.query(ProjectTodoChecklistItem)
        .join(ProjectTodo, ProjectTodo.id == ProjectTodoChecklistItem.todo_id)
        .filter(ProjectTodo.project_id == project_id)
        .all()
    )
    checklist_by_id = {item.id: item for item in checklist_items}
    meetings = db.query(ProjectMeeting).filter(ProjectMeeting.project_id == project_id).all()
    meeting_by_id = {meeting.id: meeting for meeting in meetings}
    todo_refs: dict[str, ProjectTodo] = {}
    meeting_refs: dict[str, ProjectMeeting] = {}
    created_todos: list[ProjectTodo] = []
    updated_todos: list[ProjectTodo] = []
    created_meetings: list[ProjectMeeting] = []
    updated_meetings: list[ProjectMeeting] = []

    for todo_id in set(plan.completed_todo_ids):
        todo = todo_by_id.get(todo_id)
        if not todo:
            raise ValueError(f"待办 {todo_id} 不属于当前项目")
        was_done = todo.status == "done"
        todo.status = "done"
        _sync_checklist_from_todo(db, todo)
        if not was_done:
            _spawn_next_recurrence(db, todo)
        if todo not in updated_todos:
            updated_todos.append(todo)

    for item_id in set(plan.completed_checklist_item_ids):
        item = checklist_by_id.get(item_id)
        if not item:
            raise ValueError(f"清单项 {item_id} 不属于当前项目")
        item.is_done = True
        todo = todo_by_id[item.todo_id]
        _sync_todo_from_checklist(db, todo)
        if todo not in updated_todos:
            updated_todos.append(todo)

    def resolve_todo(todo_id: int | None, todo_ref: str | None) -> ProjectTodo | None:
        if todo_id is not None:
            todo = todo_by_id.get(todo_id)
            if not todo:
                raise ValueError(f"待办 {todo_id} 不属于当前项目")
            return todo
        return todo_refs.get(todo_ref or "")

    for item in plan.todos:
        if item.action == "update":
            todo = resolve_todo(item.id, item.ref)
            if todo is None:
                raise ValueError(f"无法定位要更新的待办：{item.ref or item.id}")
            if item.title is not None:
                todo.title = item.title.strip() or todo.title
            if item.description is not None:
                todo.description = item.description
            if item.todo_type is not None:
                todo.todo_type = item.todo_type
            if item.phase is not None:
                _ensure_phase(db, project_id, item.phase)
                todo.phase = normalize_todo_phase(item.phase)
            if item.status is not None:
                if item.status == "done" and todo.status != "done":
                    _spawn_next_recurrence(db, todo)
                todo.status = item.status
                if item.status == "done":
                    _sync_checklist_from_todo(db, todo)
            if item.priority is not None:
                todo.priority = item.priority
            if item.start_at is not None:
                todo.start_at = item.start_at.replace(tzinfo=None)
            if item.due_at is not None:
                todo.due_at = item.due_at.replace(tzinfo=None)
            if item.checklist_items:
                _apply_agent_checklist_items(db, todo, item.checklist_items, checklist_by_id)
            if todo not in updated_todos:
                updated_todos.append(todo)
            if item.ref:
                todo_refs[item.ref] = todo
            continue

        title = (item.title or "").strip()
        if not title:
            raise ValueError("Agent 生成了没有标题的待办")
        phase = normalize_todo_phase(item.phase or plan.current_phase)
        _ensure_phase(db, project_id, phase)
        db_todo = ProjectTodo(
            project_id=project_id,
            title=title,
            description=item.description,
            todo_type=item.todo_type or "extra",
            phase=phase,
            status=item.status or "next",
            priority=item.priority or "normal",
            start_at=item.start_at.replace(tzinfo=None) if item.start_at else None,
            due_at=item.due_at.replace(tzinfo=None) if item.due_at else None,
            sort_order=_next_todo_sort_order(db, project_id, phase),
            source_text=source_text,
        )
        db.add(db_todo)
        db.flush()
        _add_checklist_items(
            db,
            db_todo.id,
            [
                ChecklistItemCreate(
                    title=check.title or "未命名清单项",
                    is_done=bool(check.is_done),
                    due_at=check.due_at.replace(tzinfo=None) if check.due_at else None,
                )
                for check in item.checklist_items
                if check.title and check.title.strip()
            ],
        )
        _sync_todo_from_checklist(db, db_todo)
        todo_by_id[db_todo.id] = db_todo
        created_todos.append(db_todo)
        if item.ref:
            todo_refs[item.ref] = db_todo

    if plan.current_phase:
        _ensure_phase(db, project_id, plan.current_phase)
        project.current_workflow_phase = normalize_todo_phase(plan.current_phase)
        # Once the agent has identified the active workflow phase, keep the
        # first unfinished item visible as the next working item unless the
        # plan explicitly changed its status already.
        phase_todos = [
            todo
            for todo in todo_by_id.values()
            if normalize_todo_phase(todo.phase) == normalize_todo_phase(plan.current_phase)
            and todo.status in {"next", "open", "in_progress"}
        ]
        phase_todos.sort(key=_todo_sort_key)
        if phase_todos and not any(
            todo.status == "in_progress" for todo in phase_todos
        ):
            phase_todos[0].status = "in_progress"
            if phase_todos[0] not in updated_todos and phase_todos[0] not in created_todos:
                updated_todos.append(phase_todos[0])

    for item in plan.meetings:
        if item.action == "update":
            meeting = meeting_by_id.get(item.id or -1)
            if meeting is None and item.ref:
                meeting = meeting_refs.get(item.ref)
            if not meeting:
                raise ValueError(f"无法定位要更新的会议：{item.ref or item.id}")
        else:
            if not (item.title or "").strip():
                raise ValueError("Agent 生成了没有标题的会议")
            meeting = ProjectMeeting(
                project_id=project_id,
                title=item.title.strip(),
                source_text=source_text,
            )
            db.add(meeting)
            db.flush()
            meeting_by_id[meeting.id] = meeting
            created_meetings.append(meeting)

        for field in ("title", "agenda", "meeting_url", "location", "attendees", "notes"):
            value = getattr(item, field)
            if value is not None:
                setattr(meeting, field, value)
        if item.starts_at is not None:
            meeting.starts_at = item.starts_at.replace(tzinfo=None)
        if item.ends_at is not None:
            meeting.ends_at = item.ends_at.replace(tzinfo=None)
        todo = resolve_todo(item.todo_id, item.todo_ref)
        if todo is None and item.action == "create":
            # A meeting without an explicit target still needs an actionable
            # home in the project, otherwise it is easy to miss in the task
            # workflow. Create a lightweight meeting follow-up automatically.
            follow_up_phase = normalize_todo_phase(plan.current_phase)
            _ensure_phase(db, project_id, follow_up_phase)
            todo = ProjectTodo(
                project_id=project_id,
                title=f"参加会议：{meeting.title}",
                description=meeting.agenda,
                todo_type="meeting",
                phase=follow_up_phase,
                status="next",
                priority="normal",
                due_at=meeting.starts_at.replace(tzinfo=None) if meeting.starts_at else None,
                sort_order=_next_todo_sort_order(db, project_id, follow_up_phase),
                source_text=source_text,
                meeting_id=meeting.id,
            )
            db.add(todo)
            db.flush()
            todo_by_id[todo.id] = todo
            created_todos.append(todo)
        if todo is not None:
            todo.meeting_id = meeting.id
            if todo not in updated_todos and todo not in created_todos:
                updated_todos.append(todo)
        if item.checklist_item_id is not None:
            checklist = checklist_by_id.get(item.checklist_item_id)
            if not checklist:
                raise ValueError(f"清单项 {item.checklist_item_id} 不属于当前项目")
            checklist.meeting_id = meeting.id

        if item.ref:
            meeting_refs[item.ref] = meeting
        if item.action == "update" and meeting not in updated_meetings:
            updated_meetings.append(meeting)

    _refresh_project_status(db, project_id)
    summary_lines = [plan.summary or "已更新项目安排"]
    if plan.current_phase:
        summary_lines.append(f"当前阶段：{plan.current_phase}")
    if plan.completed_todo_ids or plan.completed_checklist_item_ids:
        summary_lines.append(
            f"已完成待办 {len(set(plan.completed_todo_ids))} 项，"
            f"清单 {len(set(plan.completed_checklist_item_ids))} 项"
        )
    if created_todos:
        summary_lines.append(
            "新增待办：" + "、".join(todo.title for todo in created_todos)
        )
    if created_meetings:
        summary_lines.append(
            "新增会议：" + "、".join(meeting.title for meeting in created_meetings)
        )
    if plan.clarification:
        summary_lines.append(f"需要确认：{plan.clarification}")
    if fallback_used:
        summary_lines.append("当前使用本地规则完成解析。")
    assistant_content = "\n".join(summary_lines)
    details = {
        "intent": plan.intent,
        "current_phase": plan.current_phase,
        "completed_todo_ids": plan.completed_todo_ids,
        "completed_checklist_item_ids": plan.completed_checklist_item_ids,
        "created_todo_count": len(created_todos),
        "created_meeting_count": len(created_meetings),
    }
    db.add_all([
        ProjectAgentMessage(
            project_id=project_id,
            user_id=user_id,
            role="user",
            content=source_text,
        ),
        ProjectAgentMessage(
            project_id=project_id,
            user_id=user_id,
            role="assistant",
            content=assistant_content,
            model_used=model_used,
            fallback_used=fallback_used,
            details_json=json.dumps(details, ensure_ascii=False),
        ),
    ])
    db.commit()
    for item in (*created_todos, *updated_todos, *created_meetings, *updated_meetings):
        db.refresh(item)
    return {
        "project": project,
        "created_todos": created_todos,
        "updated_todos": updated_todos,
        "created_meetings": created_meetings,
        "updated_meetings": updated_meetings,
        "completed_todo_count": len(set(plan.completed_todo_ids)),
        "completed_checklist_count": len(set(plan.completed_checklist_item_ids)),
        "assistant_content": assistant_content,
    }


def _apply_agent_checklist_items(db, todo, items, checklist_by_id):
    for item in items:
        if item.id is not None:
            existing = checklist_by_id.get(item.id)
            if not existing or existing.todo_id != todo.id:
                raise ValueError(f"清单项 {item.id} 不属于目标待办")
            if item.title is not None:
                existing.title = item.title.strip() or existing.title
            if item.is_done is not None:
                existing.is_done = item.is_done
            if item.due_at is not None:
                existing.due_at = item.due_at.replace(tzinfo=None)
            continue
        if item.title and item.title.strip():
            _add_checklist_items(
                db,
                todo.id,
                [ChecklistItemCreate(
                    title=item.title.strip(),
                    is_done=bool(item.is_done),
                    due_at=item.due_at.replace(tzinfo=None) if item.due_at else None,
                )],
            )
    _sync_todo_from_checklist(db, todo)


def _parse_iso_datetime(value) -> Optional[datetime]:
    if not value:
        return None
    if isinstance(value, datetime):
        return value.replace(tzinfo=None) if value.tzinfo else value
    try:
        parsed = datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    except ValueError:
        return None
    return parsed.replace(tzinfo=None) if parsed.tzinfo else parsed


def normalize_parse_result(raw: dict, source_text: str) -> dict:
    intent = raw.get("intent") or "todo"
    meetings = raw.get("meetings") or []
    todos = raw.get("todos") or []
    fallback_start = _parse_due_at(source_text)
    fallback_end = _parse_end_at(source_text, fallback_start) if fallback_start else None
    has_time_range = bool(re.search(r"(?:-|~|至|到)\s*(凌晨|早上|上午|中午|下午|晚上|晚间)?\s*\d{1,2}(?::|：|点)", source_text))
    for meeting in meetings:
        meeting.setdefault("title", "项目会议")
        meeting.setdefault("source_text", source_text)
        parsed_start = _parse_iso_datetime(meeting.get("starts_at"))
        parsed_end = _parse_iso_datetime(meeting.get("ends_at"))
        bad_range = parsed_start and parsed_end and parsed_end <= parsed_start
        suspicious_start = parsed_start and parsed_start.minute == 59 and has_time_range
        if fallback_start and (not parsed_start or bad_range or suspicious_start or has_time_range):
            meeting["starts_at"] = fallback_start.isoformat()
        if fallback_end and (not parsed_end or bad_range or has_time_range):
            meeting["ends_at"] = fallback_end.isoformat()
    for todo in todos:
        todo.setdefault("title", "项目待办")
        todo.setdefault("todo_type", "extra")
        todo.setdefault("priority", "normal")
        todo.setdefault("status", "next")
        todo.setdefault("source_text", source_text)
    return {"intent": intent, "meetings": meetings, "todos": todos}


def safe_json_loads(text: str) -> Optional[dict]:
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        match = re.search(r"\{.*\}", text, re.S)
        if match:
            try:
                return json.loads(match.group(0))
            except json.JSONDecodeError:
                return None
    return None
