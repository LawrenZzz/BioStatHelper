from __future__ import annotations

import hashlib
import shutil
import subprocess
from pathlib import Path


APP_DIR = Path(__file__).resolve().parents[1]
THUMBNAIL_DIR = APP_DIR / "static" / "thumbnails" / "nas"


class ThumbnailGenerationError(RuntimeError):
    pass


def _safe_timestamp(value: float | int | None) -> float:
    try:
        timestamp = float(value if value is not None else 5.0)
    except (TypeError, ValueError):
        timestamp = 5.0
    return max(0.0, min(timestamp, 24 * 60 * 60))


def generate_video_thumbnail(
    source_path: Path,
    *,
    video_id: int,
    relative_path: str,
    timestamp_seconds: float | int | None = 5.0,
) -> str:
    ffmpeg_path = shutil.which("ffmpeg")
    if not ffmpeg_path:
        raise ThumbnailGenerationError("后端容器未安装 ffmpeg，请重新构建镜像")

    if not source_path.exists() or not source_path.is_file():
        raise ThumbnailGenerationError("视频文件不存在")

    THUMBNAIL_DIR.mkdir(parents=True, exist_ok=True)
    digest = hashlib.sha1(
        f"{relative_path}|{source_path.stat().st_mtime_ns}|{source_path.stat().st_size}".encode("utf-8")
    ).hexdigest()[:12]
    output_path = THUMBNAIL_DIR / f"nas-{video_id}-{digest}.jpg"
    temp_path = output_path.with_suffix(".tmp.jpg")

    for old_file in THUMBNAIL_DIR.glob(f"nas-{video_id}-*.jpg"):
        if old_file != output_path:
            old_file.unlink(missing_ok=True)

    timestamps = []
    requested = _safe_timestamp(timestamp_seconds)
    for candidate in [requested, 5.0, 3.0, 1.0, 0.2]:
        if candidate not in timestamps:
            timestamps.append(candidate)

    last_error = ""
    for timestamp in timestamps:
        temp_path.unlink(missing_ok=True)
        command = [
            ffmpeg_path,
            "-hide_banner",
            "-loglevel",
            "error",
            "-y",
            "-ss",
            f"{timestamp:.3f}",
            "-i",
            str(source_path),
            "-frames:v",
            "1",
            "-vf",
            "scale=640:-2",
            "-q:v",
            "3",
            str(temp_path),
        ]
        result = subprocess.run(
            command,
            capture_output=True,
            text=True,
            timeout=60,
            check=False,
        )
        if result.returncode == 0 and temp_path.exists() and temp_path.stat().st_size > 0:
            temp_path.replace(output_path)
            return f"/static/thumbnails/nas/{output_path.name}"
        last_error = (result.stderr or result.stdout or "").strip()

    temp_path.unlink(missing_ok=True)
    raise ThumbnailGenerationError(last_error or "ffmpeg 未能从该视频截取封面")
