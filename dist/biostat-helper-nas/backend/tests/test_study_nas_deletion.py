"""NAS record deletion must not silently destroy learning notes or fail with 500."""
import pytest
from fastapi import HTTPException

from app.api.endpoints import admin as admin_routes
from app.crud import admin, study, video
from app.models.models import NasVideo, NasVideoCategory, Video
from app.models.study import StudyItem, StudyNote, StudySubscription, StudyUpdate
from app.schemas import study as schema
from app.schemas.admin import NasVideoDeleteRequest


@pytest.fixture
def nas_record(db_session, user):
    root = NasVideoCategory(name="Course", path="Course")
    published = Video(title="Lesson", video_url="/test-video", is_published=True)
    db_session.add_all([root, published])
    db_session.flush()
    child = NasVideoCategory(name="Chapter", path="Course/Chapter", parent_id=root.id)
    db_session.add(child)
    db_session.flush()
    nas = NasVideo(relative_path="Course/Lesson.mp4", file_name="Lesson.mp4",
                   category_id=child.id, published_video_id=published.id, is_visible=True)
    db_session.add(nas)
    db_session.commit()
    return root, child, published, nas


@pytest.mark.parametrize("operation", ["one", "all", "published"])
def test_video_deletion_preserves_referenced_study_notes(db_session, user, nas_record, operation):
    _, _, published, nas = nas_record
    with study.transaction(db_session, user.id):
        listing = study.create_list(db_session, user.id, schema.ListCreate(name="My course"))
        item = study.create_item(db_session, user.id, schema.ItemCreate(
            list_id=listing.id, source="nas", video_id=published.id, title="Lesson"))
        study.create_note(db_session, user.id, schema.NoteCreate(item_id=item.id, content="Keep this note"))
    actions = {
        "one": lambda: admin.delete_nas_video_record(db_session, nas.id),
        "all": lambda: admin.delete_all_nas_video_records(db_session),
        "published": lambda: video.delete_video(db_session, published.id),
    }
    with pytest.raises(HTTPException) as error:
        actions[operation]()
    assert error.value.status_code == 409
    assert "学习清单" in error.value.detail
    assert db_session.query(StudyItem).count() == 1
    assert db_session.query(StudyNote).one().content == "Keep this note"
    assert db_session.get(NasVideo, nas.id) is not None
    assert db_session.get(Video, published.id) is not None


@pytest.mark.parametrize("all_categories", [False, True])
def test_category_deletion_requires_cancelling_child_subscription(db_session, user, nas_record, all_categories):
    root, child, _, nas = nas_record
    with study.transaction(db_session, user.id):
        study.create_subscription(db_session, user.id, schema.SubscriptionCreate(
            name="Follow chapter", source="nas", kind="category", category_id=child.id))
    with pytest.raises(HTTPException) as error:
        if all_categories:
            admin.delete_all_nas_video_categories(db_session)
        else:
            admin.delete_nas_video_category(db_session, root.id)
    assert error.value.status_code == 409
    assert db_session.query(NasVideoCategory).count() == 2
    assert db_session.query(StudySubscription).count() == 1
    assert db_session.get(NasVideo, nas.id).category_id == child.id


def test_subscription_updates_also_protect_published_video(db_session, user, nas_record):
    _, child, published, nas = nas_record
    with study.transaction(db_session, user.id):
        study.create_subscription(db_session, user.id, schema.SubscriptionCreate(
            name="New lessons", source="nas", kind="category", category_id=child.id))
        study.list_updates(db_session, user.id)
    assert db_session.query(StudyUpdate).count() == 1
    with pytest.raises(HTTPException) as error:
        admin.delete_nas_video_record(db_session, nas.id)
    assert error.value.status_code == 409
    assert db_session.get(Video, published.id) is not None


@pytest.mark.parametrize("operation", ["one", "all", "category", "categories"])
def test_admin_routes_keep_conflict_status_instead_of_wrapping_500(monkeypatch, operation):
    def conflict(*args, **kwargs):
        raise HTTPException(status_code=409, detail="Preserve learning data")

    for name in ("delete_nas_video_record", "delete_all_nas_video_records",
                 "delete_nas_video_category", "delete_all_nas_video_categories"):
        monkeypatch.setattr(admin, name, conflict)
    actions = {
        "one": lambda: admin_routes.delete_nas_video_record(
            1, NasVideoDeleteRequest(confirm_text="删除视频库记录"), db=object(), _admin=object()),
        "all": lambda: admin_routes.delete_nas_video_library_records(
            NasVideoDeleteRequest(confirm_text="删除整个视频库记录"), db=object(), _admin=object()),
        "category": lambda: admin_routes.delete_nas_video_category(1, db=object(), _admin=object()),
        "categories": lambda: admin_routes.delete_all_nas_video_categories(db=object(), _admin=object()),
    }
    with pytest.raises(HTTPException) as error:
        actions[operation]()
    assert error.value.status_code == 409


def test_unreferenced_nas_record_deletion_still_deletes_only_records(db_session, user, nas_record):
    _, _, published, nas = nas_record
    published_id, nas_id = published.id, nas.id
    result = admin.delete_nas_video_record(db_session, nas_id)
    assert result["deleted_local_file"] is False
    assert result["deleted_published_video"] is True
    assert db_session.get(NasVideo, nas_id) is None
    assert db_session.get(Video, published_id) is None
