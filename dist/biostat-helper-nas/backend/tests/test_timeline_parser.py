from datetime import datetime
from io import BytesIO

from openpyxl import Workbook

from app.crud.project import build_timeline_context, create_timeline_import, delete_checklist_item, delete_todo
from app.models.models import (
    Base,
    Project,
    ProjectPhase,
    ProjectTimelineItem,
    ProjectTodo,
    ProjectTodoChecklistItem,
)
from app.services.timeline_parser import parse_text_rows, parse_xlsx_bytes
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker


def _session():
    engine = create_engine("sqlite:///:memory:")
    Base.metadata.create_all(engine)
    return sessionmaker(bind=engine)()


def test_text_timeline_keeps_chinese_time_range():
    text = "会议安排 2026年8月18日 15点-15点半"
    item = parse_text_rows(text)[0]

    assert item["start_at"] == datetime(2026, 8, 18, 15, 0)
    assert item["due_at"] == datetime(2026, 8, 18, 15, 30)


def test_iso_timestamp_does_not_treat_timezone_as_end_time():
    item = parse_text_rows("事项 2026-08-18T09:00:00+08:00")[0]

    assert item["start_at"] == datetime(2026, 8, 18, 9, 0)
    assert item["due_at"] == datetime(2026, 8, 18, 9, 0)


def test_xlsx_timeline_uses_action_column_and_fills_merged_phase():
    workbook = Workbook()
    sheet = workbook.active
    sheet.append(["序号", "里程碑", "里程碑名称", "计划开始时间", "计划结束时间"])
    sheet.append([1, "SAP与TFL", "SAP/TFL撰写", "2026-08-18", "2026-08-20"])
    sheet.append([2, None, "SAP/TFL审阅", "2026-08-21", "2026-08-22"])
    stream = BytesIO()
    workbook.save(stream)

    rows = parse_xlsx_bytes(stream.getvalue())

    assert len(rows) == 2
    assert rows[0]["title"] == "SAP/TFL撰写"
    assert rows[1]["title"] == "SAP/TFL审阅"
    assert rows[0]["phase"] == "SAP与TFL"
    assert rows[1]["phase"] == "SAP与TFL"


def test_timeline_context_has_real_ids_and_deleted_targets_are_unbound():
    db = _session()
    project = Project(name="Timeline project")
    db.add(project)
    db.flush()
    phase = ProjectPhase(project_id=project.id, name="SAP与TFL", sort_order=1)
    todo = ProjectTodo(project_id=project.id, title="SAP/TFL撰写", phase=phase.name, sort_order=1)
    db.add_all([phase, todo])
    db.flush()
    checklist = ProjectTodoChecklistItem(todo_id=todo.id, title="核对SAP和TFL")
    db.add(checklist)
    db.flush()
    timeline = create_timeline_import(
        db,
        project.id,
        source_type="text",
        file_name=None,
        source_text="SAP/TFL撰写",
        raw_rows=[{"title": "SAP/TFL撰写"}],
        parsed_items=[
            {
                "title": "SAP/TFL撰写",
                "target_type": "todo",
                "matched_todo_id": todo.id,
                "start_at": datetime(2026, 8, 18),
                "due_at": datetime(2026, 8, 20),
            },
        ],
        model_used="local-rule",
        fallback_used=True,
    )
    context = build_timeline_context(db, project.id)
    timeline_item = timeline.items[0]

    assert context["phases"] == [{"id": phase.id, "name": "SAP与TFL"}]
    assert context["todos"][0]["id"] == todo.id
    assert context["todos"][0]["checklist_items"][0]["id"] == checklist.id
    assert timeline_item.matched_todo_id == todo.id

    delete_checklist_item(db, checklist.id)
    db.refresh(timeline_item)
    assert timeline_item.target_type == "todo"

    delete_todo(db, todo.id)
    db.refresh(timeline_item)
    assert timeline_item.target_type == "none"
    assert timeline_item.matched_todo_id is None
    assert db.query(ProjectTimelineItem).count() == 1
