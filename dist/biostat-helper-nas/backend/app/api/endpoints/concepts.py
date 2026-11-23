from fastapi import APIRouter, Depends, HTTPException, Query, Request
from sqlalchemy.orm import Session
from typing import List, Optional
from app.db.database import get_db
from app.api.endpoints.auth import get_current_admin_user, get_current_user
from app.crud import concept as concept_crud
from app.schemas.concept import (
    ConceptCreate, ConceptUpdate, ConceptResponse, ConceptListResponse,
    ConceptCategoryCreate, ConceptCategoryResponse
)

router = APIRouter()


async def _require_admin_from_header(request: Request, db: Session):
    auth_header = request.headers.get("Authorization", "")
    if not auth_header.lower().startswith("bearer "):
        raise HTTPException(status_code=401, detail="无法验证凭据")
    token = auth_header.split(" ", 1)[1]
    current_user = await get_current_user(token=token, db=db)
    if not current_user.is_admin:
        raise HTTPException(status_code=403, detail="需要管理员权限")
    return current_user

@router.get("", response_model=ConceptListResponse, include_in_schema=False)
@router.get("/", response_model=ConceptListResponse)
async def list_concepts(
    request: Request,
    skip: int = Query(0, ge=0),
    limit: int = Query(100, ge=1, le=1000),
    category_id: Optional[int] = None,
    search: Optional[str] = None,
    include_unpublished: bool = False,
    sort: str = Query("newest", pattern="^(newest|popular|readCount)$"),
    db: Session = Depends(get_db),
):
    """获取概念列表"""
    if include_unpublished:
        await _require_admin_from_header(request, db)

    concepts = concept_crud.get_concepts(
        db, skip=skip, limit=limit,
        category_id=category_id, search=search, sort=sort,
        include_unpublished=include_unpublished,
    )
    total = concept_crud.get_concepts_count(
        db,
        category_id=category_id,
        search=search,
        include_unpublished=include_unpublished,
    )
    
    return ConceptListResponse(
        data=[ConceptResponse.model_validate(concept) for concept in concepts],
        total=total,
        page=skip // limit + 1,
        page_size=limit,
    )

@router.post("", response_model=ConceptResponse, include_in_schema=False)
@router.post("/", response_model=ConceptResponse)
def create_concept(
    concept: ConceptCreate,
    db: Session = Depends(get_db),
    _admin=Depends(get_current_admin_user),
):
    """创建概念"""
    return concept_crud.create_concept(db, concept)

@router.put("/{concept_id}", response_model=ConceptResponse)
def update_concept(
    concept_id: int,
    concept: ConceptUpdate,
    db: Session = Depends(get_db),
    _admin=Depends(get_current_admin_user),
):
    """更新概念"""
    db_concept = concept_crud.update_concept(db, concept_id, concept)
    if not db_concept:
        raise HTTPException(status_code=404, detail="概念不存在")
    return ConceptResponse.model_validate(db_concept)

@router.delete("/{concept_id}")
def delete_concept(
    concept_id: int,
    db: Session = Depends(get_db),
    _admin=Depends(get_current_admin_user),
):
    """删除概念"""
    if not concept_crud.delete_concept(db, concept_id):
        raise HTTPException(status_code=404, detail="概念不存在")
    return {"message": "概念已删除"}

@router.get("/categories", response_model=List[ConceptCategoryResponse], include_in_schema=False)
@router.get("/categories/", response_model=List[ConceptCategoryResponse])
def list_concept_categories(
    db: Session = Depends(get_db),
):
    """获取概念分类列表"""
    categories = concept_crud.get_concept_categories(db)
    result = []
    for category in categories:
        category_dict = ConceptCategoryResponse.model_validate(category)
        category_dict.concept_count = len(
            [concept for concept in category.concepts if concept.is_published]
        )
        result.append(category_dict)
    return result

@router.post("/categories", response_model=ConceptCategoryResponse, include_in_schema=False)
@router.post("/categories/", response_model=ConceptCategoryResponse)
def create_concept_category(
    category: ConceptCategoryCreate,
    db: Session = Depends(get_db),
    _admin=Depends(get_current_admin_user),
):
    """创建概念分类"""
    return concept_crud.create_concept_category(db, category.model_dump())

@router.get("/by-title/{title}", response_model=ConceptResponse)
async def get_concept_by_title(
    request: Request,
    title: str,
    include_unpublished: bool = False,
    db: Session = Depends(get_db),
):
    """按标题获取概念详情，用于知识库内部链接跳转。"""
    if include_unpublished:
        await _require_admin_from_header(request, db)

    concept = concept_crud.get_concept_by_title(
        db,
        title=title,
        include_unpublished=include_unpublished,
    )
    if not concept:
        raise HTTPException(status_code=404, detail="概念不存在")
    if not concept.is_published:
        await _require_admin_from_header(request, db)

    concept_crud.increment_read_count(db, concept.id)
    return ConceptResponse.model_validate(concept)

@router.get("/{concept_id}", response_model=ConceptResponse)
async def get_concept(
    request: Request,
    concept_id: int,
    db: Session = Depends(get_db),
):
    """获取概念详情"""
    concept = concept_crud.get_concept(db, concept_id)
    if not concept:
        raise HTTPException(status_code=404, detail="概念不存在")
    if not concept.is_published:
        await _require_admin_from_header(request, db)
    
    # 增加阅读次数
    concept_crud.increment_read_count(db, concept_id)
    
    return ConceptResponse.model_validate(concept)

@router.get("/{concept_id}/related", response_model=List[ConceptResponse])
def get_related_concepts(
    concept_id: int,
    limit: int = Query(8, ge=1, le=20),
    db: Session = Depends(get_db),
):
    """获取相关概念"""
    concept = concept_crud.get_concept(db, concept_id)
    if not concept:
        raise HTTPException(status_code=404, detail="概念不存在")

    related_concepts = concept_crud.get_related_concepts(db, concept_id, limit=limit)
    
    return [ConceptResponse.model_validate(concept) for concept in related_concepts]
