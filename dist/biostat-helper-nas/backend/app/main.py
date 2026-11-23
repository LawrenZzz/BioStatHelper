from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import RedirectResponse
from fastapi.staticfiles import StaticFiles
from contextlib import asynccontextmanager
from pathlib import Path
import logging
import uvicorn

from app.core.config import settings

# Keep backend diagnostics visible in the NAS container console. Secrets and
# request bodies are excluded by the MIMO service log messages themselves.
logging.basicConfig(
    level=logging.DEBUG if settings.DEBUG else logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s %(message)s",
)
from app.api.endpoints import videos, concepts, references, auth, search, statistics, admin, projects, gtd, study
from app.crud.user import sync_configured_admin_user
from app.db.database import engine, SessionLocal
from app.db.migrations import run_lightweight_migrations
from app.models import models
from app.models import study as study_models

# 创建数据库表
models.Base.metadata.create_all(bind=engine)
run_lightweight_migrations()

def ensure_admin_user():
    db = SessionLocal()
    try:
        user = sync_configured_admin_user(db)
        if user:
            print(f"Admin user synced: {user.username}")
            return user.id
    finally:
        db.close()

@asynccontextmanager
async def lifespan(app: FastAPI):
    # 启动时执行
    print("启动生统助手后端服务...")
    ensure_admin_user()
    yield
    # 关闭时执行
    print("关闭生统助手后端服务...")

app = FastAPI(
    title="生统助手 API",
    description="专为生物统计师设计的学习与资源查阅工具后端API",
    version=settings.APP_VERSION,
    docs_url="/docs",
    redoc_url="/redoc",
    lifespan=lifespan,
)

# 配置CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.BACKEND_CORS_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# 注册路由
app.include_router(
    auth.router,
    prefix="/api/v1/auth",
    tags=["认证"],
)
app.include_router(
    videos.router,
    prefix="/api/v1/videos",
    tags=["视频"],
)
app.include_router(
    concepts.router,
    prefix="/api/v1/concepts",
    tags=["概念"],
)
app.include_router(
    references.router,
    prefix="/api/v1/references",
    tags=["参考"],
)
app.include_router(
    search.router,
    prefix="/api/v1/search",
    tags=["搜索"],
)
app.include_router(
    statistics.router,
    prefix="/api/v1/statistics",
    tags=["统计"],
)
app.include_router(
    admin.router,
    prefix="/api/v1/admin",
    tags=["管理"],
)
app.include_router(
    projects.router,
    prefix="/api/v1/projects",
    tags=["项目工作台"],
)
app.include_router(
    gtd.router,
    prefix="/api/v1/gtd",
    tags=["今日工作台"],
)
app.include_router(study.router)

admin_static_dir = Path(__file__).resolve().parent / "static" / "admin"
if admin_static_dir.exists():
    app.mount("/admin", StaticFiles(directory=admin_static_dir, html=True), name="admin")

static_dir = Path(__file__).resolve().parent / "static"
static_dir.mkdir(parents=True, exist_ok=True)
app.mount("/static", StaticFiles(directory=static_dir), name="static")

@app.get("/")
async def root():
    return {
        "message": "欢迎使用生统助手 API",
        "version": settings.APP_VERSION,
        "docs": "/docs",
    }

@app.get("/admin-panel")
async def admin_panel_redirect():
    return RedirectResponse(url="/admin/")

@app.get("/health")
async def health_check():
    return {"status": "healthy"}

if __name__ == "__main__":
    uvicorn.run(
        "main:app",
        host="0.0.0.0",
        port=8000,
        reload=True,
    )
