import secrets

from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer
from sqlalchemy.orm import Session
from datetime import datetime, timedelta
from jose import JWTError, jwt
from typing import Optional
from app.db.database import get_db
from app.core.config import settings
from app.crud import user as user_crud
from app.schemas.user import (
    UserCreate, UserUpdate, UserResponse,
    LoginRequest, Token, TokenData,
    LearningProgressResponse, UserSettingUpdate, UserSettingResponse,
    FavoriteCreate,
)

router = APIRouter()
oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/api/v1/auth/login")
AUTH_BUILD_ID = "2026-07-13-persistent-session-1"


def _matches_configured_admin_password(password: str) -> bool:
    if not settings.ADMIN_PASSWORD:
        return False

    candidates = {password, password.strip()}
    return any(
        secrets.compare_digest(candidate, settings.ADMIN_PASSWORD)
        for candidate in candidates
    )


def create_access_token(data: dict, expires_delta: Optional[timedelta] = None):
    to_encode = data.copy()
    if expires_delta:
        expire = datetime.utcnow() + expires_delta
        to_encode.update({"exp": expire})
    encoded_jwt = jwt.encode(to_encode, settings.SECRET_KEY, algorithm=settings.ALGORITHM)
    return encoded_jwt


@router.get("/version")
def auth_version(db: Session = Depends(get_db)):
    """Return a small deployment diagnostic marker."""
    admin_user = None

    if settings.ADMIN_USERNAME:
        admin_user = user_crud.get_user_by_username(db, settings.ADMIN_USERNAME)

    return {
        "build": AUTH_BUILD_ID,
        "admin_username_configured": bool(settings.ADMIN_USERNAME),
        "admin_email_configured": bool(settings.ADMIN_EMAIL),
        "admin_password_configured": bool(settings.ADMIN_PASSWORD),
        "admin_user_found": bool(admin_user),
        "admin_user_active": getattr(admin_user, "is_active", None),
        "admin_user_admin": getattr(admin_user, "is_admin", None),
    }

async def get_current_user(
    token: str = Depends(oauth2_scheme),
    db: Session = Depends(get_db),
):
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="无法验证凭据",
        headers={"WWW-Authenticate": "Bearer"},
    )
    try:
        payload = jwt.decode(token, settings.SECRET_KEY, algorithms=[settings.ALGORITHM])
        username: str = payload.get("sub")
        if username is None:
            raise credentials_exception
        token_data = TokenData(username=username)
    except JWTError:
        raise credentials_exception
    
    user = user_crud.get_user_by_username(db, username=token_data.username)
    if user is None:
        raise credentials_exception
    return user

async def get_current_admin_user(
    current_user = Depends(get_current_user),
):
    if not current_user.is_admin:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="需要管理员权限",
        )
    return current_user

@router.post("/register", response_model=UserResponse)
def register(
    user: UserCreate,
    db: Session = Depends(get_db),
):
    """用户注册"""
    # 检查用户名是否已存在
    db_user = user_crud.get_user_by_username(db, username=user.username)
    if db_user:
        raise HTTPException(
            status_code=400,
            detail="用户名已存在",
        )
    
    # 检查邮箱是否已存在
    db_user = user_crud.get_user_by_email(db, email=user.email)
    if db_user:
        raise HTTPException(
            status_code=400,
            detail="邮箱已被注册",
        )
    
    return user_crud.create_user(db=db, user=user)

def _login_with_password(
    login_data: LoginRequest,
    db: Session,
) -> Token:
    username = login_data.username.strip()
    password = login_data.password
    user = user_crud.authenticate_user(db, username, password)

    if not user:
        configured_admin_names = {
            value.strip().casefold()
            for value in (settings.ADMIN_USERNAME, settings.ADMIN_EMAIL)
            if value
        }
        is_configured_admin = username.casefold() in configured_admin_names
        if is_configured_admin and _matches_configured_admin_password(password):
            user = user_crud.sync_configured_admin_user(db)

    if not user:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="用户名或密码错误",
            headers={"WWW-Authenticate": "Bearer"},
        )
    
    access_token_expires = (
        None
        if settings.PERSISTENT_LOGIN
        else timedelta(minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES)
    )
    access_token = create_access_token(
        data={"sub": user.username},
        expires_delta=access_token_expires,
    )
    
    return {"access_token": access_token, "token_type": "bearer"}


@router.post("/login", response_model=Token)
def login(
    login_data: LoginRequest,
    db: Session = Depends(get_db),
):
    """用户登录"""
    return _login_with_password(login_data, db)


@router.post("/session", response_model=Token)
def create_session(
    login_data: LoginRequest,
    db: Session = Depends(get_db),
):
    """管理台登录入口，避开部分代理对 /login 路径的特殊处理。"""
    return _login_with_password(login_data, db)

@router.get("/profile", response_model=UserResponse)
async def get_profile(
    current_user: UserResponse = Depends(get_current_user),
):
    """获取用户资料"""
    return current_user

@router.get("/settings", response_model=UserSettingResponse)
async def get_settings(
    current_user: UserResponse = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """获取当前用户设置"""
    return user_crud.get_or_create_user_settings(db, current_user.id)

@router.put("/settings", response_model=UserSettingResponse)
async def update_settings(
    settings_update: UserSettingUpdate,
    current_user: UserResponse = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """更新当前用户设置"""
    return user_crud.update_user_settings(db, current_user.id, settings_update)

@router.put("/profile", response_model=UserResponse)
async def update_profile(
    user_update: UserUpdate,
    current_user: UserResponse = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """更新用户资料"""
    updated_user = user_crud.update_user(db, current_user.id, user_update)
    if not updated_user:
        raise HTTPException(status_code=404, detail="用户不存在")
    return updated_user

@router.get("/progress", response_model=LearningProgressResponse)
async def get_learning_progress(
    current_user: UserResponse = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """获取学习进度"""
    progress = user_crud.get_learning_progress(db, current_user.id)
    return LearningProgressResponse(**progress)

@router.post("/favorites")
async def add_favorite(
    favorite: FavoriteCreate,
    current_user: UserResponse = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """添加收藏"""
    success = user_crud.add_favorite(
        db, current_user.id,
        video_id=favorite.video_id,
        concept_id=favorite.concept_id,
        reference_id=favorite.reference_id,
    )
    if not success:
        raise HTTPException(status_code=400, detail="已收藏")
    return {"message": "收藏成功"}

@router.delete("/favorites/{favorite_type}/{favorite_id}")
async def remove_favorite(
    favorite_type: str,
    favorite_id: int,
    current_user: UserResponse = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """取消收藏"""
    video_id = favorite_id if favorite_type == "video" else None
    concept_id = favorite_id if favorite_type == "concept" else None
    reference_id = favorite_id if favorite_type == "reference" else None
    
    success = user_crud.remove_favorite(
        db, current_user.id,
        video_id=video_id,
        concept_id=concept_id,
        reference_id=reference_id,
    )
    if not success:
        raise HTTPException(status_code=404, detail="未收藏")
    return {"message": "取消收藏成功"}
