from sqlalchemy import Column, Integer, BigInteger, String, Text, DateTime, Boolean, ForeignKey, Table, Float, LargeBinary
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func
from app.db.database import Base

# 用户-收藏关联表
user_favorites = Table(
    'user_favorites',
    Base.metadata,
    Column('id', Integer, primary_key=True, index=True),
    Column('user_id', Integer, ForeignKey('users.id'), nullable=False),
    Column('video_id', Integer, ForeignKey('videos.id'), nullable=True),
    Column('concept_id', Integer, ForeignKey('concepts.id'), nullable=True),
    Column('reference_id', Integer, ForeignKey('references.id'), nullable=True),
    Column('created_at', DateTime, server_default=func.now()),
)

# 标签关联表
video_tags = Table(
    'video_tags',
    Base.metadata,
    Column('video_id', Integer, ForeignKey('videos.id'), primary_key=True),
    Column('tag_id', Integer, ForeignKey('tags.id'), primary_key=True),
)

concept_tags = Table(
    'concept_tags',
    Base.metadata,
    Column('concept_id', Integer, ForeignKey('concepts.id'), primary_key=True),
    Column('tag_id', Integer, ForeignKey('tags.id'), primary_key=True),
)

reference_tags = Table(
    'reference_tags',
    Base.metadata,
    Column('reference_id', Integer, ForeignKey('references.id'), primary_key=True),
    Column('tag_id', Integer, ForeignKey('tags.id'), primary_key=True),
)

class User(Base):
    __tablename__ = 'users'
    
    id = Column(Integer, primary_key=True, index=True)
    username = Column(String(50), unique=True, index=True, nullable=False)
    email = Column(String(100), unique=True, index=True, nullable=False)
    hashed_password = Column(String(100), nullable=False)
    is_active = Column(Boolean, default=True)
    is_admin = Column(Boolean, default=False)
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())
    
    # 关系
    notes = relationship("Note", back_populates="user")
    learning_progress = relationship("LearningProgress", back_populates="user")
    settings = relationship("UserSetting", back_populates="user", uselist=False)
    saved_filters = relationship("SavedFilter", back_populates="user")

class UserSetting(Base):
    __tablename__ = 'user_settings'

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey('users.id'), unique=True, nullable=False)
    theme_mode = Column(String(20), default="system")
    theme_seed = Column(String(30), default="biostat")
    use_dynamic_color = Column(Boolean, default=False)
    amoled_dark = Column(Boolean, default=False)
    font_size = Column(Float, default=16.0)
    learning_reminder = Column(Boolean, default=True)
    daily_goal_minutes = Column(Integer, default=30)
    auto_sync = Column(Boolean, default=True)
    preferred_learning_path = Column(String(50), default="beginner")
    # GTD: timestamp of the last global weekly review; drives the review prompt.
    weekly_review_at = Column(DateTime, nullable=True)
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())

    user = relationship("User", back_populates="settings")

class VideoCategory(Base):
    __tablename__ = 'video_categories'
    
    id = Column(Integer, primary_key=True, index=True)
    name = Column(String(50), unique=True, nullable=False)
    description = Column(Text)
    icon = Column(String(10))
    created_at = Column(DateTime, server_default=func.now())
    
    # 关系
    videos = relationship("Video", back_populates="category")

class Video(Base):
    __tablename__ = 'videos'
    
    id = Column(Integer, primary_key=True, index=True)
    title = Column(String(200), nullable=False)
    description = Column(Text)
    category_id = Column(Integer, ForeignKey('video_categories.id'))
    thumbnail_url = Column(String(500))
    video_url = Column(String(500), nullable=False)
    duration_seconds = Column(Integer)
    is_published = Column(Boolean, default=True)
    view_count = Column(Integer, default=0)
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())
    
    # 关系
    category = relationship("VideoCategory", back_populates="videos")
    tags = relationship("Tag", secondary=video_tags, back_populates="videos")

class NasVideo(Base):
    __tablename__ = 'nas_videos'

    id = Column(Integer, primary_key=True, index=True)
    relative_path = Column(String(1000), unique=True, index=True, nullable=False)
    file_name = Column(String(255), nullable=False)
    file_extension = Column(String(20))
    file_size = Column(BigInteger, default=0)
    modified_at = Column(DateTime)
    title = Column(String(200))
    course_name = Column(String(200))
    course_title = Column(String(200))
    lesson_title = Column(String(200))
    instructor = Column(String(100))
    description = Column(Text)
    tags = Column(String(500))
    duration_seconds = Column(Integer)
    thumbnail_url = Column(String(500))
    category_id = Column(Integer, ForeignKey('nas_video_categories.id'), nullable=True)
    episode_number = Column(Integer, nullable=True)
    sort_order = Column(Integer, default=0)
    is_manual = Column(Boolean, default=False)
    is_visible = Column(Boolean, default=True)
    published_video_id = Column(Integer, ForeignKey('videos.id'), nullable=True)
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())

    published_video = relationship("Video")
    category = relationship("NasVideoCategory", back_populates="videos")

    @property
    def category_path(self):
        return self.category.path if self.category else None

    @property
    def category_name(self):
        return self.category.name if self.category else None

class NasVideoCategory(Base):
    __tablename__ = 'nas_video_categories'

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String(200), nullable=False)
    parent_id = Column(Integer, ForeignKey('nas_video_categories.id'), nullable=True)
    path = Column(String(1000), unique=True, index=True, nullable=False)
    description = Column(Text)
    sort_order = Column(Integer, default=0)
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())

    parent = relationship("NasVideoCategory", remote_side=[id], back_populates="children")
    children = relationship("NasVideoCategory", back_populates="parent")
    videos = relationship("NasVideo", back_populates="category")

class ConceptCategory(Base):
    __tablename__ = 'concept_categories'
    
    id = Column(Integer, primary_key=True, index=True)
    name = Column(String(50), unique=True, nullable=False)
    description = Column(Text)
    icon = Column(String(10))
    created_at = Column(DateTime, server_default=func.now())
    
    # 关系
    concepts = relationship("Concept", back_populates="category")

class Concept(Base):
    __tablename__ = 'concepts'
    
    id = Column(Integer, primary_key=True, index=True)
    title = Column(String(200), nullable=False)
    category_id = Column(Integer, ForeignKey('concept_categories.id'))
    content = Column(Text, nullable=False)
    summary = Column(Text)
    read_count = Column(Integer, default=0)
    is_published = Column(Boolean, default=True)
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())
    
    # 关系
    category = relationship("ConceptCategory", back_populates="concepts")
    tags = relationship("Tag", secondary=concept_tags, back_populates="concepts")
    formulas = relationship("Formula", back_populates="concept")
    examples = relationship("Example", back_populates="concept")

class Formula(Base):
    __tablename__ = 'formulas'
    
    id = Column(Integer, primary_key=True, index=True)
    concept_id = Column(Integer, ForeignKey('concepts.id'))
    name = Column(String(100), nullable=False)
    expression = Column(Text, nullable=False)
    description = Column(Text)
    created_at = Column(DateTime, server_default=func.now())
    
    # 关系
    concept = relationship("Concept", back_populates="formulas")
    variables = relationship("FormulaVariable", back_populates="formula")

class FormulaVariable(Base):
    __tablename__ = 'formula_variables'
    
    id = Column(Integer, primary_key=True, index=True)
    formula_id = Column(Integer, ForeignKey('formulas.id'))
    symbol = Column(String(20), nullable=False)
    name = Column(String(50), nullable=False)
    description = Column(Text)
    
    # 关系
    formula = relationship("Formula", back_populates="variables")

class Example(Base):
    __tablename__ = 'examples'
    
    id = Column(Integer, primary_key=True, index=True)
    concept_id = Column(Integer, ForeignKey('concepts.id'))
    title = Column(String(200), nullable=False)
    description = Column(Text)
    solution = Column(Text)
    result = Column(Text)
    created_at = Column(DateTime, server_default=func.now())
    
    # 关系
    concept = relationship("Concept", back_populates="examples")

class ReferenceCategory(Base):
    __tablename__ = 'reference_categories'
    
    id = Column(Integer, primary_key=True, index=True)
    name = Column(String(50), unique=True, nullable=False)
    description = Column(Text)
    icon = Column(String(10))
    created_at = Column(DateTime, server_default=func.now())
    
    # 关系
    references = relationship("Reference", back_populates="category")

class Reference(Base):
    __tablename__ = 'references'
    
    id = Column(Integer, primary_key=True, index=True)
    title = Column(String(200), nullable=False)
    category_id = Column(Integer, ForeignKey('reference_categories.id'))
    content = Column(Text, nullable=False)
    reference_type = Column(String(20))  # table, formula, checklist, guideline, cheatSheet
    is_pinned = Column(Boolean, default=False)
    is_published = Column(Boolean, default=True)
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())
    
    # 关系
    category = relationship("ReferenceCategory", back_populates="references")
    tags = relationship("Tag", secondary=reference_tags, back_populates="references")

class Tag(Base):
    __tablename__ = 'tags'
    
    id = Column(Integer, primary_key=True, index=True)
    name = Column(String(50), unique=True, nullable=False)
    
    # 关系
    videos = relationship("Video", secondary=video_tags, back_populates="tags")
    concepts = relationship("Concept", secondary=concept_tags, back_populates="tags")
    references = relationship("Reference", secondary=reference_tags, back_populates="tags")

class Note(Base):
    __tablename__ = 'notes'
    
    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey('users.id'))
    title = Column(String(200))
    content = Column(Text)
    video_id = Column(Integer, ForeignKey('videos.id'), nullable=True)
    concept_id = Column(Integer, ForeignKey('concepts.id'), nullable=True)
    # GTD reference/capture: a note attached to a ProjectTodo. When set, the
    # note is that task's reference note (video/concept stay null).
    task_id = Column(Integer, ForeignKey('project_todos.id'), nullable=True)
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())

    # 关系
    user = relationship("User", back_populates="notes")

class SavedFilter(Base):
    """A user's saved GTD task-filter (Mindwtr 'saved filters').

    The reusable filter criteria are stored as a JSON object that maps 1:1
    onto the query params of GET /gtd/tasks, so a saved filter can be re-applied
    by posting its criteria back to the generic task query."""
    __tablename__ = 'saved_filters'

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey('users.id'), nullable=False, index=True)
    name = Column(String(100), nullable=False)
    # JSON object, e.g. {"status":"next","contexts":["@DM"],"q":"SAP"}.
    criteria = Column(Text, nullable=True)
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())

    user = relationship("User", back_populates="saved_filters")

class TaskAttachment(Base):
    """A file attached to a GTD task (reference material).

    Content is stored as a binary blob in the DB so a single SQLite/PostgreSQL
    backup captures everything with no filesystem-path assumptions on the NAS.
    Kept to a per-file size cap enforced at upload."""
    __tablename__ = 'task_attachments'

    id = Column(Integer, primary_key=True, index=True)
    task_id = Column(Integer, ForeignKey('project_todos.id'), nullable=False, index=True)
    user_id = Column(Integer, ForeignKey('users.id'), nullable=False, index=True)
    filename = Column(String(255), nullable=False)
    content_type = Column(String(120), nullable=True)
    size_bytes = Column(Integer, default=0)
    content = Column(LargeBinary)
    created_at = Column(DateTime, server_default=func.now())

    task = relationship("ProjectTodo")
    user = relationship("User")

class LearningProgress(Base):
    __tablename__ = 'learning_progress'
    
    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey('users.id'))
    video_id = Column(Integer, ForeignKey('videos.id'), nullable=True)
    concept_id = Column(Integer, ForeignKey('concepts.id'), nullable=True)
    progress_percent = Column(Float, default=0)
    completed = Column(Boolean, default=False)
    last_accessed = Column(DateTime, server_default=func.now())
    
    # 关系
    user = relationship("User", back_populates="learning_progress")

class Project(Base):
    __tablename__ = 'projects'

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String(200), nullable=False)
    sponsor = Column(String(200))
    protocol_no = Column(String(100))
    phase = Column(String(50))
    current_workflow_phase = Column(String(100), nullable=True)
    project_type = Column(String(50), nullable=False, default="other")
    is_cdisc = Column(Boolean, nullable=False, default=False)
    indication = Column(String(200))
    description = Column(Text)
    status = Column(String(30), default="active")
    owner_id = Column(Integer, ForeignKey('users.id'), nullable=True)
    # GTD: inbox is a hidden pseudo-project holding unprocessed captures.
    is_inbox = Column(Boolean, nullable=False, default=False)
    # GTD: timestamp of the last weekly review for this project.
    review_at = Column(DateTime, nullable=True)
    # GTD: pinned as one of the user's focused projects (≤5), storage only.
    is_focused = Column(Boolean, nullable=False, default=False)
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())

    owner = relationship("User")
    todos = relationship("ProjectTodo", back_populates="project")
    meetings = relationship("ProjectMeeting", back_populates="project")
    members = relationship(
        "ProjectMember",
        back_populates="project",
        cascade="all, delete-orphan",
        order_by="ProjectMember.sort_order",
    )
    timeline_imports = relationship(
        "ProjectTimelineImport",
        back_populates="project",
        cascade="all, delete-orphan",
        order_by="ProjectTimelineImport.created_at.desc()",
    )
    phases = relationship(
        "ProjectPhase",
        back_populates="project",
        order_by="ProjectPhase.sort_order",
    )

class ProjectPhase(Base):
    __tablename__ = 'project_phases'

    id = Column(Integer, primary_key=True, index=True)
    project_id = Column(Integer, ForeignKey('projects.id'), nullable=False)
    name = Column(String(100), nullable=False)
    sort_order = Column(Integer, default=0)
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())

    project = relationship("Project", back_populates="phases")

class ProjectTodo(Base):
    __tablename__ = 'project_todos'

    id = Column(Integer, primary_key=True, index=True)
    project_id = Column(Integer, ForeignKey('projects.id'), nullable=False)
    title = Column(String(300), nullable=False)
    description = Column(Text)
    todo_type = Column(String(30), default="extra")
    phase = Column(String(80))
    status = Column(String(30), default="open")
    priority = Column(String(20), default="normal")
    start_at = Column(DateTime, nullable=True)
    due_at = Column(DateTime, nullable=True)
    sort_order = Column(Integer, default=0)
    source_text = Column(Text)
    meeting_id = Column(Integer, ForeignKey('project_meetings.id'), nullable=True)
    assignee_id = Column(Integer, ForeignKey('users.id'), nullable=True)
    # GTD context(s): JSON array like ["@DM", "@work"].
    contexts = Column(Text, nullable=True)
    # GTD free-form tags: JSON array.
    tags = Column(Text, nullable=True)
    # GTD life area (工作/家庭/个人).
    area = Column(String(50), nullable=True)
    # GTD energy level required to do this task.
    energy_level = Column(String(20), nullable=True)
    # GTD estimated effort in minutes.
    time_estimate = Column(Integer, nullable=True)
    # GTD: flagged for today's Focus list.
    is_focused_today = Column(Boolean, nullable=False, default=False)
    # GTD: last review timestamp for this task.
    review_at = Column(DateTime, nullable=True)
    # Timestamps stamped when the task moves to a terminal status.
    completed_at = Column(DateTime, nullable=True)
    cancelled_at = Column(DateTime, nullable=True)
    # GTD recurring schedule spec: "daily"/"weekly"/"biweekly"/"monthly"/"yearly"
    # or a custom "N:unit" (unit in d/w/m/y). When a recurring task is completed,
    # the next occurrence is spawned automatically.
    recurrence = Column(String(40), nullable=True)
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())

    project = relationship("Project", back_populates="todos")
    meeting = relationship("ProjectMeeting", back_populates="todos", foreign_keys=[meeting_id])
    assignee = relationship("User")
    checklist_items = relationship(
        "ProjectTodoChecklistItem",
        back_populates="todo",
        order_by="ProjectTodoChecklistItem.sort_order",
    )

class ProjectTodoChecklistItem(Base):
    __tablename__ = 'project_todo_checklist_items'

    id = Column(Integer, primary_key=True, index=True)
    todo_id = Column(Integer, ForeignKey('project_todos.id'), nullable=False)
    title = Column(String(300), nullable=False)
    is_done = Column(Boolean, default=False)
    due_at = Column(DateTime, nullable=True)
    meeting_id = Column(Integer, ForeignKey('project_meetings.id'), nullable=True)
    sort_order = Column(Integer, default=0)
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())

    todo = relationship("ProjectTodo", back_populates="checklist_items")
    meeting = relationship("ProjectMeeting", foreign_keys=[meeting_id])


# Timeline imports intentionally keep both the normalized fields and the raw
# source row. This lets an administrator correct an AI match without losing
# the original Excel/text evidence.
class ProjectMember(Base):
    __tablename__ = 'project_members'

    id = Column(Integer, primary_key=True, index=True)
    project_id = Column(Integer, ForeignKey('projects.id'), nullable=False, index=True)
    member_type = Column(String(30), nullable=False, default="other")
    name = Column(String(200), nullable=False)
    organization = Column(String(300), nullable=True)
    role = Column(String(200), nullable=True)
    email = Column(String(200), nullable=True)
    phone = Column(String(80), nullable=True)
    notes = Column(Text, nullable=True)
    source_text = Column(Text, nullable=True)
    sort_order = Column(Integer, default=0)
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())

    project = relationship("Project", back_populates="members")


class ProjectTimelineImport(Base):
    __tablename__ = 'project_timeline_imports'

    id = Column(Integer, primary_key=True, index=True)
    project_id = Column(Integer, ForeignKey('projects.id'), nullable=False, index=True)
    file_name = Column(String(300), nullable=True)
    source_type = Column(String(30), nullable=False, default="text")
    source_text = Column(Text, nullable=True)
    raw_json = Column(Text, nullable=False, default="[]")
    model_used = Column(String(100), nullable=True)
    fallback_used = Column(Boolean, default=False)
    status = Column(String(30), nullable=False, default="parsed")
    error_message = Column(Text, nullable=True)
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())

    project = relationship("Project", back_populates="timeline_imports")
    items = relationship(
        "ProjectTimelineItem",
        back_populates="timeline_import",
        cascade="all, delete-orphan",
        order_by="ProjectTimelineItem.row_number",
    )


class ProjectTimelineItem(Base):
    __tablename__ = 'project_timeline_items'

    id = Column(Integer, primary_key=True, index=True)
    timeline_import_id = Column(Integer, ForeignKey('project_timeline_imports.id'), nullable=False, index=True)
    project_id = Column(Integer, ForeignKey('projects.id'), nullable=False, index=True)
    row_number = Column(Integer, nullable=False, default=0)
    external_id = Column(String(200), nullable=True)
    title = Column(String(300), nullable=False)
    description = Column(Text, nullable=True)
    phase = Column(String(100), nullable=True)
    start_at = Column(DateTime, nullable=True)
    due_at = Column(DateTime, nullable=True)
    status = Column(String(30), nullable=True)
    target_type = Column(String(20), nullable=False, default="none")
    matched_todo_id = Column(Integer, ForeignKey('project_todos.id'), nullable=True)
    matched_checklist_item_id = Column(Integer, ForeignKey('project_todo_checklist_items.id'), nullable=True)
    confidence = Column(Float, nullable=True)
    warning = Column(Text, nullable=True)
    raw_json = Column(Text, nullable=True)
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())

    timeline_import = relationship("ProjectTimelineImport", back_populates="items")
    matched_todo = relationship("ProjectTodo", foreign_keys=[matched_todo_id])
    matched_checklist_item = relationship(
        "ProjectTodoChecklistItem",
        foreign_keys=[matched_checklist_item_id],
    )

class ProjectMeeting(Base):
    __tablename__ = 'project_meetings'

    id = Column(Integer, primary_key=True, index=True)
    project_id = Column(Integer, ForeignKey('projects.id'), nullable=False)
    title = Column(String(300), nullable=False)
    agenda = Column(Text)
    meeting_url = Column(String(1000))
    location = Column(String(300))
    starts_at = Column(DateTime, nullable=True)
    ends_at = Column(DateTime, nullable=True)
    attendees = Column(Text)
    notes = Column(Text)
    source_text = Column(Text)
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())

    project = relationship("Project", back_populates="meetings")
    todos = relationship("ProjectTodo", back_populates="meeting", foreign_keys=[ProjectTodo.meeting_id])


class ProjectAgentMessage(Base):
    __tablename__ = 'project_agent_messages'

    id = Column(Integer, primary_key=True, index=True)
    project_id = Column(Integer, ForeignKey('projects.id'), nullable=False)
    user_id = Column(Integer, ForeignKey('users.id'), nullable=True)
    role = Column(String(20), nullable=False)
    content = Column(Text, nullable=False)
    model_used = Column(String(100))
    fallback_used = Column(Boolean, default=False)
    details_json = Column(Text)
    created_at = Column(DateTime, server_default=func.now())

    project = relationship("Project")
    user = relationship("User")
