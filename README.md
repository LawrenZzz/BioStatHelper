# BioStat Helper

生物统计师专用助手 App。当前仓库只保留两个有效入口：

- `frontend/`：Flutter App 源码，用于实机调试和前端开发。
- `dist/biostat-helper-nas/`：NAS Docker 部署目录。

## NAS 部署

```bash
cd dist/biostat-helper-nas
cp .env.example .env
```

在 `.env` 里分别填入随机生成的 `POSTGRES_PASSWORD` 和 `SECRET_KEY`。如需预建管理员，同时填写 `ADMIN_USERNAME`、`ADMIN_EMAIL` 和 `ADMIN_PASSWORD`。视频目录可通过 `NAS_VIDEO_PATH` 配置。

```bash
docker compose up -d --build
```

## App 开发

```bash
cd frontend
flutter pub get
flutter run --dart-define=API_BASE_URL=http://localhost:8000/api/v1
```

在 Android 模拟器中可使用 `http://10.0.2.2:8000/api/v1`，实机调试时填写设备可访问的后端地址。

- `frontend/lib/`：Flutter 应用源码。
- `frontend/android/`：Android 原生集成。
- `dist/biostat-helper-nas/backend/`：FastAPI 后端和 Web 管理台。
