from app.crud import project as crud
from app.models.models import ProjectTodo
from app.schemas.project import ChecklistItemCreate, ChecklistItemUpdate, TodoCreate


def _todo_with_checklist(db, project_id, titles):
    return crud.create_todo(
        db,
        project_id,
        TodoCreate(
            title="SAP定稿",
            phase=None,
            checklist_items=[ChecklistItemCreate(title=t) for t in titles],
        ),
    )


def test_checklist_full_marks_todo_done_and_stamps_completed_at(db_session, project):
    todo = _todo_with_checklist(db_session, project.id, ["核对方案", "核对TFL"])
    assert todo.status in {"next", "open"}
    items = sorted(todo.checklist_items, key=lambda i: i.sort_order)

    crud.update_checklist_item(db_session, items[0].id, ChecklistItemUpdate(is_done=True))
    db_session.expire_all()
    partial = db_session.get(ProjectTodo, todo.id)
    # one of two done -> in_progress
    assert partial.status == "in_progress"

    crud.update_checklist_item(db_session, items[1].id, ChecklistItemUpdate(is_done=True))
    db_session.expire_all()
    complete = db_session.get(ProjectTodo, todo.id)
    # all items done -> auto-completed, the core "forgot to update status" fix
    assert complete.status == "done"
    assert complete.completed_at is not None


def test_unchecking_marks_in_progress(db_session, project):
    todo = _todo_with_checklist(db_session, project.id, ["a", "b"])
    for item in todo.checklist_items:
        crud.update_checklist_item(db_session, item.id, ChecklistItemUpdate(is_done=True))
    db_session.expire_all()

    item0 = db_session.get(todo.checklist_items[0].__class__, todo.checklist_items[0].id)
    crud.update_checklist_item(db_session, item0.id, ChecklistItemUpdate(is_done=False))
    db_session.expire_all()
    reopened = db_session.get(ProjectTodo, todo.id)
    assert reopened.status == "in_progress"