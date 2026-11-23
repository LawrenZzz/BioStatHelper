from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.api.endpoints.auth import get_current_user
from app.crud import user as user_crud
from app.db.database import get_db
from app.schemas.user import LearningProgressResponse, UserResponse

router = APIRouter()


@router.get("/progress", response_model=LearningProgressResponse)
def get_learning_progress(
    current_user: UserResponse = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """获取当前用户学习进度"""
    progress = user_crud.get_learning_progress(db, current_user.id)
    return LearningProgressResponse(**progress)
