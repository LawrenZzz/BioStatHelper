from datetime import datetime
from typing import Any, List, Optional

from pydantic import BaseModel, Field, field_validator

from app.core.project_types import PROJECT_TYPE_LABELS


PROJECT_TYPE_PATTERN = "^(" + "|".join(PROJECT_TYPE_LABELS) + ")$"

# GTD statuses (inbox/next/waiting/someday/reference/archived) extend the
# existing clinical pipeline statuses (open/in_progress/done/blocked/cancelled).
# "open" is kept as a legacy synonym for "next"; new writes default to "next".
TODO_STATUS_PATTERN = "^(inbox|next|open|in_progress|waiting|someday|reference|done|blocked|cancelled|archived)$"


class ProjectBase(BaseModel):
    name: str
    sponsor: Optional[str] = None
    protocol_no: Optional[str] = None
    phase: Optional[str] = None
    current_workflow_phase: Optional[str] = None
    project_type: str = Field("other", pattern=PROJECT_TYPE_PATTERN)
    is_cdisc: bool = False
    indication: Optional[str] = None
    description: Optional[str] = None
    status: str = "active"
    is_inbox: bool = False
    review_at: Optional[datetime] = None
    is_focused: bool = False


class ProjectCreate(ProjectBase):
    create_standard_workflow: bool = True


class ProjectUpdate(BaseModel):
    name: Optional[str] = None
    sponsor: Optional[str] = None
    protocol_no: Optional[str] = None
    phase: Optional[str] = None
    current_workflow_phase: Optional[str] = None
    project_type: Optional[str] = Field(None, pattern=PROJECT_TYPE_PATTERN)
    is_cdisc: Optional[bool] = None
    indication: Optional[str] = None
    description: Optional[str] = None
    status: Optional[str] = None
    is_inbox: Optional[bool] = None
    review_at: Optional[datetime] = None
    is_focused: Optional[bool] = None


class ProjectResponse(ProjectBase):
    id: int
    owner_id: Optional[int] = None
    todo_count: int = 0
    open_todo_count: int = 0
    in_progress_todo_count: int = 0
    done_todo_count: int = 0
    meeting_count: int = 0
    progress_percent: float = 0
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True


class ProjectMemberBase(BaseModel):
    member_type: str = Field("other", pattern="^(sponsor|statistical_partner|internal|other)$")
    name: str = Field(..., min_length=1, max_length=200)
    organization: Optional[str] = None
    role: Optional[str] = None
    email: Optional[str] = None
    phone: Optional[str] = None
    notes: Optional[str] = None
    source_text: Optional[str] = None
    sort_order: int = 0


class ProjectMemberCreate(ProjectMemberBase):
    pass


class ProjectMemberUpdate(BaseModel):
    member_type: Optional[str] = Field(None, pattern="^(sponsor|statistical_partner|internal|other)$")
    name: Optional[str] = Field(None, min_length=1, max_length=200)
    organization: Optional[str] = None
    role: Optional[str] = None
    email: Optional[str] = None
    phone: Optional[str] = None
    notes: Optional[str] = None
    source_text: Optional[str] = None
    sort_order: Optional[int] = None


class ProjectMemberResponse(ProjectMemberBase):
    id: int
    project_id: int
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True


class ProjectMemberListResponse(BaseModel):
    data: List[ProjectMemberResponse] = Field(default_factory=list)
    total: int = 0


class ProjectMemberParseRequest(BaseModel):
    text: str = Field(..., min_length=1, max_length=12000)
    create_records: bool = True


class ProjectMemberParseResponse(BaseModel):
    model_used: str
    fallback_used: bool
    members: List[ProjectMemberBase] = Field(default_factory=list)
    created_count: int = 0
    raw: Optional[dict] = None


class ProjectIntakeCreateResponse(BaseModel):
    project: ProjectResponse
    model_used: str = ""
    fallback_used: bool = False
    current_phase: Optional[str] = None
    completed_todo_count: int = 0
    in_progress_todo_count: int = 0
    created_todo_count: int = 0
    error: Optional[str] = None
    debug_id: Optional[str] = None


class ProjectListResponse(BaseModel):
    data: List[ProjectResponse]
    total: int


class ProjectPhaseBase(BaseModel):
    name: str
    sort_order: int = 0


class ProjectPhaseCreate(ProjectPhaseBase):
    pass


class ProjectPhaseUpdate(BaseModel):
    name: Optional[str] = None
    sort_order: Optional[int] = None


class ProjectPhaseResponse(ProjectPhaseBase):
    id: int
    project_id: int
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True


class ProjectPhaseListResponse(BaseModel):
    data: List[ProjectPhaseResponse]
    total: int


class PhaseReorderRequest(BaseModel):
    phase_ids: List[int]


class TodoBase(BaseModel):
    title: str
    description: Optional[str] = None
    todo_type: str = Field("extra", pattern="^(standard|extra|meeting)$")
    phase: Optional[str] = None
    status: str = Field("next", pattern=TODO_STATUS_PATTERN)
    priority: str = Field("normal", pattern="^(low|normal|high|urgent)$")
    start_at: Optional[datetime] = None
    due_at: Optional[datetime] = None
    sort_order: int = 0
    source_text: Optional[str] = None
    meeting_id: Optional[int] = None
    assignee_id: Optional[int] = None
    contexts: Optional[List[str]] = None
    tags: Optional[List[str]] = None
    area: Optional[str] = None
    energy_level: Optional[str] = None
    time_estimate: Optional[int] = None
    is_focused_today: bool = False
    recurrence: Optional[str] = None
    review_at: Optional[datetime] = None
    completed_at: Optional[datetime] = None
    cancelled_at: Optional[datetime] = None

    @field_validator("contexts", "tags", mode="before")
    @classmethod
    def _parse_json_list(cls, value):
        # The DB stores GTD contexts/tags as a JSON string; coerce it back to a
        # list when hydrating a response, and pass real lists through on input.
        if value is None or isinstance(value, list):
            return value
        if isinstance(value, str):
            import json
            try:
                return json.loads(value)
            except (ValueError, TypeError):
                return []
        return value


class ChecklistItemBase(BaseModel):
    title: str
    is_done: bool = False
    due_at: Optional[datetime] = None
    meeting_id: Optional[int] = None
    sort_order: int = 0


class ChecklistItemCreate(ChecklistItemBase):
    pass


class ProjectIntakeTodo(BaseModel):
    title: str
    description: Optional[str] = None
    todo_type: str = Field("extra", pattern="^(standard|extra|meeting)$")
    phase: Optional[str] = None
    status: str = Field("next", pattern=TODO_STATUS_PATTERN)
    priority: str = Field("normal", pattern="^(low|normal|high|urgent)$")
    start_at: Optional[datetime] = None
    due_at: Optional[datetime] = None
    checklist_items: List[ChecklistItemCreate] = Field(default_factory=list)


class ProjectIntakeDraft(BaseModel):
    create_standard_workflow: bool = True
    name: str = "未命名项目"
    sponsor: Optional[str] = None
    protocol_no: Optional[str] = None
    phase: Optional[str] = None
    project_type: str = Field("other", pattern=PROJECT_TYPE_PATTERN)
    is_cdisc: Optional[bool] = None
    indication: Optional[str] = None
    description: Optional[str] = None
    status: str = Field("active", pattern="^(active|completed)$")
    current_phase: Optional[str] = None
    completed_todo_titles: List[str] = Field(default_factory=list)
    in_progress_todo_titles: List[str] = Field(default_factory=list)
    todos: List[ProjectIntakeTodo] = Field(default_factory=list)
    members: List[ProjectMemberBase] = Field(default_factory=list)


class ProjectIntakeRequest(ProjectIntakeDraft):
    text: str = Field(..., min_length=1, max_length=12000)


class ProjectIntakeDraftResponse(ProjectIntakeDraft):
    model_used: str
    fallback_used: bool
    raw: Optional[dict] = None
    error: Optional[str] = None
    debug_id: Optional[str] = None


class ChecklistItemUpdate(BaseModel):
    title: Optional[str] = None
    is_done: Optional[bool] = None
    due_at: Optional[datetime] = None
    meeting_id: Optional[int] = None
    sort_order: Optional[int] = None


class ChecklistItemResponse(ChecklistItemBase):
    id: int
    todo_id: int
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True


class TodoCreate(TodoBase):
    checklist_items: List[ChecklistItemCreate] = Field(default_factory=list)


class TodoUpdate(BaseModel):
    title: Optional[str] = None
    description: Optional[str] = None
    todo_type: Optional[str] = Field(None, pattern="^(standard|extra|meeting)$")
    phase: Optional[str] = None
    status: Optional[str] = Field(None, pattern=TODO_STATUS_PATTERN)
    priority: Optional[str] = Field(None, pattern="^(low|normal|high|urgent)$")
    start_at: Optional[datetime] = None
    due_at: Optional[datetime] = None
    sort_order: Optional[int] = None
    source_text: Optional[str] = None
    meeting_id: Optional[int] = None
    assignee_id: Optional[int] = None
    contexts: Optional[List[str]] = None
    tags: Optional[List[str]] = None
    area: Optional[str] = None
    energy_level: Optional[str] = None
    time_estimate: Optional[int] = None
    is_focused_today: Optional[bool] = None
    recurrence: Optional[str] = None
    review_at: Optional[datetime] = None
    completed_at: Optional[datetime] = None
    cancelled_at: Optional[datetime] = None


class TodoResponse(TodoBase):
    id: int
    project_id: int
    checklist_items: List[ChecklistItemResponse] = Field(default_factory=list)
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True


class TodoListResponse(BaseModel):
    data: List[TodoResponse]
    total: int


class TodoReorderRequest(BaseModel):
    phase: str
    todo_ids: List[int]


class MeetingBase(BaseModel):
    title: str
    agenda: Optional[str] = None
    meeting_url: Optional[str] = None
    location: Optional[str] = None
    starts_at: Optional[datetime] = None
    ends_at: Optional[datetime] = None
    attendees: Optional[str] = None
    notes: Optional[str] = None
    source_text: Optional[str] = None


class MeetingCreate(MeetingBase):
    pass


class MeetingUpdate(BaseModel):
    title: Optional[str] = None
    agenda: Optional[str] = None
    meeting_url: Optional[str] = None
    location: Optional[str] = None
    starts_at: Optional[datetime] = None
    ends_at: Optional[datetime] = None
    attendees: Optional[str] = None
    notes: Optional[str] = None
    source_text: Optional[str] = None


class MeetingResponse(MeetingBase):
    id: int
    project_id: int
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True


class MeetingListResponse(BaseModel):
    data: List[MeetingResponse]
    total: int


class TimelineImportRequest(BaseModel):
    source_text: Optional[str] = None
    file_name: Optional[str] = None
    rows: List[dict] = Field(default_factory=list)


class TimelineItemBase(BaseModel):
    row_number: int = 0
    external_id: Optional[str] = None
    title: str = Field(..., min_length=1, max_length=300)
    description: Optional[str] = None
    phase: Optional[str] = None
    start_at: Optional[datetime] = None
    due_at: Optional[datetime] = None
    status: Optional[str] = None
    target_type: str = Field("none", pattern="^(none|todo|checklist)$")
    matched_todo_id: Optional[int] = None
    matched_checklist_item_id: Optional[int] = None
    confidence: Optional[float] = None
    warning: Optional[str] = None
    raw_json: Optional[Any] = None


class TimelineItemUpdate(BaseModel):
    title: Optional[str] = Field(None, min_length=1, max_length=300)
    description: Optional[str] = None
    phase: Optional[str] = None
    start_at: Optional[datetime] = None
    due_at: Optional[datetime] = None
    status: Optional[str] = None
    target_type: Optional[str] = Field(None, pattern="^(none|todo|checklist)$")
    matched_todo_id: Optional[int] = None
    matched_checklist_item_id: Optional[int] = None
    confidence: Optional[float] = None
    warning: Optional[str] = None


class TimelineItemResponse(TimelineItemBase):
    id: int
    timeline_import_id: int
    project_id: int
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True


class TimelineImportResponse(BaseModel):
    id: int
    project_id: int
    file_name: Optional[str] = None
    source_type: str
    source_text: Optional[str] = None
    raw_json: List[dict] = Field(default_factory=list)
    model_used: Optional[str] = None
    fallback_used: bool = False
    status: str
    error_message: Optional[str] = None
    items: List[TimelineItemResponse] = Field(default_factory=list)
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True


class TimelineListResponse(BaseModel):
    data: List[TimelineImportResponse] = Field(default_factory=list)
    total: int = 0


class AssistantParseRequest(BaseModel):
    text: str
    create_records: bool = True


class AssistantDraftMeeting(BaseModel):
    title: str = "项目会议"
    agenda: Optional[str] = None
    meeting_url: Optional[str] = None
    location: Optional[str] = None
    starts_at: Optional[datetime] = None
    ends_at: Optional[datetime] = None
    attendees: Optional[str] = None
    notes: Optional[str] = None


class AssistantDraftTodo(BaseModel):
    title: str = "项目待办"
    description: Optional[str] = None
    todo_type: str = "extra"
    phase: Optional[str] = None
    status: str = "open"
    priority: str = "normal"
    start_at: Optional[datetime] = None
    due_at: Optional[datetime] = None


class AssistantDraftResponse(BaseModel):
    intent: str
    model_used: str
    fallback_used: bool
    meetings: List[AssistantDraftMeeting] = Field(default_factory=list)
    todos: List[AssistantDraftTodo] = Field(default_factory=list)
    raw: Optional[dict] = None


class AssistantParseResponse(BaseModel):
    intent: str
    model_used: str
    fallback_used: bool
    todos: List[TodoResponse] = Field(default_factory=list)
    meetings: List[MeetingResponse] = Field(default_factory=list)
    raw: Optional[dict] = None


class ProjectAgentRequest(BaseModel):
    text: str = Field(..., min_length=1, max_length=12000)


class ProjectAgentMessageResponse(BaseModel):
    id: int
    project_id: int
    role: str
    content: str
    model_used: Optional[str] = None
    fallback_used: bool = False
    created_at: datetime

    class Config:
        from_attributes = True


class ProjectAgentMessageListResponse(BaseModel):
    data: List[ProjectAgentMessageResponse] = Field(default_factory=list)
    total: int = 0


class ProjectAgentChecklistPlan(BaseModel):
    id: Optional[int] = None
    title: Optional[str] = None
    is_done: Optional[bool] = None
    due_at: Optional[datetime] = None


class ProjectAgentTodoPlan(BaseModel):
    ref: Optional[str] = None
    id: Optional[int] = None
    action: str = Field("create", pattern="^(create|update)$")
    title: Optional[str] = None
    description: Optional[str] = None
    todo_type: Optional[str] = Field(None, pattern="^(standard|extra|meeting)$")
    phase: Optional[str] = None
    status: Optional[str] = Field(None, pattern=TODO_STATUS_PATTERN)
    priority: Optional[str] = Field(None, pattern="^(low|normal|high|urgent)$")
    start_at: Optional[datetime] = None
    due_at: Optional[datetime] = None
    checklist_items: List[ProjectAgentChecklistPlan] = Field(default_factory=list)


class ProjectAgentMeetingPlan(BaseModel):
    ref: Optional[str] = None
    id: Optional[int] = None
    action: str = Field("create", pattern="^(create|update)$")
    title: Optional[str] = None
    agenda: Optional[str] = None
    meeting_url: Optional[str] = None
    location: Optional[str] = None
    starts_at: Optional[datetime] = None
    ends_at: Optional[datetime] = None
    attendees: Optional[str] = None
    notes: Optional[str] = None
    todo_id: Optional[int] = None
    todo_ref: Optional[str] = None
    checklist_item_id: Optional[int] = None


class ProjectAgentPlan(BaseModel):
    intent: str = "update"
    summary: str = ""
    clarification: Optional[str] = None
    current_phase: Optional[str] = None
    completed_todo_ids: List[int] = Field(default_factory=list)
    completed_checklist_item_ids: List[int] = Field(default_factory=list)
    todos: List[ProjectAgentTodoPlan] = Field(default_factory=list)
    meetings: List[ProjectAgentMeetingPlan] = Field(default_factory=list)


class ProjectAgentResponse(BaseModel):
    intent: str
    summary: str
    clarification: Optional[str] = None
    model_used: str
    fallback_used: bool
    current_phase: Optional[str] = None
    completed_todo_count: int = 0
    completed_checklist_count: int = 0
    created_todos: List[TodoResponse] = Field(default_factory=list)
    updated_todos: List[TodoResponse] = Field(default_factory=list)
    created_meetings: List[MeetingResponse] = Field(default_factory=list)
    updated_meetings: List[MeetingResponse] = Field(default_factory=list)
