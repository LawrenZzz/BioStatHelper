from datetime import datetime, timedelta

from sqlalchemy import func

from app.crud import gtd as gtd_crud
from app.crud import project as crud
from app.crud.gtd import calendar_tasks
from app.models.models import ProjectTodo
from app.schemas.project import ChecklistItemCreate, ChecklistItemUpdate, TodoCreate, TodoUpdate
from app.services.recurrence import next_due, occurrences_in_range, parse_recurrence


def _query_clones(db, todo):
    return (
        db.query(ProjectTodo)
        .filter(
            ProjectTodo.project_id == todo.project_id,
            ProjectTodo.title == todo.title,
            ProjectTodo.status == "next",
            ProjectTodo.id != todo.id,
        )
        .all()
    )


# --- schedule service -------------------------------------------------------


def test_parse_recurrence_presets_and_custom():
    assert parse_recurrence("daily") == ("day", 1)
    assert parse_recurrence("weekly") == ("week", 1)
    assert parse_recurrence("biweekly") == ("week", 2)
    assert parse_recurrence("monthly") == ("month", 1)
    assert parse_recurrence("3w") == ("week", 3)
    assert parse_recurrence("14d") == ("day", 14)
    assert parse_recurrence("") is None
    assert parse_recurrence("fortnightly") is None


def test_next_due_advances_units():
    base = datetime(2026, 9, 20, 9, 0)
    assert next_due(base, "daily") == base + timedelta(days=1)
    assert next_due(base, "weekly") == base + timedelta(days=7)
    assert next_due(base, "yearly").year == 2027


def test_occurrences_in_range_expands_from_past_base():
    # A monthly task created two months ago is due again this month and next.
    base = datetime(2026, 7, 5, 10, 0)
    hits = occurrences_in_range(base, "monthly", datetime(2026, 9, 1), datetime(2026, 10, 31))
    assert [h.day for h in hits] == [5, 5]
    assert hits[0].month == 9 and hits[1].month == 10


# --- spawn on completion ----------------------------------------------------


def test_update_todo_done_spawns_next_occurrence(db_session, project):
    due = datetime(2026, 9, 19, 17, 0)
    todo = crud.create_todo(
        db_session,
        project.id,
        TodoCreate(title="每日进度报告", phase=None, due_at=due, recurrence="daily", status="next"),
    )
    assert todo.recurrence == "daily"

    crud.update_todo(db_session, todo.id, TodoUpdate(status="done"))
    db_session.expire_all()
    clones = _query_clones(db_session, todo)
    assert len(clones) == 1
    clone = clones[0]
    assert clone.status == "next"
    assert clone.completed_at is None
    assert clone.recurrence == "daily"
    assert clone.due_at == due + timedelta(days=1)


def test_idempotent_done_does_not_double_spawn(db_session, project):
    due = datetime(2026, 9, 19, 17, 0)
    todo = crud.create_todo(
        db_session,
        project.id,
        TodoCreate(title="周报", phase=None, due_at=due, recurrence="weekly", status="next"),
    )
    crud.update_todo(db_session, todo.id, TodoUpdate(status="done"))
    # Calling done again on an already-done task must not arm another occurrence.
    crud.update_todo(db_session, todo.id, TodoUpdate(status="done"))
    db_session.expire_all()
    clones = _query_clones(db_session, todo)
    assert len(clones) == 1


def test_reopen_then_complete_spawns_again(db_session, project):
    due = datetime(2026, 9, 19, 17, 0)
    todo = crud.create_todo(
        db_session,
        project.id,
        TodoCreate(title="每日站会", phase=None, due_at=due, recurrence="daily", status="next"),
    )
    crud.update_todo(db_session, todo.id, TodoUpdate(status="done"))
    # Reopen, then complete again: each fresh transition arms one occurrence.
    crud.update_todo(db_session, todo.id, TodoUpdate(status="next"))
    crud.update_todo(db_session, todo.id, TodoUpdate(status="done"))
    db_session.expire_all()
    # The first spawn plus the reopen spawn.
    clones = _query_clones(db_session, todo)
    assert len(clones) == 2
    # Both clones are distinct rows and remain independently actionable.
    assert len({c.id for c in clones}) == 2


def test_checklist_completion_spawns_and_copies_fresh_items(db_session, project):
    due = datetime(2026, 9, 18, 12, 0)
    todo = crud.create_todo(
        db_session,
        project.id,
        TodoCreate(
            title="每日核查",
            phase=None,
            due_at=due,
            recurrence="daily",
            status="next",
            checklist_items=[ChecklistItemCreate(title="核对", is_done=False)],
        ),
    )
    first_item = todo.checklist_items[0]
    # Completing via the checklist transitions to done -> spawns a clone whose
    # copy of the checklist is un-checked again.
    crud.update_checklist_item(db_session, first_item.id, ChecklistItemUpdate(is_done=True))
    db_session.expire_all()
    clones = _query_clones(db_session, todo)
    assert len(clones) == 1
    clone = clones[0]
    assert clone.status == "next"
    assert len(clone.checklist_items) == 1
    assert clone.checklist_items[0].is_done is False
    assert clone.due_at == due + timedelta(days=1)


def test_process_inbox_done_with_recurrence_spawns(db_session, user, project):
    created = gtd_crud.create_inbox_task(
        db_session,
        user.id,
        "每周患者随访",
        due_at=datetime(2026, 9, 20, 9, 0),
    )
    todo = db_session.get(ProjectTodo, created["todo_id"])
    todo.recurrence = "weekly"
    db_session.commit()

    result = gtd_crud.process_inbox_task(db_session, user.id, todo.id, action="done")
    assert result is not None
    db_session.expire_all()
    clones = _query_clones(db_session, todo)
    assert len(clones) == 1
    assert clones[0].status == "next"


# --- calendar expansion -----------------------------------------------------


def test_calendar_tasks_expands_recurring_occurrences(db_session, project):
    # One-off due inside range...
    crud.create_todo(
        db_session,
        project.id,
        TodoCreate(title="一次性任务", phase=None, due_at=datetime(2026, 9, 21, 10, 0), status="next"),
    )
    # ...and a monthly recurrence whose base is before the range.
    crud.create_todo(
        db_session,
        project.id,
        TodoCreate(title="月报", phase=None, due_at=datetime(2026, 8, 5, 9, 0), recurrence="monthly", status="next"),
    )
    rows = calendar_tasks(db_session, project.owner_id, datetime(2026, 9, 1), datetime(2026, 9, 30))
    by_title: dict[str, list] = {}
    for row in rows:
        by_title.setdefault(row["title"], []).append(row)
    assert any(row["occurrence_due_at"].startswith("2026-09-21") for row in by_title["一次性任务"])
    sept = [r for r in by_title["月报"] if r["occurrence_due_at"].startswith("2026-09-")]
    assert len(sept) == 1
    assert sept[0]["occurrence_due_at"].startswith("2026-09-05")


def test_calendar_tasks_omits_done(db_session, project):
    crud.create_todo(
        db_session,
        project.id,
        TodoCreate(title="旧任务", phase=None, due_at=datetime(2026, 9, 21, 10, 0), status="done"),
    )
    rows = calendar_tasks(db_session, project.owner_id, datetime(2026, 9, 1), datetime(2026, 9, 30))
    assert rows == []


# --- contexts directory -----------------------------------------------------


def test_list_contexts_people_from_members_and_places_from_todos(db_session, user, project):
    from app.models.models import ProjectMember

    db_session.add(ProjectMember(project_id=project.id, name="陈统计师", member_type="statistician"))
    db_session.commit()
    crud.create_todo(
        db_session,
        project.id,
        TodoCreate(title="任务", phase=None, contexts=["@办公室", "@陈统计师"], status="next"),
    )
    contexts = gtd_crud.list_contexts(db_session, user.id)
    assert "@陈统计师" in contexts["people"]
    assert "@办公室" in contexts["places"]
    assert "@陈统计师" not in contexts["places"]