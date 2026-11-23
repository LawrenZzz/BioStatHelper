"""GTD query layer for the BioStatHelper 今日工作台.

Mindwtr's task-management model maps onto the existing clinical ProjectTodo:
a project is a GTD project, a todo is a GTD task, and the hidden inbox
pseudo-project holds unprocessed captures. This module exposes the GTD views
(inbox, focus/next-actions, waiting, someday, weekly review) as lightweight
dicts so the endpoint layer does not need schema churn.

Everything is scoped to a single user (owner_id), since the app is a personal
biostatistician workbench rather than a shared team tool.
"""
import base64
import json
from datetime import date, datetime, timedelta
from typing import List, Optional

from sqlalchemy import func, or_
from sqlalchemy.orm import Session

from app.models.models import (
    Note,
    Project,
    ProjectAgentMessage,
    ProjectMeeting,
    ProjectMember,
    ProjectPhase,
    ProjectTimelineImport,
    ProjectTimelineItem,
    ProjectTodo,
    ProjectTodoChecklistItem,
    SavedFilter,
    TaskAttachment,
)
from app.crud.project import (
    GTD_ACTIVE,
    GTD_CLOSED,
    GTD_DONE,
    GTD_SOMEDAY,
    GTD_INBOX,
    inbox_project,
)


WEEKLY_REVIEW_DAYS = 7

# Attachment size caps mirrored from the upload endpoint. A GTD export never
# contains a larger attachment (uploads are capped), so a longer base64 blob in
# an import can only be hostile or corrupt.
MAX_ATTACHMENT_BYTES = 20 * 1024 * 1024
# Upper bound for the whole /import request body (guarded at the endpoint by
# Content-Length; bounded here as a backstop).
MAX_IMPORT_BYTES = 200 * 1024 * 1024


def _serialize_contexts(value: Optional[str]) -> List[str]:
    if not value:
        return []
    try:
        parsed = json.loads(value)
        return parsed if isinstance(parsed, list) else []
    except (ValueError, TypeError):
        return []


def _todo_dto(todo: ProjectTodo) -> dict:
    return {
        "todo_id": todo.id,
        "title": todo.title,
        "description": todo.description,
        "project_id": todo.project_id,
        "project_name": todo.project.name if todo.project else None,
        "project_is_inbox": bool(todo.project and todo.project.is_inbox),
        "status": todo.status,
        "priority": todo.priority,
        "phase": todo.phase,
        "start_at": todo.start_at.isoformat() if todo.start_at else None,
        "due_at": todo.due_at.isoformat() if todo.due_at else None,
        "is_focused_today": bool(todo.is_focused_today),
        "contexts": _serialize_contexts(todo.contexts),
        "tags": _serialize_contexts(todo.tags),
        "area": todo.area,
        "energy_level": todo.energy_level,
        "time_estimate": todo.time_estimate,
        "recurrence": todo.recurrence,
        "completed_at": todo.completed_at.isoformat() if todo.completed_at else None,
        "cancelled_at": todo.cancelled_at.isoformat() if todo.cancelled_at else None,
    }


def _user_todo_query(db: Session, user_id: int):
    return (
        db.query(ProjectTodo)
        .join(Project, Project.id == ProjectTodo.project_id)
        .filter(Project.owner_id == user_id)
    )


def get_inbox_project(db: Session, user_id: int) -> Project:
    return inbox_project(db, user_id)


def create_inbox_task(
    db: Session,
    user_id: int,
    title: str,
    description: Optional[str] = None,
    due_at: Optional[datetime] = None,
) -> dict:
    """Capture a raw item into the inbox pseudo-project."""
    title = (title or "").strip()
    if not title:
        raise ValueError("标题不能为空")
    inbox = inbox_project(db, user_id)
    todo = ProjectTodo(
        project_id=inbox.id,
        title=title[:300],
        description=description,
        todo_type="extra",
        phase="收件箱",
        status="inbox",
        priority="normal",
        due_at=due_at,
    )
    db.add(todo)
    db.commit()
    db.refresh(todo)
    return _todo_dto(todo)


def list_inbox(db: Session, user_id: int) -> List[dict]:
    todos = (
        _user_todo_query(db, user_id)
        .filter(ProjectTodo.status.in_(GTD_INBOX))
        .order_by(ProjectTodo.created_at.asc(), ProjectTodo.id.asc())
        .all()
    )
    return [_todo_dto(todo) for todo in todos]


def process_inbox_task(
    db: Session,
    user_id: int,
    todo_id: int,
    *,
    action: str = "next",
    project_id: Optional[int] = None,
    phase: Optional[str] = None,
    title: Optional[str] = None,
    due_at: Optional[datetime] = None,
    is_focused_today: Optional[bool] = None,
) -> Optional[dict]:
    """Move an inbox item into the GTD workflow.

    action maps to a target status:
      next      -> a concrete next action (default, may move to a real project)
      waiting   -> wait for someone else
      someday   -> park for later
      reference -> store as reference (no action)
      done      -> complete immediately
    """
    todo = _user_todo_query(db, user_id).filter(ProjectTodo.id == todo_id).first()
    if not todo:
        return None

    action = (action or "next").lower()
    was_done = todo.status == "done"
    if action == "done":
        todo.status = "done"
        todo.completed_at = todo.completed_at or datetime.now()
    elif action == "waiting":
        todo.status = "waiting"
    elif action == "someday":
        todo.status = "someday"
    elif action == "reference":
        todo.status = "reference"
    else:
        todo.status = "next"

    # Only the inbox items may be reparented into a real project during
    # processing. Guard against moving into the inbox itself.
    if project_id and project_id != todo.project_id:
        target = db.query(Project).filter(
            Project.id == project_id,
            Project.owner_id == user_id,
            Project.is_inbox == False,  # noqa: E712
        ).first()
        if target:
            todo.project_id = project_id
            if phase:
                from app.crud.project import _ensure_phase, normalize_todo_phase

                _ensure_phase(db, project_id, phase)
                todo.phase = normalize_todo_phase(phase)
            else:
                todo.phase = "流程待办"

    if title is not None and title.strip():
        todo.title = title.strip()[:300]
    if due_at is not None:
        todo.due_at = due_at
    if is_focused_today is not None:
        todo.is_focused_today = bool(is_focused_today)

    if action == "done" and not was_done:
        from app.crud.project import _spawn_next_recurrence

        _spawn_next_recurrence(db, todo)

    db.commit()
    db.refresh(todo)
    return _todo_dto(todo)


def focus_tasks(db: Session, user_id: int, on_date: Optional[date] = None) -> List[dict]:
    """Tasks on today's Focus list: flagged is_focused_today OR due/starting
    on or before the given date. This is the core "just do it now" surface."""
    on_date = on_date or date.today()
    day_start = datetime.combine(on_date, datetime.min.time())
    todos = (
        _user_todo_query(db, user_id)
        .filter(
            ProjectTodo.status.in_(GTD_ACTIVE),
            (
                ProjectTodo.is_focused_today == True  # noqa: E712
            ) | (
                ProjectTodo.due_at <= day_start
            ) | (
                ProjectTodo.start_at <= day_start
            ),
        )
        .order_by(ProjectTodo.is_focused_today.desc(), ProjectTodo.due_at.asc().nulls_last(), ProjectTodo.id.asc())
        .all()
    )
    return [_todo_dto(todo) for todo in todos]


def next_actions(db: Session, user_id: int) -> List[dict]:
    """Concrete next actions not bound to a date: status next/blocked/in_progress."""
    todos = (
        _user_todo_query(db, user_id)
        .filter(ProjectTodo.status.in_({"next", "open", "in_progress", "blocked"}))
        .order_by(ProjectTodo.is_focused_today.desc(), ProjectTodo.priority.desc(), ProjectTodo.id.asc())
        .all()
    )
    return [_todo_dto(todo) for todo in todos]


def list_waiting(db: Session, user_id: int) -> List[dict]:
    todos = (
        _user_todo_query(db, user_id)
        .filter(ProjectTodo.status == "waiting")
        .order_by(ProjectTodo.due_at.asc().nulls_last(), ProjectTodo.id.asc())
        .all()
    )
    return [_todo_dto(todo) for todo in todos]


def list_someday(db: Session, user_id: int) -> List[dict]:
    todos = (
        _user_todo_query(db, user_id)
        .filter(ProjectTodo.status.in_(GTD_SOMEDAY))
        .order_by(ProjectTodo.updated_at.desc(), ProjectTodo.id.asc())
        .all()
    )
    return [_todo_dto(todo) for todo in todos]


def calendar_tasks(
    db: Session,
    user_id: int,
    range_start: datetime,
    range_end: datetime,
) -> List[dict]:
    """Active tasks with a due date in [range_start, range_end].

    Recurring tasks are expanded into every occurrence that falls inside the
    range (each occurrence carries its own ``occurrence_due_at``), so a monthly
    task created long ago still shows up on each due day in the view."""
    from app.services.recurrence import occurrences_in_range

    todos = (
        _user_todo_query(db, user_id)
        .filter(ProjectTodo.status.in_(GTD_ACTIVE), ProjectTodo.due_at.isnot(None))
        .filter(ProjectTodo.due_at <= range_end)
        .all()
    )
    results: List[dict] = []
    for todo in todos:
        base = todo.due_at
        if base is None:
            continue
        if todo.recurrence:
            for occurrence in occurrences_in_range(base, todo.recurrence, range_start, range_end):
                dto = _todo_dto(todo)
                dto["occurrence_due_at"] = occurrence.isoformat()
                results.append(dto)
        elif range_start <= base <= range_end:
            dto = _todo_dto(todo)
            dto["occurrence_due_at"] = base.isoformat()
            results.append(dto)
    results.sort(key=lambda row: row["occurrence_due_at"])
    return results


def _escape_like(value: str) -> str:
    """Escape SQL LIKE wildcards so user input is matched literally.

    ``%`` and ``_`` are wildcards inside LIKE patterns; without escaping a
    search for ``SAS_analysis`` or ``@h`` would broaden to unrelated rows. This
    only affects pattern semantics (values are still bound, never injected)."""
    return (
        value.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")
    )


def query_tasks(
    db: Session,
    user_id: int,
    status: Optional[str] = None,
    project_id: Optional[int] = None,
    q: Optional[str] = None,
    contexts: Optional[List[str]] = None,
    tags: Optional[List[str]] = None,
    area: Optional[str] = None,
    priority: Optional[str] = None,
    is_focused_today: Optional[bool] = None,
    limit: int = 200,
) -> List[dict]:
    """Generic scoped task query for saved filters / global search.

    ``contexts`` / ``tags`` match rows whose stored JSON array contains *any*
    of the given values (an OR within a dimension). ``q`` matches the title,
    description or phase text case-insensitively."""
    query = _user_todo_query(db, user_id)
    if status:
        query = query.filter(ProjectTodo.status == status)
    if project_id:
        query = query.filter(ProjectTodo.project_id == project_id)
    if priority:
        query = query.filter(ProjectTodo.priority == priority)
    if area:
        query = query.filter(ProjectTodo.area == area)
    if is_focused_today is not None:
        query = query.filter(ProjectTodo.is_focused_today == is_focused_today)
    if q and q.strip():
        needle = f"%{_escape_like(q.strip().lower())}%"
        query = query.filter(
            or_(
                func.lower(ProjectTodo.title).like(needle, escape="\\"),
                func.lower(ProjectTodo.description).like(needle, escape="\\"),
                func.lower(ProjectTodo.phase).like(needle, escape="\\"),
            )
        )
    if contexts:
        query = query.filter(
            or_(*[ProjectTodo.contexts.like(f"%{_escape_like(c)}%", escape="\\") for c in contexts])
        )
    if tags:
        query = query.filter(
            or_(*[ProjectTodo.tags.like(f"%{_escape_like(tag)}%", escape="\\") for tag in tags])
        )
    todos = (
        query.order_by(ProjectTodo.updated_at.desc(), ProjectTodo.id.asc())
        .limit(limit)
        .all()
    )
    return [_todo_dto(todo) for todo in todos]


def list_contexts(db: Session, user_id: int) -> dict:
    """GTD contexts grouped by kind: ``people`` (@人, seeded from project
    members) and ``places`` (@地点, collected from task context chips minus
    any member names). New places are added implicitly when a task is edited
    with a context chip, so this surface is a read-mostly directory."""
    from app.models.models import ProjectMember

    member_names = [
        row[0]
        for row in db.query(ProjectMember.name)
        .join(Project, Project.id == ProjectMember.project_id)
        .filter(
            Project.owner_id == user_id,
            ProjectMember.name.isnot(None),
        )
        .all()
    ]
    people = sorted({f"@{name}" for name in member_names if name and name.strip()})
    contexts: set[str] = set()
    rows = (
        db.query(ProjectTodo.contexts)
        .join(Project, Project.id == ProjectTodo.project_id)
        .filter(Project.owner_id == user_id)
        .all()
    )
    for (raw,) in rows:
        contexts.update(_parse_contexts(raw))
    places = sorted({c for c in contexts if c not in people})
    return {"people": people, "places": places}


# --- saved filters ---------------------------------------------------------


def _saved_filter_dto(filter_row: SavedFilter) -> dict:
    criteria: dict = {}
    if filter_row.criteria:
        try:
            parsed = json.loads(filter_row.criteria)
            if isinstance(parsed, dict):
                criteria = parsed
        except (ValueError, TypeError):
            criteria = {}
    return {
        "id": filter_row.id,
        "name": filter_row.name,
        "criteria": criteria,
    }


def list_saved_filters(db: Session, user_id: int) -> List[dict]:
    rows = (
        db.query(SavedFilter)
        .filter(SavedFilter.user_id == user_id)
        .order_by(SavedFilter.created_at.desc(), SavedFilter.id.asc())
        .all()
    )
    return [_saved_filter_dto(row) for row in rows]


def create_saved_filter(
    db: Session,
    user_id: int,
    name: str,
    criteria: Optional[dict],
) -> dict:
    name = (name or "").strip()
    if not name:
        raise ValueError("筛选名称不能为空")
    row = SavedFilter(
        user_id=user_id,
        name=name[:100],
        criteria=json.dumps(criteria or {}, ensure_ascii=False),
    )
    db.add(row)
    db.commit()
    db.refresh(row)
    return _saved_filter_dto(row)


def delete_saved_filter(db: Session, user_id: int, filter_id: int) -> bool:
    row = (
        db.query(SavedFilter)
        .filter(SavedFilter.id == filter_id, SavedFilter.user_id == user_id)
        .first()
    )
    if not row:
        return False
    db.delete(row)
    db.commit()
    return True


# --- task notes (reference/capture) ---------------------------------------


def _require_user_todo(db: Session, user_id: int, todo_id: int) -> Optional[ProjectTodo]:
    return (
        _user_todo_query(db, user_id).filter(ProjectTodo.id == todo_id).first()
    )


def _task_note_dto(note: Note) -> dict:
    return {
        "id": note.id,
        "title": note.title,
        "content": note.content,
        "created_at": note.created_at.isoformat() if note.created_at else None,
        "updated_at": note.updated_at.isoformat() if note.updated_at else None,
    }


def task_notes(db: Session, user_id: int, todo_id: int) -> Optional[List[dict]]:
    if not _require_user_todo(db, user_id, todo_id):
        return None
    rows = (
        db.query(Note)
        .filter(Note.task_id == todo_id, Note.user_id == user_id)
        .order_by(Note.created_at.desc(), Note.id.asc())
        .all()
    )
    return [_task_note_dto(row) for row in rows]


def create_task_note(
    db: Session,
    user_id: int,
    todo_id: int,
    title: str,
    content: str,
) -> Optional[dict]:
    if not _require_user_todo(db, user_id, todo_id):
        return None
    title = (title or "").strip() or "未命名笔记"
    note = Note(
        user_id=user_id,
        task_id=todo_id,
        title=title[:200],
        content=content or "",
    )
    db.add(note)
    db.commit()
    db.refresh(note)
    return _task_note_dto(note)


def delete_task_note(db: Session, user_id: int, note_id: int) -> bool:
    note = (
        db.query(Note)
        .filter(Note.id == note_id, Note.task_id.isnot(None), Note.user_id == user_id)
        .first()
    )
    if not note:
        return False
    db.delete(note)
    db.commit()
    return True


# --- task attachments ------------------------------------------------------


def _task_attachment_dto(row: TaskAttachment, include_content: bool = False) -> dict:
    dto = {
        "id": row.id,
        "task_id": row.task_id,
        "filename": row.filename,
        "content_type": row.content_type,
        "size_bytes": row.size_bytes,
        "created_at": row.created_at.isoformat() if row.created_at else None,
    }
    if include_content:
        dto["content"] = row.content
    return dto


def task_attachments(db: Session, user_id: int, todo_id: int) -> Optional[List[dict]]:
    if not _require_user_todo(db, user_id, todo_id):
        return None
    rows = (
        db.query(TaskAttachment)
        .filter(TaskAttachment.task_id == todo_id, TaskAttachment.user_id == user_id)
        .order_by(TaskAttachment.created_at.desc(), TaskAttachment.id.asc())
        .all()
    )
    return [_task_attachment_dto(row) for row in rows]


def create_task_attachment(
    db: Session,
    user_id: int,
    todo_id: int,
    filename: str,
    content: bytes,
    content_type: Optional[str] = None,
    max_bytes: int = 20 * 1024 * 1024,
) -> Optional[dict]:
    if not _require_user_todo(db, user_id, todo_id):
        return None
    if len(content) > max_bytes:
        raise ValueError(f"附件不能超过 {max_bytes // (1024 * 1024)}MB")
    row = TaskAttachment(
        task_id=todo_id,
        user_id=user_id,
        filename=(filename or "file").strip()[:255] or "file",
        content_type=content_type,
        size_bytes=len(content),
        content=content,
    )
    db.add(row)
    db.commit()
    db.refresh(row)
    return _task_attachment_dto(row)


def get_task_attachment(db: Session, user_id: int, attachment_id: int) -> Optional[TaskAttachment]:
    return (
        db.query(TaskAttachment)
        .filter(TaskAttachment.id == attachment_id, TaskAttachment.user_id == user_id)
        .first()
    )


def delete_task_attachment(db: Session, user_id: int, attachment_id: int) -> bool:
    row = (
        db.query(TaskAttachment)
        .filter(TaskAttachment.id == attachment_id, TaskAttachment.user_id == user_id)
        .first()
    )
    if not row:
        return False
    db.delete(row)
    db.commit()
    return True


def toggle_focus(db: Session, user_id: int, todo_id: int) -> Optional[dict]:
    todo = _user_todo_query(db, user_id).filter(ProjectTodo.id == todo_id).first()
    if not todo:
        return None
    todo.is_focused_today = not todo.is_focused_today
    db.commit()
    db.refresh(todo)
    return _todo_dto(todo)


def _parse_contexts(value) -> List[str]:
    if isinstance(value, list):
        return value
    if isinstance(value, str):
        try:
            parsed = json.loads(value)
            return parsed if isinstance(parsed, list) else []
        except (ValueError, TypeError):
            return []
    return []


def review_status(db: Session, user_id: int) -> dict:
    """Weekly review availability: due when it has never run or it ran 7+ days ago."""
    from app.models.models import UserSetting

    row = db.query(UserSetting).filter(UserSetting.user_id == user_id).first()
    last = row.weekly_review_at if row else None
    due = True
    if last is not None:
        due = (datetime.now() - last) >= timedelta(days=WEEKLY_REVIEW_DAYS)
    return {
        "due": due,
        "last_review_at": last.isoformat() if last else None,
        "weekly_review_days": WEEKLY_REVIEW_DAYS,
    }


def _update_review_timestamp(db: Session, user_id: int) -> None:
    from app.models.models import UserSetting

    row = db.query(UserSetting).filter(UserSetting.user_id == user_id).first()
    if row:
        row.weekly_review_at = datetime.now()
        db.commit()


def weekly_review(db: Session, user_id: int) -> dict:
    """Compile the GTD weekly review digest.

    Period counters + the two signals that matter most to a biostatistician:
      - stale_open: tasks whose checklist is 100% done but status is not done
        (the classic "I finished but forgot to update status"), plus tasks that
        are past due but still sitting in next/in_progress.
      - needs_review: real projects carrying stale_open tasks.
    """
    week_start = datetime.combine(
        date.today() - timedelta(days=date.today().weekday()),
        datetime.min.time(),
    )
    base = _user_todo_query(db, user_id)

    completed_todos = base.filter(
        ProjectTodo.status.in_(GTD_DONE),
        ProjectTodo.completed_at >= week_start,
    ).count()

    checklist_done = db.query(ProjectTodo).join(Project, Project.id == ProjectTodo.project_id).filter(
        Project.owner_id == user_id,
        ProjectTodo.status.in_(GTD_DONE),
        ProjectTodo.completed_at >= week_start,
    ).count()

    inbox_count = base.filter(ProjectTodo.status.in_(GTD_INBOX)).count()
    next_count = base.filter(ProjectTodo.status.in_({"next", "open"})).count()
    waiting_count = base.filter(ProjectTodo.status == "waiting").count()
    someday_count = base.filter(ProjectTodo.status.in_(GTD_SOMEDAY)).count()

    now = datetime.now()
    todos = base.filter(ProjectTodo.status.in_(GTD_ACTIVE | GTD_DONE)).all()

    stale_open: List[dict] = []
    project_ids = set()
    from app.models.models import ProjectTodoChecklistItem

    for todo in todos:
        item_rows = db.query(ProjectTodoChecklistItem).filter(
            ProjectTodoChecklistItem.todo_id == todo.id
        ).all()
        checklist_full = bool(item_rows) and all(item.is_done for item in item_rows)
        overdue = todo.due_at is not None and todo.due_at < now and todo.status in {"next", "open", "in_progress"}
        if checklist_full and todo.status not in GTD_DONE:
            # 100% checklist but not marked done => user forgot to update status.
            stale_open.append({
                "todo_id": todo.id,
                "title": todo.title,
                "project_id": todo.project_id,
                "project_name": todo.project.name if todo.project else None,
                "reason": "checklist_done",
            })
            project_ids.add(todo.project_id)
        elif overdue:
            stale_open.append({
                "todo_id": todo.id,
                "title": todo.title,
                "project_id": todo.project_id,
                "project_name": todo.project.name if todo.project else None,
                "reason": "overdue",
                "due_at": todo.due_at.isoformat() if todo.due_at else None,
            })
            project_ids.add(todo.project_id)

    # Mark the review as run so the prompt clears until next week.
    _update_review_timestamp(db, user_id)

    return {
        "period_start": week_start.isoformat(),
        "period_end": datetime.now().isoformat(),
        "counts": {
            "completed_todos": completed_todos,
            "completed_checklist_items": checklist_done,
            "inbox": inbox_count,
            "next": next_count,
            "waiting": waiting_count,
            "someday": someday_count,
        },
        "stale_open": stale_open,
        "needs_review": [
            {"project_id": pid, "project_name": db.query(Project).filter(Project.id == pid).first().name}
            for pid in project_ids
        ],
    }


# --- import / export backup -------------------------------------------------
#
# A versioned, single-user JSON backup of the GTD workspace. It deliberately
# covers the GTD-facing surface (saved filters, inbox, real projects with their
# phases/members/todos, plus per-task checklist/notes/attachments) and skips the
# meeting agenda and timeline-import records, which are clinical-workflow detail
# rather than task-management state. Attachment content is embedded as base64 so
# the whole backup is one self-contained JSON document.


BACKUP_APP = "biostat-helper"
BACKUP_KIND = "gtd-backup"
BACKUP_VERSION = 1

_EXPORTED_TODO_FIELDS = (
    "title", "description", "todo_type", "phase", "status", "priority",
    "start_at", "due_at", "sort_order", "source_text", "contexts", "tags",
    "area", "energy_level", "time_estimate", "is_focused_today", "review_at",
    "completed_at", "cancelled_at", "recurrence",
)


def _iso(value) -> Optional[str]:
    return value.isoformat() if value else None


def _export_todo(db: Session, user_id: int, todo: ProjectTodo) -> dict:
    data = {field: getattr(todo, field) for field in _EXPORTED_TODO_FIELDS}
    # Normalize the DB JSON strings back to lists and datetimes to ISO strings.
    data["contexts"] = _serialize_contexts(todo.contexts)
    data["tags"] = _serialize_contexts(todo.tags)
    for field in ("start_at", "due_at", "review_at", "completed_at", "cancelled_at"):
        data[field] = _iso(getattr(todo, field))

    checklist = (
        db.query(ProjectTodoChecklistItem)
        .filter(ProjectTodoChecklistItem.todo_id == todo.id)
        .order_by(ProjectTodoChecklistItem.sort_order.asc(), ProjectTodoChecklistItem.id.asc())
        .all()
    )
    data["checklist"] = [
        {
            "title": item.title,
            "is_done": bool(item.is_done),
            "due_at": _iso(item.due_at),
            "sort_order": item.sort_order,
        }
        for item in checklist
    ]

    notes = (
        db.query(Note)
        .filter(Note.task_id == todo.id, Note.user_id == user_id)
        .order_by(Note.created_at.asc(), Note.id.asc())
        .all()
    )
    data["notes"] = [{"title": n.title, "content": n.content} for n in notes]

    attachments = (
        db.query(TaskAttachment)
        .filter(TaskAttachment.task_id == todo.id, TaskAttachment.user_id == user_id)
        .order_by(TaskAttachment.created_at.asc(), TaskAttachment.id.asc())
        .all()
    )
    data["attachments"] = [
        {
            "filename": a.filename,
            "content_type": a.content_type,
            "content_base64": base64.b64encode(a.content or b"").decode("ascii"),
        }
        for a in attachments
    ]
    return data


def export_all(db: Session, user_id: int) -> dict:
    """Snapshot the user's whole GTD workspace as a single JSON document."""
    doc = {
        "app": BACKUP_APP,
        "kind": BACKUP_KIND,
        "version": BACKUP_VERSION,
        "exported_at": datetime.now().isoformat(),
        "saved_filters": [
            _saved_filter_dto(row) for row in
            db.query(SavedFilter).filter(SavedFilter.user_id == user_id)
            .order_by(SavedFilter.created_at.asc(), SavedFilter.id.asc()).all()
        ],
        "inbox": [],
        "projects": [],
    }

    inbox = inbox_project(db, user_id)
    inbox_todos = (
        db.query(ProjectTodo)
        .filter(ProjectTodo.project_id == inbox.id)
        .order_by(ProjectTodo.created_at.asc(), ProjectTodo.id.asc())
        .all()
    )
    doc["inbox"] = [_export_todo(db, user_id, todo) for todo in inbox_todos]

    projects = (
        db.query(Project)
        .filter(Project.owner_id == user_id, Project.is_inbox == False)  # noqa: E712
        .order_by(Project.created_at.asc(), Project.id.asc())
        .all()
    )
    for project in projects:
        phases = (
            db.query(ProjectPhase).filter(ProjectPhase.project_id == project.id)
            .order_by(ProjectPhase.sort_order.asc(), ProjectPhase.id.asc()).all()
        )
        members = (
            db.query(ProjectMember).filter(ProjectMember.project_id == project.id)
            .order_by(ProjectMember.sort_order.asc(), ProjectMember.id.asc()).all()
        )
        todos = (
            db.query(ProjectTodo).filter(ProjectTodo.project_id == project.id)
            .order_by(ProjectTodo.sort_order.asc(), ProjectTodo.id.asc()).all()
        )
        doc["projects"].append({
            "name": project.name,
            "sponsor": project.sponsor,
            "protocol_no": project.protocol_no,
            "phase": project.phase,
            "current_workflow_phase": project.current_workflow_phase,
            "project_type": project.project_type,
            "is_cdisc": bool(project.is_cdisc),
            "indication": project.indication,
            "description": project.description,
            "status": project.status,
            "review_at": _iso(project.review_at),
            "is_focused": bool(project.is_focused),
            "phases": [
                {"name": p.name, "sort_order": p.sort_order} for p in phases
            ],
            "members": [
                {
                    "member_type": m.member_type,
                    "name": m.name,
                    "organization": m.organization,
                    "role": m.role,
                    "email": m.email,
                    "phone": m.phone,
                    "notes": m.notes,
                    "sort_order": m.sort_order,
                }
                for m in members
            ],
            "todos": [_export_todo(db, user_id, todo) for todo in todos],
        })
    return doc


def _as_int(value, default: int = 0) -> int:
    """Coerce a JSON value to int defensively; never raises on bad input."""
    if isinstance(value, bool):
        return default
    if isinstance(value, int):
        return value
    if isinstance(value, (float, str)):
        try:
            return int(value)
        except (ValueError, TypeError):
            return default
    return default


# Per-record caps applied during import so one hostile backup cannot force
# unbounded memory / DB-write amplification through a single small todo.
MAX_TODO_CHILDREN = 500        # checklist items per todo
MAX_TODO_NOTES = 200           # reference notes per todo
MAX_TODO_ATTACHMENTS = 200     # attachments per todo
MAX_TAG_LIST = 50              # contexts/tags per todo
MAX_TAG_LEN = 100              # characters per context/tag


def _validate_doc_shape(doc: dict) -> None:
    """Reject structurally malformed/foreign backups before any DB write so a
    bad document fails with a clear 400 instead of an unhandled 500."""
    for key in ("saved_filters", "inbox", "projects"):
        value = doc.get(key)
        if value is None:
            continue
        if not isinstance(value, list):
            raise ValueError(f"备份字段 {key} 格式不正确")
        for item in value:
            if not isinstance(item, dict):
                raise ValueError(f"备份字段 {key} 中包含无效记录")


def _delete_todo_tree(db: Session, project_id: int) -> None:
    """Delete a project's todos plus their checklist children (checklist rows
    hold a hard FK to project_todos, so they must go first). Does not commit."""
    todo_ids = [
        t for (t,) in db.query(ProjectTodo.id)
        .filter(ProjectTodo.project_id == project_id).all()
    ]
    if todo_ids:
        db.query(ProjectTodoChecklistItem).filter(
            ProjectTodoChecklistItem.todo_id.in_(todo_ids)
        ).delete(synchronize_session=False)
    db.query(ProjectTodo).filter(ProjectTodo.project_id == project_id) \
        .delete(synchronize_session=False)


def _delete_project_rows(db: Session, project_id: int) -> None:
    """Delete a project's child rows in FK-safe order (mirrors delete_project)
    without committing, so a replace-import stays one atomic transaction."""
    timeline_ids = [
        i for (i,) in db.query(ProjectTimelineImport.id)
        .filter(ProjectTimelineImport.project_id == project_id).all()
    ]
    if timeline_ids:
        db.query(ProjectTimelineItem).filter(
            ProjectTimelineItem.timeline_import_id.in_(timeline_ids)
        ).delete(synchronize_session=False)
    db.query(ProjectTimelineImport).filter(
        ProjectTimelineImport.project_id == project_id
    ).delete(synchronize_session=False)
    db.query(ProjectMember).filter(ProjectMember.project_id == project_id) \
        .delete(synchronize_session=False)
    _delete_todo_tree(db, project_id)
    db.query(ProjectMeeting).filter(ProjectMeeting.project_id == project_id) \
        .delete(synchronize_session=False)
    db.query(ProjectPhase).filter(ProjectPhase.project_id == project_id) \
        .delete(synchronize_session=False)
    db.query(ProjectAgentMessage).filter(ProjectAgentMessage.project_id == project_id) \
        .delete(synchronize_session=False)
    db.query(Project).filter(Project.id == project_id) \
        .delete(synchronize_session=False)


def _wipe_user_gtd(db: Session, user_id: int, inbox_id: int) -> None:
    """Delete all of a user's GTD data in FK-safe order without committing. The
    inbox pseudo-project row itself is kept (only its todos are removed)."""
    # Task-scoped notes/attachments reference todos; remove them first.
    db.query(Note).filter(Note.user_id == user_id, Note.task_id.isnot(None)) \
        .delete(synchronize_session=False)
    db.query(TaskAttachment).filter(TaskAttachment.user_id == user_id) \
        .delete(synchronize_session=False)
    db.query(SavedFilter).filter(SavedFilter.user_id == user_id) \
        .delete(synchronize_session=False)
    for (pid,) in db.query(Project.id).filter(
        Project.owner_id == user_id, Project.is_inbox == False  # noqa: E712
    ).all():
        _delete_project_rows(db, pid)
    _delete_todo_tree(db, inbox_id)


def _build_project(db: Session, user_id: int, p: dict) -> Project:
    project = Project(
        name=str(p.get("name") or "未命名项目")[:200],
        sponsor=p.get("sponsor"),
        protocol_no=p.get("protocol_no"),
        phase=p.get("phase"),
        current_workflow_phase=p.get("current_workflow_phase"),
        project_type=p.get("project_type") or "other",
        is_cdisc=bool(p.get("is_cdisc")),
        indication=p.get("indication"),
        description=p.get("description"),
        status=p.get("status") or "active",
        review_at=_parse_dt_value(p.get("review_at")),
        is_focused=bool(p.get("is_focused")),
        owner_id=user_id,
        is_inbox=False,
    )
    db.add(project)
    db.flush()
    for idx, ph in enumerate(p.get("phases") or []):
        db.add(ProjectPhase(
            project_id=project.id,
            name=str(ph.get("name") or "阶段")[:100],
            sort_order=_as_int(ph.get("sort_order"), idx),
        ))
    for idx, m in enumerate(p.get("members") or []):
        db.add(ProjectMember(
            project_id=project.id,
            member_type=str(m.get("member_type") or "other")[:30],
            name=str(m.get("name") or "")[:200],
            organization=m.get("organization"),
            role=m.get("role"),
            email=m.get("email"),
            phone=m.get("phone"),
            notes=m.get("notes"),
            sort_order=_as_int(m.get("sort_order"), idx),
        ))
    return project


def _build_todo(db: Session, user_id: int, project_id: int, t: dict, skipped: Optional[dict] = None) -> ProjectTodo:
    skipped = skipped if skipped is not None else {}
    contexts = [c[:MAX_TAG_LEN] for c in (t.get("contexts") or []) if isinstance(c, str)][:MAX_TAG_LIST]
    tags = [tg[:MAX_TAG_LEN] for tg in (t.get("tags") or []) if isinstance(tg, str)][:MAX_TAG_LIST]
    todo = ProjectTodo(
        project_id=project_id,
        title=str(t.get("title") or "未命名任务")[:300],
        description=t.get("description"),
        todo_type=t.get("todo_type") or "extra",
        phase=t.get("phase"),
        status=t.get("status") or "next",
        priority=t.get("priority") or "normal",
        start_at=_parse_dt_value(t.get("start_at")),
        due_at=_parse_dt_value(t.get("due_at")),
        sort_order=_as_int(t.get("sort_order"), 0),
        source_text=t.get("source_text"),
        contexts=json.dumps([c for c in contexts if isinstance(c, str)], ensure_ascii=False) if contexts else None,
        tags=json.dumps([tg for tg in tags if isinstance(tg, str)], ensure_ascii=False) if tags else None,
        area=t.get("area"),
        energy_level=t.get("energy_level"),
        time_estimate=t.get("time_estimate"),
        is_focused_today=bool(t.get("is_focused_today")),
        review_at=_parse_dt_value(t.get("review_at")),
        completed_at=_parse_dt_value(t.get("completed_at")),
        cancelled_at=_parse_dt_value(t.get("cancelled_at")),
        recurrence=t.get("recurrence"),
    )
    db.add(todo)
    db.flush()

    for idx, item in enumerate((t.get("checklist") or [])[:MAX_TODO_CHILDREN]):
        if not isinstance(item, dict):
            continue
        db.add(ProjectTodoChecklistItem(
            todo_id=todo.id,
            title=str(item.get("title") or "")[:300],
            is_done=bool(item.get("is_done")),
            due_at=_parse_dt_value(item.get("due_at")),
            sort_order=_as_int(item.get("sort_order"), idx),
        ))
    for note in (t.get("notes") or [])[:MAX_TODO_NOTES]:
        if not isinstance(note, dict):
            continue
        title = str(note.get("title") or "").strip() or "未命名笔记"
        db.add(Note(
            user_id=user_id,
            task_id=todo.id,
            title=title[:200],
            content=note.get("content") or "",
        ))
    for att in (t.get("attachments") or [])[:MAX_TODO_ATTACHMENTS]:
        if not isinstance(att, dict):
            continue
        raw = att.get("content_base64")
        # A present-but-empty base64 string is a legitimate empty attachment and
        # must round-trip; an absent key is a malformed/hostile record to skip.
        if raw is None:
            continue
        if not isinstance(raw, str):
            continue
        # Reject oversized attachments BEFORE decoding: the upload path caps a
        # file at MAX_ATTACHMENT_BYTES, and a base64 string is ~4/3x its decoded
        # size, so a longer string can only be hostile/malformed. This prevents
        # a crafted backup from forcing a multi-hundred-MB buffer into memory.
        if len(raw) > MAX_ATTACHMENT_BYTES * 4 // 3 + 8:
            skipped["oversized_attachments"] = skipped.get("oversized_attachments", 0) + 1
            continue
        try:
            content = base64.b64decode(raw)
        except (ValueError, TypeError):
            content = b""
        db.add(TaskAttachment(
            task_id=todo.id,
            user_id=user_id,
            filename=str(att.get("filename") or "file")[:255] or "file",
            content_type=att.get("content_type"),
            size_bytes=len(content),
            content=content,
        ))
    return todo


def _parse_dt_value(value) -> Optional[datetime]:
    if not value:
        return None
    if isinstance(value, datetime):
        return value
    try:
        return datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    except (ValueError, TypeError):
        return None


def import_all(db: Session, user_id: int, doc: dict, mode: str = "merge") -> dict:
    """Restore a GTD backup. ``mode='replace'`` wipes the user's existing GTD
    data first; ``mode='merge'`` appends on top. Returns a counts summary.

    The whole restore (wipe + rebuild, for replace) runs in ONE transaction and
    is rolled back on any failure, so a bad backup can never destroy the user's
    existing data. Note the backup intentionally omits assignee/meeting links
    and timeline imports: those point at tables the GTD backup does not carry."""
    if not isinstance(doc, dict):
        raise ValueError("备份文件格式不正确")
    _validate_doc_shape(doc)
    if doc.get("app") != BACKUP_APP or doc.get("kind") != BACKUP_KIND:
        raise ValueError("不是 BioStatHelper 的 GTD 备份文件")
    if _as_int(doc.get("version")) > BACKUP_VERSION:
        raise ValueError("备份文件版本过高，请升级后再导入")

    counts = {
        "saved_filters": 0,
        "inbox": 0,
        "projects": 0,
        "todos": 0,
        "notes": 0,
        "attachments": 0,
    }
    skipped: dict = {}

    try:
        inbox = inbox_project(db, user_id)
        if mode == "replace":
            _wipe_user_gtd(db, user_id, inbox.id)
            # Bulk-deleting rows leaves any matching in-session objects pointing
            # at now-deleted rows (identity-map staleness). Detach everything so
            # the rebuild starts clean and a later access can't hit a deleted
            # instance.
            db.expunge_all()
            inbox = inbox_project(db, user_id)

        for sf in doc.get("saved_filters") or []:
            # Create the row directly rather than via create_saved_filter, which
            # commits internally and would break the single-transaction restore.
            name = str(sf.get("name") or "").strip()[:100]
            if not name:
                continue
            criteria = sf.get("criteria") if isinstance(sf.get("criteria"), dict) else {}
            db.add(SavedFilter(
                user_id=user_id,
                name=name,
                criteria=json.dumps(criteria, ensure_ascii=False),
            ))
            counts["saved_filters"] += 1

        for t in doc.get("inbox") or []:
            before = skipped.get("oversized_attachments", 0)
            _build_todo(db, user_id, inbox.id, t, skipped)
            counts["inbox"] += 1
            counts["todos"] += 1
            counts["notes"] += len(t.get("notes") or [])
            counts["attachments"] += len(t.get("attachments") or []) - (skipped.get("oversized_attachments", 0) - before)

        for p in doc.get("projects") or []:
            project = _build_project(db, user_id, p)
            for t in p.get("todos") or []:
                before = skipped.get("oversized_attachments", 0)
                _build_todo(db, user_id, project.id, t, skipped)
                counts["todos"] += 1
                counts["notes"] += len(t.get("notes") or [])
                counts["attachments"] += len(t.get("attachments") or []) - (skipped.get("oversized_attachments", 0) - before)
            counts["projects"] += 1

        db.commit()
    except Exception:
        db.rollback()
        raise
    return {"mode": mode, "imported": counts, "skipped": skipped}
