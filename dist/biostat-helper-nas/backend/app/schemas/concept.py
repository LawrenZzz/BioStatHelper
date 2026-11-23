from pydantic import BaseModel, Field
from typing import List, Optional
from datetime import datetime

# 概念分类模式
class ConceptCategoryBase(BaseModel):
    name: str
    description: Optional[str] = None
    icon: Optional[str] = None

class ConceptCategoryCreate(ConceptCategoryBase):
    pass

class ConceptCategoryResponse(ConceptCategoryBase):
    id: int
    concept_count: int = 0
    
    class Config:
        from_attributes = True

# 标签模式
class TagResponse(BaseModel):
    id: int
    name: str

    class Config:
        from_attributes = True

# 公式变量模式
class FormulaVariableBase(BaseModel):
    symbol: str
    name: str
    description: Optional[str] = None

class FormulaVariableCreate(FormulaVariableBase):
    pass

class FormulaVariableResponse(FormulaVariableBase):
    id: int
    
    class Config:
        from_attributes = True

# 公式模式
class FormulaBase(BaseModel):
    name: str
    expression: str
    description: Optional[str] = None

class FormulaCreate(FormulaBase):
    variables: List[FormulaVariableCreate] = Field(default_factory=list)

class FormulaResponse(FormulaBase):
    id: int
    variables: List[FormulaVariableResponse] = Field(default_factory=list)
    
    class Config:
        from_attributes = True

# 示例模式
class ExampleBase(BaseModel):
    title: str
    description: Optional[str] = None
    solution: Optional[str] = None
    result: Optional[str] = None

class ExampleCreate(ExampleBase):
    pass

class ExampleResponse(ExampleBase):
    id: int
    
    class Config:
        from_attributes = True

# 概念模式
class ConceptBase(BaseModel):
    title: str
    category_id: int
    content: str
    summary: Optional[str] = None

class ConceptCreate(ConceptBase):
    tags: List[str] = Field(default_factory=list)
    formulas: List[FormulaCreate] = Field(default_factory=list)
    examples: List[ExampleCreate] = Field(default_factory=list)

class ConceptUpdate(BaseModel):
    title: Optional[str] = None
    category_id: Optional[int] = None
    content: Optional[str] = None
    summary: Optional[str] = None
    is_published: Optional[bool] = None
    tags: Optional[List[str]] = None
    formulas: Optional[List[FormulaCreate]] = None
    examples: Optional[List[ExampleCreate]] = None

class ConceptResponse(ConceptBase):
    id: int
    read_count: int
    is_published: bool
    created_at: datetime
    updated_at: datetime
    category: Optional[ConceptCategoryResponse] = None
    tags: List[TagResponse] = Field(default_factory=list)
    formulas: List[FormulaResponse] = Field(default_factory=list)
    examples: List[ExampleResponse] = Field(default_factory=list)
    
    class Config:
        from_attributes = True

class ConceptListResponse(BaseModel):
    data: List[ConceptResponse]
    total: int
    page: int
    page_size: int

# 概念学习进度
class ConceptProgressUpdate(BaseModel):
    read: bool = True
    notes: Optional[str] = None

class ConceptProgressResponse(BaseModel):
    concept_id: int
    read_count: int
    last_accessed: datetime
    
    class Config:
        from_attributes = True
