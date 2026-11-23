"""Parse text/XLSX project timelines into a stable JSON-like row format.

The parser deliberately keeps the source row intact. AI is used only to
normalize titles, phases and dates; the original values remain available for
review when a spreadsheet has an unusual layout.
"""

from __future__ import annotations

import csv
import io
import re
from datetime import date, datetime, time, timedelta
from typing import Any
from zoneinfo import ZoneInfo


HEADER_ALIASES = {
    "title": {"title", "name", "task", "activity", "milestone_name", "事项", "任务", "活动", "里程碑名称", "里程碑任务", "活动名称", "任务名称", "工作内容", "工作事项", "任务描述"},
    "description": {"description", "detail", "备注", "说明", "描述", "工作说明"},
    "phase": {"phase", "stage", "阶段", "流程阶段", "项目阶段", "里程碑", "里程碑分类", "工作包"},
    "start_at": {"start", "startdate", "start_date", "开始", "开始日期", "开始时间", "计划开始", "计划开始日期"},
    "due_at": {"end", "enddate", "end_date", "due", "duedate", "截止", "截止日期", "截止时间", "计划完成", "计划结束时间", "完成日期", "结束"},
    "status": {"status", "state", "状态", "进度", "当前进度"},
    "external_id": {"id", "no", "编号", "序号", "任务编号", "活动编号"},
}


def _header_key(value: Any) -> str:
    return re.sub(r"[\s_\-/:：]+", "", str(value or "").strip().lower())


def _clean(value: Any, limit: int = 1000) -> str | None:
    if value is None:
        return None
    text = str(value).strip()
    return text[:limit] or None


def _excel_serial_to_datetime(value: float) -> datetime | None:
    # Excel's default 1900 date system, including its historical leap-year bug.
    if value <= 0:
        return None
    return datetime(1899, 12, 30) + timedelta(days=float(value))


def parse_datetime(value: Any, *, default_year: int | None = None) -> datetime | None:
    if value is None or value == "":
        return None
    if isinstance(value, datetime):
        if value.tzinfo is not None:
            return value.astimezone(ZoneInfo("Asia/Shanghai")).replace(tzinfo=None)
        return value.replace(tzinfo=None)
    if isinstance(value, date):
        return datetime.combine(value, time())
    if isinstance(value, time):
        return datetime.combine(
            date(default_year or datetime.now().year, 1, 1),
            value.replace(tzinfo=None),
        )
    if isinstance(value, (int, float)):
        return _excel_serial_to_datetime(float(value))
    text = str(value).strip()
    if not text:
        return None
    # Handle ISO strings with timezone offsets before the locale-specific
    # formats below. Datetimes are stored as naive Asia/Shanghai values in the
    # existing project schema, so normalize an offset and then remove it.
    iso_text = text.replace("Z", "+00:00")
    try:
        parsed = datetime.fromisoformat(iso_text)
        if parsed.tzinfo is not None:
            parsed = parsed.astimezone(ZoneInfo("Asia/Shanghai")).replace(tzinfo=None)
        return parsed
    except ValueError:
        pass
    normalized = text.replace("年", "-").replace("月", "-").replace("日", "")
    normalized = normalized.replace("/", "-").replace(".", "-")
    normalized = re.sub(r"\s+", " ", normalized)
    for pattern in (
        "%Y-%m-%d %H:%M", "%Y-%m-%d %H:%M:%S", "%Y-%m-%d",
        "%m-%d %H:%M", "%m-%d", "%Y%m%d", "%Y-%m-%dT%H:%M:%S",
    ):
        try:
            parsed = datetime.strptime(normalized, pattern)
            if parsed.year == 1900:
                parsed = parsed.replace(year=default_year or datetime.now().year)
            return parsed
        except ValueError:
            continue
    # Parse a Chinese date and time even when the separator is "点半" or the
    # input contains a date followed by a time range.
    date_match = re.search(
        r"(?P<year>\d{4})\s*[年/-]\s*(?P<month>\d{1,2})\s*[月/-]\s*(?P<day>\d{1,2})\s*日?",
        text,
    )
    base_date = None
    if date_match:
        try:
            base_date = datetime(
                int(date_match.group("year")),
                int(date_match.group("month")),
                int(date_match.group("day")),
            )
        except ValueError:
            base_date = None
    time_source = text[date_match.end():] if date_match else text
    match = re.search(
        r"(凌晨|早上|上午|中午|下午|晚上|晚间)?\s*(\d{1,2})\s*(?:(?:点|:|：)\s*(\d{1,2})?)?\s*(半)?(?:分)?",
        time_source,
    )
    if match:
        period, hour_text, minute_text, half_text = match.groups()
        hour = int(hour_text)
        minute = 30 if half_text else int(minute_text or 0)
        if hour > 23 or minute > 59:
            return None
        if period in {"下午", "晚上", "晚间"} and hour < 12:
            hour += 12
        if period == "中午" and hour < 11:
            hour += 12
        base = base_date or datetime(default_year or datetime.now().year, 1, 1)
        return base.replace(hour=hour, minute=minute, second=0, microsecond=0)
    return None


def _parse_text_date_range(value: str, *, default_year: int | None = None) -> tuple[datetime | None, datetime | None]:
    """Parse one date plus optional time range without confusing 15:30 with a date."""
    text = str(value or "")

    # Parse ISO timestamps as complete tokens first. Otherwise the generic
    # clock matcher can mistake the ``08:00`` in ``+08:00`` for a second
    # timeline time and turn a single point into an incorrect next-day range.
    iso_pattern = re.compile(
        r"\b\d{4}-\d{1,2}-\d{1,2}[T\s]+"
        r"\d{1,2}:\d{2}(?::\d{2})?(?:Z|[+-]\d{2}:?\d{2})?\b"
    )
    iso_matches = list(iso_pattern.finditer(text))
    if iso_matches:
        iso_values = [
            parse_datetime(match.group(0), default_year=default_year)
            for match in iso_matches
        ]
        iso_values = [item for item in iso_values if item is not None]
        if iso_values:
            if len(iso_values) > 1:
                return iso_values[0], iso_values[1]
            return iso_values[0], iso_values[0]

    date_pattern = re.compile(
        r"\d{4}\s*[年/-]\s*\d{1,2}\s*[月/-]\s*\d{1,2}\s*日?"
        r"|\d{1,2}\s*月\s*\d{1,2}\s*日?"
        r"|\d{1,2}\s*/\s*\d{1,2}"
    )
    date_matches = list(date_pattern.finditer(text))
    parsed_dates = [parse_datetime(match.group(0), default_year=default_year) for match in date_matches]
    parsed_dates = [item for item in parsed_dates if item is not None]
    if len(parsed_dates) >= 2:
        return parsed_dates[0], parsed_dates[1]

    base = parsed_dates[0] if parsed_dates else None
    time_pattern = re.compile(
        r"(?:凌晨|早上|上午|中午|下午|晚上|晚间)?\s*"
        r"(?<![\d:])\d{1,2}\s*(?:(?:点|:|：)\s*\d{0,2})?\s*(?:半)?(?:分)?"
    )
    search_start = date_matches[0].end() if date_matches else 0
    time_matches = list(time_pattern.finditer(text[search_start:]))
    parsed_times = [parse_datetime(match.group(0), default_year=default_year) for match in time_matches]
    parsed_times = [item for item in parsed_times if item is not None]
    if base is None and parsed_times:
        base = datetime.now().replace(
            year=parsed_times[0].year,
            month=parsed_times[0].month,
            day=parsed_times[0].day,
        )
    if base is None:
        return None, None
    if parsed_times:
        start = base.replace(
            hour=parsed_times[0].hour,
            minute=parsed_times[0].minute,
            second=0,
            microsecond=0,
        )
        if len(parsed_times) == 1:
            # Preserve the existing zero-duration semantics for a single
            # timeline timestamp while keeping the end on the same day.
            return start, start
        end = base.replace(
                hour=parsed_times[1].hour,
                minute=parsed_times[1].minute,
                second=0,
                microsecond=0,
            )
        if end < start:
            end += timedelta(days=1)
        return start, end
    return base, base


def _canonical_headers(headers: list[Any]) -> list[str]:
    result = []
    used: set[str] = set()
    for index, value in enumerate(headers, start=1):
        key = _header_key(value)
        canonical = f"column_{index}"
        for candidate, aliases in HEADER_ALIASES.items():
            if key in {_header_key(alias) for alias in aliases}:
                canonical = candidate
                break
        if canonical in used:
            canonical = f"{canonical}_{index}"
        used.add(canonical)
        result.append(canonical)
    return result


def _rows_from_matrix(matrix: list[list[Any]]) -> list[dict]:
    nonempty = [row for row in matrix if any(_clean(value) for value in row)]
    if not nonempty:
        return []
    header_index = None
    headers = []
    for candidate_index, candidate_row in enumerate(nonempty[:8]):
        candidate_headers = _canonical_headers(candidate_row)
        known_count = sum(
            1 for header in candidate_headers
            if header in HEADER_ALIASES
        )
        if known_count >= 2:
            header_index = candidate_index
            headers = candidate_headers
            break
    # If no header row is recognizable, use generic columns and keep every
    # row. This handles simple two-column timelines with no header line.
    has_known_header = header_index is not None
    data_rows = nonempty[header_index + 1:] if has_known_header else nonempty
    if not has_known_header:
        headers = [f"column_{index}" for index in range(1, max(len(row) for row in nonempty) + 1)]
    has_phase_column = any(
        header == "phase" or header.startswith("phase_")
        for header in headers
    )
    rows = []
    previous_phase = None
    row_start = (header_index + 2) if has_known_header else 1
    for row_number, values in enumerate(data_rows, start=row_start):
        raw = {
            headers[index]: _clean(values[index])
            for index in range(min(len(headers), len(values)))
            if _clean(values[index]) is not None
        }
        if not raw:
            continue
        # Many clinical timelines use both "里程碑" (a broad bucket) and
        # "里程碑名称" (the actionable item). Prefer the latter when both
        # columns exist, while retaining the broad bucket as phase.
        title = (
            raw.get("title_3")
            or raw.get("title_2")
            or raw.get("title")
            or raw.get("column_3")
            or raw.get("column_1")
            or raw.get("column_2")
        )
        if not title:
            title = "；".join(str(value) for value in raw.values())[:300]
        phase = raw.get("phase")
        if not phase and not has_known_header and len(headers) >= 3:
            phase = raw.get("column_2")
        if phase:
            previous_phase = phase
        elif has_phase_column:
            # Merged milestone/stage cells are represented only on the first
            # row by openpyxl/xlrd. Fill the stage down across its child rows.
            phase = previous_phase
        rows.append({
            "row_number": row_number,
            "title": title,
            "description": raw.get("description"),
            "phase": phase,
            "start_at": parse_datetime(raw.get("start_at") or raw.get("column_4")),
            "due_at": parse_datetime(raw.get("due_at") or raw.get("column_5")),
            "status": raw.get("status") or raw.get("column_8"),
            "external_id": raw.get("external_id") or raw.get("column_1"),
            "raw": raw,
        })
    return rows


def parse_xlsx_bytes(content: bytes) -> list[dict]:
    from openpyxl import load_workbook

    workbook = load_workbook(io.BytesIO(content), read_only=True, data_only=True)
    try:
        for worksheet in workbook.worksheets:
            matrix = [list(row) for row in worksheet.iter_rows(values_only=True)]
            rows = _rows_from_matrix(matrix)
            if rows:
                return rows
    finally:
        workbook.close()
    return []


def parse_xls_bytes(content: bytes) -> list[dict]:
    """Read legacy BIFF .xls workbooks and return the same JSON-ready rows."""
    import xlrd

    workbook = xlrd.open_workbook(file_contents=content, on_demand=True)
    try:
        for worksheet in workbook.sheets():
            matrix = []
            for row_index in range(worksheet.nrows):
                values = []
                for column_index in range(worksheet.ncols):
                    cell = worksheet.cell(row_index, column_index)
                    if cell.ctype == xlrd.XL_CELL_DATE:
                        try:
                            value = xlrd.xldate_as_datetime(cell.value, workbook.datemode)
                        except (TypeError, ValueError, OverflowError):
                            value = cell.value
                    elif cell.ctype in {xlrd.XL_CELL_EMPTY, xlrd.XL_CELL_BLANK}:
                        value = None
                    else:
                        value = cell.value
                    values.append(value)
                matrix.append(values)
            rows = _rows_from_matrix(matrix)
            if rows:
                return rows
    finally:
        workbook.release_resources()
    return []


def parse_text_rows(text: str) -> list[dict]:
    lines = [line.strip() for line in text.splitlines() if line.strip()]
    if not lines:
        return []
    # Treat delimited text as a table only when its first row looks like a
    # header. This keeps ordinary prose containing commas on the simple text
    # path while allowing pasted CSV/TSV/pipe tables to retain all columns.
    for delimiter in ("\t", ",", ";", "|"):
        if not any(delimiter in line for line in lines):
            continue
        matrix = list(csv.reader(lines, delimiter=delimiter))
        if len(matrix) < 2:
            continue
        headers = _canonical_headers(matrix[0])
        known_count = sum(1 for header in headers if header in HEADER_ALIASES)
        if known_count >= 2:
            return _rows_from_matrix(matrix)
    rows = []
    for row_number, line in enumerate(lines, start=1):
        parts = [part.strip() for part in re.split(r"\s*[|｜]\s*", line) if part.strip()]
        if len(parts) == 1:
            parts = [part.strip() for part in re.split(r"\s*[,，;；]\s*", line) if part.strip()]
        title = parts[0] if parts else line
        start_at, due_at = _parse_text_date_range(line)
        rows.append({
            "row_number": row_number,
            "title": title[:300],
            "description": line[:1000],
            "phase": None,
            "start_at": start_at,
            "due_at": due_at,
            "status": None,
            "external_id": None,
            "raw": {"text": line, "parts": parts},
        })
    return rows


def rows_to_jsonable(rows: list[dict]) -> list[dict]:
    result = []
    for row in rows:
        result.append({
            key: value.isoformat() if isinstance(value, datetime) else value
            for key, value in row.items()
        })
    return result
