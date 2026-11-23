from sqlalchemy.orm import Session
from sqlalchemy import or_, func
from typing import List, Optional
from app.models.models import Reference, ReferenceCategory, Tag, reference_tags
from app.schemas.reference import ReferenceCreate, ReferenceUpdate

def get_reference(db: Session, reference_id: int) -> Optional[Reference]:
    return db.query(Reference).filter(Reference.id == reference_id).first()

def get_references(
    db: Session,
    skip: int = 0,
    limit: int = 100,
    category_id: Optional[int] = None,
    reference_type: Optional[str] = None,
    search: Optional[str] = None,
    pinned_only: bool = False,
) -> List[Reference]:
    query = db.query(Reference).filter(Reference.is_published == True)
    
    if category_id:
        query = query.filter(Reference.category_id == category_id)
    
    if reference_type:
        query = query.filter(Reference.reference_type == reference_type)
    
    if search:
        query = query.filter(
            or_(
                Reference.title.ilike(f"%{search}%"),
                Reference.content.ilike(f"%{search}%"),
            )
        )
    
    if pinned_only:
        query = query.filter(Reference.is_pinned == True)
    
    query = query.order_by(Reference.is_pinned.desc(), Reference.created_at.desc())
    
    return query.offset(skip).limit(limit).all()

def get_references_count(
    db: Session,
    category_id: Optional[int] = None,
    reference_type: Optional[str] = None,
    search: Optional[str] = None,
) -> int:
    query = db.query(func.count(Reference.id)).filter(Reference.is_published == True)
    
    if category_id:
        query = query.filter(Reference.category_id == category_id)
    
    if reference_type:
        query = query.filter(Reference.reference_type == reference_type)
    
    if search:
        query = query.filter(
            or_(
                Reference.title.ilike(f"%{search}%"),
                Reference.content.ilike(f"%{search}%"),
            )
        )
    
    return query.scalar()

def create_reference(db: Session, reference: ReferenceCreate) -> Reference:
    # 创建参考
    db_reference = Reference(
        title=reference.title,
        category_id=reference.category_id,
        content=reference.content,
        reference_type=reference.reference_type,
        is_pinned=reference.is_pinned,
    )
    db.add(db_reference)
    db.flush()
    
    # 处理标签
    for tag_name in reference.tags:
        tag = db.query(Tag).filter(Tag.name == tag_name).first()
        if not tag:
            tag = Tag(name=tag_name)
            db.add(tag)
            db.flush()
        db_reference.tags.append(tag)
    
    db.commit()
    db.refresh(db_reference)
    return db_reference

def update_reference(db: Session, reference_id: int, reference: ReferenceUpdate) -> Optional[Reference]:
    db_reference = db.query(Reference).filter(Reference.id == reference_id).first()
    if not db_reference:
        return None
    
    update_data = reference.model_dump(exclude_unset=True)
    for field, value in update_data.items():
        setattr(db_reference, field, value)
    
    db.commit()
    db.refresh(db_reference)
    return db_reference

def delete_reference(db: Session, reference_id: int) -> bool:
    db_reference = db.query(Reference).filter(Reference.id == reference_id).first()
    if not db_reference:
        return False
    
    db.delete(db_reference)
    db.commit()
    return True

def toggle_pin(db: Session, reference_id: int, is_pinned: bool) -> Optional[Reference]:
    db_reference = db.query(Reference).filter(Reference.id == reference_id).first()
    if not db_reference:
        return None
    
    db_reference.is_pinned = is_pinned
    db.commit()
    db.refresh(db_reference)
    return db_reference

# 参考分类CRUD
def get_reference_categories(db: Session) -> List[ReferenceCategory]:
    return db.query(ReferenceCategory).all()

def get_reference_category(db: Session, category_id: int) -> Optional[ReferenceCategory]:
    return db.query(ReferenceCategory).filter(ReferenceCategory.id == category_id).first()

def create_reference_category(db: Session, category: dict) -> ReferenceCategory:
    db_category = ReferenceCategory(**category)
    db.add(db_category)
    db.commit()
    db.refresh(db_category)
    return db_category
