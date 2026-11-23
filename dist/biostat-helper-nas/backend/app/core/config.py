from pydantic import Field
from pydantic_settings import BaseSettings
from secrets import token_urlsafe
from typing import List, Optional
import os

class Settings(BaseSettings):
    # 应用配置
    APP_NAME: str = "生统助手"
    APP_VERSION: str = "0.1.67"
    DEBUG: bool = True
    
    # 数据库配置
    DATABASE_URL: str = "sqlite:///./biostat_helper.db"
    
    # PostgreSQL配置（生产环境）
    POSTGRES_USER: str = "biostat"
    POSTGRES_PASSWORD: str = ""
    POSTGRES_SERVER: str = "localhost"
    POSTGRES_PORT: int = 5432
    POSTGRES_DB: str = "biostat_helper"
    
    # JWT配置
    SECRET_KEY: str = Field(default_factory=lambda: token_urlsafe(32))
    ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 30
    PERSISTENT_LOGIN: bool = True
    
    # NAS视频配置
    NAS_HOST: str = "localhost"
    NAS_PORT: int = 8080
    NAS_VIDEO_PATH: str = "/videos"
    NAS_VIDEO_MOUNT_PATH: str = "/nas/videos"

    # 管理员初始化配置（可选）
    ADMIN_USERNAME: Optional[str] = None
    ADMIN_EMAIL: Optional[str] = None
    ADMIN_PASSWORD: Optional[str] = None

    # Xiaomi MiMo / OpenAI-compatible chat completion配置（可选）
    MIMO_API_BASE_URL: Optional[str] = None
    MIMO_API_KEY: Optional[str] = None
    MIMO_MODEL: str = "mimo-V2.5-pro"
    MIMO_TIMEOUT_SECONDS: int = 20
    # Project intake/agent requests must finish before mobile clients give up.
    # Video organization can keep the longer general timeout.
    MIMO_PROJECT_TIMEOUT_SECONDS: int = 30
    
    # CORS配置
    BACKEND_CORS_ORIGINS: List[str] = [
        "http://localhost:3000",
        "http://localhost:8000",
        "http://localhost:8080",
        "*",
    ]
    
    # 文件上传配置
    UPLOAD_DIR: str = "./uploads"
    MAX_FILE_SIZE: int = 100 * 1024 * 1024  # 100MB
    
    class Config:
        env_file = ".env"
        case_sensitive = True
    
    @property
    def database_url(self) -> str:
        if os.getenv("DATABASE_URL"):
            return os.getenv("DATABASE_URL")
        return f"postgresql+psycopg://{self.POSTGRES_USER}:{self.POSTGRES_PASSWORD}@{self.POSTGRES_SERVER}:{self.POSTGRES_PORT}/{self.POSTGRES_DB}"

settings = Settings()
