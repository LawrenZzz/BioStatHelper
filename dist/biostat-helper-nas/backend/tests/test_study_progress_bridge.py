"""Both old NAS playback and unified study playback share the user's progress."""
from app.crud import study, video
from app.models.models import LearningProgress, User, Video
from app.models.study import StudyItem, StudyList
from app.schemas.study import ItemUpdate
from app.schemas.video import VideoProgressUpdate


def test_legacy_nas_updates_all_of_the_users_learning_lists(db_session, user):
    published = Video(title="NAS lesson", video_url="/lesson", duration_seconds=600, is_published=True)
    other = User(username="other-watcher", email="other-watcher@example.test", hashed_password="x")
    db_session.add_all([published, other])
    db_session.flush()
    items = []
    for index, owner in enumerate([user, user, other]):
        listing = StudyList(user_id=owner.id, name=f"List {index}")
        db_session.add(listing)
        db_session.flush()
        item = StudyItem(user_id=owner.id, list_id=listing.id, video_id=published.id,
                         source="nas", source_key=f"nas:{published.id}", title="Lesson",
                         duration_seconds=0 if index == 1 else 600)
        db_session.add(item)
        items.append(item)
    db_session.commit()

    video.update_video_progress(db_session, user.id, published.id,
                                VideoProgressUpdate(progress_percent=25, completed=False))
    assert [(item.position_seconds, item.status) for item in items] == [
        (150, "learning"), (150, "learning"), (0, "planned")]
    assert items[1].duration_seconds == 600
    assert items[0].last_watched_at is not None
    video.update_video_progress(db_session, user.id, published.id,
                                VideoProgressUpdate(progress_percent=96, completed=False))
    assert all(item.status == "completed" and item.completed_at for item in items[:2])
    video.update_video_progress(db_session, user.id, published.id,
                                VideoProgressUpdate(progress_percent=0, completed=False))
    assert all(item.status == "planned" and item.completed_at is None for item in items[:2])
    assert items[2].last_watched_at is None

    with study.transaction(db_session, user.id):
        study.update_item(db_session, user.id, items[0].id, ItemUpdate(
            position_seconds=240, status="learning"))
    db_session.expire_all()
    legacy = db_session.query(LearningProgress).filter_by(user_id=user.id, video_id=published.id).one()
    assert legacy.progress_percent == 40
    assert legacy.completed is False
