from datetime import datetime
import hashlib
import os
from pathlib import Path
import re
from typing import Optional

from sqlalchemy import func, or_
from sqlalchemy.orm import Session

from app.core.config import settings
from app.models.models import (
    Concept,
    LearningProgress,
    NasVideo,
    NasVideoCategory,
    Note,
    Reference,
    User,
    Video,
    VideoCategory,
    user_favorites,
    video_tags,
)
from app.schemas.admin import ManualNasVideoCreate, NasVideoCategoryCreate, NasVideoCategoryUpdate, NasVideoUpdate
from app.services.video_thumbnail import generate_video_thumbnail


VIDEO_EXTENSIONS = {
    ".mp4",
    ".m4v",
    ".mov",
    ".mkv",
    ".avi",
    ".webm",
    ".flv",
    ".wmv",
}

MAX_DB_INTEGER = 2_147_483_647

CHINESE_NUMERAL_DIGITS = {
    "零": 0,
    "〇": 0,
    "一": 1,
    "二": 2,
    "两": 2,
    "三": 3,
    "四": 4,
    "五": 5,
    "六": 6,
    "七": 7,
    "八": 8,
    "九": 9,
}
CHINESE_NUMERAL_UNITS = {
    "十": 10,
    "百": 100,
    "千": 1000,
    "万": 10_000,
    "亿": 100_000_000,
}
CHINESE_NUMERAL_CHARS = "零〇一二两三四五六七八九十百千万亿"

SIDECAR_EXTENSIONS = {
    ".ass",
    ".srt",
    ".ssa",
    ".vtt",
    ".xml",
    ".json",
    ".danmaku",
    ".nfo",
}

SUBTITLE_EXTENSIONS = {".ass", ".srt", ".ssa", ".vtt"}
DANMAKU_EXTENSIONS = {".xml", ".json", ".danmaku"}
DANMAKU_PREFIXES = ["历史弹幕", "弹幕", "danmaku", "barrage", "comments", "comment"]
SUBTITLE_PREFIXES = ["字幕", "subtitle", "subtitles", "subs", "sub", "cc"]
SIDECAR_ROLE_PREFIX_RE = re.compile(
    r"^\s*(?:[（(【\[]\s*)?"
    r"(?P<prefix>历史弹幕|弹幕|字幕|danmaku|barrage|comments?|subtitles?|subs?|cc)"
    r"(?:\s*[）)】\]])?\s*(?:[\s.、:：/\\|_-]+)?",
    re.IGNORECASE,
)

NOISE_TITLE_WORDS = [
    "已下载",
    "高清",
    "超清",
    "蓝光",
    "字幕",
    "弹幕",
    "水印",
    "试看",
    "完整",
    "1080",
    "720",
    "4k",
    "bilibili",
    "youtube",
]

NOISE_LEADING_PREFIX_WORDS = sorted(
    [
        "课程音视频",
        "课程视频",
        "课件视频",
        "课堂视频",
        "直播回放",
        "音视频",
        "视频",
        "音频",
        "录屏",
        "回放",
        "正课",
        "主课",
        "课件",
        "讲义",
        "资料",
        "素材",
        "附件",
    ],
    key=len,
    reverse=True,
)

NOISE_LEADING_PREFIX_RE = re.compile(
    rf"^\s*(?:[（(【\[]\s*)?(?:{'|'.join(re.escape(word) for word in NOISE_LEADING_PREFIX_WORDS)})(?:\s*[）)】\]])?\s*(?:[\s.、:：/\\|_-])*(?=(?:\d|第|EP\b|P\b|Part\b|Lesson\b|Lecture\b|$))",
    re.IGNORECASE,
)


def get_admin_stats(db: Session) -> dict:
    nas_videos = db.query(func.count(NasVideo.id)).scalar() or 0
    published_nas_videos = db.query(func.count(NasVideo.id)).filter(
        NasVideo.published_video_id.isnot(None)
    ).scalar() or 0

    return {
        "users": db.query(func.count(User.id)).scalar() or 0,
        "videos": db.query(func.count(Video.id)).scalar() or 0,
        "concepts": db.query(func.count(Concept.id)).scalar() or 0,
        "references": db.query(func.count(Reference.id)).scalar() or 0,
        "nas_videos": nas_videos,
        "published_nas_videos": published_nas_videos,
    }


def get_nas_videos(
    db: Session,
    skip: int = 0,
    limit: int = 100,
    search: Optional[str] = None,
    course_name: Optional[str] = None,
    published: Optional[bool] = None,
    category_id: Optional[int] = None,
):
    query = db.query(NasVideo)

    if search:
        query = query.filter(
            or_(
                NasVideo.file_name.ilike(f"%{search}%"),
                NasVideo.relative_path.ilike(f"%{search}%"),
                NasVideo.title.ilike(f"%{search}%"),
                NasVideo.course_name.ilike(f"%{search}%"),
                NasVideo.course_title.ilike(f"%{search}%"),
                NasVideo.lesson_title.ilike(f"%{search}%"),
                NasVideo.instructor.ilike(f"%{search}%"),
                NasVideo.tags.ilike(f"%{search}%"),
            )
        )

    if course_name:
        query = query.filter(NasVideo.course_name == course_name)

    if category_id:
        category = db.query(NasVideoCategory).filter(NasVideoCategory.id == category_id).first()
        if category:
            category_ids = [
                row[0]
                for row in db.query(NasVideoCategory.id)
                .filter(
                    or_(
                        NasVideoCategory.id == category.id,
                        NasVideoCategory.path.like(f"{category.path}/%"),
                    )
                )
                .all()
            ]
            query = query.filter(NasVideo.category_id.in_(category_ids))
        else:
            query = query.filter(NasVideo.category_id == -1)

    if published is True:
        query = query.filter(NasVideo.published_video_id.isnot(None))
    elif published is False:
        query = query.filter(NasVideo.published_video_id.is_(None))

    items = query.all()
    items.sort(key=_nas_video_sort_key)
    total = len(items)
    return items[skip:skip + limit], total


def get_nas_video(db: Session, video_id: int) -> Optional[NasVideo]:
    return db.query(NasVideo).filter(NasVideo.id == video_id).first()


def _natural_sort_key(value: str):
    text = str(value or "")

    # Convert chapter/lesson headings such as "第十章" before splitting on
    # Arabic digits. This keeps 第一章、第二章、...、第十章 in reading order.
    def replace_chinese_heading(match):
        number = _chinese_numeral_to_int(match.group(1))
        return f"第{number:010d}" if number is not None else match.group(0)

    text = re.sub(
        rf"第\s*([{CHINESE_NUMERAL_CHARS}]+)\s*(?=[章节集讲课篇])",
        replace_chinese_heading,
        text,
    )
    chunks = re.split(r"(\d+)", text.casefold())
    key = []
    for chunk in chunks:
        if not chunk:
            continue
        if chunk.isdigit():
            key.append((0, int(chunk)))
        else:
            key.append((1, chunk))
    return key


def _category_path_sort_key(path: str):
    return [_natural_sort_key(part) for part in str(path or "未分类").split("/")]


def _safe_video_category_name(value: str) -> str:
    clean_value = _normalize_category_path(str(value or "NAS课程").split("/"))
    if len(clean_value) <= 50:
        return clean_value
    leaf = clean_value.split("/")[-1] or "NAS课程"
    digest = hashlib.sha1(clean_value.encode("utf-8")).hexdigest()[:8]
    max_leaf_len = max(1, 50 - len(digest) - 4)
    return f"{leaf[:max_leaf_len]}...{digest}"


def _nas_video_sort_key(video: NasVideo):
    category_path = video.category_path or "未分类"
    episode_number = _safe_db_integer(video.episode_number, 0) or 0
    sort_order = _safe_db_integer(video.sort_order, 0) or 0
    if not video.is_manual:
        file_episode, file_sort_order = _file_order_hint(video.file_name or video.relative_path)
        if file_episode:
            episode_number = file_episode
        if file_sort_order:
            sort_order = file_sort_order
    return (
        _category_path_sort_key(category_path),
        sort_order,
        episode_number,
        _natural_sort_key(video.course_name or ""),
        _natural_sort_key(video.lesson_title or video.title or video.file_name),
        _natural_sort_key(video.relative_path),
    )


def _space_normalize(value: str) -> str:
    text = str(value or "")
    text = text.replace("_", " ").replace("-", " ")
    text = re.sub(r"\s+", " ", text)
    return text.strip()


def _strip_leading_noise_prefixes(value: str) -> str:
    text = str(value or "").strip()
    for _ in range(5):
        new_text = NOISE_LEADING_PREFIX_RE.sub("", text).strip()
        if new_text == text:
            break
        text = new_text
    return text


def _has_leading_noise_prefix(value: str) -> bool:
    text = _space_normalize(Path(value or "").stem)
    return bool(NOISE_LEADING_PREFIX_RE.search(text))


def _strip_noise_tokens(value: str) -> str:
    text = _space_normalize(Path(value or "").stem)
    for word in NOISE_TITLE_WORDS:
        text = re.sub(rf"【[^】]*{re.escape(word)}[^】]*】", " ", text, flags=re.IGNORECASE)
        text = re.sub(rf"\[[^\]]*{re.escape(word)}[^\]]*\]", " ", text, flags=re.IGNORECASE)
    text = re.sub(r"(?i)\b(?:1080p?|720p?|4k|x264|h264|h265|hevc|aac)\b", " ", text)
    text = _strip_leading_noise_prefixes(text)
    return _space_normalize(text).strip(" .、_-")


def _clean_metadata_title(value: str) -> str:
    text = _strip_noise_tokens(value)
    outline_match = re.search(r"(?<![\d.])\d+(?:\.\d+){1,5}(?![\d.])", text)
    if outline_match:
        tail = text[outline_match.end():].strip(" .、:：_-")
        head = text[:outline_match.start()].strip(" .、:：_-")
        text = tail or head or text
    text = re.sub(r"^\s*\d+(?:\.\d+){0,5}[\s\.、:：_-]*", "", text)
    text = re.sub(r"(?i)^\s*(?:EP|P|Part|Lesson|Lecture)\s*0*\d{1,4}[\s\.、:：_-]*", "", text)
    text = re.sub(r"^\s*(?:第\s*)?\d{1,4}\s*[集讲课节][\s\.、:：_-]*", "", text)
    text = re.sub(
        rf"^\s*第\s*[{CHINESE_NUMERAL_CHARS}]+\s*[章节集讲课篇][\s\.、:：_-]*",
        "",
        text,
    )
    text = re.sub(r"^\s*(?:课时|课程|视频)\s*\d{0,4}[\s\.、:：_-]*", "", text)
    return _space_normalize(text).strip(" .、_-") or _space_normalize(Path(value or "").stem)


def _metadata_text_needs_cleaning(current: Optional[str], cleaned: Optional[str]) -> bool:
    if not cleaned:
        return False
    cleaned_norm = _space_normalize(cleaned).strip(" .、_-")
    current_norm = _space_normalize(current).strip(" .、_-") if current else ""
    if not current_norm:
        return True
    if current_norm == cleaned_norm:
        return False
    if _has_leading_noise_prefix(current_norm):
        return True
    return _space_normalize(_clean_metadata_title(current_norm)).strip(" .、_-") == cleaned_norm


def _file_order_hint(value: str) -> tuple[Optional[int], Optional[int]]:
    parsed = _parse_outline_name(value)
    if parsed:
        episode = _safe_db_integer(str(parsed["outline_code"]).split(".")[-1])
        sort_order = _safe_db_integer(parsed.get("outline_sort_order"), episode)
        return episode, sort_order
    episode = _safe_db_integer(extract_episode_number(value))
    return episode, episode


def _chinese_numeral_to_int(value: str) -> Optional[int]:
    """Parse common Chinese integers used by chapter and lesson headings."""
    text = str(value or "").strip()
    if not text or any(char not in CHINESE_NUMERAL_DIGITS and char not in CHINESE_NUMERAL_UNITS for char in text):
        return None
    if all(char in CHINESE_NUMERAL_DIGITS for char in text):
        return _safe_db_integer(
            "".join(str(CHINESE_NUMERAL_DIGITS[char]) for char in text)
        )

    total = 0
    section = 0
    number = 0
    for char in text:
        if char in CHINESE_NUMERAL_DIGITS:
            number = CHINESE_NUMERAL_DIGITS[char]
            continue

        unit = CHINESE_NUMERAL_UNITS[char]
        if unit >= 10_000:
            section = (section + number) * unit
            total += section
            section = 0
            number = 0
        else:
            if number == 0:
                number = 1
            section += number * unit
            number = 0

    return _safe_db_integer(total + section + number)


def _outline_sort_order(parts: list[str]) -> int:
    sort_order = 0
    # Keep outline order inside PostgreSQL INTEGER. Four base-100 chunks are
    # enough for course-like outlines such as 1.2.3.4 and stay below 100M.
    for part in parts[:4]:
        try:
            chunk = max(0, min(int(part), 99))
        except (TypeError, ValueError):
            chunk = 0
        sort_order = sort_order * 100 + chunk
    return sort_order


def _safe_db_integer(value, default=None):
    if value in (None, ""):
        return default
    if isinstance(value, str) and re.fullmatch(r"\d+(?:\.\d+)+", value.strip()):
        value = value.strip().split(".")[-1]
    try:
        number = int(value)
    except (TypeError, ValueError):
        return default
    return max(0, min(number, MAX_DB_INTEGER))


def _default_outline_title(code: str) -> str:
    return f"第{code}章" if "." not in code else f"第{code}节"


def _record_scan_error(errors: Optional[list], path, exc: Exception) -> None:
    if errors is None or len(errors) >= 50:
        return
    errors.append({
        "path": str(path or ""),
        "error": str(exc),
    })


def _iter_video_paths(base_path: Path, errors: Optional[list] = None):
    def onerror(exc):
        _record_scan_error(errors, getattr(exc, "filename", base_path), exc)

    for root, _dirs, files in os.walk(base_path, onerror=onerror, followlinks=False):
        root_path = Path(root)
        for file_name in files:
            path = root_path / file_name
            try:
                if path.suffix.lower() in VIDEO_EXTENSIONS and path.is_file():
                    yield path
            except OSError as exc:
                _record_scan_error(errors, path, exc)


def _looks_like_episode_folder(folder_name: str, video_stem: str) -> bool:
    clean_folder = folder_name.replace("_", " ").replace("-", " ").strip().lower()
    clean_stem = video_stem.replace("_", " ").replace("-", " ").strip().lower()
    if extract_episode_number(clean_folder):
        return True
    keywords = ["episode", "lesson", "lecture", "part", "第", "集", "讲", "课", "节"]
    if any(keyword in clean_folder for keyword in keywords):
        return True
    return bool(clean_folder and (clean_folder in clean_stem or clean_stem in clean_folder))


def _parse_outline_name(value: str) -> dict:
    normalized = _strip_noise_tokens(value)
    match = None
    for candidate in re.finditer(r"(?<![\d.])(\d+(?:\.\d+){1,5})(?![\d.])", normalized):
        match = candidate
        break
    if match:
        code = match.group(1)
        title = normalized[match.end():].strip(" .、:：_-")
        if not title:
            title = normalized[:match.start()].strip(" .、:：_-")
    else:
        match = re.match(r"^\s*(\d{1,4})(?!\.\d)(?:[\s\.、:：_-]+|$)(.*)$", normalized)
        if not match:
            return {}
        code = match.group(1)
        title = match.group(2).strip(" .、:：_-")

    if re.fullmatch(r"(?:720|1080|2160|4)", code):
        return {}

    title = _clean_metadata_title(title) if title else None
    parts = code.split(".")
    return {
        "outline_code": code,
        "outline_parts": [".".join(parts[:index]) for index in range(1, len(parts) + 1)],
        "outline_depth": len(parts),
        "outline_leaf_title": title,
        "outline_sort_order": _outline_sort_order(parts),
    }


def _course_root_for_path(base_path: Path, path: Path) -> Path:
    try:
        relative_parts = path.relative_to(base_path).parts
    except ValueError:
        return base_path
    if len(relative_parts) <= 1:
        return base_path
    return base_path / relative_parts[0]


def _outline_item_for_path(root: Path, item: Path) -> Optional[dict]:
    name = item.stem if item.is_file() else item.name
    parsed = _parse_outline_name(name)
    if not parsed:
        return None
    try:
        relative_path = item.relative_to(root).as_posix()
        parent_path = item.parent.relative_to(root).as_posix()
    except ValueError:
        relative_path = item.name
        parent_path = ""
    return {
        "file_name": item.name,
        "relative_path": relative_path,
        "parent_path": "" if parent_path == "." else parent_path,
        "kind": "video" if item.is_file() else "folder",
        "outline_code": parsed.get("outline_code"),
        "title": parsed.get("outline_leaf_title"),
        "clean_title": parsed.get("outline_leaf_title") or _clean_metadata_title(name),
        "depth": parsed.get("outline_depth"),
    }


def _collect_outline_items(root: Path, errors: Optional[list] = None) -> list[dict]:
    if not root.exists():
        return []
    outline_items = []
    def onerror(exc):
        _record_scan_error(errors, getattr(exc, "filename", root), exc)

    for current_root, dirs, files in os.walk(root, onerror=onerror, followlinks=False):
        current_path = Path(current_root)
        for dir_name in dirs:
            item = current_path / dir_name
            try:
                outline_item = _outline_item_for_path(root, item)
            except OSError as exc:
                _record_scan_error(errors, item, exc)
                outline_item = None
            if outline_item:
                outline_items.append(outline_item)
        for file_name in files:
            item = current_path / file_name
            try:
                if item.suffix.lower() not in VIDEO_EXTENSIONS or not item.is_file():
                    continue
                outline_item = _outline_item_for_path(root, item)
            except OSError as exc:
                _record_scan_error(errors, item, exc)
                outline_item = None
            if outline_item:
                outline_items.append(outline_item)
    outline_items.sort(key=lambda item: _outline_sort_order(str(item["outline_code"]).split(".")))
    return outline_items


def build_nas_video_outline_catalog(base_path: Path, errors: Optional[list] = None) -> dict[str, list[dict]]:
    if not base_path.exists():
        return {}
    roots = set()
    for path in _iter_video_paths(base_path, errors):
        roots.add(_course_root_for_path(base_path, path).resolve())
    return {root.as_posix(): _collect_outline_items(root, errors) for root in roots}


def _outline_title_for_code(code: str, outline_items: list[dict]) -> Optional[str]:
    for item in outline_items:
        if item.get("outline_code") == code and item.get("title"):
            return item["title"]
    return None


def _outline_context_for_code(code: str, outline_items: list[dict]) -> dict:
    code_parts = code.split(".")
    child_prefix = f"{code}."
    descendants = [
        item for item in outline_items
        if item.get("outline_code") == code or str(item.get("outline_code", "")).startswith(child_prefix)
    ]
    direct_child_codes = []
    direct_child_titles = []
    sample_titles = []
    sample_files = []
    for item in descendants:
        item_code = str(item.get("outline_code") or "")
        if item_code.startswith(child_prefix):
            child_parts = item_code.split(".")
            if len(child_parts) > len(code_parts):
                direct_child_code = ".".join(child_parts[:len(code_parts) + 1])
                direct_child_codes.append(direct_child_code)
                clean_title = item.get("title") or item.get("clean_title")
                if clean_title:
                    child_label = f"{direct_child_code} {clean_title}"
                    if child_label not in direct_child_titles:
                        direct_child_titles.append(child_label)
        clean_title = item.get("title") or item.get("clean_title")
        if clean_title and clean_title not in sample_titles:
            sample_titles.append(clean_title)
        if item.get("file_name") and item["file_name"] not in sample_files:
            sample_files.append(item["file_name"])
    return {
        "outline_code": code,
        "depth": len(code_parts),
        "known_title": _outline_title_for_code(code, outline_items),
        "fallback_title": _default_outline_title(code),
        "direct_child_codes": sorted(set(direct_child_codes), key=lambda value: _outline_sort_order(value.split(".")))[:20],
        "direct_child_titles": direct_child_titles[:20],
        "sample_titles": sample_titles[:12],
        "sample_files": sample_files[:12],
        "naming_hint": "如果known_title为空，请根据sample_titles和direct_child_titles概括这一层的中文章节名。",
    }


def _outline_summary_for_path(
    base_path: Path,
    path: Path,
    outline_catalog: Optional[dict[str, list[dict]]] = None,
    current_outline: Optional[dict] = None,
) -> dict:
    course_root = _course_root_for_path(base_path, path).resolve()
    outline_items = (outline_catalog or {}).get(course_root.as_posix())
    if outline_items is None:
        outline_items = _collect_outline_items(course_root)
    current = current_outline or _parse_outline_name(path.stem)
    current_code = current.get("outline_code")
    current_parent_code = ".".join(current_code.split(".")[:-1]) if current_code and "." in current_code else None
    siblings = []
    for item in outline_items:
        code = str(item.get("outline_code") or "")
        parent_code = ".".join(code.split(".")[:-1]) if "." in code else None
        if current_parent_code == parent_code:
            siblings.append(item)
    ancestor_codes = (current.get("outline_parts") or [])[:-1]
    ancestor_context = [_outline_context_for_code(code, outline_items) for code in ancestor_codes]
    return {
        "course_root": course_root.name if course_root != base_path else None,
        "outline_siblings": siblings[:80],
        "outline_codes": [item["outline_code"] for item in outline_items[:120]],
        "outline_ancestor_context": ancestor_context,
    }


def build_nas_video_file_context(
    base_path: Path,
    path: Path,
    outline_catalog: Optional[dict[str, list[dict]]] = None,
) -> dict:
    relative_parts = list(path.relative_to(base_path).parts)
    folder_parts = relative_parts[:-1]
    parent = path.parent
    try:
        sibling_files = [item for item in parent.iterdir() if item.is_file()] if parent.exists() else []
    except OSError:
        sibling_files = []
    sibling_video_files = [item.name for item in sibling_files if item.suffix.lower() in VIDEO_EXTENSIONS]
    sidecar_files = [
        item.name
        for item in sibling_files
        if item.suffix.lower() in SIDECAR_EXTENSIONS or item.stem == path.stem and item.name != path.name
    ]
    standalone_folder = (
        len(sibling_video_files) == 1
        and parent != base_path
        and (bool(sidecar_files) or _looks_like_episode_folder(parent.name, path.stem))
    )
    cleaned_folder_parts = [_strip_noise_tokens(part) for part in folder_parts]
    suggested_parts = cleaned_folder_parts[:-1] if standalone_folder and len(cleaned_folder_parts) > 1 else cleaned_folder_parts
    lesson_folder_name = folder_parts[-1] if standalone_folder and folder_parts else None
    outline = _parse_outline_name(path.stem)
    outline_from = "file_name" if outline else None
    if not outline and lesson_folder_name:
        outline = _parse_outline_name(lesson_folder_name)
        outline_from = "lesson_folder" if outline else None
    outline_summary = _outline_summary_for_path(base_path, path, outline_catalog, outline)
    outline_category_parts = []
    if outline:
        outline_category_parts.extend(suggested_parts)
        outline_parts = outline.get("outline_parts") or []
        existing_outline_codes = {
            parsed["outline_code"]
            for part in suggested_parts
            if (parsed := _parse_outline_name(part))
        }
        deepest_existing = None
        if existing_outline_codes:
            deepest_existing = max(existing_outline_codes, key=lambda code: len(code.split(".")))
        context_by_code = {
            item["outline_code"]: item
            for item in outline_summary.get("outline_ancestor_context", [])
            if item.get("outline_code")
        }
        for code in outline_parts[:-1]:
            if code in existing_outline_codes:
                continue
            if deepest_existing and not code.startswith(f"{deepest_existing}."):
                continue
            context = context_by_code.get(code) or {}
            title = context.get("known_title") or context.get("fallback_title") or _default_outline_title(code)
            outline_category_parts.append(f"{code} {title}".strip())
    if outline_category_parts:
        suggested_parts = outline_category_parts
    suggested_category_path = _normalize_category_path(suggested_parts)
    clean_file_title = _clean_metadata_title(path.stem)
    clean_lesson_title = (
        outline.get("outline_leaf_title")
        or _clean_metadata_title(lesson_folder_name or "")
        if lesson_folder_name
        else outline.get("outline_leaf_title") or clean_file_title
    )
    course_name = outline_summary.get("course_root") or (suggested_parts[0] if suggested_parts else None)

    return {
        "folder_parts": folder_parts,
        "parent_folder": folder_parts[-1] if folder_parts else None,
        "ancestor_folders": folder_parts[:-1],
        "sibling_video_count": len(sibling_video_files),
        "sibling_video_files": sibling_video_files[:20],
        "sidecar_files": sidecar_files[:30],
        "has_subtitle_or_danmaku": bool(sidecar_files),
        "standalone_video_folder": standalone_folder,
        "lesson_folder_name": lesson_folder_name,
        "clean_file_title": clean_file_title,
        "clean_lesson_title": clean_lesson_title,
        "suggested_category_path": suggested_category_path,
        "course_name": course_name,
        "outline_from": outline_from,
        **outline,
        **outline_summary,
    }


def get_nas_video_sidecars(nas_video: NasVideo) -> list[dict]:
    base_path = Path(settings.NAS_VIDEO_MOUNT_PATH).resolve()
    video_path = (base_path / nas_video.relative_path).resolve()
    if base_path != video_path and base_path not in video_path.parents:
        return []
    if not video_path.exists() or not video_path.is_file():
        return []

    parent = video_path.parent
    try:
        sibling_files = [item for item in parent.iterdir() if item.is_file()]
    except OSError:
        return []

    sibling_video_count = sum(
        1 for item in sibling_files if item.suffix.lower() in VIDEO_EXTENSIONS
    )
    matched = []
    for item in sibling_files:
        extension = item.suffix.lower()
        if extension not in SUBTITLE_EXTENSIONS and extension not in DANMAKU_EXTENSIONS:
            continue
        kind = _classify_sidecar_kind(item)
        clean_stem = _strip_sidecar_role_prefix(item.stem)[1]
        same_stem = _sidecar_stem_matches_video(clean_stem, video_path.stem)
        single_video_folder = sibling_video_count == 1
        if not same_stem and not single_video_folder:
            continue
        matched.append((kind, item))

    def sort_key(entry):
        kind, item = entry
        priority = 0 if kind == "subtitle" else 1
        clean_stem = _strip_sidecar_role_prefix(item.stem)[1]
        same_stem = 0 if _normalize_sidecar_match_key(clean_stem) == _normalize_sidecar_match_key(video_path.stem) else 1
        return (priority, same_stem, _natural_sort_key(item.name))

    sidecars = []
    for index, (kind, item) in enumerate(sorted(matched, key=sort_key)):
        sidecars.append(
            {
                "id": index,
                "file_name": item.name,
                "extension": item.suffix.lower(),
                "kind": kind,
                "title": _clean_metadata_title(item.stem) or item.name,
                "relative_path": item.relative_to(base_path).as_posix(),
            }
        )
    return sidecars


def _strip_sidecar_role_prefix(value: str) -> tuple[Optional[str], str]:
    stem = str(value or "").strip()
    match = SIDECAR_ROLE_PREFIX_RE.match(stem)
    if not match:
        return None, stem

    prefix = match.group("prefix").casefold()
    if prefix in {item.casefold() for item in DANMAKU_PREFIXES}:
        kind = "danmaku"
    elif prefix in {item.casefold() for item in SUBTITLE_PREFIXES}:
        kind = "subtitle"
    else:
        kind = None
    return kind, stem[match.end():].strip(" .、:：/\\|_-")


def _normalize_sidecar_match_key(value: str) -> str:
    text = _space_normalize(_clean_metadata_title(value) or value)
    text = re.sub(r"(?i)\b(?:zh|chs|cht|cn|sc|tc|gb|big5|utf8|utf-8)\b", "", text)
    return re.sub(r"[\s.、:：/\\|_\-()\[\]【】（）]+", "", text.casefold())


def _sidecar_stem_matches_video(sidecar_stem: str, video_stem: str) -> bool:
    sidecar_keys = {
        _normalize_sidecar_match_key(sidecar_stem),
        _normalize_sidecar_match_key(Path(sidecar_stem).stem),
    }
    video_keys = {
        _normalize_sidecar_match_key(video_stem),
        _normalize_sidecar_match_key(_strip_noise_tokens(video_stem)),
    }
    sidecar_keys = {key for key in sidecar_keys if len(key) >= 2}
    video_keys = {key for key in video_keys if len(key) >= 2}
    for sidecar_key in sidecar_keys:
        for video_key in video_keys:
            if sidecar_key == video_key:
                return True
            if sidecar_key.startswith(video_key) or video_key.startswith(sidecar_key):
                return True
    return False


def _classify_sidecar_kind(path: Path) -> str:
    explicit_kind, _clean_stem = _strip_sidecar_role_prefix(path.stem)
    if explicit_kind:
        return explicit_kind

    extension = path.suffix.lower()
    if extension in DANMAKU_EXTENSIONS:
        return "danmaku"
    if extension in {".ass", ".ssa"} and _ass_sidecar_looks_like_danmaku(path):
        return "danmaku"
    return "subtitle"


def _ass_sidecar_looks_like_danmaku(path: Path) -> bool:
    try:
        sample = path.read_text(encoding="utf-8", errors="ignore")[:100_000]
    except OSError:
        return False
    if not sample:
        return False
    lower_sample = sample.casefold()
    if "danmaku" in lower_sample or "弹幕" in sample:
        return True
    dialogue_lines = [line for line in sample.splitlines() if line.startswith("Dialogue:")]
    if not dialogue_lines:
        return False
    moving_lines = sum(1 for line in dialogue_lines[:80] if "\\move(" in line or "\\pos(" in line)
    return moving_lines >= 5 and moving_lines / max(1, min(len(dialogue_lines), 80)) >= 0.25


def scan_nas_video_sidecars(db: Session) -> dict:
    videos = db.query(NasVideo).all()
    videos.sort(key=_nas_video_sort_key)

    matched_videos = 0
    subtitle_files = 0
    danmaku_files = 0
    data = []
    for nas_video in videos:
        sidecars = get_nas_video_sidecars(nas_video)
        if not sidecars:
            continue

        subtitle_count = sum(1 for item in sidecars if item["kind"] == "subtitle")
        danmaku_count = sum(1 for item in sidecars if item["kind"] == "danmaku")
        matched_videos += 1
        subtitle_files += subtitle_count
        danmaku_files += danmaku_count
        data.append(
            {
                "video_id": nas_video.id,
                "relative_path": nas_video.relative_path,
                "file_name": nas_video.file_name,
                "subtitle_count": subtitle_count,
                "danmaku_count": danmaku_count,
                "sidecar_count": len(sidecars),
                "sidecars": sidecars,
            }
        )

    return {
        "total": len(videos),
        "matched_videos": matched_videos,
        "subtitle_files": subtitle_files,
        "danmaku_files": danmaku_files,
        "sidecar_files": subtitle_files + danmaku_files,
        "data": data,
    }


def update_nas_video(
    db: Session,
    video_id: int,
    video_update: NasVideoUpdate,
) -> Optional[NasVideo]:
    nas_video = get_nas_video(db, video_id)
    if not nas_video:
        return None

    update_data = video_update.model_dump(exclude_unset=True)
    # A deliberate episode/sort edit is an administrator override. Scanning
    # and AI organization must not silently replace that manual ordering.
    if {"episode_number", "sort_order"}.intersection(update_data):
        update_data["is_manual"] = True
    for field, value in update_data.items():
        setattr(nas_video, field, value)

    db.commit()
    db.refresh(nas_video)
    if nas_video.published_video_id:
        published_video = db.query(Video).filter(Video.id == nas_video.published_video_id).first()
        publish_nas_video(
            db,
            nas_video.id,
            is_published=published_video.is_published if published_video else True,
        )
        db.refresh(nas_video)
    return nas_video


def reorder_nas_videos(db: Session, video_ids: list[int]) -> list[NasVideo]:
    """Persist the administrator's drag order for the supplied video list."""
    cleaned_ids = [int(video_id) for video_id in video_ids if int(video_id) > 0]
    if not cleaned_ids:
        raise ValueError("至少需要保留一个视频")
    if len(cleaned_ids) != len(set(cleaned_ids)):
        raise ValueError("排序列表包含重复视频")

    videos = {
        video.id: video
        for video in db.query(NasVideo).filter(NasVideo.id.in_(cleaned_ids)).all()
    }
    missing_ids = [video_id for video_id in cleaned_ids if video_id not in videos]
    if missing_ids:
        raise ValueError("排序列表中包含不存在的视频")

    try:
        for index, video_id in enumerate(cleaned_ids, start=1):
            video = videos[video_id]
            # Gaps leave room for an individual numeric adjustment later.
            video.sort_order = index * 10
            video.is_manual = True
        db.commit()
    except Exception:
        db.rollback()
        raise
    return [videos[video_id] for video_id in cleaned_ids]


def generate_nas_video_thumbnail(
    db: Session,
    video_id: int,
    source_path: Path,
    timestamp_seconds: float | int | None = 5.0,
    overwrite: bool = True,
) -> Optional[NasVideo]:
    nas_video = get_nas_video(db, video_id)
    if not nas_video:
        return None
    if nas_video.thumbnail_url and not overwrite:
        return nas_video

    thumbnail_url = generate_video_thumbnail(
        source_path,
        video_id=nas_video.id,
        relative_path=nas_video.relative_path,
        timestamp_seconds=timestamp_seconds,
    )
    nas_video.thumbnail_url = thumbnail_url
    if nas_video.published_video_id:
        published_video = db.query(Video).filter(Video.id == nas_video.published_video_id).first()
        if published_video:
            published_video.thumbnail_url = thumbnail_url
    db.commit()
    db.refresh(nas_video)
    return nas_video


def delete_nas_video_record(db: Session, video_id: int) -> Optional[dict]:
    nas_video = get_nas_video(db, video_id)
    if not nas_video:
        return None

    published_video_id = nas_video.published_video_id
    from app.crud.study import ensure_videos_unused
    ensure_videos_unused(db, [published_video_id] if published_video_id else [])
    relative_path = nas_video.relative_path
    file_name = nas_video.file_name

    try:
        deleted_published_video = False
        if published_video_id:
            db.query(Note).filter(Note.video_id == published_video_id).update({"video_id": None}, synchronize_session=False)
            db.query(LearningProgress).filter(LearningProgress.video_id == published_video_id).update({"video_id": None}, synchronize_session=False)
            db.execute(user_favorites.delete().where(user_favorites.c.video_id == published_video_id))
            db.execute(video_tags.delete().where(video_tags.c.video_id == published_video_id))

        db.delete(nas_video)
        db.flush()

        if published_video_id:
            video = db.query(Video).filter(Video.id == published_video_id).first()
            if video:
                db.delete(video)
                deleted_published_video = True

        db.commit()
        return {
            "deleted": True,
            "deleted_local_file": False,
            "deleted_published_video": deleted_published_video,
            "relative_path": relative_path,
            "file_name": file_name,
        }
    except Exception:
        db.rollback()
        raise


def delete_all_nas_video_records(db: Session) -> dict:
    published_video_ids = list(dict.fromkeys(
        video_id
        for (video_id,) in db.query(NasVideo.published_video_id)
        .filter(NasVideo.published_video_id.isnot(None))
        .all()
        if video_id
    ))
    nas_count = db.query(func.count(NasVideo.id)).scalar() or 0
    deleted_published_count = 0
    from app.crud.study import ensure_videos_unused
    ensure_videos_unused(db, published_video_ids)

    try:
        if published_video_ids:
            db.query(Note).filter(Note.video_id.in_(published_video_ids)).update({"video_id": None}, synchronize_session=False)
            db.query(LearningProgress).filter(LearningProgress.video_id.in_(published_video_ids)).update({"video_id": None}, synchronize_session=False)
            db.execute(user_favorites.delete().where(user_favorites.c.video_id.in_(published_video_ids)))
            db.execute(video_tags.delete().where(video_tags.c.video_id.in_(published_video_ids)))

        db.query(NasVideo).delete(synchronize_session=False)
        db.flush()

        if published_video_ids:
            deleted_published_count = (
                db.query(Video)
                .filter(Video.id.in_(published_video_ids))
                .delete(synchronize_session=False)
            )

        db.commit()
        return {
            "deleted": nas_count,
            "deleted_local_file": False,
            "deleted_published_videos": deleted_published_count,
        }
    except Exception:
        db.rollback()
        raise


def _normalize_category_path(parts) -> str:
    clean_parts = [str(part).strip() for part in parts if str(part).strip()]
    return "/".join(clean_parts) if clean_parts else "未分类"


def _category_path_from_parent(db: Session, parent_id: Optional[int], name: str) -> str:
    clean_name = name.strip()
    if parent_id:
        parent = db.query(NasVideoCategory).filter(NasVideoCategory.id == parent_id).first()
        if parent:
            return _normalize_category_path([parent.path, clean_name])
    return _normalize_category_path([clean_name])


def get_or_create_nas_video_category_by_path(db: Session, path: str) -> NasVideoCategory:
    normalized = _normalize_category_path(path.split("/"))
    category = db.query(NasVideoCategory).filter(NasVideoCategory.path == normalized).first()
    if category:
        return category

    parent = None
    current_parts = []
    for part in normalized.split("/"):
        current_parts.append(part)
        current_path = _normalize_category_path(current_parts)
        category = db.query(NasVideoCategory).filter(NasVideoCategory.path == current_path).first()
        if not category:
            category = NasVideoCategory(
                name=part,
                parent_id=parent.id if parent else None,
                path=current_path,
            )
            db.add(category)
            db.flush()
        parent = category
    return parent


def get_nas_video_categories(db: Session):
    categories = db.query(NasVideoCategory).all()
    for category in categories:
        category.video_count = db.query(func.count(NasVideo.id)).filter(NasVideo.category_id == category.id).scalar() or 0
        category.children_count = db.query(func.count(NasVideoCategory.id)).filter(NasVideoCategory.parent_id == category.id).scalar() or 0

    by_parent = {}
    valid_ids = {category.id for category in categories}
    for category in categories:
        parent_id = category.parent_id if category.parent_id in valid_ids else None
        by_parent.setdefault(parent_id, []).append(category)

    def sort_siblings(items):
        return sorted(
            items,
            key=lambda category: (
                category.sort_order if (category.sort_order or 0) > 0 else MAX_DB_INTEGER,
                _natural_sort_key(category.name),
                category.id,
            ),
        )

    ordered = []
    visited = set()

    def append_branch(parent_id):
        for category in sort_siblings(by_parent.get(parent_id, [])):
            if category.id in visited:
                continue
            visited.add(category.id)
            ordered.append(category)
            append_branch(category.id)

    append_branch(None)
    # A corrupted parent relation must not hide categories from the admin UI.
    for category in sort_siblings(categories):
        if category.id not in visited:
            visited.add(category.id)
            ordered.append(category)
            append_branch(category.id)
    return ordered


def create_nas_video_category(db: Session, category: NasVideoCategoryCreate) -> NasVideoCategory:
    path = _category_path_from_parent(db, category.parent_id, category.name)
    existing = db.query(NasVideoCategory).filter(NasVideoCategory.path == path).first()
    if existing:
        return existing
    db_category = NasVideoCategory(
        name=category.name.strip(),
        parent_id=category.parent_id,
        path=path,
        description=category.description,
        sort_order=category.sort_order,
    )
    db.add(db_category)
    db.commit()
    db.refresh(db_category)
    return db_category


def update_nas_video_category(db: Session, category_id: int, category_update: NasVideoCategoryUpdate) -> Optional[NasVideoCategory]:
    category = db.query(NasVideoCategory).filter(NasVideoCategory.id == category_id).first()
    if not category:
        return None
    old_path = category.path
    data = category_update.model_dump(exclude_unset=True)
    new_parent_id = data.get("parent_id", category.parent_id)
    if new_parent_id == category.id:
        return None
    if new_parent_id:
        parent = db.query(NasVideoCategory).filter(NasVideoCategory.id == new_parent_id).first()
        if not parent or parent.path == old_path or parent.path.startswith(f"{old_path}/"):
            return None
    for field, value in data.items():
        setattr(category, field, value)
    if "name" in data or "parent_id" in data:
        new_path = _category_path_from_parent(db, category.parent_id, category.name)
        if new_path != old_path:
            descendants = db.query(NasVideoCategory).filter(NasVideoCategory.path.like(f"{old_path}/%")).all()
            category.path = new_path
            for child in descendants:
                child.path = f"{new_path}{child.path[len(old_path):]}"
    db.commit()
    db.refresh(category)
    return category


def delete_nas_video_category(db: Session, category_id: int) -> Optional[dict]:
    category = db.query(NasVideoCategory).filter(NasVideoCategory.id == category_id).first()
    if not category:
        return None

    target_path = category.path
    categories = (
        db.query(NasVideoCategory)
        .filter(
            or_(
                NasVideoCategory.id == category.id,
                NasVideoCategory.path.like(f"{target_path}/%"),
            )
        )
        .all()
    )
    category_ids = [item.id for item in categories]
    from app.crud.study import ensure_categories_unused
    ensure_categories_unused(db, category_ids)
    category_count = len(category_ids)
    video_count = (
        db.query(func.count(NasVideo.id))
        .filter(NasVideo.category_id.in_(category_ids))
        .scalar()
        or 0
    )

    try:
        db.query(NasVideo).filter(NasVideo.category_id.in_(category_ids)).update(
            {"category_id": None},
            synchronize_session=False,
        )
        for item in sorted(categories, key=lambda value: value.path.count("/"), reverse=True):
            db.delete(item)
        db.commit()
        return {
            "deleted": True,
            "deleted_local_files": False,
            "category_path": target_path,
            "deleted_categories": category_count,
            "unassigned_videos": video_count,
        }
    except Exception:
        db.rollback()
        raise


def delete_all_nas_video_categories(db: Session) -> dict:
    from app.crud.study import ensure_categories_unused
    ensure_categories_unused(db, [row.id for row in db.query(NasVideoCategory.id)])
    category_count = db.query(func.count(NasVideoCategory.id)).scalar() or 0
    video_count = (
        db.query(func.count(NasVideo.id))
        .filter(NasVideo.category_id.isnot(None))
        .scalar()
        or 0
    )

    try:
        db.query(NasVideo).filter(NasVideo.category_id.isnot(None)).update(
            {"category_id": None},
            synchronize_session=False,
        )
        db.query(NasVideoCategory).delete(synchronize_session=False)
        db.commit()
        return {
            "deleted": True,
            "deleted_local_files": False,
            "deleted_categories": category_count,
            "unassigned_videos": video_count,
        }
    except Exception:
        db.rollback()
        raise


def extract_episode_number(title: str) -> Optional[int]:
    clean_title = _strip_noise_tokens(title)
    patterns = [
        r"(?:第\s*)?(\d{1,4})(?:\s*[集讲课节])",
        r"(?:EP|Ep|ep|P|p)\s*0*(\d{1,4})",
    ]
    for pattern in patterns:
        match = re.search(pattern, clean_title)
        if match:
            try:
                return int(match.group(1))
            except ValueError:
                return None
    chinese_match = re.search(
        rf"第\s*([{CHINESE_NUMERAL_CHARS}]+)\s*[章节集讲课篇]",
        clean_title,
    )
    if chinese_match:
        number = _chinese_numeral_to_int(chinese_match.group(1))
        if number is not None:
            return number
    for match in re.finditer(r"(?<![\d.])0*(\d{1,4})(?![\d.])", clean_title):
        try:
            number = int(match.group(1))
        except ValueError:
            continue
        if number not in {4, 720, 1080, 2160}:
            return number
    return None


def scan_nas_videos(db: Session) -> dict:
    base_path = Path(settings.NAS_VIDEO_MOUNT_PATH).resolve()
    if not base_path.exists() or not base_path.is_dir():
        return {"scanned": 0, "created": 0, "updated": 0, "missing": 0, "video_ids": [], "created_ids": [], "updated_ids": [], "skipped": 0, "errors": []}

    scanned = 0
    created = 0
    updated = 0
    video_ids = []
    created_ids = []
    updated_ids = []
    seen_paths = set()
    scan_errors = []
    outline_catalog = build_nas_video_outline_catalog(base_path, scan_errors)

    for path in _iter_video_paths(base_path, scan_errors):
        try:
            scanned += 1
            relative_path = path.relative_to(base_path).as_posix()
            seen_paths.add(relative_path)
            stat = path.stat()
            modified_at = datetime.fromtimestamp(stat.st_mtime)
            title = _clean_metadata_title(path.stem)
            file_context = build_nas_video_file_context(base_path, path, outline_catalog)
            category = get_or_create_nas_video_category_by_path(db, file_context["suggested_category_path"])
            file_episode_number = extract_episode_number(path.stem) or extract_episode_number(title)
            episode_number = file_episode_number
            if file_context.get("outline_code"):
                episode_number = _safe_db_integer(file_context["outline_code"].split(".")[-1], episode_number)
            episode_number = _safe_db_integer(episode_number)
            sort_order = _safe_db_integer(file_context.get("outline_sort_order"), episode_number or 0)
            lesson_title = file_context.get("clean_lesson_title") or title

            nas_video = db.query(NasVideo).filter(
                NasVideo.relative_path == relative_path
            ).first()

            if nas_video is None:
                course_name = file_context.get("course_name") or (path.parent.name if path.parent != base_path else None)
                nas_video = NasVideo(
                    relative_path=relative_path,
                    file_name=path.name,
                    file_extension=path.suffix.lower(),
                    file_size=stat.st_size,
                    modified_at=modified_at,
                    title=title,
                    course_name=course_name,
                    lesson_title=lesson_title,
                    category_id=category.id,
                    episode_number=episode_number,
                    sort_order=sort_order,
                )
                db.add(nas_video)
                db.flush()
                created += 1
                created_ids.append(nas_video.id)
            else:
                changed = False
                updates = {
                    "file_name": path.name,
                    "file_extension": path.suffix.lower(),
                    "file_size": stat.st_size,
                    "modified_at": modified_at,
                }
                if not nas_video.category_id:
                    updates["category_id"] = category.id
                repair_from_file_name = (
                    not nas_video.is_manual
                    and episode_number is not None
                    and (
                        file_context.get("outline_from") == "file_name"
                        or file_episode_number is not None
                        or _has_leading_noise_prefix(nas_video.file_name)
                        or _has_leading_noise_prefix(nas_video.title or "")
                        or _has_leading_noise_prefix(nas_video.lesson_title or "")
                    )
                )
                if (
                    episode_number is not None
                    and (nas_video.episode_number in (None, 0) or (repair_from_file_name and nas_video.episode_number != episode_number))
                ):
                    updates["episode_number"] = episode_number
                if (
                    sort_order is not None
                    and (not nas_video.sort_order or (repair_from_file_name and nas_video.sort_order != sort_order))
                ):
                    updates["sort_order"] = sort_order
                if _metadata_text_needs_cleaning(nas_video.title, title):
                    updates["title"] = title
                if _metadata_text_needs_cleaning(nas_video.lesson_title, lesson_title):
                    updates["lesson_title"] = lesson_title
                for field, value in updates.items():
                    if getattr(nas_video, field) != value:
                        setattr(nas_video, field, value)
                        changed = True
                if changed:
                    updated += 1
                    updated_ids.append(nas_video.id)
            video_ids.append(nas_video.id)
            db.commit()
        except Exception as exc:
            db.rollback()
            _record_scan_error(scan_errors, path, exc)

    missing = db.query(NasVideo).filter(~NasVideo.relative_path.in_(seen_paths)).count() if seen_paths else db.query(NasVideo).count()
    db.commit()

    return {
        "scanned": scanned,
        "created": created,
        "updated": updated,
        "missing": missing,
        "video_ids": video_ids,
        "created_ids": created_ids,
        "updated_ids": updated_ids,
        "skipped": len(scan_errors),
        "errors": scan_errors,
    }


def create_manual_nas_video(db: Session, video: ManualNasVideoCreate) -> Optional[NasVideo]:
    base_path = Path(settings.NAS_VIDEO_MOUNT_PATH).resolve()
    target_path = (base_path / video.relative_path).resolve()
    if base_path != target_path and base_path not in target_path.parents:
        return None
    if not target_path.exists() or not target_path.is_file() or target_path.suffix.lower() not in VIDEO_EXTENSIONS:
        return None

    stat = target_path.stat()
    modified_at = datetime.fromtimestamp(stat.st_mtime)
    existing = db.query(NasVideo).filter(NasVideo.relative_path == video.relative_path).first()
    title = video.title or target_path.stem.replace("_", " ").replace("-", " ").strip()
    episode_number = video.episode_number if video.episode_number is not None else extract_episode_number(title)

    payload = {
        "relative_path": video.relative_path,
        "file_name": target_path.name,
        "file_extension": target_path.suffix.lower(),
        "file_size": stat.st_size,
        "modified_at": modified_at,
        "title": title,
        "course_name": video.course_name,
        "course_title": video.course_title,
        "lesson_title": video.lesson_title or title,
        "instructor": video.instructor,
        "description": video.description,
        "tags": video.tags,
        "duration_seconds": video.duration_seconds,
        "category_id": video.category_id,
        "episode_number": episode_number,
        "sort_order": video.sort_order if video.sort_order is not None else (episode_number or 0),
        "is_visible": video.is_visible,
        "is_manual": True,
    }

    if existing:
        for key, value in payload.items():
            setattr(existing, key, value)
        db.commit()
        db.refresh(existing)
        return existing

    nas_video = NasVideo(**payload)
    db.add(nas_video)
    db.commit()
    db.refresh(nas_video)
    return nas_video


def apply_nas_video_ai_suggestion(
    db: Session,
    nas_video: NasVideo,
    suggestion: dict,
    overwrite_existing: bool = True,
) -> NasVideo:
    category_path = suggestion.get("category_path")
    if category_path:
        category = get_or_create_nas_video_category_by_path(db, category_path)
        nas_video.category_id = category.id

    field_map = [
        "title",
        "course_name",
        "course_title",
        "lesson_title",
        "instructor",
        "description",
        "tags",
        "episode_number",
        "sort_order",
    ]
    for field in field_map:
        value = suggestion.get(field)
        if value is None:
            continue
        if nas_video.is_manual and field in {"episode_number", "sort_order"}:
            continue
        if field in {"episode_number", "sort_order"}:
            value = _safe_db_integer(value)
            if value is None:
                continue
        current_value = getattr(nas_video, field)
        if overwrite_existing or current_value in (None, "", 0):
            setattr(nas_video, field, value)

    if (
        not nas_video.is_manual
        and nas_video.episode_number
        and (overwrite_existing or not nas_video.sort_order)
    ):
        nas_video.sort_order = _safe_db_integer(suggestion.get("sort_order"), nas_video.episode_number)

    db.commit()
    db.refresh(nas_video)
    return nas_video


def ensure_uncategorized_video_category(db: Session) -> VideoCategory:
    category = db.query(VideoCategory).filter(VideoCategory.name == "NAS课程").first()
    if category:
        return category

    category = VideoCategory(
        name="NAS课程",
        description="从NAS视频目录发布的课程",
        icon="🎬",
    )
    db.add(category)
    db.commit()
    db.refresh(category)
    return category


def publish_nas_video(
    db: Session,
    video_id: int,
    category_id: Optional[int] = None,
    is_published: bool = True,
) -> Optional[Video]:
    nas_video = get_nas_video(db, video_id)
    if not nas_video:
        return None

    category = None
    if category_id:
        category = db.query(VideoCategory).filter(VideoCategory.id == category_id).first()
    if not category:
        if nas_video.category:
            category_name = _safe_video_category_name(nas_video.category.path)
            category = db.query(VideoCategory).filter(VideoCategory.name == category_name).first()
            if not category:
                category = VideoCategory(
                    name=category_name,
                    description=f"NAS分类：{nas_video.category.path}",
                    icon="🎬",
                )
                db.add(category)
                db.flush()
        else:
            category = ensure_uncategorized_video_category(db)

    video_url = f"/api/v1/admin/nas-videos/{nas_video.id}/stream"
    title = (
        nas_video.title
        or nas_video.lesson_title
        or nas_video.course_title
        or Path(nas_video.file_name).stem
    )
    description_parts = [
        f"分类：{nas_video.category.path}" if nas_video.category else None,
        f"第 {nas_video.episode_number} 集" if nas_video.episode_number else None,
        nas_video.course_name,
        nas_video.course_title,
        nas_video.description,
    ]
    description = "\n".join([part for part in description_parts if part])

    if nas_video.published_video_id:
        video = db.query(Video).filter(Video.id == nas_video.published_video_id).first()
        if not video:
            nas_video.published_video_id = None
            db.flush()
        else:
            video.title = title
            video.description = description
            video.category_id = category.id
            video.thumbnail_url = nas_video.thumbnail_url
            video.video_url = video_url
            video.duration_seconds = nas_video.duration_seconds
            video.is_published = is_published
            db.commit()
            db.refresh(video)
            return video

    video = Video(
        title=title,
        description=description,
        category_id=category.id,
        thumbnail_url=nas_video.thumbnail_url,
        video_url=video_url,
        duration_seconds=nas_video.duration_seconds,
        is_published=is_published,
    )
    db.add(video)
    db.flush()
    nas_video.published_video_id = video.id
    db.commit()
    db.refresh(video)
    return video


def publish_nas_video_category(
    db: Session,
    category_id: int,
    is_published: bool = True,
) -> Optional[dict]:
    category = db.query(NasVideoCategory).filter(NasVideoCategory.id == category_id).first()
    if not category:
        return None

    category_ids = [
        row[0]
        for row in db.query(NasVideoCategory.id)
        .filter(
            or_(
                NasVideoCategory.id == category.id,
                NasVideoCategory.path.like(f"{category.path}/%"),
            )
        )
        .all()
    ]
    videos = db.query(NasVideo).filter(NasVideo.category_id.in_(category_ids)).all()
    videos.sort(key=_nas_video_sort_key)

    published = 0
    failed_count = 0
    failed = []
    for nas_video in videos:
        try:
            video = publish_nas_video(db, nas_video.id, is_published=is_published)
            if video:
                published += 1
        except Exception as exc:
            db.rollback()
            failed_count += 1
            if len(failed) < 20:
                failed.append({
                    "id": nas_video.id,
                    "file_name": nas_video.file_name,
                    "error": str(exc),
                })

    return {
        "category_id": category.id,
        "category_path": category.path,
        "total": len(videos),
        "published": published,
        "failed": failed_count,
        "errors": failed,
    }
