from pydantic import ValidationError

from app.crud.project import GTD_ACTIVE, GTD_CLOSED, GTD_SOMEDAY, GTD_DONE
from app.schemas.project import TodoCreate


def test_todo_schema_accepts_gtd_statuses():
    assert TodoCreate(title="写SAP", status="next").status == "next"
    assert TodoCreate(title="旧数据", status="open").status == "open"
    assert TodoCreate(title="等DM", status="waiting").status == "waiting"
    assert TodoCreate(title="以后", status="someday").status == "someday"
    assert TodoCreate(title="参考", status="reference").status == "reference"
    assert TodoCreate(title="归档", status="archived").status == "archived"


def test_todo_schema_rejects_unknown_status():
    with __import__("pytest").raises(ValidationError):
        TodoCreate(title="bad", status="banana")


def test_predicate_sets_classify_statuses():
    # Legacy clinical pipeline statuses are preserved and grouped into GTD sets.
    assert GTD_ACTIVE == {"next", "open", "in_progress", "blocked", "waiting"}
    assert "done" in GTD_DONE
    assert GTD_CLOSED == {"done", "cancelled", "archived"}
    assert GTD_SOMEDAY == {"someday", "reference"}
    # open is kept as a legacy synonym and still counts as active.
    assert "open" in GTD_ACTIVE