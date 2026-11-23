"""Independent, user-owned study workflow tables; import before create_all."""

from datetime import datetime, timezone

from sqlalchemy import (
    Boolean, CheckConstraint, Column, DateTime, ForeignKey,
    ForeignKeyConstraint, Integer, JSON, String, Text, UniqueConstraint,
)
from sqlalchemy.orm import relationship

from app.db.database import Base


def utcnow():
    return datetime.now(timezone.utc).replace(tzinfo=None)


class StudyList(Base):
    __tablename__ = "study_lists"
    __table_args__ = (
        UniqueConstraint("user_id", "id", name="uq_study_list_owner"),
        UniqueConstraint("user_id", "name", name="uq_study_list_name"),
        CheckConstraint("sort_order >= 0", name="ck_study_list_sort"),
    )

    id = Column(Integer, primary_key=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    name = Column(String(200), nullable=False)
    description = Column(Text, nullable=False, default="")
    sort_order = Column(Integer, nullable=False, default=0)
    archived = Column(Boolean, nullable=False, default=False)
    created_at = Column(DateTime, nullable=False, default=utcnow)
    updated_at = Column(DateTime, nullable=False, default=utcnow, onupdate=utcnow)


class StudyItem(Base):
    __tablename__ = "study_items"
    __table_args__ = (
        UniqueConstraint("user_id", "id", name="uq_study_item_owner"),
        UniqueConstraint("user_id", "list_id", "source_key", name="uq_study_item_source"),
        ForeignKeyConstraint(["user_id", "list_id"], ["study_lists.user_id", "study_lists.id"], ondelete="CASCADE"),
        CheckConstraint("source IN ('nas', 'bilibili')", name="ck_study_item_source"),
        CheckConstraint("(source = 'nas' AND video_id IS NOT NULL) OR (source = 'bilibili' AND video_id IS NULL)", name="ck_study_item_target"),
        CheckConstraint("status IN ('planned', 'learning', 'completed')", name="ck_study_item_status"),
        CheckConstraint("position_seconds >= 0 AND duration_seconds >= 0 AND sort_order >= 0", name="ck_study_item_numbers"),
        CheckConstraint("duration_seconds = 0 OR position_seconds <= duration_seconds", name="ck_study_item_position"),
    )

    id = Column(Integer, primary_key=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    list_id = Column(Integer, nullable=False, index=True)
    video_id = Column(Integer, ForeignKey("videos.id"), nullable=True)
    source = Column(String(20), nullable=False)
    source_key = Column(String(160), nullable=False)
    source_data = Column(JSON, nullable=False, default=dict)
    title = Column(String(500), nullable=False)
    thumbnail_url = Column(String(2000))
    status = Column(String(20), nullable=False, default="planned")
    position_seconds = Column(Integer, nullable=False, default=0)
    duration_seconds = Column(Integer, nullable=False, default=0)
    favorite = Column(Boolean, nullable=False, default=False)
    sort_order = Column(Integer, nullable=False, default=0)
    last_watched_at = Column(DateTime)
    completed_at = Column(DateTime)
    created_at = Column(DateTime, nullable=False, default=utcnow)
    updated_at = Column(DateTime, nullable=False, default=utcnow, onupdate=utcnow)


class StudyNote(Base):
    __tablename__ = "study_notes"
    __table_args__ = (
        ForeignKeyConstraint(["user_id", "item_id"], ["study_items.user_id", "study_items.id"], ondelete="CASCADE"),
        CheckConstraint("position_seconds >= 0", name="ck_study_note_position"),
    )

    id = Column(Integer, primary_key=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    item_id = Column(Integer, nullable=False, index=True)
    content = Column(Text, nullable=False, default="")
    position_seconds = Column(Integer, nullable=False, default=0)
    image_data = Column(Text)
    created_at = Column(DateTime, nullable=False, default=utcnow)
    updated_at = Column(DateTime, nullable=False, default=utcnow, onupdate=utcnow)


class StudyFocusSession(Base):
    __tablename__ = "study_focus_sessions"
    __table_args__ = (
        ForeignKeyConstraint(["user_id", "item_id"], ["study_items.user_id", "study_items.id"]),
        CheckConstraint("elapsed_seconds >= 0", name="ck_study_focus_elapsed"),
        CheckConstraint("ended_at IS NULL OR ended_at >= started_at", name="ck_study_focus_dates"),
        CheckConstraint("NOT completed OR ended_at IS NOT NULL", name="ck_study_focus_completed"),
    )

    id = Column(Integer, primary_key=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    item_id = Column(Integer, nullable=True, index=True)
    elapsed_seconds = Column(Integer, nullable=False)
    started_at = Column(DateTime, nullable=False, index=True)
    ended_at = Column(DateTime)
    completed = Column(Boolean, nullable=False, default=False)
    created_at = Column(DateTime, nullable=False, default=utcnow)


class StudySubscription(Base):
    __tablename__ = "study_subscriptions"
    __table_args__ = (
        UniqueConstraint("user_id", "id", name="uq_study_subscription_owner"),
        UniqueConstraint("user_id", "target_key", name="uq_study_subscription_target"),
        CheckConstraint("(source = 'nas' AND kind = 'category' AND category_id IS NOT NULL AND mid IS NULL AND owner_mid IS NULL AND season_id IS NULL) OR (source = 'bilibili' AND category_id IS NULL AND ((kind = 'up' AND mid IS NOT NULL AND owner_mid IS NULL AND season_id IS NULL) OR (kind = 'collection' AND mid IS NULL AND owner_mid IS NOT NULL AND season_id IS NOT NULL)))", name="ck_study_subscription_target"),
    )

    id = Column(Integer, primary_key=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    name = Column(String(200), nullable=False, default="")
    source = Column(String(20), nullable=False)
    kind = Column(String(20), nullable=False)
    category_id = Column(Integer, ForeignKey("nas_video_categories.id"))
    mid = Column(String(32))
    owner_mid = Column(String(32))
    season_id = Column(String(32))
    target_key = Column(String(160), nullable=False)
    last_checked_at = Column(DateTime)
    created_at = Column(DateTime, nullable=False, default=utcnow)
    updated_at = Column(DateTime, nullable=False, default=utcnow, onupdate=utcnow)
    state = relationship("StudySubscriptionState", uselist=False, cascade="all, delete-orphan")

    @property
    def paused(self):
        return self.state.paused if self.state else False

    @property
    def enabled(self):
        return not self.paused


class StudyUpdate(Base):
    __tablename__ = "study_updates"
    __table_args__ = (
        ForeignKeyConstraint(["user_id", "subscription_id"], ["study_subscriptions.user_id", "study_subscriptions.id"], ondelete="CASCADE"),
        UniqueConstraint("user_id", "subscription_id", "source_key", name="uq_study_update_source"),
        CheckConstraint("source IN ('nas', 'bilibili')", name="ck_study_update_source"),
        CheckConstraint("(source = 'nas' AND video_id IS NOT NULL) OR (source = 'bilibili' AND video_id IS NULL)", name="ck_study_update_target"),
        CheckConstraint("duration_seconds >= 0", name="ck_study_update_duration"),
    )

    id = Column(Integer, primary_key=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    subscription_id = Column(Integer, nullable=False, index=True)
    source = Column(String(20), nullable=False)
    source_key = Column(String(160), nullable=False)
    video_id = Column(Integer, ForeignKey("videos.id"))
    source_data = Column(JSON, nullable=False, default=dict)
    title = Column(String(500), nullable=False)
    thumbnail_url = Column(String(2000))
    duration_seconds = Column(Integer, nullable=False, default=0)
    published_at = Column(DateTime, nullable=False)
    seen = Column(Boolean, nullable=False, default=False)
    read = Column(Boolean, nullable=False, default=False)
    created_at = Column(DateTime, nullable=False, default=utcnow)
    state = relationship("StudyUpdateState", uselist=False, cascade="all, delete-orphan")

    @property
    def deleted(self):
        return self.state is not None


class StudyPreferences(Base):
    __tablename__ = "study_preferences"

    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), primary_key=True)
    data = Column(JSON, nullable=False, default=dict)


# Sidecars allow create_all to upgrade existing study databases without ALTER TABLE.
class StudySubscriptionState(Base):
    __tablename__ = "study_subscription_states"
    __table_args__ = (
        ForeignKeyConstraint(["user_id", "subscription_id"], ["study_subscriptions.user_id", "study_subscriptions.id"], ondelete="CASCADE"),
    )

    subscription_id = Column(Integer, primary_key=True)
    user_id = Column(Integer, nullable=False, index=True)
    paused = Column(Boolean, nullable=False, default=False)


class StudyUpdateState(Base):
    __tablename__ = "study_update_states"

    update_id = Column(Integer, ForeignKey("study_updates.id", ondelete="CASCADE"), primary_key=True)
