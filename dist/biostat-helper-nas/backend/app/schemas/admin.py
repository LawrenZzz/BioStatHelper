from datetime import datetime
from typing import List, Optional

from pydantic import BaseModel


class NasVideoBase(BaseModel):
    title: Optional[str] = None
    course_name: Optional[str] = None
    course_title: Optional[str] = None
    lesson_title: Optional[str] = None
    instructor: Optional[str] = None
    description: Optional[str] = None
    tags: Optional[str] = None
    duration_seconds: Optional[int] = None
    thumbnail_url: Optional[str] = None
    category_id: Optional[int] = None
    episode_number: Optional[int] = None
    sort_order: Optional[int] = None
    is_manual: bool = False
    is_visible: bool = True


class NasVideoUpdate(NasVideoBase):
    pass


class NasVideoReorderRequest(BaseModel):
    video_ids: List[int]


class NasVideoResponse(NasVideoBase):
    id: int
    relative_path: str
    file_name: str
    file_extension: Optional[str] = None
    file_size: int = 0
    modified_at: Optional[datetime] = None
    published_video_id: Optional[int] = None
    category_path: Optional[str] = None
    category_name: Optional[str] = None
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True


class NasVideoListResponse(BaseModel):
    data: List[NasVideoResponse]
    total: int


class NasScanResponse(BaseModel):
    scanned: int
    created: int
    updated: int
    missing: int
    video_ids: List[int] = []
    created_ids: List[int] = []
    updated_ids: List[int] = []
    skipped: int = 0
    errors: List[dict] = []


class NasVideoSidecarScanVideo(BaseModel):
    video_id: int
    relative_path: str
    file_name: str
    subtitle_count: int = 0
    danmaku_count: int = 0
    sidecar_count: int = 0
    sidecars: List[dict] = []


class NasVideoSidecarScanResponse(BaseModel):
    total: int
    matched_videos: int
    subtitle_files: int
    danmaku_files: int
    sidecar_files: int
    data: List[NasVideoSidecarScanVideo] = []


class NasVideoCategoryBase(BaseModel):
    name: str
    parent_id: Optional[int] = None
    description: Optional[str] = None
    sort_order: int = 0


class NasVideoCategoryCreate(NasVideoCategoryBase):
    pass


class NasVideoCategoryUpdate(BaseModel):
    name: Optional[str] = None
    parent_id: Optional[int] = None
    description: Optional[str] = None
    sort_order: Optional[int] = None


class NasVideoCategoryResponse(NasVideoCategoryBase):
    id: int
    path: str
    video_count: int = 0
    children_count: int = 0
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True


class ManualNasVideoCreate(BaseModel):
    relative_path: str
    category_id: Optional[int] = None
    title: Optional[str] = None
    course_name: Optional[str] = None
    course_title: Optional[str] = None
    lesson_title: Optional[str] = None
    instructor: Optional[str] = None
    description: Optional[str] = None
    tags: Optional[str] = None
    duration_seconds: Optional[int] = None
    episode_number: Optional[int] = None
    sort_order: Optional[int] = None
    is_visible: bool = True


class PublishNasVideoRequest(BaseModel):
    category_id: Optional[int] = None
    is_published: bool = True


class NasVideoDeleteRequest(BaseModel):
    confirm_text: str


class NasVideoAiOrganizeRequest(BaseModel):
    apply: bool = True
    overwrite_existing: bool = True


class NasVideoAiBatchOrganizeRequest(BaseModel):
    video_ids: Optional[List[int]] = None
    search: Optional[str] = None
    published: Optional[bool] = None
    category_id: Optional[int] = None
    limit: int = 50
    apply: bool = True
    overwrite_existing: bool = True


class NasVideoThumbnailRequest(BaseModel):
    timestamp_seconds: Optional[float] = 5.0
    overwrite: bool = True


class NasVideoAiSuggestion(BaseModel):
    video_id: int
    relative_path: str
    model_used: str
    fallback_used: bool
    applied: bool = False
    category_path: Optional[str] = None
    course_name: Optional[str] = None
    course_title: Optional[str] = None
    lesson_title: Optional[str] = None
    title: Optional[str] = None
    episode_number: Optional[int] = None
    sort_order: Optional[int] = None
    instructor: Optional[str] = None
    tags: Optional[str] = None
    description: Optional[str] = None
    error: Optional[str] = None


class NasVideoAiOrganizeResponse(BaseModel):
    data: List[NasVideoAiSuggestion]
    total: int
    applied: int
    fallback_count: int


class AdminStatsResponse(BaseModel):
    users: int
    videos: int
    concepts: int
    references: int
    nas_videos: int
    published_nas_videos: int
