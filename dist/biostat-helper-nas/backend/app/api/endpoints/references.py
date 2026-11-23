from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session
from typing import List, Optional
from app.db.database import get_db
from app.api.endpoints.auth import get_current_admin_user
from app.crud import reference as reference_crud
from app.schemas.reference import (
    ReferenceCreate, ReferenceUpdate, ReferenceResponse, ReferenceListResponse,
    ReferenceCategoryCreate, ReferenceCategoryResponse, PinUpdate
)

router = APIRouter()

@router.get("/", response_model=ReferenceListResponse)
def list_references(
    skip: int = Query(0, ge=0),
    limit: int = Query(100, ge=1, le=1000),
    category_id: Optional[int] = None,
    reference_type: Optional[str] = None,
    search: Optional[str] = None,
    pinned_only: bool = False,
    db: Session = Depends(get_db),
):
    """获取参考列表"""
    references = reference_crud.get_references(
        db, skip=skip, limit=limit,
        category_id=category_id, reference_type=reference_type,
        search=search, pinned_only=pinned_only,
    )
    total = reference_crud.get_references_count(
        db, category_id=category_id,
        reference_type=reference_type, search=search,
    )
    
    return ReferenceListResponse(
        data=[ReferenceResponse.model_validate(ref) for ref in references],
        total=total,
        page=skip // limit + 1,
        page_size=limit,
    )

@router.post("/", response_model=ReferenceResponse)
def create_reference(
    reference: ReferenceCreate,
    db: Session = Depends(get_db),
    _admin=Depends(get_current_admin_user),
):
    """创建参考"""
    return reference_crud.create_reference(db, reference)

@router.put("/{reference_id}", response_model=ReferenceResponse)
def update_reference(
    reference_id: int,
    reference: ReferenceUpdate,
    db: Session = Depends(get_db),
    _admin=Depends(get_current_admin_user),
):
    """更新参考"""
    db_reference = reference_crud.update_reference(db, reference_id, reference)
    if not db_reference:
        raise HTTPException(status_code=404, detail="参考不存在")
    return ReferenceResponse.model_validate(db_reference)

@router.delete("/{reference_id}")
def delete_reference(
    reference_id: int,
    db: Session = Depends(get_db),
    _admin=Depends(get_current_admin_user),
):
    """删除参考"""
    if not reference_crud.delete_reference(db, reference_id):
        raise HTTPException(status_code=404, detail="参考不存在")
    return {"message": "参考已删除"}

@router.put("/{reference_id}/pin", response_model=ReferenceResponse)
def toggle_pin(
    reference_id: int,
    pin_update: PinUpdate,
    db: Session = Depends(get_db),
    _admin=Depends(get_current_admin_user),
):
    """切换置顶状态"""
    db_reference = reference_crud.toggle_pin(db, reference_id, pin_update.is_pinned)
    if not db_reference:
        raise HTTPException(status_code=404, detail="参考不存在")
    return ReferenceResponse.model_validate(db_reference)

@router.get("/categories/", response_model=List[ReferenceCategoryResponse])
def list_reference_categories(
    db: Session = Depends(get_db),
):
    """获取参考分类列表"""
    categories = reference_crud.get_reference_categories(db)
    result = []
    for category in categories:
        category_dict = ReferenceCategoryResponse.model_validate(category)
        category_dict.reference_count = len(category.references)
        result.append(category_dict)
    return result

@router.post("/categories/", response_model=ReferenceCategoryResponse)
def create_reference_category(
    category: ReferenceCategoryCreate,
    db: Session = Depends(get_db),
    _admin=Depends(get_current_admin_user),
):
    """创建参考分类"""
    return reference_crud.create_reference_category(db, category.model_dump())

@router.get("/{reference_id}", response_model=ReferenceResponse)
def get_reference(
    reference_id: int,
    db: Session = Depends(get_db),
):
    """获取参考详情"""
    reference = reference_crud.get_reference(db, reference_id)
    if not reference:
        raise HTTPException(status_code=404, detail="参考不存在")
    return ReferenceResponse.model_validate(reference)
