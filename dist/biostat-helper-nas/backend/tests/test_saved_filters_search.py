from app.crud import gtd as gtd_crud
from app.crud import project as crud
from app.schemas.project import TodoCreate


def _mk(db, project, title, **kw):
    crud.create_todo(db, project.id, TodoCreate(title=title, phase=None, **kw))


def test_query_tasks_fulltext_search(db_session, project):
    _mk(db_session, project, "撰写统计分析方法SAP")
    _mk(db_session, project, "核查可行性预报", description="评估SAP覆盖率")
    _mk(db_session, project, "无关事项")

    hits = [t["title"] for t in gtd_crud.query_tasks(db_session, project.owner_id, q="SAP")]
    assert set(hits) == {"核查可行性预报", "撰写统计分析方法SAP"}
    none = gtd_crud.query_tasks(db_session, project.owner_id, q="不存在关键词xyz")
    assert none == []


def test_query_tasks_context_and_tag_filter(db_session, project):
    _mk(db_session, project, "A", contexts=["@DM", "@work"], tags=["SAP"])
    _mk(db_session, project, "B", contexts=["@home"], tags=["TFL"])

    dm = [t["title"] for t in gtd_crud.query_tasks(db_session, project.owner_id, contexts=["@DM"])]
    assert dm == ["A"]
    sap = [t["title"] for t in gtd_crud.query_tasks(db_session, project.owner_id, tags=["SAP"])]
    assert sap == ["A"]
    # OR within a dimension: matching either context.
    either = [t["title"] for t in gtd_crud.query_tasks(
        db_session, project.owner_id, contexts=["@DM", "@home"])]
    assert sorted(either) == ["A", "B"]


def test_query_tasks_area_priority_focus(db_session, project):
    _mk(db_session, project, "重要", priority="high", area="工作", is_focused_today=True)
    _mk(db_session, project, "普通", priority="normal", area="家庭")

    focus = gtd_crud.query_tasks(db_session, project.owner_id, is_focused_today=True)
    assert [t["title"] for t in focus] == ["重要"]
    high = gtd_crud.query_tasks(db_session, project.owner_id, priority="high")
    assert [t["title"] for t in high] == ["重要"]
    family = gtd_crud.query_tasks(db_session, project.owner_id, area="家庭")
    assert [t["title"] for t in family] == ["普通"]


def test_saved_filter_crud(db_session, user, project):
    _mk(db_session, project, "待办甲", status="next")
    _mk(db_session, project, "待办乙", status="done")

    created = gtd_crud.create_saved_filter(
        db_session, user.id, "我的下一步", {"status": "next", "area": "工作"})["id"]
    listed = gtd_crud.list_saved_filters(db_session, user.id)
    assert len(listed) == 1
    assert listed[0]["name"] == "我的下一步"
    assert listed[0]["criteria"] == {"status": "next", "area": "工作"}

    # Round-trip: applying the saved criteria reproduces the filtered set.
    applied = gtd_crud.query_tasks(db_session, user.id, status="next")
    assert {t["title"] for t in applied} == {"待办甲"}

    assert gtd_crud.delete_saved_filter(db_session, user.id, created) is True
    assert gtd_crud.list_saved_filters(db_session, user.id) == []
    # Deleting someone else's / unknown filter is a no-op false.
    assert gtd_crud.delete_saved_filter(db_session, user.id, created) is False


def test_query_tasks_escapes_like_wildcards(db_session, project):
    # % and _ must be treated literally, not as LIKE wildcards, so a search or
    # tag/context filter for a string containing them matches exactly and never
    # broadens to unrelated rows.
    _mk(db_session, project, "SAS_analysis 提交流程")
    _mk(db_session, project, "SAS-analysis 备份")
    _mk(db_session, project, "普通任务")

    literal = [t["title"] for t in gtd_crud.query_tasks(
        db_session, project.owner_id, q="SAS_analysis")]
    assert literal == ["SAS_analysis 提交流程"]

    # q="%" previously matched every row; now it matches nothing.
    assert gtd_crud.query_tasks(db_session, project.owner_id, q="%") == []

    # Tag matching is literal too: "_" must not match a single arbitrary char.
    _mk(db_session, project, "带标签", tags=["ADaM_var"])
    _mk(db_session, project, "迷惑项", tags=["ADaMxvar"])  # differs only at position 4
    tagged = [t["title"] for t in gtd_crud.query_tasks(
        db_session, project.owner_id, tags=["ADaM_var"])]
    assert tagged == ["带标签"]


def test_create_saved_filter_requires_name(db_session, user):
    import pytest

    with pytest.raises(ValueError):
        gtd_crud.create_saved_filter(db_session, user.id, "   ", {})