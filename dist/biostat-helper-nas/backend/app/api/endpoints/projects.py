from datetime import datetime, timezone
import logging
from typing import Optional
from zoneinfo import ZoneInfo

from fastapi import APIRouter, Depends, File, Form, HTTPException, Query, UploadFile
import json
from sqlalchemy.orm import Session

from app.api.endpoints.auth import get_current_user
from app.core.project_types import PROJECT_TYPE_DESCRIPTIONS, PROJECT_TYPE_OPTIONS
from app.crud import project as project_crud
from app.db.database import get_db
from app.models.models import (
    ProjectMember,
    ProjectMeeting,
    ProjectPhase,
    ProjectTimelineImport,
    ProjectTimelineItem,
    ProjectTodo,
    ProjectTodoChecklistItem,
)
from app.schemas.project import (
    AssistantDraftMeeting,
    AssistantDraftResponse,
    AssistantDraftTodo,
    AssistantParseRequest,
    AssistantParseResponse,
    ProjectAgentPlan,
    ProjectAgentMessageListResponse,
    ProjectAgentMessageResponse,
    ProjectAgentRequest,
    ProjectMemberCreate,
    ProjectMemberListResponse,
    ProjectMemberParseRequest,
    ProjectMemberParseResponse,
    ProjectMemberResponse,
    ProjectMemberUpdate,
    ProjectAgentResponse,
    ChecklistItemCreate,
    ChecklistItemResponse,
    ChecklistItemUpdate,
    MeetingCreate,
    MeetingListResponse,
    MeetingResponse,
    MeetingUpdate,
    PhaseReorderRequest,
    ProjectCreate,
    ProjectIntakeCreateResponse,
    ProjectIntakeDraft,
    ProjectIntakeDraftResponse,
    ProjectIntakeRequest,
    ProjectPhaseCreate,
    ProjectPhaseListResponse,
    ProjectPhaseResponse,
    ProjectPhaseUpdate,
    ProjectListResponse,
    ProjectResponse,
    ProjectUpdate,
    TodoCreate,
    TodoListResponse,
    TodoReorderRequest,
    TodoResponse,
    TodoUpdate,
    TimelineImportRequest,
    TimelineImportResponse,
    TimelineItemResponse,
    TimelineItemUpdate,
    TimelineListResponse,
)
from app.services.mimo_assistant import (
    parse_project_agent,
    parse_project_intake,
    parse_project_members,
    parse_project_text,
    parse_timeline_rows,
    tailor_project_workflow,
)
from app.services.timeline_parser import (
    parse_text_rows,
    parse_xls_bytes,
    parse_xlsx_bytes,
    rows_to_jsonable,
)

router = APIRouter()
logger = logging.getLogger(__name__)


def _project_or_404(db: Session, project_id: int, user):
    project = project_crud.get_project_for_user(db, project_id, user)
    if not project:
        raise HTTPException(status_code=404, detail="项目不存在")
    return project


def _project_child_or_404(db: Session, model, child_id: int, user):
    item = project_crud.get_project_child_for_user(db, model, child_id, user)
    if not item:
        raise HTTPException(status_code=404, detail="项目记录不存在")
    return item


def _parse_dt(value):
    if not value:
        return None
    if isinstance(value, datetime):
        parsed = value
    else:
        try:
            parsed = datetime.fromisoformat(str(value).replace("Z", "+00:00"))
        except ValueError:
            return None
    if parsed.tzinfo is not None:
        return parsed.astimezone(ZoneInfo("Asia/Shanghai")).replace(tzinfo=None)
    return parsed


def _json_value(value, default):
    if value is None:
        return default
    if isinstance(value, (list, dict)):
        return value
    try:
        return json.loads(value)
    except (TypeError, ValueError, json.JSONDecodeError):
        return default


def _timeline_item_response(item) -> TimelineItemResponse:
    return TimelineItemResponse(
        id=item.id,
        timeline_import_id=item.timeline_import_id,
        project_id=item.project_id,
        row_number=item.row_number or 0,
        external_id=item.external_id,
        title=item.title,
        description=item.description,
        phase=item.phase,
        start_at=item.start_at,
        due_at=item.due_at,
        status=item.status,
        target_type=item.target_type or "none",
        matched_todo_id=item.matched_todo_id,
        matched_checklist_item_id=item.matched_checklist_item_id,
        confidence=item.confidence,
        warning=item.warning,
        raw_json=_json_value(item.raw_json, {}),
        created_at=item.created_at,
        updated_at=item.updated_at,
    )


def _timeline_response(item) -> TimelineImportResponse:
    return TimelineImportResponse(
        id=item.id,
        project_id=item.project_id,
        file_name=item.file_name,
        source_type=item.source_type,
        source_text=item.source_text,
        raw_json=_json_value(item.raw_json, []),
        model_used=item.model_used,
        fallback_used=bool(item.fallback_used),
        status=item.status,
        error_message=item.error_message,
        items=[_timeline_item_response(child) for child in item.items],
        created_at=item.created_at,
        updated_at=item.updated_at,
    )


async def _create_timeline_from_rows(
    db: Session,
    project_id: int,
    *,
    rows: list[dict],
    source_type: str,
    file_name: Optional[str] = None,
    source_text: Optional[str] = None,
) -> TimelineImportResponse:
    if not rows:
        raise HTTPException(status_code=400, detail="Timeline 中没有可解析的非空行")
    parsed, model_used, fallback_used, _raw = await parse_timeline_rows(
        rows,
        context=project_crud.build_timeline_context(db, project_id),
    )
    normalized = []
    for index, item in enumerate(parsed, start=1):
        normalized.append({
            **item,
            "row_number": item.get("row_number") or index,
            "start_at": _parse_dt(item.get("start_at")),
            "due_at": _parse_dt(item.get("due_at")),
        })
    timeline = project_crud.create_timeline_import(
        db,
        project_id,
        source_type=source_type,
        file_name=file_name,
        source_text=source_text,
        raw_rows=rows_to_jsonable(rows),
        parsed_items=normalized,
        model_used=model_used,
        fallback_used=fallback_used,
    )
    return _timeline_response(timeline)


@router.get("", response_model=ProjectListResponse, include_in_schema=False)
@router.get("/", response_model=ProjectListResponse)
def list_projects(
    skip: int = Query(0, ge=0),
    limit: int = Query(100, ge=1, le=1000),
    search: Optional[str] = None,
    db: Session = Depends(get_db),
    _user=Depends(get_current_user),
):
    projects, total = project_crud.get_projects_for_user(db, _user, skip=skip, limit=limit, search=search)
    return ProjectListResponse(data=[ProjectResponse.model_validate(project) for project in projects], total=total)


@router.post("", response_model=ProjectResponse, include_in_schema=False)
@router.post("/", response_model=ProjectResponse)
async def create_project(
    project: ProjectCreate,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user),
):
    workflow_blueprint = None
    project_created_at = datetime.now(timezone.utc)
    if project.create_standard_workflow:
        project_context = "；".join(
            value for value in [
                project.name,
                project.sponsor,
                project.protocol_no,
                project.phase,
                project.indication,
                project.description,
            ]
            if value
        )
        logger.info("create_project AI workflow start: project=%s type=%s",
                    project.name, project.project_type)
        workflow_blueprint, _model, _fallback, _raw = await tailor_project_workflow(
            project.project_type,
            project.is_cdisc,
            project_context,
        )
        logger.info("create_project AI workflow done: project=%s elapsed=%.1fs",
                    project.name,
                    (datetime.now(timezone.utc) - project_created_at).total_seconds())
    db_started = datetime.now(timezone.utc)
    created = project_crud.create_project(
        db,
        project,
        owner_id=current_user.id,
        workflow_blueprint=workflow_blueprint,
    )
    logger.info("create_project row committed: project_id=%s elapsed=%.3fs total=%.1fs",
                created.id,
                (datetime.now(timezone.utc) - db_started).total_seconds(),
                (datetime.now(timezone.utc) - project_created_at).total_seconds())
    return created


@router.post("/assistant/project-intake/draft", response_model=ProjectIntakeDraftResponse)
async def draft_project_intake(
    request: ProjectIntakeRequest,
    _user=Depends(get_current_user),
):
    logger.info("Project intake draft requested: text_length=%d", len(request.text))
    try:
        parsed, model_used, fallback_used, raw = await parse_project_intake(request.text.strip())
        error = parsed.pop("error", None)
        debug_id = parsed.pop("debug_id", None)
        logger.info(
            "Project intake draft result: model=%s fallback=%s raw_keys=%s name=%s todo_count=%d member_count=%d error=%s debug_id=%s",
            model_used, fallback_used, list(raw.keys()) if isinstance(raw, dict) else [],
            parsed.get("name"), len(parsed.get("todos") or []), len(parsed.get("members") or []),
            error, debug_id,
        )
        draft = ProjectIntakeDraft.model_validate(parsed)
        return ProjectIntakeDraftResponse(
            **draft.model_dump(),
            model_used=model_used,
            fallback_used=fallback_used,
            raw=raw,
            error=error,
            debug_id=debug_id,
        )
    except Exception as exc:
        # Do not let a malformed model response or a schema mismatch close the
        # HTTP connection without a response. The client can display this JSON.
        logger.exception("Project intake draft failed")
        raise HTTPException(
            status_code=502,
            detail=f"项目识别服务暂时不可用：{type(exc).__name__}",
        ) from exc


@router.post("/assistant/project-intake", response_model=ProjectIntakeCreateResponse)
async def create_project_from_intake(
    request: ProjectIntakeRequest,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user),
):
    try:
        has_confirmed_tasks = bool(
            request.todos or request.completed_todo_titles or
            request.in_progress_todo_titles or request.current_phase
        )
        if has_confirmed_tasks:
            draft = ProjectIntakeDraft.model_validate(request.model_dump())
            model_used = "client-confirmed"
            fallback_used = False
            carried_error = None
            carried_debug_id = None
        else:
            parsed, model_used, fallback_used, _raw = await parse_project_intake(request.text.strip())
            carried_error = parsed.pop("error", None)
            carried_debug_id = parsed.pop("debug_id", None)
            # A direct create request may contain only `text` and schema
            # defaults. Use the AI result for the project fields in that case;
            # an edited confirmation form still takes precedence whenever it
            # sends a non-default value.
            merged = request.model_dump()
            parsed_fields = {
                "name",
                "sponsor",
                "protocol_no",
                "phase",
                "project_type",
                "is_cdisc",
                "indication",
                "description",
                "status",
            }
            defaults = {
                "name": "未命名项目",
                "project_type": "other",
                "status": "active",
                "is_cdisc": None,
            }
            for field in parsed_fields:
                current = merged.get(field)
                is_default = current is None or current == "" or current == defaults.get(field)
                if is_default and field in parsed:
                    merged[field] = parsed[field]
            for field in (
                "current_phase",
                "completed_todo_titles",
                "in_progress_todo_titles",
                "todos",
                "members",
            ):
                if field in parsed:
                    merged[field] = parsed[field]
            draft = ProjectIntakeDraft.model_validate(merged)
        workflow_blueprint = None
        workflow_model = ""
        workflow_fallback = False
        if draft.create_standard_workflow:
            workflow_blueprint, workflow_model, workflow_fallback, _workflow_raw = (
                await tailor_project_workflow(
                    draft.project_type,
                    bool(draft.is_cdisc),
                    "\n".join(
                        value for value in [request.text.strip(), draft.description]
                        if value
                    ),
                )
            )
        result = project_crud.create_project_from_intake(
            db,
            draft,
            request.text.strip(),
            owner_id=current_user.id,
            model_used=model_used,
            fallback_used=fallback_used or workflow_fallback,
            workflow_blueprint=workflow_blueprint,
        )
        if workflow_model:
            result["model_used"] = f"{model_used} + workflow:{workflow_model}"
    except HTTPException:
        db.rollback()
        raise
    except ValueError as exc:
        db.rollback()
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    except Exception as exc:
        db.rollback()
        raise HTTPException(status_code=500, detail=f"项目建档失败：{exc}") from exc
    return ProjectIntakeCreateResponse(
        project=ProjectResponse.model_validate(result["project"]),
        model_used=result["model_used"],
        fallback_used=result["fallback_used"],
        current_phase=draft.current_phase,
        completed_todo_count=result["completed_todo_count"],
        in_progress_todo_count=result["in_progress_todo_count"],
        created_todo_count=result["created_todo_count"],
        error=carried_error,
        debug_id=carried_debug_id,
    )


@router.get("/metadata/options")
def project_metadata_options(_user=Depends(get_current_user)):
    return {
        "project_types": [
            {
                "value": value,
                "label": label,
                "description": PROJECT_TYPE_DESCRIPTIONS[value],
            }
            for value, label in PROJECT_TYPE_OPTIONS
        ],
        "member_types": [
            {"value": "sponsor", "label": "申办方"},
            {"value": "statistical_partner", "label": "合作统计方"},
            {"value": "internal", "label": "内部团队"},
            {"value": "other", "label": "其他"},
        ],
    }


@router.get("/{project_id}/members", response_model=ProjectMemberListResponse)
def list_project_members(
    project_id: int,
    db: Session = Depends(get_db),
    _user=Depends(get_current_user),
):
    _project_or_404(db, project_id, _user)
    members, total = project_crud.get_project_members(db, project_id)
    return ProjectMemberListResponse(
        data=[ProjectMemberResponse.model_validate(item) for item in members],
        total=total,
    )


@router.post("/{project_id}/members", response_model=ProjectMemberResponse)
def create_project_member(
    project_id: int,
    member: ProjectMemberCreate,
    db: Session = Depends(get_db),
    _user=Depends(get_current_user),
):
    _project_or_404(db, project_id, _user)
    return ProjectMemberResponse.model_validate(
        project_crud.create_project_member(db, project_id, member)
    )


@router.post("/{project_id}/members/parse", response_model=ProjectMemberParseResponse)
async def parse_project_member_text(
    project_id: int,
    request: ProjectMemberParseRequest,
    db: Session = Depends(get_db),
    _user=Depends(get_current_user),
):
    _project_or_404(db, project_id, _user)
    parsed, model_used, fallback_used, raw = await parse_project_members(request.text.strip())
    created = []
    if request.create_records:
        for item in parsed:
            created.append(project_crud.create_project_member(
                db,
                project_id,
                ProjectMemberCreate.model_validate({**item, "source_text": request.text.strip()}),
            ))
    return ProjectMemberParseResponse(
        model_used=model_used,
        fallback_used=fallback_used,
        members=[ProjectMemberResponse.model_validate(item) for item in created] if created else parsed,
        created_count=len(created),
        raw=raw,
    )


@router.put("/members/{member_id}", response_model=ProjectMemberResponse)
def update_project_member(
    member_id: int,
    member_update: ProjectMemberUpdate,
    db: Session = Depends(get_db),
    _user=Depends(get_current_user),
):
    _project_child_or_404(db, ProjectMember, member_id, _user)
    member = project_crud.update_project_member(db, member_id, member_update)
    if not member:
        raise HTTPException(status_code=404, detail="项目成员不存在")
    return ProjectMemberResponse.model_validate(member)


@router.delete("/members/{member_id}")
def delete_project_member(
    member_id: int,
    db: Session = Depends(get_db),
    _user=Depends(get_current_user),
):
    _project_child_or_404(db, ProjectMember, member_id, _user)
    if not project_crud.delete_project_member(db, member_id):
        raise HTTPException(status_code=404, detail="项目成员不存在")
    return {"message": "项目成员已删除"}


@router.get("/{project_id}/timeline", response_model=TimelineListResponse)
def list_project_timeline_imports(
    project_id: int,
    db: Session = Depends(get_db),
    _user=Depends(get_current_user),
):
    _project_or_404(db, project_id, _user)
    items, total = project_crud.get_timeline_imports(db, project_id)
    return TimelineListResponse(data=[_timeline_response(item) for item in items], total=total)


@router.post("/{project_id}/timeline/text", response_model=TimelineImportResponse)
async def import_project_timeline_text(
    project_id: int,
    request: TimelineImportRequest,
    db: Session = Depends(get_db),
    _user=Depends(get_current_user),
):
    _project_or_404(db, project_id, _user)
    rows = request.rows or parse_text_rows(request.source_text or "")
    return await _create_timeline_from_rows(
        db,
        project_id,
        rows=rows,
        source_type="json" if request.rows else "text",
        file_name=request.file_name,
        source_text=request.source_text,
    )


@router.post("/{project_id}/timeline/file", response_model=TimelineImportResponse)
async def import_project_timeline_file(
    project_id: int,
    file: UploadFile = File(...),
    source_text: Optional[str] = Form(None),
    db: Session = Depends(get_db),
    _user=Depends(get_current_user),
):
    _project_or_404(db, project_id, _user)
    name = (file.filename or "timeline.xlsx").strip()
    extension = name.rsplit(".", 1)[-1].lower() if "." in name else ""
    content = await file.read()
    if len(content) > 15 * 1024 * 1024:
        raise HTTPException(status_code=413, detail="Timeline 文件不能超过 15MB")
    try:
        if extension in {"xlsx", "xlsm"}:
            rows = parse_xlsx_bytes(content)
            source_type_value = "xlsx"
        elif extension == "xls":
            rows = parse_xls_bytes(content)
            source_type_value = "xls"
        elif extension in {"csv", "txt", "tsv"}:
            text_value = content.decode("utf-8-sig", errors="replace")
            rows = parse_text_rows(text_value)
            source_text = source_text or text_value
            source_type_value = extension or "text"
        else:
            raise HTTPException(status_code=400, detail="仅支持 .xlsx、.xls、.xlsm、.csv、.tsv 和 .txt")
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(status_code=400, detail=f"Timeline 文件读取失败：{exc}") from exc
    return await _create_timeline_from_rows(
        db,
        project_id,
        rows=rows,
        source_type=source_type_value,
        file_name=name,
        source_text=source_text,
    )


@router.put("/timeline/items/{item_id}", response_model=TimelineItemResponse)
def update_project_timeline_item(
    item_id: int,
    item_update: TimelineItemUpdate,
    db: Session = Depends(get_db),
    _user=Depends(get_current_user),
):
    _project_child_or_404(db, ProjectTimelineItem, item_id, _user)
    try:
        item = project_crud.update_timeline_item(db, item_id, item_update)
    except ValueError as exc:
        db.rollback()
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    if not item:
        raise HTTPException(status_code=404, detail="Timeline 事项不存在")
    return _timeline_item_response(item)


@router.delete("/timeline/{timeline_id}")
def delete_project_timeline_import(
    timeline_id: int,
    db: Session = Depends(get_db),
    _user=Depends(get_current_user),
):
    _project_child_or_404(db, ProjectTimelineImport, timeline_id, _user)
    if not project_crud.delete_timeline_import(db, timeline_id):
        raise HTTPException(status_code=404, detail="Timeline 导入记录不存在")
    return {"message": "Timeline 导入记录已删除；此前写入待办的日期不会自动清空"}


@router.get("/{project_id}", response_model=ProjectResponse)
def get_project(
    project_id: int,
    db: Session = Depends(get_db),
    _user=Depends(get_current_user),
):
    return ProjectResponse.model_validate(_project_or_404(db, project_id, _user))


@router.put("/{project_id}", response_model=ProjectResponse)
def update_project(
    project_id: int,
    project_update: ProjectUpdate,
    db: Session = Depends(get_db),
    _user=Depends(get_current_user),
):
    _project_or_404(db, project_id, _user)
    project = project_crud.update_project(db, project_id, project_update)
    if not project:
        raise HTTPException(status_code=404, detail="项目不存在")
    return ProjectResponse.model_validate(project)


@router.delete("/{project_id}")
def delete_project(
    project_id: int,
    confirm_name: str = Query(..., min_length=1, max_length=200),
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user),
):
    project = _project_or_404(db, project_id, current_user)
    if confirm_name.strip() != project.name.strip():
        raise HTTPException(status_code=400, detail="项目名称不匹配，不会执行删除")
    if not project_crud.delete_project(db, project_id):
        raise HTTPException(status_code=404, detail="项目不存在")
    return {"message": "项目及其阶段、待办、清单、会议和Agent记录已删除"}


@router.post("/{project_id}/standard-workflow")
async def seed_standard_workflow(
    project_id: int,
    db: Session = Depends(get_db),
    _user=Depends(get_current_user),
):
    project = _project_or_404(db, project_id, _user)
    workflow, model_used, fallback_used, _raw = await tailor_project_workflow(
        project.project_type,
        project.is_cdisc,
        "\n".join(value for value in [project.name, project.description] if value),
    )
    created = project_crud.seed_standard_workflow(
        db,
        project_id,
        workflow_blueprint=workflow,
    )
    return {
        "created": created,
        "model_used": model_used,
        "fallback_used": fallback_used,
    }


@router.get("/{project_id}/phases", response_model=ProjectPhaseListResponse)
def list_project_phases(
    project_id: int,
    db: Session = Depends(get_db),
    _user=Depends(get_current_user),
):
    _project_or_404(db, project_id, _user)
    phases, total = project_crud.get_project_phases(db, project_id)
    return ProjectPhaseListResponse(
        data=[ProjectPhaseResponse.model_validate(phase) for phase in phases],
        total=total,
    )


@router.post("/{project_id}/phases", response_model=ProjectPhaseResponse)
def create_project_phase(
    project_id: int,
    phase: ProjectPhaseCreate,
    db: Session = Depends(get_db),
    _user=Depends(get_current_user),
):
    _project_or_404(db, project_id, _user)
    try:
        return ProjectPhaseResponse.model_validate(
            project_crud.create_project_phase(db, project_id, phase)
        )
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


@router.post("/{project_id}/phases/reorder", response_model=ProjectPhaseListResponse)
def reorder_project_phases(
    project_id: int,
    request: PhaseReorderRequest,
    db: Session = Depends(get_db),
    _user=Depends(get_current_user),
):
    _project_or_404(db, project_id, _user)
    phases = project_crud.reorder_project_phases(db, project_id, request.phase_ids)
    return ProjectPhaseListResponse(
        data=[ProjectPhaseResponse.model_validate(phase) for phase in phases],
        total=len(phases),
    )


@router.put("/phases/{phase_id}", response_model=ProjectPhaseResponse)
def update_project_phase(
    phase_id: int,
    phase_update: ProjectPhaseUpdate,
    db: Session = Depends(get_db),
    _user=Depends(get_current_user),
):
    _project_child_or_404(db, ProjectPhase, phase_id, _user)
    try:
        phase = project_crud.update_project_phase(db, phase_id, phase_update)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    if not phase:
        raise HTTPException(status_code=404, detail="阶段不存在")
    return ProjectPhaseResponse.model_validate(phase)


@router.delete("/phases/{phase_id}")
def delete_project_phase(
    phase_id: int,
    db: Session = Depends(get_db),
    _user=Depends(get_current_user),
):
    _project_child_or_404(db, ProjectPhase, phase_id, _user)
    try:
        deleted = project_crud.delete_project_phase(db, phase_id)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    if not deleted:
        raise HTTPException(status_code=404, detail="阶段不存在")
    return {"message": "阶段已删除，原阶段待办已移动到流程待办"}


@router.get("/{project_id}/todos", response_model=TodoListResponse)
def list_todos(
    project_id: int,
    todo_type: Optional[str] = Query(None, pattern="^(standard|extra|meeting)$"),
    status: Optional[str] = None,
    db: Session = Depends(get_db),
    _user=Depends(get_current_user),
):
    _project_or_404(db, project_id, _user)
    todos, total = project_crud.get_todos(db, project_id, todo_type=todo_type, status=status)
    return TodoListResponse(data=[TodoResponse.model_validate(todo) for todo in todos], total=total)


@router.post("/{project_id}/todos/reorder", response_model=TodoListResponse)
def reorder_todos(
    project_id: int,
    request: TodoReorderRequest,
    db: Session = Depends(get_db),
    _user=Depends(get_current_user),
):
    _project_or_404(db, project_id, _user)
    todos = project_crud.reorder_todos(db, project_id, request.phase, request.todo_ids)
    return TodoListResponse(data=[TodoResponse.model_validate(todo) for todo in todos], total=len(todos))


@router.post("/{project_id}/todos", response_model=TodoResponse)
def create_todo(
    project_id: int,
    todo: TodoCreate,
    db: Session = Depends(get_db),
    _user=Depends(get_current_user),
):
    _project_or_404(db, project_id, _user)
    try:
        return TodoResponse.model_validate(project_crud.create_todo(db, project_id, todo))
    except ValueError as exc:
        db.rollback()
        raise HTTPException(status_code=400, detail=str(exc)) from exc


@router.put("/todos/{todo_id}", response_model=TodoResponse)
def update_todo(
    todo_id: int,
    todo_update: TodoUpdate,
    db: Session = Depends(get_db),
    _user=Depends(get_current_user),
):
    _project_child_or_404(db, ProjectTodo, todo_id, _user)
    try:
        todo = project_crud.update_todo(db, todo_id, todo_update)
    except ValueError as exc:
        db.rollback()
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    if not todo:
        raise HTTPException(status_code=404, detail="待办不存在")
    return TodoResponse.model_validate(todo)


@router.delete("/todos/{todo_id}")
def delete_todo(
    todo_id: int,
    db: Session = Depends(get_db),
    _user=Depends(get_current_user),
):
    _project_child_or_404(db, ProjectTodo, todo_id, _user)
    if not project_crud.delete_todo(db, todo_id):
        raise HTTPException(status_code=404, detail="待办不存在")
    return {"message": "待办已删除"}


@router.post("/todos/{todo_id}/checklist", response_model=ChecklistItemResponse)
def create_checklist_item(
    todo_id: int,
    item: ChecklistItemCreate,
    db: Session = Depends(get_db),
    _user=Depends(get_current_user),
):
    _project_child_or_404(db, ProjectTodo, todo_id, _user)
    checklist_item = project_crud.create_checklist_item(db, todo_id, item)
    if not checklist_item:
        raise HTTPException(status_code=404, detail="待办不存在")
    return ChecklistItemResponse.model_validate(checklist_item)


@router.put("/todos/checklist/{item_id}", response_model=ChecklistItemResponse)
def update_checklist_item(
    item_id: int,
    item_update: ChecklistItemUpdate,
    db: Session = Depends(get_db),
    _user=Depends(get_current_user),
):
    _project_child_or_404(db, ProjectTodoChecklistItem, item_id, _user)
    checklist_item = project_crud.update_checklist_item(db, item_id, item_update)
    if not checklist_item:
        raise HTTPException(status_code=404, detail="清单项不存在")
    return ChecklistItemResponse.model_validate(checklist_item)


@router.delete("/todos/checklist/{item_id}")
def delete_checklist_item(
    item_id: int,
    db: Session = Depends(get_db),
    _user=Depends(get_current_user),
):
    _project_child_or_404(db, ProjectTodoChecklistItem, item_id, _user)
    if not project_crud.delete_checklist_item(db, item_id):
        raise HTTPException(status_code=404, detail="清单项不存在")
    return {"message": "清单项已删除"}


@router.get("/{project_id}/meetings", response_model=MeetingListResponse)
def list_meetings(
    project_id: int,
    db: Session = Depends(get_db),
    _user=Depends(get_current_user),
):
    _project_or_404(db, project_id, _user)
    meetings, total = project_crud.get_meetings(db, project_id)
    return MeetingListResponse(data=[MeetingResponse.model_validate(meeting) for meeting in meetings], total=total)


@router.post("/{project_id}/meetings", response_model=MeetingResponse)
def create_meeting(
    project_id: int,
    meeting: MeetingCreate,
    db: Session = Depends(get_db),
    _user=Depends(get_current_user),
):
    _project_or_404(db, project_id, _user)
    return MeetingResponse.model_validate(project_crud.create_meeting(db, project_id, meeting))


@router.put("/meetings/{meeting_id}", response_model=MeetingResponse)
def update_meeting(
    meeting_id: int,
    meeting_update: MeetingUpdate,
    db: Session = Depends(get_db),
    _user=Depends(get_current_user),
):
    _project_child_or_404(db, ProjectMeeting, meeting_id, _user)
    meeting = project_crud.update_meeting(db, meeting_id, meeting_update)
    if not meeting:
        raise HTTPException(status_code=404, detail="会议不存在")
    return MeetingResponse.model_validate(meeting)


@router.delete("/meetings/{meeting_id}")
def delete_meeting(
    meeting_id: int,
    db: Session = Depends(get_db),
    _user=Depends(get_current_user),
):
    _project_child_or_404(db, ProjectMeeting, meeting_id, _user)
    if not project_crud.delete_meeting(db, meeting_id):
        raise HTTPException(status_code=404, detail="会议不存在")
    return {"message": "会议已删除"}


def _draft_response(parsed: dict, model_used: str, fallback_used: bool, raw: dict | None) -> AssistantDraftResponse:
    meetings = []
    for item in parsed.get("meetings", []):
        meetings.append(AssistantDraftMeeting(
            title=item.get("title") or "项目会议",
            agenda=item.get("agenda"),
            meeting_url=item.get("meeting_url"),
            location=item.get("location"),
            starts_at=_parse_dt(item.get("starts_at")),
            ends_at=_parse_dt(item.get("ends_at")),
            attendees=item.get("attendees"),
            notes=item.get("notes"),
        ))

    todos = []
    for item in parsed.get("todos", []):
        todos.append(AssistantDraftTodo(
            title=item.get("title") or "项目待办",
            description=item.get("description"),
            todo_type=item.get("todo_type") or "extra",
            phase=item.get("phase"),
            status=item.get("status") or "open",
            priority=item.get("priority") or "normal",
            start_at=_parse_dt(item.get("start_at")),
            due_at=_parse_dt(item.get("due_at")),
        ))

    return AssistantDraftResponse(
        intent=parsed.get("intent") or "todo",
        model_used=model_used,
        fallback_used=fallback_used,
        meetings=meetings,
        todos=todos,
        raw=raw,
    )


@router.post("/{project_id}/assistant/draft", response_model=AssistantDraftResponse)
async def draft_project_assistant_text(
    project_id: int,
    request: AssistantParseRequest,
    db: Session = Depends(get_db),
    _user=Depends(get_current_user),
):
    _project_or_404(db, project_id, _user)
    parsed, model_used, fallback_used, raw = await parse_project_text(request.text)
    return _draft_response(parsed, model_used, fallback_used, raw)


@router.post("/{project_id}/assistant/parse", response_model=AssistantParseResponse)
async def parse_project_assistant_text(
    project_id: int,
    request: AssistantParseRequest,
    db: Session = Depends(get_db),
    _user=Depends(get_current_user),
):
    _project_or_404(db, project_id, _user)
    parsed, model_used, fallback_used, raw = await parse_project_text(request.text)

    created_meetings = []
    created_todos = []
    if request.create_records:
        for item in parsed.get("meetings", []):
            meeting = project_crud.create_meeting(
                db,
                project_id,
                MeetingCreate(
                    title=item.get("title") or "项目会议",
                    agenda=item.get("agenda"),
                    meeting_url=item.get("meeting_url"),
                    location=item.get("location"),
                    starts_at=_parse_dt(item.get("starts_at")),
                    ends_at=_parse_dt(item.get("ends_at")),
                    attendees=item.get("attendees"),
                    notes=item.get("notes"),
                    source_text=request.text,
                ),
            )
            created_meetings.append(MeetingResponse.model_validate(meeting))

        for item in parsed.get("todos", []):
            todo = project_crud.create_todo(
                db,
                project_id,
                TodoCreate(
                    title=item.get("title") or "项目待办",
                    description=item.get("description"),
                    todo_type=item.get("todo_type") or "extra",
                    phase=item.get("phase"),
                    status=item.get("status") or "open",
                    priority=item.get("priority") or "normal",
                    start_at=_parse_dt(item.get("start_at")),
                    due_at=_parse_dt(item.get("due_at")),
                    source_text=request.text,
                    meeting_id=item.get("meeting_id"),
                ),
            )
            created_todos.append(TodoResponse.model_validate(todo))

    return AssistantParseResponse(
        intent=parsed.get("intent") or "todo",
        model_used=model_used,
        fallback_used=fallback_used,
        todos=created_todos,
        meetings=created_meetings,
        raw=raw,
    )


@router.post("/{project_id}/agent", response_model=ProjectAgentResponse)
async def run_project_agent(
    project_id: int,
    request: ProjectAgentRequest,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user),
):
    """Parse and apply a natural-language project update in one transaction."""
    try:
        _project_or_404(db, project_id, current_user)
        context = project_crud.build_agent_context(db, project_id)
        parsed, model_used, fallback_used, _raw = await parse_project_agent(
            request.text.strip(), context
        )
        plan = ProjectAgentPlan.model_validate(parsed)
        applied = project_crud.apply_agent_plan(
            db,
            project_id,
            plan,
            request.text.strip(),
            user_id=current_user.id,
            model_used=model_used,
            fallback_used=fallback_used,
        )
    except HTTPException:
        db.rollback()
        raise
    except ValueError as exc:
        db.rollback()
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    except Exception as exc:
        db.rollback()
        raise HTTPException(status_code=500, detail=f"项目整理失败：{exc}") from exc

    try:
        return ProjectAgentResponse(
            intent=plan.intent,
            summary=applied["assistant_content"],
            clarification=plan.clarification,
            model_used=model_used,
            fallback_used=fallback_used,
            current_phase=plan.current_phase,
            completed_todo_count=applied["completed_todo_count"],
            completed_checklist_count=applied["completed_checklist_count"],
            created_todos=[TodoResponse.model_validate(item) for item in applied["created_todos"]],
            updated_todos=[TodoResponse.model_validate(item) for item in applied["updated_todos"]],
            created_meetings=[MeetingResponse.model_validate(item) for item in applied["created_meetings"]],
            updated_meetings=[MeetingResponse.model_validate(item) for item in applied["updated_meetings"]],
        )
    except Exception as exc:
        db.rollback()
        raise HTTPException(status_code=500, detail=f"项目整理结果无法返回：{exc}") from exc


@router.get("/{project_id}/agent/messages", response_model=ProjectAgentMessageListResponse)
def list_project_agent_messages(
    project_id: int,
    limit: int = Query(100, ge=1, le=500),
    db: Session = Depends(get_db),
    _user=Depends(get_current_user),
):
    _project_or_404(db, project_id, _user)
    messages, total = project_crud.get_agent_messages(db, project_id, limit=limit)
    return ProjectAgentMessageListResponse(
        data=[ProjectAgentMessageResponse.model_validate(item) for item in messages],
        total=total,
    )
