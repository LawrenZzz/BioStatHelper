"""Owner/admin authorization through the real projects router, without startup."""

from types import SimpleNamespace
from unittest.mock import AsyncMock, Mock

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient
from sqlalchemy import create_engine, event, select
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.api.endpoints import projects
from app.api.endpoints.auth import get_current_user
from app.crud import project as project_crud
from app.db.database import get_db
from app.models.models import (
    Base, Project, ProjectAgentMessage, ProjectMember, ProjectMeeting,
    ProjectPhase, ProjectTimelineImport, ProjectTimelineItem, ProjectTodo,
    ProjectTodoChecklistItem, User,
)


PARENT_READS = [
    "", "/members", "/timeline", "/phases", "/todos", "/meetings", "/agent/messages",
]
PARENT_WRITES = [
    ("PUT", "/{project_id}", {"description": "changed"}),
    ("DELETE", "/{project_id}?confirm_name={name}", None),
    ("POST", "/{project_id}/members", {"name": "new contact"}),
    ("POST", "/{project_id}/members/parse", {"text": "private source"}),
    ("POST", "/{project_id}/timeline/text", {"source_text": "private source"}),
    ("POST", "/{project_id}/timeline/file", None),
    ("POST", "/{project_id}/standard-workflow", None),
    ("POST", "/{project_id}/phases", {"name": "new phase"}),
    ("POST", "/{project_id}/phases/reorder", {"phase_ids": []}),
    ("POST", "/{project_id}/todos", {"title": "new todo"}),
    ("POST", "/{project_id}/todos/reorder", {"phase": "review", "todo_ids": []}),
    ("POST", "/{project_id}/meetings", {"title": "new meeting"}),
    ("POST", "/{project_id}/assistant/draft", {"text": "private source"}),
    ("POST", "/{project_id}/assistant/parse", {"text": "private source"}),
    ("POST", "/{project_id}/agent", {"text": "private source"}),
]
CHILD_WRITES = [
    ("PUT", "/members/{member_id}", {"notes": "changed"}),
    ("DELETE", "/members/{member_id}", None),
    ("PUT", "/timeline/items/{timeline_item_id}", {"title": "changed"}),
    ("DELETE", "/timeline/{timeline_id}", None),
    ("PUT", "/phases/{phase_id}", {"name": "changed"}),
    ("DELETE", "/phases/{phase_id}", None),
    ("PUT", "/todos/{todo_id}", {"title": "changed"}),
    ("DELETE", "/todos/{todo_id}", None),
    ("POST", "/todos/{todo_id}/checklist", {"title": "new checklist item"}),
    ("PUT", "/todos/checklist/{checklist_id}", {"title": "changed"}),
    ("DELETE", "/todos/checklist/{checklist_id}", None),
    ("PUT", "/meetings/{meeting_id}", {"title": "changed"}),
    ("DELETE", "/meetings/{meeting_id}", None),
]
PRIVATE_ROUTES = [
    *(('GET', '/{project_id}' + suffix, None) for suffix in PARENT_READS),
    *PARENT_WRITES,
    *CHILD_WRITES,
]
AI_FUNCTIONS = (
    "parse_project_agent", "parse_project_intake", "parse_project_members",
    "parse_project_text", "parse_timeline_rows", "tailor_project_workflow",
)


@pytest.fixture()
def auth_api(monkeypatch):
    engine = create_engine(
        "sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool,
    )

    @event.listens_for(engine, "connect")
    def enable_foreign_keys(connection, _record):
        connection.execute("PRAGMA foreign_keys=ON")

    Base.metadata.create_all(engine)
    sessions = sessionmaker(bind=engine)
    api = SimpleNamespace(engine=engine, sessions=sessions, users={}, records={}, ai={})
    with sessions() as db:
        for name in ("owner", "other", "admin"):
            user = User(
                username=name, email=f"{name}@example.test", hashed_password="unused",
                is_admin=name == "admin", is_active=True,
            )
            db.add(user)
            db.flush()
            api.users[name] = SimpleNamespace(id=user.id, is_admin=user.is_admin, is_active=True)
        for name, owner_id in (
            ("owner", api.users["owner"].id), ("other", api.users["other"].id), ("legacy", None),
        ):
            project = Project(
                name=f"private-{name}", owner_id=owner_id, status="active",
                description=f"private source evidence for {name}",
            )
            db.add(project)
            db.flush()
            phase = ProjectPhase(project_id=project.id, name="review", sort_order=1)
            meeting = ProjectMeeting(project_id=project.id, title="private meeting", notes="private notes")
            # Neither appearing as a contact nor being assigned work grants access.
            member = ProjectMember(
                project_id=project.id, name="other", email="other@example.test", notes="private contact",
            )
            timeline = ProjectTimelineImport(project_id=project.id, source_text="private timeline")
            message = ProjectAgentMessage(project_id=project.id, role="user", content="private agent history")
            db.add_all([phase, meeting, member, timeline, message])
            db.flush()
            todo = ProjectTodo(
                project_id=project.id, title="private todo", phase="review", status="next",
                meeting_id=meeting.id, assignee_id=api.users["other"].id, sort_order=1,
            )
            done_todo = ProjectTodo(project_id=project.id, title="done todo", phase="review", status="done")
            db.add_all([todo, done_todo])
            db.flush()
            checklist = ProjectTodoChecklistItem(todo_id=todo.id, title="private checklist", meeting_id=meeting.id)
            db.add(checklist)
            db.flush()
            timeline_item = ProjectTimelineItem(
                project_id=project.id, timeline_import_id=timeline.id,
                title="private timeline item", target_type="checklist",
                matched_todo_id=todo.id, matched_checklist_item_id=checklist.id,
            )
            db.add(timeline_item)
            db.flush()
            api.records[name] = dict(
                project_id=project.id, name=project.name, phase_id=phase.id, member_id=member.id,
                meeting_id=meeting.id, todo_id=todo.id, checklist_id=checklist.id,
                timeline_id=timeline.id, timeline_item_id=timeline_item.id,
            )
        db.add(Project(name="hidden inbox", owner_id=api.users["owner"].id, is_inbox=True))
        db.commit()

    app = FastAPI()
    app.include_router(projects.router, prefix="/projects")

    def override_db():
        with sessions() as db:
            yield db

    api.actor = api.users["other"]
    app.dependency_overrides[get_db] = override_db
    app.dependency_overrides[get_current_user] = lambda: api.actor
    api.app = app
    for name in AI_FUNCTIONS:
        api.ai[name] = AsyncMock(side_effect=AssertionError("Unexpected external AI invocation"))
        monkeypatch.setattr(projects, name, api.ai[name])
    with TestClient(app) as client:
        api.client = client
        yield api
    engine.dispose()


def _database_rows(api):
    models = (
        Project, ProjectMember, ProjectMeeting, ProjectPhase, ProjectTodo,
        ProjectTodoChecklistItem, ProjectTimelineImport, ProjectTimelineItem, ProjectAgentMessage,
    )
    with api.engine.connect() as conn:
        return {
            model.__tablename__: conn.execute(select(model.__table__).order_by(model.id)).fetchall()
            for model in models
        }


def _request(api, route, ids):
    method, path, body = route
    path = "/projects" + path.format(**ids)
    if path.endswith("/timeline/file"):
        return api.client.request(method, path, files={"file": ("timeline.csv", b"title\nprivate", "text/csv")})
    return api.client.request(method, path, json=body)


@pytest.mark.parametrize("target", ["owner", "legacy"])
@pytest.mark.parametrize("route", PRIVATE_ROUTES, ids=lambda item: str(item))
def test_nonowner_cannot_read_or_mutate_any_project_route(auth_api, target, route):
    api = auth_api
    before = _database_rows(api)
    response = _request(api, route, api.records[target])
    assert response.status_code == 404, response.text
    assert "private" not in response.text
    missing_ids = {key: value + 100000 if isinstance(value, int) else value for key, value in api.records[target].items()}
    missing = _request(api, route, missing_ids)
    assert response.json() == missing.json()
    assert _database_rows(api) == before
    for ai in api.ai.values():
        ai.assert_not_awaited()


@pytest.mark.parametrize("actor,target", [("owner", "owner"), ("admin", "owner"), ("admin", "legacy")])
@pytest.mark.parametrize("suffix", PARENT_READS)
def test_owner_and_admin_can_read_project_lists_and_counts(auth_api, actor, target, suffix):
    api = auth_api
    api.actor = api.users[actor]
    ids = api.records[target]
    response = api.client.get(f"/projects/{ids['project_id']}{suffix}")
    assert response.status_code == 200, response.text
    if suffix:
        assert response.json()["total"] == (2 if suffix == "/todos" else 1)
        assert response.json()["data"]
    else:
        result = response.json()
        assert result["todo_count"] == 2
        assert result["done_todo_count"] == 1
        assert result["open_todo_count"] == 1
        assert result["meeting_count"] == 1
        assert result["progress_percent"] == 50
        assert result["description"] == f"private source evidence for {target}"


@pytest.mark.parametrize("actor,target", [("owner", "owner"), ("admin", "owner"), ("admin", "legacy")])
@pytest.mark.parametrize("route", CHILD_WRITES, ids=lambda item: str(item))
def test_owner_and_admin_keep_child_update_and_delete_capabilities(auth_api, actor, target, route):
    api = auth_api
    api.actor = api.users[actor]
    before = _database_rows(api)
    response = _request(api, route, api.records[target])
    assert response.status_code == 200, response.text
    assert _database_rows(api) != before


@pytest.mark.parametrize("actor,target", [("owner", "owner"), ("admin", "owner"), ("admin", "legacy")])
@pytest.mark.parametrize("route", [PARENT_WRITES[index] for index in (0, 1, 2, 7, 8, 9, 10, 11)])
def test_owner_and_admin_keep_parent_write_capabilities(auth_api, actor, target, route):
    api = auth_api
    api.actor = api.users[actor]
    response = _request(api, route, api.records[target])
    assert response.status_code == 200, response.text


@pytest.mark.parametrize("actor,expected", [("owner", ["owner"]), ("other", ["other"]), ("admin", ["owner", "other", "legacy"])])
@pytest.mark.parametrize("path", ["/projects", "/projects/"])
def test_library_and_totals_are_scoped_and_hide_inbox(auth_api, actor, expected, path):
    api = auth_api
    api.actor = api.users[actor]
    response = api.client.get(path)
    assert response.status_code == 200, response.text
    result = response.json()
    assert result["total"] == len(expected)
    assert {row["id"] for row in result["data"]} == {api.records[name]["project_id"] for name in expected}


def test_search_and_pagination_scope_before_count_and_limit(auth_api):
    api = auth_api
    api.actor = api.users["owner"]
    with api.sessions() as db:
        extra = Project(name="private-owner-extra", owner_id=api.actor.id)
        db.add(extra)
        db.commit()
        owned_ids = {extra.id, api.records["owner"]["project_id"]}
    seen = set()
    for skip in (0, 1):
        result = api.client.get("/projects/", params={"search": "private", "skip": skip, "limit": 1}).json()
        assert result["total"] == 2
        assert len(result["data"]) == 1
        seen.add(result["data"][0]["id"])
    assert seen == owned_ids
    assert api.client.get("/projects/", params={"search": "private-other"}).json() == {"data": [], "total": 0}
    result = api.client.get("/projects/", params={"skip": 2, "limit": 1}).json()
    assert result == {"data": [], "total": 2}


def test_unauthorized_reads_never_calculate_private_project_counts(auth_api, monkeypatch):
    api = auth_api
    counts = Mock(wraps=project_crud._project_counts)
    monkeypatch.setattr(project_crud, "_project_counts", counts)
    response = api.client.get("/projects/")
    assert response.status_code == 200
    assert [call.args[1].id for call in counts.call_args_list] == [api.records["other"]["project_id"]]
    counts.reset_mock()
    response = api.client.get(f"/projects/{api.records['owner']['project_id']}")
    assert response.status_code == 404
    counts.assert_not_called()


@pytest.mark.parametrize("actor", [None, SimpleNamespace(is_admin=True), SimpleNamespace(id=1, is_admin=True, is_active=False)])
def test_scope_helpers_fail_closed_without_active_identity(auth_api, actor):
    api = auth_api
    with api.sessions() as db:
        assert project_crud.get_projects_for_user(db, actor) == ([], 0)
        assert project_crud.get_project_for_user(db, api.records["owner"]["project_id"], actor) is None
        assert project_crud.get_project_child_for_user(db, ProjectTodoChecklistItem, api.records["owner"]["checklist_id"], actor) is None


@pytest.mark.parametrize("actor", ["owner", "admin"])
@pytest.mark.parametrize("binding", ["foreign", "missing", "zero"])
@pytest.mark.parametrize("operation", ["create_todo", "update_todo", "nested_checklist", "create_checklist", "update_checklist"])
def test_cannot_bind_meetings_outside_current_project(auth_api, actor, binding, operation):
    api = auth_api
    api.actor = api.users[actor]
    ids = api.records["owner"]
    meeting_id = {"foreign": api.records["other"]["meeting_id"], "missing": 100000, "zero": 0}[binding]
    before = _database_rows(api)
    if operation == "create_todo":
        response = api.client.post(f"/projects/{ids['project_id']}/todos", json={"title": "invalid", "phase": "must not be created", "meeting_id": meeting_id})
    elif operation == "update_todo":
        response = api.client.put(f"/projects/todos/{ids['todo_id']}", json={"title": "invalid", "phase": "must not be created", "meeting_id": meeting_id})
    elif operation == "nested_checklist":
        response = api.client.post(f"/projects/{ids['project_id']}/todos", json={"title": "invalid", "phase": "must not be created", "checklist_items": [{"title": "invalid", "meeting_id": meeting_id}]})
    elif operation == "create_checklist":
        response = api.client.post(f"/projects/todos/{ids['todo_id']}/checklist", json={"title": "invalid", "meeting_id": meeting_id})
    else:
        response = api.client.put(f"/projects/todos/checklist/{ids['checklist_id']}", json={"title": "invalid", "meeting_id": meeting_id})
    assert response.status_code == (404 if operation in {"create_checklist", "update_checklist"} else 400), response.text
    assert _database_rows(api) == before


def test_owner_can_bind_same_project_meeting_and_clear_it(auth_api):
    api = auth_api
    api.actor = api.users["owner"]
    ids = api.records["owner"]
    response = api.client.post(f"/projects/{ids['project_id']}/todos", json={
        "title": "valid", "meeting_id": ids["meeting_id"],
        "checklist_items": [{"title": "valid", "meeting_id": ids["meeting_id"]}],
    })
    assert response.status_code == 200, response.text
    todo = response.json()
    assert todo["meeting_id"] == ids["meeting_id"]
    checklist = todo["checklist_items"][0]
    assert checklist["meeting_id"] == ids["meeting_id"]
    response = api.client.put(f"/projects/todos/{todo['id']}", json={"meeting_id": None})
    assert response.status_code == 200, response.text
    assert response.json()["meeting_id"] is None
    response = api.client.put(f"/projects/todos/checklist/{checklist['id']}", json={"meeting_id": None})
    assert response.status_code == 200, response.text
    assert response.json()["meeting_id"] is None


@pytest.mark.parametrize("target_type,id_key", [("todo", "todo_id"), ("checklist", "checklist_id")])
def test_timeline_rejects_cross_project_target_ids(auth_api, target_type, id_key):
    api = auth_api
    api.actor = api.users["owner"]
    before = _database_rows(api)
    field = "matched_todo_id" if target_type == "todo" else "matched_checklist_item_id"
    response = api.client.put(f"/projects/timeline/items/{api.records['owner']['timeline_item_id']}", json={
        "target_type": target_type, field: api.records["other"][id_key], "title": "invalid",
    })
    assert response.status_code == 400, response.text
    assert _database_rows(api) == before


def test_reordering_cannot_update_foreign_children(auth_api):
    api = auth_api
    api.actor = api.users["owner"]
    own, other = api.records["owner"], api.records["other"]
    with api.sessions() as db:
        old_phase_order = db.get(ProjectPhase, other["phase_id"]).sort_order
        old_todo_order = db.get(ProjectTodo, other["todo_id"]).sort_order
    response = api.client.post(f"/projects/{own['project_id']}/phases/reorder", json={"phase_ids": [other["phase_id"], own["phase_id"]]})
    assert response.status_code == 200, response.text
    assert other["phase_id"] not in {row["id"] for row in response.json()["data"]}
    response = api.client.post(f"/projects/{own['project_id']}/todos/reorder", json={"phase": "review", "todo_ids": [other["todo_id"], own["todo_id"]]})
    assert response.status_code == 200, response.text
    assert other["todo_id"] not in {row["id"] for row in response.json()["data"]}
    with api.sessions() as db:
        assert db.get(ProjectPhase, other["phase_id"]).sort_order == old_phase_order
        assert db.get(ProjectTodo, other["todo_id"]).sort_order == old_todo_order


def test_project_creation_cannot_forge_another_owner(auth_api):
    api = auth_api
    api.actor = api.users["other"]
    response = api.client.post("/projects/", json={
        "name": "new private project", "create_standard_workflow": False,
        "owner_id": api.users["owner"].id,
    })
    assert response.status_code == 200, response.text
    assert response.json()["owner_id"] == api.actor.id
    project_id = response.json()["id"]
    response = api.client.put(f"/projects/{project_id}", json={"owner_id": api.users["owner"].id})
    assert response.status_code == 200
    assert response.json()["owner_id"] == api.actor.id


def test_projects_still_require_authentication(auth_api):
    api = auth_api
    del api.app.dependency_overrides[get_current_user]
    assert api.client.get("/projects/").status_code == 401
