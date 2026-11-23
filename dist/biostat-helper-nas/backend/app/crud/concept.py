from sqlalchemy.orm import Session
from sqlalchemy import or_, func
from typing import List, Optional
from app.models.models import (
    Concept, ConceptCategory, Tag, Formula, FormulaVariable, Example, concept_tags
)
from app.schemas.concept import ConceptCreate, ConceptUpdate

def get_concept(db: Session, concept_id: int) -> Optional[Concept]:
    return db.query(Concept).filter(Concept.id == concept_id).first()

def get_concept_by_title(db: Session, title: str, include_unpublished: bool = False) -> Optional[Concept]:
    query = db.query(Concept).filter(func.lower(Concept.title) == title.lower())
    if not include_unpublished:
        query = query.filter(Concept.is_published == True)
    return query.first()

def get_concepts(
    db: Session,
    skip: int = 0,
    limit: int = 100,
    category_id: Optional[int] = None,
    search: Optional[str] = None,
    sort: str = "newest",
    include_unpublished: bool = False,
) -> List[Concept]:
    query = db.query(Concept)
    if not include_unpublished:
        query = query.filter(Concept.is_published == True)
    
    if category_id:
        query = query.filter(Concept.category_id == category_id)
    
    if search:
        query = query.filter(
            or_(
                Concept.title.ilike(f"%{search}%"),
                Concept.content.ilike(f"%{search}%"),
                Concept.summary.ilike(f"%{search}%"),
            )
        )
    
    if sort == "newest":
        query = query.order_by(Concept.created_at.desc())
    elif sort == "popular":
        query = query.order_by(Concept.read_count.desc())
    elif sort == "readCount":
        query = query.order_by(Concept.read_count.desc())
    
    return query.offset(skip).limit(limit).all()

def get_concepts_count(
    db: Session,
    category_id: Optional[int] = None,
    search: Optional[str] = None,
    include_unpublished: bool = False,
) -> int:
    query = db.query(func.count(Concept.id))
    if not include_unpublished:
        query = query.filter(Concept.is_published == True)
    
    if category_id:
        query = query.filter(Concept.category_id == category_id)
    
    if search:
        query = query.filter(
            or_(
                Concept.title.ilike(f"%{search}%"),
                Concept.content.ilike(f"%{search}%"),
            )
        )
    
    return query.scalar()

def get_related_concepts(db: Session, concept_id: int, limit: int = 8) -> List[Concept]:
    concept = get_concept(db, concept_id)
    if not concept:
        return []

    related: list[Concept] = []
    seen_ids = {concept.id}
    tag_ids = [tag.id for tag in concept.tags]

    if tag_ids:
        tag_matches = (
            db.query(Concept, func.count(Tag.id).label("tag_overlap"))
            .join(concept_tags, concept_tags.c.concept_id == Concept.id)
            .join(Tag, Tag.id == concept_tags.c.tag_id)
            .filter(Concept.id != concept.id)
            .filter(Concept.is_published == True)
            .filter(Tag.id.in_(tag_ids))
            .group_by(Concept.id)
            .order_by(func.count(Tag.id).desc(), Concept.read_count.desc(), Concept.updated_at.desc())
            .limit(limit)
            .all()
        )
        for matched_concept, _overlap in tag_matches:
            related.append(matched_concept)
            seen_ids.add(matched_concept.id)

    if len(related) < limit:
        category_matches = (
            db.query(Concept)
            .filter(Concept.category_id == concept.category_id)
            .filter(Concept.id.notin_(seen_ids))
            .filter(Concept.is_published == True)
            .order_by(Concept.read_count.desc(), Concept.updated_at.desc())
            .limit(limit - len(related))
            .all()
        )
        related.extend(category_matches)

    return related[:limit]

def create_concept(db: Session, concept: ConceptCreate) -> Concept:
    # 创建概念
    db_concept = Concept(
        title=concept.title,
        category_id=concept.category_id,
        content=concept.content,
        summary=concept.summary,
    )
    db.add(db_concept)
    db.flush()
    
    # 处理标签
    for tag_name in concept.tags:
        tag = db.query(Tag).filter(Tag.name == tag_name).first()
        if not tag:
            tag = Tag(name=tag_name)
            db.add(tag)
            db.flush()
        db_concept.tags.append(tag)
    
    # 处理公式
    for formula_data in concept.formulas:
        db_formula = Formula(
            concept_id=db_concept.id,
            name=formula_data.name,
            expression=formula_data.expression,
            description=formula_data.description,
        )
        db.add(db_formula)
        db.flush()
        
        # 处理公式变量
        for variable_data in formula_data.variables:
            db_variable = FormulaVariable(
                formula_id=db_formula.id,
                symbol=variable_data.symbol,
                name=variable_data.name,
                description=variable_data.description,
            )
            db.add(db_variable)
    
    # 处理示例
    for example_data in concept.examples:
        db_example = Example(
            concept_id=db_concept.id,
            title=example_data.title,
            description=example_data.description,
            solution=example_data.solution,
            result=example_data.result,
        )
        db.add(db_example)
    
    db.commit()
    db.refresh(db_concept)
    return db_concept

def _sync_concept_tags(db: Session, db_concept: Concept, tags: List[str]) -> None:
    db_concept.tags.clear()
    for tag_name in tags:
        clean_name = tag_name.strip()
        if not clean_name:
            continue
        tag = db.query(Tag).filter(Tag.name == clean_name).first()
        if not tag:
            tag = Tag(name=clean_name)
            db.add(tag)
            db.flush()
        db_concept.tags.append(tag)

def _replace_concept_formulas(db: Session, db_concept: Concept, formulas) -> None:
    formula_ids = [formula.id for formula in db_concept.formulas]
    if formula_ids:
        db.query(FormulaVariable).filter(FormulaVariable.formula_id.in_(formula_ids)).delete(synchronize_session=False)
    db.query(Formula).filter(Formula.concept_id == db_concept.id).delete(synchronize_session=False)
    db.flush()

    for formula_data in formulas:
        db_formula = Formula(
            concept_id=db_concept.id,
            name=formula_data.name,
            expression=formula_data.expression,
            description=formula_data.description,
        )
        db.add(db_formula)
        db.flush()

        for variable_data in formula_data.variables:
            db.add(FormulaVariable(
                formula_id=db_formula.id,
                symbol=variable_data.symbol,
                name=variable_data.name,
                description=variable_data.description,
            ))

def _replace_concept_examples(db: Session, db_concept: Concept, examples) -> None:
    db.query(Example).filter(Example.concept_id == db_concept.id).delete(synchronize_session=False)
    db.flush()

    for example_data in examples:
        db.add(Example(
            concept_id=db_concept.id,
            title=example_data.title,
            description=example_data.description,
            solution=example_data.solution,
            result=example_data.result,
        ))

def update_concept(db: Session, concept_id: int, concept: ConceptUpdate) -> Optional[Concept]:
    db_concept = db.query(Concept).filter(Concept.id == concept_id).first()
    if not db_concept:
        return None
    
    update_data = concept.model_dump(exclude_unset=True)
    tags = update_data.pop("tags", None)
    formulas = update_data.pop("formulas", None)
    examples = update_data.pop("examples", None)

    for field, value in update_data.items():
        setattr(db_concept, field, value)

    if tags is not None:
        _sync_concept_tags(db, db_concept, tags)

    if formulas is not None:
        _replace_concept_formulas(db, db_concept, concept.formulas or [])

    if examples is not None:
        _replace_concept_examples(db, db_concept, concept.examples or [])
    
    db.commit()
    db.refresh(db_concept)
    return db_concept

def delete_concept(db: Session, concept_id: int) -> bool:
    db_concept = db.query(Concept).filter(Concept.id == concept_id).first()
    if not db_concept:
        return False

    formula_ids = [formula.id for formula in db_concept.formulas]
    if formula_ids:
        db.query(FormulaVariable).filter(FormulaVariable.formula_id.in_(formula_ids)).delete(synchronize_session=False)
    db.query(Formula).filter(Formula.concept_id == db_concept.id).delete(synchronize_session=False)
    db.query(Example).filter(Example.concept_id == db_concept.id).delete(synchronize_session=False)
    db.execute(concept_tags.delete().where(concept_tags.c.concept_id == db_concept.id))
    db.delete(db_concept)
    db.commit()
    return True

def increment_read_count(db: Session, concept_id: int) -> None:
    db_concept = db.query(Concept).filter(Concept.id == concept_id).first()
    if db_concept:
        db_concept.read_count += 1
        db.commit()

# 概念分类CRUD
def get_concept_categories(db: Session) -> List[ConceptCategory]:
    return db.query(ConceptCategory).all()

def get_concept_category(db: Session, category_id: int) -> Optional[ConceptCategory]:
    return db.query(ConceptCategory).filter(ConceptCategory.id == category_id).first()

def create_concept_category(db: Session, category: dict) -> ConceptCategory:
    db_category = ConceptCategory(**category)
    db.add(db_category)
    db.commit()
    db.refresh(db_category)
    return db_category
