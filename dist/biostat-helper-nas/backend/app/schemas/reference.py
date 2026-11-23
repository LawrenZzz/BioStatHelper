from pydantic import BaseModel, Field
from typing import List, Optional
from datetime import datetime

# 参考分类模式
class ReferenceCategoryBase(BaseModel):
    name: str
    description: Optional[str] = None
    icon: Optional[str] = None

class ReferenceCategoryCreate(ReferenceCategoryBase):
    pass

class ReferenceCategoryResponse(ReferenceCategoryBase):
    id: int
    reference_count: int = 0
    
    class Config:
        from_attributes = True

# 标签模式
class TagResponse(BaseModel):
    id: int
    name: str

    class Config:
        from_attributes = True

# 参考模式
class ReferenceBase(BaseModel):
    title: str
    category_id: int
    content: str
    reference_type: str  # table, formula, checklist, guideline, cheatSheet

class ReferenceCreate(ReferenceBase):
    tags: List[str] = Field(default_factory=list)
    is_pinned: bool = False

class ReferenceUpdate(BaseModel):
    title: Optional[str] = None
    category_id: Optional[int] = None
    content: Optional[str] = None
    reference_type: Optional[str] = None
    is_pinned: Optional[bool] = None
    is_published: Optional[bool] = None

class ReferenceResponse(ReferenceBase):
    id: int
    is_pinned: bool
    is_published: bool
    created_at: datetime
    updated_at: datetime
    category: Optional[ReferenceCategoryResponse] = None
    tags: List[TagResponse] = Field(default_factory=list)
    
    class Config:
        from_attributes = True

class ReferenceListResponse(BaseModel):
    data: List[ReferenceResponse]
    total: int
    page: int
    page_size: int

# 置顶状态更新
class PinUpdate(BaseModel):
    is_pinned: bool
