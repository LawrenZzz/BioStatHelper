import base64

import pytest

from app.crud import gtd as gtd_crud
from app.crud import project as crud
from app.schemas.project import ProjectCreate, ProjectMemberCreate, ProjectPhaseCreate, TodoCreate


def _seed(db, user):
    """Create a representative GTD workspace and return (inbox_todo_id,
    project_id, todo_id)."""
    # A saved filter.
    gtd_crud.create_saved_filter(db, user.id, "下一步-SAP", {"status": "next", "q": "SAP"})

    # An inbox capture with a note + attachment.
    inbox = gtd_crud.create_inbox_task(db, user.id, "整理周五演示", "从收件箱捕获")
    gtd_crud.create_task_note(db, user.id, inbox["todo_id"], "背景", "需要材料A")
    gtd_crud.create_task_attachment(
        db, user.id, inbox["todo_id"], "演示.pptx", b"PK\x03\x04demo", "application/vnd.openxmlformats-officedocument.presentationml.presentation"
    )

    # A real project with a phase, a member and a todo carrying checklist/notes/attachments.
    project = crud.create_project(
        db, ProjectCreate(name="SAP分析", protocol_no="P-9", create_standard_workflow=False),
        owner_id=user.id,
    )
    crud.create_project_phase(db, project.id, ProjectPhaseCreate(name="SDTM", sort_order=0))
    crud.create_project_member(
        db, project.id,
        ProjectMemberCreate(member_type="sponsor", name="辉瑞", email="pf@example.com"),
    )
    todo = crud.create_todo(
        db, project.id,
        TodoCreate(
            title="生成ADaM", phase="SDTM", status="next", contexts=["@DM"], tags=["ADaM"],
            checklist_items=[
                {"title": "跑宏", "is_done": False, "sort_order": 0},
                {"title": "审阅", "is_done": False, "sort_order": 1},
            ],
        ),
    )
    gtd_crud.create_task_note(db, user.id, todo.id, "SAP", "第3章")
    gtd_crud.create_task_attachment(
        db, user.id, todo.id, "输出.docx", b"PK\x03\x04fake", "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
    )
    return inbox["todo_id"], project.id, todo.id


def test_export_import_roundtrip_preserves_gtd_state(db_session, user):
    _seed(db_session, user)
    doc = gtd_crud.export_all(db_session, user.id)

    # Sanity: versioned envelope.
    assert doc["app"] == "biostat-helper"
    assert doc["kind"] == "gtd-backup"
    assert doc["version"] == 1

    # Replace-import into the same session and verify counts.
    result = gtd_crud.import_all(db_session, user.id, doc, mode="replace")
    imported = result["imported"]
    assert imported["saved_filters"] == 1
    assert imported["inbox"] == 1
    assert imported["projects"] == 1
    assert imported["todos"] == 2          # one inbox + one project todo
    assert imported["notes"] == 2
    assert imported["attachments"] == 2

    # The re-imported project todo kept its contexts/tags/checklist as lists,
    # not re-serialized JSON strings (round-trip fidelity).
    todos = gtd_crud.query_tasks(db_session, user.id, q="生成ADaM")
    assert len(todos) == 1
    assert todos[0]["contexts"] == ["@DM"]
    assert todos[0]["tags"] == ["ADaM"]
    assert todos[0]["project_name"] == "SAP分析"

    # Attachment content survived the base64 round-trip.
    atts = gtd_crud.task_attachments(db_session, user.id, todos[0]["todo_id"])
    assert len(atts) == 1
    row = gtd_crud.get_task_attachment(db_session, user.id, atts[0]["id"])
    assert row.content == b"PK\x03\x04fake"

    # Saved filters came back.
    filters = gtd_crud.list_saved_filters(db_session, user.id)
    assert filters[0]["name"] == "下一步-SAP"


def test_import_replace_wipes_existing_but_keeps_unrelated(db_session, user):
    _seed(db_session, user)
    doc = gtd_crud.export_all(db_session, user.id)

    # Add a second distinct project; after replace-import it must be gone.
    extra = crud.create_project(
        db_session, ProjectCreate(name="临时项目", create_standard_workflow=False),
        owner_id=user.id,
    )
    assert crud.get_project(db_session, extra.id) is not None

    gtd_crud.import_all(db_session, user.id, doc, mode="replace")

    # The extra project (added after the export) is wiped, and not in the backup.
    assert crud.get_project(db_session, extra.id) is None
    # The backup's own data is restored: the capture + the real project.
    assert len(gtd_crud.list_inbox(db_session, user.id)) == 1
    projects, _ = crud.get_projects(db_session)
    assert len([p for p in projects if not p.is_inbox]) == 1


def test_import_merge_appends_without_deleting(db_session, user):
    _seed(db_session, user)
    doc = gtd_crud.export_all(db_session, user.id)
    before = len(gtd_crud.list_inbox(db_session, user.id))

    gtd_crud.import_all(db_session, user.id, doc, mode="merge")

    # Merge duplicates the inbox item but leaves the original untouched.
    assert len(gtd_crud.list_inbox(db_session, user.id)) == before + 1


def test_import_rejects_foreign_document(db_session, user):
    with pytest.raises(ValueError):
        gtd_crud.import_all(db_session, user.id, {"app": "other", "kind": "nope"}, mode="merge")
    with pytest.raises(ValueError):
        gtd_crud.import_all(db_session, user.id, {"app": "biostat-helper", "kind": "gtd-backup", "version": 99}, mode="merge")


def test_export_is_scoped_to_owner(db_session, user):
    _seed(db_session, user)
    # A different owner must not see the user's projects/filters in export.
    other_doc = gtd_crud.export_all(db_session, 9999)
    assert other_doc["projects"] == []
    assert other_doc["inbox"] == []
    assert other_doc["saved_filters"] == []

    # Importing the user's backup as another user restores it for *that* user,
    # and must not disturb the original owner's data (replace only wipes the
    # importing user's own scope).
    doc = gtd_crud.export_all(db_session, user.id)
    gtd_crud.import_all(db_session, 9999, doc, mode="replace")
    assert len(gtd_crud.list_saved_filters(db_session, 9999)) == 1
    assert len(gtd_crud.list_inbox(db_session, 9999)) == 1
    # The original owner's data is untouched.
    assert len(gtd_crud.list_saved_filters(db_session, user.id)) == 1
    assert len(gtd_crud.list_inbox(db_session, user.id)) == 1


def test_import_replace_is_atomic(db_session, user, monkeypatch):
    """A replace-import that fails mid-rebuild must not destroy existing data."""
    _seed(db_session, user)
    doc = gtd_crud.export_all(db_session, user.id)

    import app.crud.gtd as g

    def boom(db, user_id, p):
        raise ValueError("boom")

    monkeypatch.setattr(g, "_build_project", boom)
    with pytest.raises(ValueError):
        g.import_all(db_session, user.id, doc, mode="replace")

    # The rollback undid the wipe: the user's original data is intact.
    assert len(gtd_crud.list_saved_filters(db_session, user.id)) == 1
    assert len(gtd_crud.list_inbox(db_session, user.id)) == 1
    projects, _ = crud.get_projects(db_session)
    assert len([p for p in projects if not p.is_inbox]) == 1


def test_import_rejects_malformed_shape(db_session, user):
    with pytest.raises(ValueError):
        gtd_crud.import_all(
            db_session, user.id,
            {"app": "biostat-helper", "kind": "gtd-backup", "version": 1, "projects": "notalist"},
            mode="merge",
        )
    with pytest.raises(ValueError):
        gtd_crud.import_all(
            db_session, user.id,
            {"app": "biostat-helper", "kind": "gtd-backup", "version": 1, "projects": [1, 2]},
            mode="merge",
        )


def test_empty_attachment_roundtrips(db_session, user):
    inbox = gtd_crud.create_inbox_task(db_session, user.id, "空附件测试")
    gtd_crud.create_task_attachment(db_session, user.id, inbox["todo_id"], "empty.txt", b"", "text/plain")
    doc = gtd_crud.export_all(db_session, user.id)
    gtd_crud.import_all(db_session, user.id, doc, mode="replace")

    inbox_after = gtd_crud.list_inbox(db_session, user.id)
    assert len(inbox_after) == 1
    atts = gtd_crud.task_attachments(db_session, user.id, inbox_after[0]["todo_id"])
    assert len(atts) == 1          # empty-but-valid attachment is preserved
    row = gtd_crud.get_task_attachment(db_session, user.id, atts[0]["id"])
    assert row.content == b""


def test_import_tolerates_bad_values(db_session, user):
    """Defensive parsing: bad sort_order/version fall back instead of crashing."""
    doc = {
        "app": "biostat-helper", "kind": "gtd-backup", "version": "1.0.0",
        "saved_filters": [], "inbox": [],
        "projects": [{
            "name": "P", "sort_order": "abc",
            "phases": [{"name": "Ph", "sort_order": "oops"}],
            "members": [{"name": "M", "sort_order": "xyz"}],
            "todos": [{"title": "T", "sort_order": "bad",
                       "checklist": [{"title": "c", "sort_order": "nope"}]}],
        }],
    }
    result = gtd_crud.import_all(db_session, user.id, doc, mode="merge")
    assert result["imported"]["projects"] == 1
    assert result["imported"]["todos"] == 1
    # And a non-numeric version is treated as the oldest, not a crash.
    doc["version"] = "latest"
    gtd_crud.import_all(db_session, user.id, doc, mode="merge")
    doc["version"] = 99
    with pytest.raises(ValueError):
        gtd_crud.import_all(db_session, user.id, doc, mode="merge")
