from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from fastapi import HTTPException
from types import SimpleNamespace

from app.api.endpoints.projects import delete_project as delete_project_endpoint
from app.crud.project import apply_agent_plan, create_project_from_intake
from app.services.project_workflow import build_workflow_blueprint
from app.models.models import (
    Base,
    Project,
    ProjectAgentMessage,
    ProjectMeeting,
    ProjectPhase,
    ProjectTodo,
    ProjectTodoChecklistItem,
)
from app.schemas.project import ProjectAgentPlan, ProjectIntakeDraft, ProjectIntakeTodo


def _session():
    engine = create_engine("sqlite:///:memory:")
    Base.metadata.create_all(engine)
    return sessionmaker(bind=engine)()


def test_agent_applies_completion_task_and_bound_meeting():
    db = _session()
    project = Project(name="Agent test", status="active")
    db.add(project)
    db.flush()
    db.add(ProjectPhase(project_id=project.id, name="SAP与TFL", sort_order=1))
    existing = ProjectTodo(
        project_id=project.id,
        title="完成SAP初稿",
        phase="SAP与TFL",
        status="in_progress",
        sort_order=1,
    )
    db.add(existing)
    db.commit()

    plan = ProjectAgentPlan.model_validate(
        {
            "intent": "mixed",
            "summary": "SAP初稿已完成，安排审阅并创建会议。",
            "current_phase": "SAP与TFL",
            "completed_todo_ids": [existing.id],
            "todos": [
                {
                    "ref": "review",
                    "action": "create",
                    "title": "完成SAP交叉审阅",
                    "phase": "SAP与TFL",
                    "status": "open",
                    "due_at": "2026-09-01T18:00:00+08:00",
                    "checklist_items": [
                        {"title": "汇总审阅意见", "is_done": False}
                    ],
                }
            ],
            "meetings": [
                {
                    "action": "create",
                    "title": "SAP审阅会",
                    "starts_at": "2026-08-28T15:00:00+08:00",
                    "ends_at": "2026-08-28T15:30:00+08:00",
                    "todo_ref": "review",
                }
            ],
        }
    )
    result = apply_agent_plan(db, project.id, plan, "SAP初稿完成，安排审阅会")

    db.refresh(existing)
    created = result["created_todos"][0]
    meeting = result["created_meetings"][0]
    assert existing.status == "done"
    assert created.phase == "SAP与TFL"
    assert created.meeting_id == meeting.id
    assert len(created.checklist_items) == 1
    assert meeting.starts_at.hour == 15
    assert meeting.ends_at.minute == 30
    assert result["completed_todo_count"] == 1


def test_agent_rejects_cross_project_todo_reference():
    db = _session()
    first = Project(name="First")
    second = Project(name="Second")
    db.add_all([first, second])
    db.flush()
    foreign_todo = ProjectTodo(
        project_id=second.id,
        title="Foreign todo",
        phase="项目启动",
        status="open",
    )
    db.add(foreign_todo)
    db.commit()

    plan = ProjectAgentPlan.model_validate(
        {"completed_todo_ids": [foreign_todo.id]}
    )
    try:
        apply_agent_plan(db, first.id, plan, "完成任务")
    except ValueError as exc:
        assert "不属于当前项目" in str(exc)
        db.rollback()
    else:
        raise AssertionError("Cross-project reference should have been rejected")


def test_create_project_from_intake_applies_progress_and_keeps_clinical_phase():
    db = _session()
    draft = ProjectIntakeDraft.model_validate(
        {
            "name": "Intake test",
            "phase": "Phase II",
            "current_phase": "SAP与TFL",
            "completed_todo_titles": ["起草或审阅SAP，明确主要/次要终点、模型、缺失数据和敏感性分析策略"],
            "in_progress_todo_titles": ["准备TFL shell/mock，并与医学、运营、DM和编程确认"],
            "todos": [
                ProjectIntakeTodo(
                    title="安排统计团队评审",
                    phase="SAP与TFL",
                    status="open",
                )
            ],
        }
    )
    result = create_project_from_intake(db, draft, "项目背景和当前进展", owner_id=None)

    project = result["project"]
    assert project.phase == "Phase II"
    assert project.current_workflow_phase == "SAP与TFL"
    todos = db.query(ProjectTodo).filter(ProjectTodo.project_id == project.id).all()
    assert any(todo.status == "done" for todo in todos)
    assert any(todo.status == "in_progress" for todo in todos)
    assert any(todo.title == "安排统计团队评审" for todo in todos)


def test_project_owner_can_delete_project_and_all_related_records():
    db = _session()
    project = Project(name="待删除项目", owner_id=7, status="active")
    db.add(project)
    db.flush()
    phase = ProjectPhase(project_id=project.id, name="SAP与TFL", sort_order=1)
    meeting = ProjectMeeting(project_id=project.id, title="项目会议")
    db.add_all([phase, meeting])
    db.flush()
    todo = ProjectTodo(
        project_id=project.id,
        title="审阅SAP",
        phase="SAP与TFL",
        meeting_id=meeting.id,
    )
    db.add(todo)
    db.flush()
    checklist = ProjectTodoChecklistItem(
        todo_id=todo.id,
        title="关闭审阅意见",
        meeting_id=meeting.id,
    )
    message = ProjectAgentMessage(
        project_id=project.id,
        user_id=7,
        role="user",
        content="记录下一步安排",
    )
    db.add_all([checklist, message])
    db.commit()

    result = delete_project_endpoint(
        project.id,
        confirm_name=project.name,
        db=db,
        current_user=SimpleNamespace(id=7, is_admin=False),
    )

    assert "已删除" in result["message"]
    assert db.query(Project).count() == 0
    assert db.query(ProjectPhase).count() == 0
    assert db.query(ProjectTodo).count() == 0
    assert db.query(ProjectTodoChecklistItem).count() == 0
    assert db.query(ProjectMeeting).count() == 0
    assert db.query(ProjectAgentMessage).count() == 0


def test_workflow_keeps_sap_and_tfl_together_but_separates_checklists():
    workflow = build_workflow_blueprint("drug", False)
    sap_tfl = next(phase for phase in workflow if phase["name"] == "SAP与TFL")
    titles = {todo["title"] for todo in sap_tfl["todos"]}
    assert {"SAP/TFL撰写", "SAP/TFL联合审阅", "SAP/TFL定稿"} <= titles
    writing = next(todo for todo in sap_tfl["todos"] if todo["title"] == "SAP/TFL撰写")
    assert any("SAP" in item for item in writing["checklist_items"])
    assert any("TFL" in item for item in writing["checklist_items"])
    assert all(phase["name"] != "CDISC与数据集" for phase in workflow)


def test_cdisc_workflow_contains_submission_data_standard_tasks():
    workflow = build_workflow_blueprint("vaccine", True)
    phases = {phase["name"]: phase for phase in workflow}
    assert "CDISC与数据集" in phases
    titles = {
        todo["title"]
        for phase in workflow
        for todo in phase["todos"]
    }
    assert "SDTM策略、映射与验证" in titles
    assert "ADaM规格、编程与可追溯性" in titles
    assert "Define与审评资料准备" in titles


def test_create_project_from_intake_persists_type_and_cdisc():
    db = _session()
    draft = ProjectIntakeDraft.model_validate(
        {
            "name": "Vaccine project",
            "project_type": "vaccine",
            "is_cdisc": True,
            "create_standard_workflow": True,
        }
    )
    result = create_project_from_intake(
        db,
        draft,
        "疫苗项目，采用SDTM和ADaM",
        owner_id=None,
    )
    project = result["project"]
    assert project.project_type == "vaccine"
    assert project.is_cdisc is True
    assert db.query(ProjectPhase).filter(
        ProjectPhase.project_id == project.id,
        ProjectPhase.name == "CDISC与数据集",
    ).count() == 1


def test_project_delete_rejects_wrong_confirmation_name():
    db = _session()
    project = Project(name="保留项目", owner_id=9, status="active")
    db.add(project)
    db.commit()

    try:
        delete_project_endpoint(
            project.id,
            confirm_name="错误名称",
            db=db,
            current_user=SimpleNamespace(id=9, is_admin=False),
        )
    except HTTPException as exc:
        assert exc.status_code == 400
    else:
        raise AssertionError("错误确认名称不应删除项目")

    assert db.query(Project).filter(Project.id == project.id).count() == 1
