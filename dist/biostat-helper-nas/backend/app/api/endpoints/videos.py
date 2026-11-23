from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session
from typing import List, Optional
from app.db.database import get_db
from app.api.endpoints.auth import get_current_admin_user, get_current_user
from app.crud import admin as admin_crud
from app.crud import video as video_crud
from app.schemas.admin import NasVideoCategoryResponse
from app.schemas.video import (
    VideoCreate, VideoUpdate, VideoResponse, VideoListResponse,
    VideoCategoryCreate, VideoCategoryResponse, VideoSidecarResponse,
    VideoProgressResponse, VideoProgressUpdate,
)

router = APIRouter()

def _video_response(
    db: Session,
    video,
    current_user=None,
    include_sidecars: bool = False,
) -> VideoResponse:
    response = VideoResponse.model_validate(video)
    nas_video = video_crud.get_nas_video_by_published_video(db, video.id)
    if nas_video:
        response.nas_video_id = nas_video.id
        response.nas_category_id = nas_video.category_id
        response.nas_category_path = nas_video.category_path
        response.episode_number = nas_video.episode_number
        response.sort_order = nas_video.sort_order
        if include_sidecars:
            response.sidecars = [
                VideoSidecarResponse(
                    id=item["id"],
                    file_name=item["file_name"],
                    extension=item["extension"],
                    kind=item["kind"],
                    title=item["title"],
                    url=f"/api/v1/admin/nas-videos/{nas_video.id}/sidecars/{item['id']}/stream",
                )
                for item in admin_crud.get_nas_video_sidecars(nas_video)
            ]
    if current_user:
        progress = video_crud.get_video_progress(db, current_user.id, video.id)
        if progress:
            response.progress_percent = progress.progress_percent or 0
            response.completed = bool(progress.completed)
    return response

@router.get("/", response_model=VideoListResponse)
def list_videos(
    skip: int = Query(0, ge=0),
    limit: int = Query(100, ge=1, le=1000),
    category_id: Optional[int] = None,
    nas_category_id: Optional[int] = None,
    search: Optional[str] = None,
    sort: str = Query("episode", pattern="^(episode|newest|popular|duration|recent)$"),
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user),
):
    """获取视频列表"""
    videos = video_crud.get_videos(
        db, skip=skip, limit=limit,
        category_id=category_id, nas_category_id=nas_category_id,
        search=search, sort=sort,
    )
    total = video_crud.get_videos_count(
        db,
        category_id=category_id,
        nas_category_id=nas_category_id,
        search=search,
    )
    
    return VideoListResponse(
        data=[_video_response(db, video, current_user) for video in videos],
        total=total,
        page=skip // limit + 1,
        page_size=limit,
    )

@router.post("/", response_model=VideoResponse)
def create_video(
    video: VideoCreate,
    db: Session = Depends(get_db),
    _admin=Depends(get_current_admin_user),
):
    """创建视频"""
    return video_crud.create_video(db, video)

@router.put("/{video_id}", response_model=VideoResponse)
def update_video(
    video_id: int,
    video: VideoUpdate,
    db: Session = Depends(get_db),
    _admin=Depends(get_current_admin_user),
):
    """更新视频"""
    db_video = video_crud.update_video(db, video_id, video)
    if not db_video:
        raise HTTPException(status_code=404, detail="视频不存在")
    return VideoResponse.model_validate(db_video)

@router.delete("/{video_id}")
def delete_video(
    video_id: int,
    db: Session = Depends(get_db),
    _admin=Depends(get_current_admin_user),
):
    """删除视频"""
    if not video_crud.delete_video(db, video_id):
        raise HTTPException(status_code=404, detail="视频不存在")
    return {"message": "视频已删除"}

@router.get("/categories", response_model=List[VideoCategoryResponse], include_in_schema=False)
@router.get("/categories/", response_model=List[VideoCategoryResponse])
def list_video_categories(
    db: Session = Depends(get_db),
):
    """获取视频分类列表"""
    categories = video_crud.get_video_categories(db)
    result = []
    for category in categories:
        category_dict = VideoCategoryResponse.model_validate(category)
        category_dict.video_count = len(category.videos)
        result.append(category_dict)
    return result

@router.get("/nas-categories", response_model=List[NasVideoCategoryResponse])
@router.get("/nas-categories/", response_model=List[NasVideoCategoryResponse], include_in_schema=False)
def list_nas_video_categories_for_app(
    db: Session = Depends(get_db),
):
    """获取与后台NAS视频库同步的分类树，供App视频库筛选使用。"""
    return video_crud.get_nas_video_categories_for_app(db)

@router.post("/categories/", response_model=VideoCategoryResponse)
def create_video_category(
    category: VideoCategoryCreate,
    db: Session = Depends(get_db),
    _admin=Depends(get_current_admin_user),
):
    """创建视频分类"""
    return video_crud.create_video_category(db, category.model_dump())

@router.get("/{video_id}", response_model=VideoResponse)
def get_video(
    video_id: int,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user),
):
    """获取视频详情"""
    video = video_crud.get_video(db, video_id)
    if not video:
        raise HTTPException(status_code=404, detail="视频不存在")
    
    # 增加观看次数
    video_crud.increment_view_count(db, video_id)
    
    return _video_response(db, video, current_user, include_sidecars=True)

@router.put("/{video_id}/progress", response_model=VideoProgressResponse)
def update_video_progress(
    video_id: int,
    progress_update: VideoProgressUpdate,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user),
):
    """更新当前用户的视频观看进度。"""
    video = video_crud.get_video(db, video_id)
    if not video:
        raise HTTPException(status_code=404, detail="视频不存在")
    progress = video_crud.update_video_progress(
        db,
        current_user.id,
        video_id,
        progress_update,
    )
    return VideoProgressResponse.model_validate(progress)

@router.get("/{video_id}/related", response_model=List[VideoResponse])
def get_related_videos(
    video_id: int,
    limit: int = Query(5, ge=1, le=20),
    db: Session = Depends(get_db),
):
    """获取相关视频"""
    video = video_crud.get_video(db, video_id)
    if not video:
        raise HTTPException(status_code=404, detail="视频不存在")
    
    # 获取同分类的其他视频
    related_videos = video_crud.get_videos(
        db, limit=limit, category_id=video.category_id,
    )
    # 排除当前视频
    related_videos = [v for v in related_videos if v.id != video_id][:limit]
    
    return [_video_response(db, video) for video in related_videos]
