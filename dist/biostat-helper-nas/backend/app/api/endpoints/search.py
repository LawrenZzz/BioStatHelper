from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session
from typing import List, Optional
from app.db.database import get_db
from app.crud import video as video_crud
from app.crud import concept as concept_crud
from app.crud import reference as reference_crud
from app.schemas.video import VideoResponse
from app.schemas.concept import ConceptResponse
from app.schemas.reference import ReferenceResponse

router = APIRouter()

@router.get("/")
def search(
    q: str = Query(..., min_length=1, description="搜索关键词"),
    type: Optional[str] = Query(None, description="搜索类型: video, concept, reference, all"),
    limit: int = Query(20, ge=1, le=100),
    db: Session = Depends(get_db),
):
    """全局搜索"""
    results = {
        "videos": [],
        "concepts": [],
        "references": [],
    }
    
    if type is None or type == "all" or type == "video":
        videos = video_crud.get_videos(db, limit=limit, search=q)
        results["videos"] = [VideoResponse.model_validate(v) for v in videos]
    
    if type is None or type == "all" or type == "concept":
        concepts = concept_crud.get_concepts(db, limit=limit, search=q)
        results["concepts"] = [ConceptResponse.model_validate(c) for c in concepts]
    
    if type is None or type == "all" or type == "reference":
        references = reference_crud.get_references(db, limit=limit, search=q)
        results["references"] = [ReferenceResponse.model_validate(r) for r in references]
    
    # 计算总数
    total = len(results["videos"]) + len(results["concepts"]) + len(results["references"])
    
    return {
        "query": q,
        "total": total,
        "results": results,
    }

@router.get("/suggestions")
def get_search_suggestions(
    q: str = Query(..., min_length=1, description="搜索关键词"),
    limit: int = Query(10, ge=1, le=20),
    db: Session = Depends(get_db),
):
    """获取搜索建议"""
    suggestions = []
    
    # 从视频标题获取建议
    videos = video_crud.get_videos(db, limit=limit, search=q)
    for video in videos:
        if video.title not in suggestions:
            suggestions.append(video.title)
    
    # 从概念标题获取建议
    concepts = concept_crud.get_concepts(db, limit=limit, search=q)
    for concept in concepts:
        if concept.title not in suggestions:
            suggestions.append(concept.title)
    
    # 从参考标题获取建议
    references = reference_crud.get_references(db, limit=limit, search=q)
    for reference in references:
        if reference.title not in suggestions:
            suggestions.append(reference.title)
    
    return {
        "query": q,
        "suggestions": suggestions[:limit],
    }

@router.get("/hot")
def get_hot_searches(
    limit: int = Query(10, ge=1, le=20),
    db: Session = Depends(get_db),
):
    """获取热门搜索"""
    # 获取热门视频标签
    hot_tags = []
    
    # 获取热门概念
    concepts = concept_crud.get_concepts(db, limit=limit, sort="popular")
    for concept in concepts:
        if concept.title not in hot_tags:
            hot_tags.append(concept.title)
    
    # 获取热门视频
    videos = video_crud.get_videos(db, limit=limit, sort="popular")
    for video in videos:
        if video.title not in hot_tags:
            hot_tags.append(video.title)
    
    return {
        "hot_searches": hot_tags[:limit],
    }
