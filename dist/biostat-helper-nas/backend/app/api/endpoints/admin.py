from pathlib import Path
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from fastapi.responses import FileResponse
from sqlalchemy.orm import Session

from app.api.endpoints.auth import get_current_admin_user, get_current_user
from app.core.config import settings
from app.crud import admin as admin_crud
from app.models.models import Concept
from app.db.database import get_db
from app.schemas.admin import (
    AdminStatsResponse,
    ManualNasVideoCreate,
    NasVideoAiBatchOrganizeRequest,
    NasVideoAiOrganizeRequest,
    NasVideoAiOrganizeResponse,
    NasVideoAiSuggestion,
    NasVideoCategoryCreate,
    NasVideoCategoryResponse,
    NasVideoCategoryUpdate,
    NasVideoDeleteRequest,
    NasScanResponse,
    NasVideoSidecarScanResponse,
    NasVideoListResponse,
    NasVideoResponse,
    NasVideoReorderRequest,
    NasVideoThumbnailRequest,
    NasVideoUpdate,
    PublishNasVideoRequest,
)
from app.schemas.video import VideoResponse
from app.services.mimo_assistant import organize_video_metadata

router = APIRouter()


def _nas_file_path(relative_path: str) -> Path:
    base_path = Path(settings.NAS_VIDEO_MOUNT_PATH).resolve()
    target_path = (base_path / relative_path).resolve()
    if base_path != target_path and base_path not in target_path.parents:
        raise HTTPException(status_code=400, detail="非法文件路径")
    if not target_path.exists() or not target_path.is_file():
        raise HTTPException(status_code=404, detail="视频文件不存在")
    return target_path


def _nas_sidecar_path(nas_video, sidecar_id: int) -> Path:
    sidecars = admin_crud.get_nas_video_sidecars(nas_video)
    sidecar = next((item for item in sidecars if item["id"] == sidecar_id), None)
    if not sidecar:
        raise HTTPException(status_code=404, detail="瀛楀箷鎴栧脊骞曟枃浠朵笉瀛樺湪")

    base_path = Path(settings.NAS_VIDEO_MOUNT_PATH).resolve()
    target_path = (base_path / sidecar["relative_path"]).resolve()
    if base_path != target_path and base_path not in target_path.parents:
        raise HTTPException(status_code=400, detail="闈炴硶鏂囦欢璺緞")
    if not target_path.exists() or not target_path.is_file():
        raise HTTPException(status_code=404, detail="瀛楀箷鎴栧脊骞曟枃浠朵笉瀛樺湪")
    return target_path


def _video_ai_payload(nas_video) -> dict:
    file_context = {}
    try:
        target_path = _nas_file_path(nas_video.relative_path)
        base_path = Path(settings.NAS_VIDEO_MOUNT_PATH).resolve()
        file_context = admin_crud.build_nas_video_file_context(base_path, target_path)
    except HTTPException as exc:
        file_context = {"context_error": exc.detail}
    except Exception as exc:
        file_context = {"context_error": str(exc)}
    return {
        "id": nas_video.id,
        "relative_path": nas_video.relative_path,
        "file_name": nas_video.file_name,
        "category_path": nas_video.category_path,
        "course_name": nas_video.course_name,
        "course_title": nas_video.course_title,
        "lesson_title": nas_video.lesson_title,
        "title": nas_video.title,
        "episode_number": nas_video.episode_number,
        "sort_order": nas_video.sort_order,
        "instructor": nas_video.instructor,
        "tags": nas_video.tags,
        "description": nas_video.description,
        "file_context": file_context,
    }


def _nas_video_category_path(nas_video) -> Optional[str]:
    try:
        return nas_video.category_path
    except Exception:
        return None


def _build_ai_suggestion_response(nas_video, suggestion: dict, model_used: str, fallback_used: bool, applied: bool) -> NasVideoAiSuggestion:
    return NasVideoAiSuggestion(
        video_id=nas_video.id,
        relative_path=nas_video.relative_path,
        model_used=model_used,
        fallback_used=fallback_used,
        applied=applied,
        **suggestion,
    )


def _build_ai_error_response(nas_video, error: Exception | str) -> NasVideoAiSuggestion:
    message = str(error)
    return NasVideoAiSuggestion(
        video_id=nas_video.id,
        relative_path=nas_video.relative_path,
        model_used="error",
        fallback_used=True,
        applied=False,
        category_path=_nas_video_category_path(nas_video),
        course_name=nas_video.course_name,
        course_title=nas_video.course_title,
        lesson_title=nas_video.lesson_title,
        title=nas_video.title,
        episode_number=nas_video.episode_number,
        sort_order=nas_video.sort_order,
        instructor=nas_video.instructor,
        tags=nas_video.tags,
        description=nas_video.description,
        error=message,
    )


@router.get("/stats", response_model=AdminStatsResponse)
def get_admin_stats(
    db: Session = Depends(get_db),
    _admin=Depends(get_current_admin_user),
):
    """管理台统计数据"""
    return admin_crud.get_admin_stats(db)


@router.post("/knowledge/publish-all")
def publish_all_knowledge(
    db: Session = Depends(get_db),
    _admin=Depends(get_current_admin_user),
):
    """一键发布全部知识库概念。"""
    hidden_count = db.query(Concept).filter(Concept.is_published == False).count()
    db.query(Concept).filter(Concept.is_published == False).update(
        {"is_published": True},
        synchronize_session=False,
    )
    db.commit()
    return {"published": hidden_count}


@router.post("/nas-videos/scan", response_model=NasScanResponse)
def scan_nas_videos(
    db: Session = Depends(get_db),
    _admin=Depends(get_current_admin_user),
):
    """扫描挂载到容器内的NAS视频目录"""
    try:
        return admin_crud.scan_nas_videos(db)
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"扫描视频目录失败：{exc}") from exc


@router.get("/nas-videos", response_model=NasVideoListResponse)
def list_nas_videos(
    skip: int = Query(0, ge=0),
    limit: int = Query(100, ge=1, le=1000),
    search: Optional[str] = None,
    course_name: Optional[str] = None,
    published: Optional[bool] = None,
    category_id: Optional[int] = None,
    db: Session = Depends(get_db),
    _admin=Depends(get_current_admin_user),
):
    """获取NAS视频元数据列表"""
    items, total = admin_crud.get_nas_videos(
        db,
        skip=skip,
        limit=limit,
        search=search,
        course_name=course_name,
        published=published,
        category_id=category_id,
    )
    return NasVideoListResponse(data=items, total=total)


@router.get("/nas-video-categories", response_model=list[NasVideoCategoryResponse])
def list_nas_video_categories(
    db: Session = Depends(get_db),
    _admin=Depends(get_current_admin_user),
):
    """获取NAS视频无限层级分类列表。"""
    return admin_crud.get_nas_video_categories(db)


@router.post("/nas-video-categories", response_model=NasVideoCategoryResponse)
def create_nas_video_category(
    category: NasVideoCategoryCreate,
    db: Session = Depends(get_db),
    _admin=Depends(get_current_admin_user),
):
    """创建NAS视频分类。"""
    return admin_crud.create_nas_video_category(db, category)


@router.delete("/nas-video-categories")
def delete_all_nas_video_categories(
    db: Session = Depends(get_db),
    _admin=Depends(get_current_admin_user),
):
    """删除全部NAS视频分类，不删除NAS本地视频文件。"""
    try:
        return admin_crud.delete_all_nas_video_categories(db)
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"删除全部分类失败：{exc}") from exc


@router.put("/nas-video-categories/{category_id}", response_model=NasVideoCategoryResponse)
def update_nas_video_category(
    category_id: int,
    category: NasVideoCategoryUpdate,
    db: Session = Depends(get_db),
    _admin=Depends(get_current_admin_user),
):
    """更新NAS视频分类。"""
    db_category = admin_crud.update_nas_video_category(db, category_id, category)
    if not db_category:
        raise HTTPException(status_code=404, detail="分类不存在")
    return db_category


@router.delete("/nas-video-categories/{category_id}")
def delete_nas_video_category(
    category_id: int,
    db: Session = Depends(get_db),
    _admin=Depends(get_current_admin_user),
):
    """删除NAS视频分类及其子分类，不删除NAS本地视频文件。"""
    try:
        result = admin_crud.delete_nas_video_category(db, category_id)
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"删除分类失败：{exc}") from exc
    if not result:
        raise HTTPException(status_code=404, detail="分类不存在")
    return result


@router.post("/nas-video-categories/{category_id}/publish")
def publish_nas_video_category(
    category_id: int,
    publish_request: PublishNasVideoRequest,
    db: Session = Depends(get_db),
    _admin=Depends(get_current_admin_user),
):
    """发布某个NAS分类及子分类下的全部视频到App视频列表。"""
    try:
        result = admin_crud.publish_nas_video_category(
            db,
            category_id,
            is_published=publish_request.is_published,
        )
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"发布课程失败：{exc}") from exc
    if not result:
        raise HTTPException(status_code=404, detail="分类不存在")
    return result


@router.post("/nas-videos/manual", response_model=NasVideoResponse)
def create_manual_nas_video(
    video: ManualNasVideoCreate,
    db: Session = Depends(get_db),
    _admin=Depends(get_current_admin_user),
):
    """手动添加挂载目录中的单独视频文件。"""
    nas_video = admin_crud.create_manual_nas_video(db, video)
    if not nas_video:
        raise HTTPException(status_code=400, detail="视频路径不存在或不是受支持的视频文件")
    return nas_video


@router.post("/nas-videos/ai-organize", response_model=NasVideoAiOrganizeResponse)
async def batch_organize_nas_videos_with_ai(
    request: NasVideoAiBatchOrganizeRequest,
    db: Session = Depends(get_db),
    _admin=Depends(get_current_admin_user),
):
    """使用MiMo整理当前筛选范围内的NAS视频课程分类与元数据。"""
    limit = max(1, min(request.limit, 200))
    if request.video_ids:
        videos = [
            video
            for video in (admin_crud.get_nas_video(db, video_id) for video_id in request.video_ids[:limit])
            if video
        ]
    else:
        videos, _total = admin_crud.get_nas_videos(
            db,
            skip=0,
            limit=limit,
            search=request.search,
            published=request.published,
            category_id=request.category_id,
        )

    category_paths = [category.path for category in admin_crud.get_nas_video_categories(db)]
    results = []
    applied = 0
    fallback_count = 0
    for nas_video in videos:
        try:
            suggestion, model_used, fallback_used, _raw = await organize_video_metadata(
                _video_ai_payload(nas_video),
                category_paths=category_paths,
            )
            if request.apply:
                nas_video = admin_crud.apply_nas_video_ai_suggestion(
                    db,
                    nas_video,
                    suggestion,
                    overwrite_existing=request.overwrite_existing,
                )
                applied += 1
                category_path = _nas_video_category_path(nas_video)
                if category_path and category_path not in category_paths:
                    category_paths.append(category_path)
            if fallback_used:
                fallback_count += 1
            results.append(_build_ai_suggestion_response(nas_video, suggestion, model_used, fallback_used, request.apply))
        except Exception as exc:
            db.rollback()
            fallback_count += 1
            latest_video = admin_crud.get_nas_video(db, nas_video.id) or nas_video
            results.append(_build_ai_error_response(latest_video, exc))

    return NasVideoAiOrganizeResponse(
        data=results,
        total=len(results),
        applied=applied,
        fallback_count=fallback_count,
    )


@router.post("/nas-videos/{video_id}/ai-organize", response_model=NasVideoAiOrganizeResponse)
async def organize_nas_video_with_ai(
    video_id: int,
    request: NasVideoAiOrganizeRequest,
    db: Session = Depends(get_db),
    _admin=Depends(get_current_admin_user),
):
    """使用MiMo整理单个NAS视频课程分类与元数据。"""
    nas_video = admin_crud.get_nas_video(db, video_id)
    if not nas_video:
        raise HTTPException(status_code=404, detail="NAS视频不存在")

    category_paths = [category.path for category in admin_crud.get_nas_video_categories(db)]
    applied = 0
    try:
        suggestion, model_used, fallback_used, _raw = await organize_video_metadata(
            _video_ai_payload(nas_video),
            category_paths=category_paths,
        )
        if request.apply:
            nas_video = admin_crud.apply_nas_video_ai_suggestion(
                db,
                nas_video,
                suggestion,
                overwrite_existing=request.overwrite_existing,
            )
            applied = 1

        return NasVideoAiOrganizeResponse(
            data=[_build_ai_suggestion_response(nas_video, suggestion, model_used, fallback_used, request.apply)],
            total=1,
            applied=applied,
            fallback_count=1 if fallback_used else 0,
        )
    except Exception as exc:
        db.rollback()
        latest_video = admin_crud.get_nas_video(db, nas_video.id) or nas_video
        return NasVideoAiOrganizeResponse(
            data=[_build_ai_error_response(latest_video, exc)],
            total=1,
            applied=0,
            fallback_count=1,
        )


@router.delete("/nas-videos/library")
def delete_nas_video_library_records(
    request: NasVideoDeleteRequest,
    db: Session = Depends(get_db),
    _admin=Depends(get_current_admin_user),
):
    """删除整个NAS视频库的数据库记录，不删除NAS本地视频文件。"""
    if request.confirm_text.strip() != "删除整个视频库记录":
        raise HTTPException(status_code=400, detail="确认文本不正确，不会执行删除")
    try:
        return admin_crud.delete_all_nas_video_records(db)
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"删除视频库记录失败：{exc}") from exc


@router.post("/nas-videos/sidecars/scan", response_model=NasVideoSidecarScanResponse)
def scan_nas_video_sidecars(
    db: Session = Depends(get_db),
    _admin=Depends(get_current_admin_user),
):
    """搜索已有NAS视频同目录下可匹配的字幕/弹幕sidecar文件，不修改NAS本地文件。"""
    try:
        return admin_crud.scan_nas_video_sidecars(db)
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"搜索字幕/弹幕失败：{exc}") from exc


@router.get("/nas-videos/{video_id}", response_model=NasVideoResponse)
def get_nas_video(
    video_id: int,
    db: Session = Depends(get_db),
    _admin=Depends(get_current_admin_user),
):
    """获取单个NAS视频元数据"""
    nas_video = admin_crud.get_nas_video(db, video_id)
    if not nas_video:
        raise HTTPException(status_code=404, detail="NAS视频不存在")
    return nas_video


@router.put("/nas-videos/reorder", response_model=list[NasVideoResponse])
def reorder_nas_videos(
    request: NasVideoReorderRequest,
    db: Session = Depends(get_db),
    _admin=Depends(get_current_admin_user),
):
    """Save drag-and-drop order for the selected NAS video records."""
    try:
        return admin_crud.reorder_nas_videos(db, request.video_ids)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


@router.post("/nas-videos/{video_id}/thumbnail", response_model=NasVideoResponse)
def generate_nas_video_thumbnail(
    video_id: int,
    request: NasVideoThumbnailRequest,
    db: Session = Depends(get_db),
    _admin=Depends(get_current_admin_user),
):
    """从NAS视频文件截取一帧作为封面，不修改本地视频文件。"""
    nas_video = admin_crud.get_nas_video(db, video_id)
    if not nas_video:
        raise HTTPException(status_code=404, detail="NAS视频不存在")
    target_path = _nas_file_path(nas_video.relative_path)
    try:
        updated = admin_crud.generate_nas_video_thumbnail(
            db,
            video_id,
            target_path,
            timestamp_seconds=request.timestamp_seconds,
            overwrite=request.overwrite,
        )
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"生成视频截图封面失败：{exc}") from exc
    if not updated:
        raise HTTPException(status_code=404, detail="NAS视频不存在")
    return updated


@router.put("/nas-videos/{video_id}", response_model=NasVideoResponse)
def update_nas_video(
    video_id: int,
    video_update: NasVideoUpdate,
    db: Session = Depends(get_db),
    _admin=Depends(get_current_admin_user),
):
    """更新NAS视频课程信息"""
    nas_video = admin_crud.update_nas_video(db, video_id, video_update)
    if not nas_video:
        raise HTTPException(status_code=404, detail="NAS视频不存在")
    return nas_video


@router.delete("/nas-videos/{video_id}")
def delete_nas_video_record(
    video_id: int,
    request: NasVideoDeleteRequest,
    db: Session = Depends(get_db),
    _admin=Depends(get_current_admin_user),
):
    """只删除视频库数据库记录，不删除NAS本地视频文件。"""
    if request.confirm_text.strip() != "删除视频库记录":
        raise HTTPException(status_code=400, detail="确认文本不正确，不会执行删除")
    try:
        result = admin_crud.delete_nas_video_record(db, video_id)
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"删除视频记录失败：{exc}") from exc
    if not result:
        raise HTTPException(status_code=404, detail="NAS视频不存在")
    return result


@router.post("/nas-videos/{video_id}/publish", response_model=VideoResponse)
def publish_nas_video(
    video_id: int,
    publish_request: PublishNasVideoRequest,
    db: Session = Depends(get_db),
    _admin=Depends(get_current_admin_user),
):
    """将NAS视频发布到App视频列表"""
    video = admin_crud.publish_nas_video(
        db,
        video_id,
        category_id=publish_request.category_id,
        is_published=publish_request.is_published,
    )
    if not video:
        raise HTTPException(status_code=404, detail="NAS视频不存在")
    return VideoResponse.model_validate(video)


@router.get("/nas-videos/{video_id}/stream")
def stream_nas_video(
    video_id: int,
    db: Session = Depends(get_db),
    _user=Depends(get_current_user),
):
    """播放已扫描且可见的NAS视频文件。需要登录。"""
    nas_video = admin_crud.get_nas_video(db, video_id)
    if not nas_video or not nas_video.is_visible:
        raise HTTPException(status_code=404, detail="NAS视频不存在")

    target_path = _nas_file_path(nas_video.relative_path)
    return FileResponse(
        target_path,
        media_type="video/mp4",
        filename=nas_video.file_name,
    )


@router.get("/nas-videos/{video_id}/sidecars/{sidecar_id}/stream")
def stream_nas_video_sidecar(
    video_id: int,
    sidecar_id: int,
    db: Session = Depends(get_db),
    _user=Depends(get_current_user),
):
    """读取NAS视频同目录下匹配的字幕/弹幕sidecar文件。"""
    nas_video = admin_crud.get_nas_video(db, video_id)
    if not nas_video or not nas_video.is_visible:
        raise HTTPException(status_code=404, detail="NAS video not found")

    target_path = _nas_sidecar_path(nas_video, sidecar_id)
    media_type = "text/plain; charset=utf-8"
    if target_path.suffix.lower() == ".vtt":
        media_type = "text/vtt; charset=utf-8"
    elif target_path.suffix.lower() == ".json":
        media_type = "application/json; charset=utf-8"
    elif target_path.suffix.lower() == ".xml":
        media_type = "application/xml; charset=utf-8"
    return FileResponse(
        target_path,
        media_type=media_type,
        filename=target_path.name,
    )
