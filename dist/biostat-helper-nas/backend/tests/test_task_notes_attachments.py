import pytest

from app.crud import gtd as gtd_crud
from app.crud import project as crud
from app.schemas.project import TodoCreate


def _todo(db, project, title="任务"):
    return crud.create_todo(db, project.id, TodoCreate(title=title, phase=None, status="next"))


def test_task_notes_crud(db_session, project):
    todo = _todo(db_session, project)
    n = gtd_crud.create_task_note(db_session, project.owner_id, todo.id, "参考", "SAP 模板链接")
    assert n["title"] == "参考"
    notes = gtd_crud.task_notes(db_session, project.owner_id, todo.id)
    assert len(notes) == 1
    assert notes[0]["content"] == "SAP 模板链接"

    assert gtd_crud.delete_task_note(db_session, project.owner_id, n["id"]) is True
    assert gtd_crud.task_notes(db_session, project.owner_id, todo.id) == []


def test_task_notes_scoped_to_user_todo(db_session, user, project):
    todo = _todo(db_session, project)
    # A different user cannot see or annotate this task.
    assert gtd_crud.task_notes(db_session, 9999, todo.id) is None
    assert gtd_crud.create_task_note(db_session, 9999, todo.id, "x", "y") is None
    # A nonexistent task errors for the owner too.
    assert gtd_crud.task_notes(db_session, project.owner_id, 123456) is None


def test_task_attachment_upload_and_download(db_session, project):
    todo = _todo(db_session, project)
    created = gtd_crud.create_task_attachment(
        db_session, project.owner_id, todo.id, "SAP.docx", b"PK\x03\x04fake", "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
    )
    assert created["filename"] == "SAP.docx"
    assert created["size_bytes"] == 8

    listed = gtd_crud.task_attachments(db_session, project.owner_id, todo.id)
    assert len(listed) == 1
    # The list DTO must NOT include raw content bytes.
    assert "content" not in listed[0]

    row = gtd_crud.get_task_attachment(db_session, project.owner_id, created["id"])
    assert row is not None and row.content == b"PK\x03\x04fake"

    assert gtd_crud.delete_task_attachment(db_session, project.owner_id, created["id"]) is True
    assert gtd_crud.task_attachments(db_session, project.owner_id, todo.id) == []


def test_task_attachment_size_cap(db_session, project):
    todo = _todo(db_session, project)
    with pytest.raises(ValueError):
        gtd_crud.create_task_attachment(
            db_session, project.owner_id, todo.id, "big.bin", b"x" * (21 * 1024 * 1024)
        )


def test_content_disposition_handles_chinese_filename():
    from app.api.endpoints.gtd import _content_disposition

    value = _content_disposition("统计分析报告.xlsx")
    # Every header value is latin-1 encoded by Starlette; it must survive that.
    value.encode("latin-1")
    # The original Chinese name is preserved via RFC 5987 filename*.
    assert "filename*=UTF-8''" in value
    # CR/LF injection is neutralised even when a hostile name is present.
    hostile = _content_disposition("x\r\nX-Custom: injected")
    assert "\r" not in hostile and "\n" not in hostile
    hostile.encode("latin-1")