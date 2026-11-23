import logging

from sqlalchemy.orm import Session
from sqlalchemy import func
from typing import List, Optional
from datetime import datetime, timedelta
from passlib.context import CryptContext
from app.core.config import settings
from app.models.models import User, UserSetting, Note, LearningProgress, user_favorites
from app.schemas.user import (
    UserCreate, UserUpdate, UserSettingUpdate, NoteCreate, NoteUpdate
)

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")
logger = logging.getLogger(__name__)

def get_user(db: Session, user_id: int) -> Optional[User]:
    return db.query(User).filter(User.id == user_id).first()

def get_user_by_username(db: Session, username: str) -> Optional[User]:
    return db.query(User).filter(User.username == username).first()

def get_user_by_email(db: Session, email: str) -> Optional[User]:
    return db.query(User).filter(User.email == email).first()

def get_user_by_username_or_email(db: Session, username_or_email: str) -> Optional[User]:
    return db.query(User).filter(
        (User.username == username_or_email) | (User.email == username_or_email)
    ).first()

def sync_configured_admin_user(db: Session) -> Optional[User]:
    if not settings.ADMIN_USERNAME or not settings.ADMIN_PASSWORD:
        return None

    user = get_user_by_username(db, settings.ADMIN_USERNAME)
    if user is None:
        user = User(
            username=settings.ADMIN_USERNAME,
            email=settings.ADMIN_EMAIL or f"{settings.ADMIN_USERNAME}@example.com",
            hashed_password=pwd_context.hash(settings.ADMIN_PASSWORD),
            is_active=True,
            is_admin=True,
        )
        db.add(user)
        db.flush()
        db.add(UserSetting(user_id=user.id))
    else:
        user.email = settings.ADMIN_EMAIL or user.email
        user.hashed_password = pwd_context.hash(settings.ADMIN_PASSWORD)
        user.is_active = True
        user.is_admin = True

        if user.settings is None:
            db.add(UserSetting(user_id=user.id))

    db.commit()
    db.refresh(user)
    return user

def get_users(db: Session, skip: int = 0, limit: int = 100) -> List[User]:
    return db.query(User).offset(skip).limit(limit).all()

def create_user(db: Session, user: UserCreate) -> User:
    hashed_password = pwd_context.hash(user.password)
    first_user = db.query(func.count(User.id)).scalar() == 0
    db_user = User(
        username=user.username,
        email=user.email,
        hashed_password=hashed_password,
        is_admin=first_user,
    )
    db.add(db_user)
    db.flush()
    db.add(UserSetting(user_id=db_user.id))
    db.commit()
    db.refresh(db_user)
    return db_user

def update_user(db: Session, user_id: int, user: UserUpdate) -> Optional[User]:
    db_user = db.query(User).filter(User.id == user_id).first()
    if not db_user:
        return None
    
    update_data = user.model_dump(exclude_unset=True)
    if "password" in update_data:
        update_data["hashed_password"] = pwd_context.hash(update_data.pop("password"))
    
    for field, value in update_data.items():
        setattr(db_user, field, value)
    
    db.commit()
    db.refresh(db_user)
    return db_user

def delete_user(db: Session, user_id: int) -> bool:
    db_user = db.query(User).filter(User.id == user_id).first()
    if not db_user:
        return False
    
    db.delete(db_user)
    db.commit()
    return True

def authenticate_user(db: Session, username: str, password: str) -> Optional[User]:
    user = get_user_by_username_or_email(db, username.strip())
    if not user:
        return None
    if not user.is_active:
        return None
    try:
        password_matches = pwd_context.verify(password, user.hashed_password)
    except Exception:
        # Older deployments may contain a legacy or malformed password hash.
        # Treat it as a failed local password check so configured-admin
        # recovery can safely replace it instead of crashing the login API.
        logger.warning(
            "Password verification failed for user_id=%s username=%r",
            user.id,
            user.username,
            exc_info=True,
        )
        return None
    if not password_matches:
        return None
    return user

def get_or_create_user_settings(db: Session, user_id: int) -> UserSetting:
    settings = db.query(UserSetting).filter(UserSetting.user_id == user_id).first()
    if settings:
        return settings

    settings = UserSetting(user_id=user_id)
    db.add(settings)
    db.commit()
    db.refresh(settings)
    return settings

def update_user_settings(
    db: Session,
    user_id: int,
    settings_update: UserSettingUpdate,
) -> UserSetting:
    settings = get_or_create_user_settings(db, user_id)
    update_data = settings_update.model_dump(exclude_unset=True)

    for field, value in update_data.items():
        setattr(settings, field, value)

    db.commit()
    db.refresh(settings)
    return settings

# 笔记CRUD
def get_note(db: Session, note_id: int) -> Optional[Note]:
    return db.query(Note).filter(Note.id == note_id).first()

def get_user_notes(db: Session, user_id: int, skip: int = 0, limit: int = 100) -> List[Note]:
    return db.query(Note).filter(Note.user_id == user_id).offset(skip).limit(limit).all()

def create_note(db: Session, user_id: int, note: NoteCreate) -> Note:
    db_note = Note(
        user_id=user_id,
        title=note.title,
        content=note.content,
        video_id=note.video_id,
        concept_id=note.concept_id,
    )
    db.add(db_note)
    db.commit()
    db.refresh(db_note)
    return db_note

def update_note(db: Session, note_id: int, note: NoteUpdate) -> Optional[Note]:
    db_note = db.query(Note).filter(Note.id == note_id).first()
    if not db_note:
        return None
    
    update_data = note.model_dump(exclude_unset=True)
    for field, value in update_data.items():
        setattr(db_note, field, value)
    
    db.commit()
    db.refresh(db_note)
    return db_note

def delete_note(db: Session, note_id: int) -> bool:
    db_note = db.query(Note).filter(Note.id == note_id).first()
    if not db_note:
        return False
    
    db.delete(db_note)
    db.commit()
    return True

# 学习进度
def get_learning_progress(db: Session, user_id: int) -> dict:
    # 获取视频学习进度
    total_videos = db.query(func.count(LearningProgress.id)).filter(
        LearningProgress.user_id == user_id,
        LearningProgress.video_id.isnot(None),
    ).scalar() or 0
    
    completed_videos = db.query(func.count(LearningProgress.id)).filter(
        LearningProgress.user_id == user_id,
        LearningProgress.video_id.isnot(None),
        LearningProgress.completed == True,
    ).scalar() or 0
    
    # 获取概念学习进度
    total_concepts = db.query(func.count(LearningProgress.id)).filter(
        LearningProgress.user_id == user_id,
        LearningProgress.concept_id.isnot(None),
    ).scalar() or 0
    
    completed_concepts = db.query(func.count(LearningProgress.id)).filter(
        LearningProgress.user_id == user_id,
        LearningProgress.concept_id.isnot(None),
        LearningProgress.completed == True,
    ).scalar() or 0
    
    # 计算学习时长（简化计算）
    study_hours = (completed_videos * 0.5) + (completed_concepts * 0.25)
    
    # 计算连续学习天数（简化计算）
    streak_days = 7  # 示例数据
    
    return {
        "completed_videos": completed_videos,
        "total_videos": total_videos,
        "completed_concepts": completed_concepts,
        "total_concepts": total_concepts,
        "study_hours": study_hours,
        "streak_days": streak_days,
    }

# 收藏功能
def add_favorite(db: Session, user_id: int, video_id: Optional[int] = None, 
                 concept_id: Optional[int] = None, reference_id: Optional[int] = None) -> bool:
    # 检查是否已收藏
    existing = db.query(user_favorites).filter(
        user_favorites.c.user_id == user_id,
        user_favorites.c.video_id == video_id,
        user_favorites.c.concept_id == concept_id,
        user_favorites.c.reference_id == reference_id,
    ).first()
    
    if existing:
        return False
    
    # 添加收藏
    stmt = user_favorites.insert().values(
        user_id=user_id,
        video_id=video_id,
        concept_id=concept_id,
        reference_id=reference_id,
    )
    db.execute(stmt)
    db.commit()
    return True

def remove_favorite(db: Session, user_id: int, video_id: Optional[int] = None,
                    concept_id: Optional[int] = None, reference_id: Optional[int] = None) -> bool:
    stmt = user_favorites.delete().where(
        user_favorites.c.user_id == user_id,
        user_favorites.c.video_id == video_id,
        user_favorites.c.concept_id == concept_id,
        user_favorites.c.reference_id == reference_id,
    )
    result = db.execute(stmt)
    db.commit()
    return result.rowcount > 0
