from pydantic import BaseModel, Field
from typing import List, Optional
from datetime import datetime

# 视频分类模式
class VideoCategoryBase(BaseModel):
    name: str
    description: Optional[str] = None
    icon: Optional[str] = None

class VideoCategoryCreate(VideoCategoryBase):
    pass

class VideoCategoryResponse(VideoCategoryBase):
    id: int
    video_count: int = 0
    
    class Config:
        from_attributes = True

# 标签模式
class TagBase(BaseModel):
    name: str

class TagCreate(TagBase):
    pass

class TagResponse(TagBase):
    id: int
    
    class Config:
        from_attributes = True

# 视频模式
class VideoBase(BaseModel):
    title: str
    description: Optional[str] = None
    category_id: int
    thumbnail_url: Optional[str] = None
    video_url: str
    duration_seconds: Optional[int] = None

class VideoCreate(VideoBase):
    tags: List[str] = Field(default_factory=list)

class VideoUpdate(BaseModel):
    title: Optional[str] = None
    description: Optional[str] = None
    category_id: Optional[int] = None
    thumbnail_url: Optional[str] = None
    video_url: Optional[str] = None
    duration_seconds: Optional[int] = None
    is_published: Optional[bool] = None

class VideoSidecarResponse(BaseModel):
    id: int
    file_name: str
    extension: str
    kind: str
    title: str
    url: str

class VideoResponse(VideoBase):
    id: int
    is_published: bool
    view_count: int
    created_at: datetime
    updated_at: datetime
    category: Optional[VideoCategoryResponse] = None
    tags: List[TagResponse] = Field(default_factory=list)
    is_favorite: bool = False
    nas_video_id: Optional[int] = None
    nas_category_id: Optional[int] = None
    nas_category_path: Optional[str] = None
    episode_number: Optional[int] = None
    sort_order: Optional[int] = None
    progress_percent: float = 0
    completed: bool = False
    sidecars: List[VideoSidecarResponse] = Field(default_factory=list)
    
    class Config:
        from_attributes = True

class VideoListResponse(BaseModel):
    data: List[VideoResponse]
    total: int
    page: int
    page_size: int

# 视频播放进度
class VideoProgressUpdate(BaseModel):
    progress_percent: float = Field(..., ge=0, le=100)
    completed: bool = False

class VideoProgressResponse(BaseModel):
    video_id: int
    progress_percent: float
    completed: bool
    last_accessed: datetime
    
    class Config:
        from_attributes = True
