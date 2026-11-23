from app.crud import gtd as gtd_crud
from app.crud import project as crud
from app.models.models import Project, ProjectTodo
from app.schemas.project import ProjectCreate, TodoCreate


def test_inbox_project_get_or_create_is_idempotent(db_session, user):
    first = gtd_crud.get_inbox_project(db_session, user.id)
    second = gtd_crud.get_inbox_project(db_session, user.id)
    assert first.id == second.id
    assert first.is_inbox is True
    assert first.name == "收件箱"


def test_inbox_task_created_under_hidden_project(db_session, user):
    item = gtd_crud.create_inbox_task(db_session, user.id, "确认锁库前Query关闭")
    assert item["status"] == "inbox"
    assert item["project_is_inbox"] is True
    assert item["project_name"] == "收件箱"


def test_inbox_project_hidden_from_project_library(db_session, user):
    gtd_crud.create_inbox_task(db_session, user.id, "捕获一条")
    # create a real project so the library is non-empty
    crud.create_project(
        db_session,
        ProjectCreate(name="真实项目", create_standard_workflow=False),
        owner_id=user.id,
    )
    projects, total = crud.get_projects(db_session)
    names = [p.name for p in projects]
    assert "收件箱" not in names
    assert "真实项目" in names


def test_process_inbox_moves_to_next_and_reparents(db_session, user, project):
    item = gtd_crud.create_inbox_task(db_session, user.id, "写SAP统计方法章节")
    processed = gtd_crud.process_inbox_task(
        db_session,
        user.id,
        item["todo_id"],
        action="next",
        project_id=project.id,
        phase="SAP与TFL",
    )
    assert processed["status"] == "next"
    assert processed["project_id"] == project.id
    assert processed["project_name"] == project.name
    assert processed["phase"] == "SAP与TFL"

    inbox_remaining = gtd_crud.list_inbox(db_session, user.id)
    assert inbox_remaining == []


def test_process_inbox_to_waiting_and_someday(db_session, user, project):
    waiting = gtd_crud.create_inbox_task(db_session, user.id, "等DM回复query")
    processed = gtd_crud.process_inbox_task(db_session, user.id, waiting["todo_id"], action="waiting")
    assert processed["status"] == "waiting"

    someday = gtd_crud.create_inbox_task(db_session, user.id, "以后学混合模型")
    processed2 = gtd_crud.process_inbox_task(db_session, user.id, someday["todo_id"], action="someday")
    assert processed2["status"] == "someday"
    assert len(gtd_crud.list_waiting(db_session, user.id)) == 1
    assert len(gtd_crud.list_someday(db_session, user.id)) == 1