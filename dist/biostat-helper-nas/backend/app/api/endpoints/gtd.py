from datetime import date, datetime
from typing import List, Optional
from urllib.parse import quote
from zoneinfo import ZoneInfo

from fastapi import APIRouter, Body, Depends, File, HTTPException, Query, Request, UploadFile
from fastapi.responses import Response
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from app.api.endpoints.auth import get_current_user
from app.crud import gtd as gtd_crud
from app.db.database import get_db


router = APIRouter()


def _owner_id(current_user) -> int:
    return current_user.id


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


class InboxCreateRequest(BaseModel):
    title: str = Field(..., min_length=1, max_length=300)
    description: Optional[str] = None
    due_at: Optional[datetime] = None


class InboxProcessRequest(BaseModel):
    # Maps to a GTD status: next / waiting / someday / reference / done
    action: str = Field("next", pattern="^(next|waiting|someday|reference|done)$")
    project_id: Optional[int] = None
    phase: Optional[str] = None
    title: Optional[str] = None
    due_at: Optional[datetime] = None
    is_focused_today: Optional[bool] = None


class FocusToggleRequest(BaseModel):
    todo_id: int


class TaskQueryRequest(BaseModel):
    status: Optional[str] = None
    project_id: Optional[int] = None


class SavedFilterCreate(BaseModel):
    name: str = Field(..., min_length=1, max_length=100)
    # Reusable criteria mapping 1:1 onto GET /gtd/tasks query params.
    criteria: dict = Field(default_factory=dict)


def _split_csv(value: Optional[str]) -> Optional[List[str]]:
    if not value:
        return None
    parts = [part.strip() for part in value.split(",") if part.strip()]
    return parts or None


def _sanitize_filename(raw: Optional[str], fallback: str = "file") -> str:
    """Return a header-safe, latin-1-encodable ASCII fallback filename.

    Strips CR/LF (response-header splitting), quotes, backslash and control
    chars. Non-latin-1 characters (e.g. Chinese) are replaced so the value can
    be placed in ``Content-Disposition`` without a UnicodeEncodeError."""
    cleaned = "".join(
        ch for ch in (raw or fallback)
        if ch.isprintable() and ch not in ('"', "\\", "\r", "\n")
    ).strip()[:255] or fallback
    ascii_name = cleaned.encode("ascii", "replace").decode("ascii")
    ascii_name = "".join("_" if not (ch.isalnum() or ch in ".-_ ") else ch for ch in ascii_name)
    ascii_name = ascii_name.strip() or fallback
    return ascii_name


def _content_disposition(raw: Optional[str]) -> str:
    """Build a Content-Disposition value preserving the original (possibly
    non-latin-1) filename via RFC 5987 ``filename*=`` while keeping an ASCII
    ``filename=`` fallback that is safe for the latin-1-encoded header."""
    safe = _sanitize_filename(raw)
    original = "".join(
        ch for ch in (raw or "file")
        if ch.isprintable() and ch not in ('"', "\\", "\r", "\n")
    ).strip()[:255]
    if original and original != safe:
        return f"attachment; filename=\"{safe}\"; filename*=UTF-8''{quote(original)}"
    return f"attachment; filename=\"{safe}\""


@router.get("/inbox")
def get_inbox(db: Session = Depends(get_db), _user=Depends(get_current_user)):
    return gtd_crud.list_inbox(db, _owner_id(_user))


@router.post("/inbox")
def create_inbox(
    body: InboxCreateRequest,
    db: Session = Depends(get_db),
    _user=Depends(get_current_user),
):
    return gtd_crud.create_inbox_task(
        db,
        _owner_id(_user),
        body.title,
        description=body.description,
        due_at=_parse_dt(body.due_at),
    )


@router.post("/inbox/{todo_id}/process")
def process_inbox(
    todo_id: int,
    body: InboxProcessRequest,
    db: Session = Depends(get_db),
    _user=Depends(get_current_user),
):
    result = gtd_crud.process_inbox_task(
        db,
        _owner_id(_user),
        todo_id,
        action=body.action,
        project_id=body.project_id,
        phase=body.phase,
        title=body.title,
        due_at=_parse_dt(body.due_at),
        is_focused_today=body.is_focused_today,
    )
    if result is None:
        raise HTTPException(status_code=404, detail="收件箱事项不存在")
    return result


@router.get("/focus")
def get_focus(
    on_date: Optional[date] = Query(None, description="YYYY-MM-DD, 默认今天"),
    db: Session = Depends(get_db),
    _user=Depends(get_current_user),
):
    return gtd_crud.focus_tasks(db, _owner_id(_user), on_date)


@router.post("/focus/toggle")
def toggle_focus(
    body: FocusToggleRequest,
    db: Session = Depends(get_db),
    _user=Depends(get_current_user),
):
    result = gtd_crud.toggle_focus(db, _owner_id(_user), body.todo_id)
    if result is None:
        raise HTTPException(status_code=404, detail="任务不存在")
    return result


@router.get("/next-actions")
def get_next_actions(db: Session = Depends(get_db), _user=Depends(get_current_user)):
    return gtd_crud.next_actions(db, _owner_id(_user))


@router.get("/waiting")
def get_waiting(db: Session = Depends(get_db), _user=Depends(get_current_user)):
    return gtd_crud.list_waiting(db, _owner_id(_user))


@router.get("/someday")
def get_someday(db: Session = Depends(get_db), _user=Depends(get_current_user)):
    return gtd_crud.list_someday(db, _owner_id(_user))


@router.get("/review/status")
def get_review_status(db: Session = Depends(get_db), _user=Depends(get_current_user)):
    return gtd_crud.review_status(db, _owner_id(_user))


@router.get("/review/weekly")
def get_weekly_review(db: Session = Depends(get_db), _user=Depends(get_current_user)):
    return gtd_crud.weekly_review(db, _owner_id(_user))


@router.get("/tasks")
def query_tasks(
    status: Optional[str] = Query(None),
    project_id: Optional[int] = Query(None),
    q: Optional[str] = Query(None, description="全文搜索标题/描述/阶段"),
    contexts: Optional[str] = Query(None, description="逗号分隔的 @上下文"),
    tags: Optional[str] = Query(None, description="逗号分隔的标签"),
    area: Optional[str] = Query(None),
    priority: Optional[str] = Query(None),
    is_focused_today: Optional[bool] = Query(None),
    db: Session = Depends(get_db),
    _user=Depends(get_current_user),
):
    """Generic GTD task query powering saved filters and global search."""
    return gtd_crud.query_tasks(
        db,
        _owner_id(_user),
        status=status,
        project_id=project_id,
        q=q,
        contexts=_split_csv(contexts),
        tags=_split_csv(tags),
        area=area,
        priority=priority,
        is_focused_today=is_focused_today,
    )


@router.get("/filters")
def get_saved_filters(db: Session = Depends(get_db), _user=Depends(get_current_user)):
    return gtd_crud.list_saved_filters(db, _owner_id(_user))


@router.post("/filters")
def create_saved_filter(
    body: SavedFilterCreate,
    db: Session = Depends(get_db),
    _user=Depends(get_current_user),
):
    try:
        return gtd_crud.create_saved_filter(
            db, _owner_id(_user), body.name, body.criteria
        )
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))


@router.delete("/filters/{filter_id}")
def delete_saved_filter(
    filter_id: int,
    db: Session = Depends(get_db),
    _user=Depends(get_current_user),
):
    if not gtd_crud.delete_saved_filter(db, _owner_id(_user), filter_id):
        raise HTTPException(status_code=404, detail="筛选不存在")
    return {"ok": True}


@router.get("/calendar")
def get_calendar(
    start: date = Query(..., description="YYYY-MM-DD 范围起始"),
    end: date = Query(..., description="YYYY-MM-DD 范围结束(含当天)"),
    db: Session = Depends(get_db),
    _user=Depends(get_current_user),
):
    """Active tasks due inside [start, end]. Recurring tasks are expanded into
    every occurrence landing in the range (each carries ``occurrence_due_at``)."""
    range_start = datetime.combine(start, datetime.min.time())
    range_end = datetime.combine(end, datetime.max.time())
    return gtd_crud.calendar_tasks(db, _owner_id(_user), range_start, range_end)


@router.get("/contexts")
def get_contexts(db: Session = Depends(get_db), _user=Depends(get_current_user)):
    """GTD context directory: @people (seeded from project members) and
    @places (collected from task context chips that are not member names)."""
    return gtd_crud.list_contexts(db, _owner_id(_user))


class NoteCreateRequest(BaseModel):
    title: str = Field("", max_length=200)
    content: str = ""


@router.get("/tasks/{todo_id}/notes")
def get_task_notes(
    todo_id: int,
    db: Session = Depends(get_db),
    _user=Depends(get_current_user),
):
    result = gtd_crud.task_notes(db, _owner_id(_user), todo_id)
    if result is None:
        raise HTTPException(status_code=404, detail="任务不存在")
    return result


@router.post("/tasks/{todo_id}/notes")
def create_task_note(
    todo_id: int,
    body: NoteCreateRequest,
    db: Session = Depends(get_db),
    _user=Depends(get_current_user),
):
    result = gtd_crud.create_task_note(
        db, _owner_id(_user), todo_id, body.title, body.content
    )
    if result is None:
        raise HTTPException(status_code=404, detail="任务不存在")
    return result


@router.delete("/notes/{note_id}")
def delete_task_note(
    note_id: int,
    db: Session = Depends(get_db),
    _user=Depends(get_current_user),
):
    if not gtd_crud.delete_task_note(db, _owner_id(_user), note_id):
        raise HTTPException(status_code=404, detail="笔记不存在")
    return {"ok": True}


@router.get("/tasks/{todo_id}/attachments")
def get_task_attachments(
    todo_id: int,
    db: Session = Depends(get_db),
    _user=Depends(get_current_user),
):
    result = gtd_crud.task_attachments(db, _owner_id(_user), todo_id)
    if result is None:
        raise HTTPException(status_code=404, detail="任务不存在")
    return result


@router.post("/tasks/{todo_id}/attachments")
async def upload_task_attachment(
    todo_id: int,
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
    _user=Depends(get_current_user),
):
    # Enforce the 20MB cap before/while buffering the body. When Content-Length
    # is available (file.size) we reject up front; otherwise we read in bounded
    # chunks and abort as soon as the cap is exceeded, so a chunked/streaming
    # upload cannot force a multi-GB payload into process memory.
    max_bytes = 20 * 1024 * 1024
    if file.size is not None and file.size > max_bytes:
        raise HTTPException(
            status_code=413,
            detail=f"附件不能超过 {max_bytes // (1024 * 1024)}MB",
        )
    chunks = []
    total = 0
    while True:
        chunk = await file.read(1024 * 1024)
        if not chunk:
            break
        chunks.append(chunk)
        total += len(chunk)
        if total > max_bytes:
            raise HTTPException(
                status_code=413,
                detail=f"附件不能超过 {max_bytes // (1024 * 1024)}MB",
            )
    content = b"".join(chunks)
    try:
        result = gtd_crud.create_task_attachment(
            db,
            _owner_id(_user),
            todo_id,
            file.filename or "file",
            content,
            content_type=file.content_type,
        )
    except ValueError as exc:
        raise HTTPException(status_code=413, detail=str(exc)) from exc
    if result is None:
        raise HTTPException(status_code=404, detail="任务不存在")
    return result


@router.get("/attachments/{attachment_id}/download")
def download_task_attachment(
    attachment_id: int,
    db: Session = Depends(get_db),
    _user=Depends(get_current_user),
):
    row = gtd_crud.get_task_attachment(db, _owner_id(_user), attachment_id)
    if not row or not row.content:
        raise HTTPException(status_code=404, detail="附件不存在")
    return Response(
        content=row.content,
        media_type=row.content_type or "application/octet-stream",
        headers={
            "Content-Disposition": _content_disposition(row.filename)
        },
    )


@router.delete("/attachments/{attachment_id}")
def delete_task_attachment(
    attachment_id: int,
    db: Session = Depends(get_db),
    _user=Depends(get_current_user),
):
    if not gtd_crud.delete_task_attachment(db, _owner_id(_user), attachment_id):
        raise HTTPException(status_code=404, detail="附件不存在")
    return {"ok": True}


@router.get("/export")
def export_gtd(db: Session = Depends(get_db), _user=Depends(get_current_user)):
    """Download the user's entire GTD workspace as one versioned JSON backup."""
    return gtd_crud.export_all(db, _owner_id(_user))


@router.post("/import")
def import_gtd(
    request: Request,
    payload: dict = Body(..., description="GTD 备份 JSON 文档"),
    mode: str = Query("merge", pattern="^(merge|replace)$"),
    db: Session = Depends(get_db),
    _user=Depends(get_current_user),
):
    """Restore a GTD backup. ``mode=merge`` appends, ``mode=replace`` wipes the
    user's current GTD data first (use with care — it is not reversible)."""
    # Reject oversized requests up front when Content-Length is advertised, so a
    # huge backup cannot force the whole body + decoded attachments into memory.
    content_length = request.headers.get("content-length")
    if content_length is not None:
        try:
            if int(content_length) > gtd_crud.MAX_IMPORT_BYTES:
                raise HTTPException(
                    status_code=413,
                    detail=f"备份文件不能超过 {gtd_crud.MAX_IMPORT_BYTES // (1024 * 1024)}MB",
                )
        except ValueError:
            pass
    try:
        return gtd_crud.import_all(db, _owner_id(_user), payload, mode=mode)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))
