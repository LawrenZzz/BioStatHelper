from datetime import datetime, timedelta

from app.crud import gtd as gtd_crud
from app.crud import project as crud
from app.models.models import ProjectTodo
from app.schemas.project import ChecklistItemCreate, TodoUpdate, TodoCreate


def _make_todo(db, project_id, title, **kwargs):
    return crud.create_todo(db, project_id, TodoCreate(title=title, **kwargs))


def test_weekly_review_counts_completed_and_flags_stale_open(db_session, user, project):
    # 1) a task completed this week
    done = _make_todo(db_session, project.id, "完成锁库QC", status="next")
    crud.update_todo(db_session, done.id, TodoUpdate(status="done"))

    # 2) checklist full but status was downgraded out of done => stale (checklist_done)
    stale_todo = crud.create_todo(
        db_session,
        project.id,
        TodoCreate(
            title="TFL已核对完",
            checklist_items=[ChecklistItemCreate(title="核对表1"), ChecklistItemCreate(title="核对表2")],
        ),
    )
    from app.schemas.project import ChecklistItemUpdate
    for item in stale_todo.checklist_items:
        crud.update_checklist_item(db_session, item.id, ChecklistItemUpdate(is_done=True))
    db_session.expire_all()
    stale = db_session.get(ProjectTodo, stale_todo.id)
    assert stale.status == "done"
    # simulate the "forgot to update status" by moving it out of done
    crud.update_todo(db_session, stale.id, TodoUpdate(status="in_progress"))

    # 3) an overdue, still-open task => stale (overdue)
    overdue = _make_todo(
        db_session,
        project.id,
        "提交SAP",
        status="next",
        due_at=datetime.now() - timedelta(days=2),
    )

    report = gtd_crud.weekly_review(db_session, user.id)
    counts = report["counts"]
    assert counts["completed_todos"] >= 1

    reasons = {item["title"]: item["reason"] for item in report["stale_open"]}
    assert reasons.get("TFL已核对完") == "checklist_done"
    assert reasons.get("提交SAP") == "overdue"

    assert any(n["project_name"] == project.name for n in report["needs_review"])

    # review ran -> prompt clears
    assert gtd_crud.review_status(db_session, user.id)["due"] is False


def test_review_due_before_run_true(db_session, user):
    assert gtd_crud.review_status(db_session, user.id)["due"] is True
    gtd_crud.weekly_review(db_session, user.id)
    assert gtd_crud.review_status(db_session, user.id)["due"] is False
    # a fresh user (no record) is due
    from app.models.models import User
    u2 = User(username="u2", email="u2@example.com", hashed_password="x")
    db_session.add(u2)
    db_session.commit()
    assert gtd_crud.review_status(db_session, u2.id)["due"] is True