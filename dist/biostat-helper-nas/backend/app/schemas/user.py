from pydantic import BaseModel, EmailStr
from typing import Optional
from datetime import datetime

# 用户模式
class UserBase(BaseModel):
    username: str
    email: EmailStr

class UserCreate(UserBase):
    password: str

class UserUpdate(BaseModel):
    username: Optional[str] = None
    email: Optional[EmailStr] = None
    password: Optional[str] = None

class UserResponse(UserBase):
    id: int
    is_active: bool
    is_admin: bool = False
    created_at: datetime
    
    class Config:
        from_attributes = True

# 认证模式
class LoginRequest(BaseModel):
    username: str
    password: str

class Token(BaseModel):
    access_token: str
    token_type: str = "bearer"

class TokenData(BaseModel):
    username: Optional[str] = None

# 笔记模式
class NoteBase(BaseModel):
    title: str
    content: str
    video_id: Optional[int] = None
    concept_id: Optional[int] = None

class NoteCreate(NoteBase):
    pass

class NoteUpdate(BaseModel):
    title: Optional[str] = None
    content: Optional[str] = None

class NoteResponse(NoteBase):
    id: int
    user_id: int
    created_at: datetime
    updated_at: datetime
    
    class Config:
        from_attributes = True

# 学习进度模式
class LearningProgressResponse(BaseModel):
    completed_videos: int
    total_videos: int
    completed_concepts: int
    total_concepts: int
    study_hours: float
    streak_days: int
    
    class Config:
        from_attributes = True

# 用户设置
class UserSettingBase(BaseModel):
    theme_mode: str = "system"
    theme_seed: str = "biostat"
    use_dynamic_color: bool = False
    amoled_dark: bool = False
    font_size: float = 16.0
    learning_reminder: bool = True
    daily_goal_minutes: int = 30
    auto_sync: bool = True
    preferred_learning_path: str = "beginner"

class UserSettingUpdate(BaseModel):
    theme_mode: Optional[str] = None
    theme_seed: Optional[str] = None
    use_dynamic_color: Optional[bool] = None
    amoled_dark: Optional[bool] = None
    font_size: Optional[float] = None
    learning_reminder: Optional[bool] = None
    daily_goal_minutes: Optional[int] = None
    auto_sync: Optional[bool] = None
    preferred_learning_path: Optional[str] = None

class UserSettingResponse(UserSettingBase):
    id: int
    user_id: int
    updated_at: datetime

    class Config:
        from_attributes = True

# 收藏模式
class FavoriteCreate(BaseModel):
    video_id: Optional[int] = None
    concept_id: Optional[int] = None
    reference_id: Optional[int] = None

class FavoriteResponse(BaseModel):
    id: int
    video_id: Optional[int] = None
    concept_id: Optional[int] = None
    reference_id: Optional[int] = None
    created_at: datetime
    
    class Config:
        from_attributes = True
