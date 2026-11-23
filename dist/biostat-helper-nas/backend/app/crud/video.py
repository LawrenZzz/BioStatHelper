from datetime import datetime

from sqlalchemy.orm import Session
from sqlalchemy import or_, func
from typing import List, Optional
from app.models.models import LearningProgress, NasVideo, NasVideoCategory, Video, VideoCategory, Tag, video_tags
from app.schemas.video import VideoCreate, VideoProgressUpdate, VideoUpdate

def get_video(db: Session, video_id: int) -> Optional[Video]:
    return db.query(Video).filter(Video.id == video_id).first()

def get_videos(
    db: Session,
    skip: int = 0,
    limit: int = 100,
    category_id: Optional[int] = None,
    nas_category_id: Optional[int] = None,
    search: Optional[str] = None,
    sort: str = "episode",
) -> List[Video]:
    query = db.query(Video).filter(Video.is_published == True)
    joined_nas = False
    
    if category_id:
        query = query.filter(Video.category_id == category_id)

    if nas_category_id:
        nas_category_ids = _nas_category_descendant_ids(db, nas_category_id)
        if nas_category_ids:
            query = query.join(NasVideo, NasVideo.published_video_id == Video.id).filter(
                NasVideo.category_id.in_(nas_category_ids),
                NasVideo.is_visible == True,
            )
            joined_nas = True
        else:
            query = query.filter(Video.id == -1)
    
    if search:
        query = query.filter(
            or_(
                Video.title.ilike(f"%{search}%"),
                Video.description.ilike(f"%{search}%"),
            )
        )
    
    if sort == "episode":
        if not joined_nas:
            query = query.outerjoin(NasVideo, NasVideo.published_video_id == Video.id)
        query = query.order_by(
            func.coalesce(NasVideo.sort_order, 2147483647).asc(),
            func.coalesce(NasVideo.episode_number, 2147483647).asc(),
            Video.title.asc(),
        )
    elif sort in ("newest", "recent"):
        query = query.order_by(Video.created_at.desc())
    elif sort == "popular":
        query = query.order_by(Video.view_count.desc())
    elif sort == "duration":
        query = query.order_by(Video.duration_seconds.asc())
    
    return query.offset(skip).limit(limit).all()

def get_videos_count(
    db: Session,
    category_id: Optional[int] = None,
    nas_category_id: Optional[int] = None,
    search: Optional[str] = None,
) -> int:
    query = db.query(func.count(Video.id)).filter(Video.is_published == True)
    
    if category_id:
        query = query.filter(Video.category_id == category_id)

    if nas_category_id:
        nas_category_ids = _nas_category_descendant_ids(db, nas_category_id)
        if nas_category_ids:
            query = query.join(NasVideo, NasVideo.published_video_id == Video.id).filter(
                NasVideo.category_id.in_(nas_category_ids),
                NasVideo.is_visible == True,
            )
        else:
            query = query.filter(Video.id == -1)
    
    if search:
        query = query.filter(
            or_(
                Video.title.ilike(f"%{search}%"),
                Video.description.ilike(f"%{search}%"),
            )
        )
    
    return query.scalar()

def create_video(db: Session, video: VideoCreate) -> Video:
    # 创建视频
    db_video = Video(
        title=video.title,
        description=video.description,
        category_id=video.category_id,
        thumbnail_url=video.thumbnail_url,
        video_url=video.video_url,
        duration_seconds=video.duration_seconds,
    )
    db.add(db_video)
    db.flush()
    
    # 处理标签
    for tag_name in video.tags:
        tag = db.query(Tag).filter(Tag.name == tag_name).first()
        if not tag:
            tag = Tag(name=tag_name)
            db.add(tag)
            db.flush()
        db_video.tags.append(tag)
    
    db.commit()
    db.refresh(db_video)
    return db_video

def update_video(db: Session, video_id: int, video: VideoUpdate) -> Optional[Video]:
    db_video = db.query(Video).filter(Video.id == video_id).first()
    if not db_video:
        return None
    
    update_data = video.model_dump(exclude_unset=True)
    for field, value in update_data.items():
        setattr(db_video, field, value)
    
    db.commit()
    db.refresh(db_video)
    return db_video

def delete_video(db: Session, video_id: int) -> bool:
    db_video = db.query(Video).filter(Video.id == video_id).first()
    if not db_video:
        return False

    from app.crud.study import ensure_videos_unused
    ensure_videos_unused(db, [video_id])
    db.delete(db_video)
    db.commit()
    return True

def increment_view_count(db: Session, video_id: int) -> None:
    db_video = db.query(Video).filter(Video.id == video_id).first()
    if db_video:
        db_video.view_count += 1
        db.commit()

def get_nas_video_by_published_video(db: Session, video_id: int) -> Optional[NasVideo]:
    return db.query(NasVideo).filter(NasVideo.published_video_id == video_id).first()

def get_video_progress(db: Session, user_id: int, video_id: int) -> Optional[LearningProgress]:
    return (
        db.query(LearningProgress)
        .filter(
            LearningProgress.user_id == user_id,
            LearningProgress.video_id == video_id,
        )
        .first()
    )

def update_video_progress(
    db: Session,
    user_id: int,
    video_id: int,
    progress_update: VideoProgressUpdate,
) -> LearningProgress:
    progress = get_video_progress(db, user_id, video_id)
    if not progress:
        progress = LearningProgress(user_id=user_id, video_id=video_id)
        db.add(progress)
        db.flush()

    progress_percent = max(0, min(float(progress_update.progress_percent), 100))
    progress.progress_percent = progress_percent
    progress.completed = bool(progress_update.completed or progress_percent >= 95)
    progress.last_accessed = datetime.utcnow()
    from app.models.study import StudyItem
    items = db.query(StudyItem).filter(
        StudyItem.user_id == user_id, StudyItem.source == "nas",
        StudyItem.video_id == video_id,
    ).all()
    video_duration = db.query(Video.duration_seconds).filter(Video.id == video_id).scalar() or 0
    for item in items:
        duration = item.duration_seconds or video_duration
        if duration > 0:
            item.duration_seconds = duration
            item.position_seconds = min(duration, int(duration * progress_percent / 100))
        item.status = "completed" if progress.completed else ("learning" if progress_percent > 0 else "planned")
        item.last_watched_at = progress.last_accessed
        item.completed_at = (item.completed_at or progress.last_accessed) if progress.completed else None
    db.commit()
    db.refresh(progress)
    return progress

# 视频分类CRUD
def get_video_categories(db: Session) -> List[VideoCategory]:
    return db.query(VideoCategory).all()

def _natural_sort_key(value: str):
    import re

    text = str(value or "")
    chunks = re.split(r"(\d+)", text.casefold())
    key = []
    for chunk in chunks:
        if not chunk:
            continue
        key.append((0, int(chunk)) if chunk.isdigit() else (1, chunk))
    return key

def _category_path_sort_key(path: str):
    return [_natural_sort_key(part) for part in str(path or "未分类").split("/")]

def _nas_category_descendant_ids(db: Session, category_id: int) -> List[int]:
    category = db.query(NasVideoCategory).filter(NasVideoCategory.id == category_id).first()
    if not category:
        return []
    return [
        row[0]
        for row in db.query(NasVideoCategory.id)
        .filter(
            or_(
                NasVideoCategory.id == category.id,
                NasVideoCategory.path.like(f"{category.path}/%"),
            )
        )
        .all()
    ]

def get_nas_video_categories_for_app(db: Session) -> List[NasVideoCategory]:
    categories = db.query(NasVideoCategory).all()
    for category in categories:
        category_ids = [
            item.id
            for item in categories
            if item.id == category.id or str(item.path or "").startswith(f"{category.path}/")
        ]
        category.video_count = (
            db.query(func.count(NasVideo.id))
            .filter(
                NasVideo.category_id.in_(category_ids),
                NasVideo.published_video_id.isnot(None),
                NasVideo.is_visible == True,
            )
            .scalar()
            or 0
        )
        category.children_count = (
            db.query(func.count(NasVideoCategory.id))
            .filter(NasVideoCategory.parent_id == category.id)
            .scalar()
            or 0
        )
    return sorted(categories, key=lambda category: _category_path_sort_key(category.path))

def get_video_category(db: Session, category_id: int) -> Optional[VideoCategory]:
    return db.query(VideoCategory).filter(VideoCategory.id == category_id).first()

def create_video_category(db: Session, category: dict) -> VideoCategory:
    db_category = VideoCategory(**category)
    db.add(db_category)
    db.commit()
    db.refresh(db_category)
    return db_category
