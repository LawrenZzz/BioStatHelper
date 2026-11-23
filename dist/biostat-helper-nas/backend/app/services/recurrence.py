"""GTD recurring-task schedule service.

A ProjectTodo carries a lightweight `recurrence` spec that expands into future
due dates. Supported specs:
  daily, weekly, biweekly, monthly, yearly          (named presets)
  Nd / Nw / Nm / Ny                                  (every N days/weeks/months/years)

The completion hooks in app.crud.project spawn the next occurrence when a
recurring task is marked done; the calendar view expands the full schedule for
a date range for display.
"""
import re
from datetime import datetime, timedelta
from typing import List, Optional, Tuple

_UNIT_ALIASES = {"d": "day", "w": "week", "m": "month", "y": "year"}
_PRESETS = {
    "daily": ("day", 1),
    "weekly": ("week", 1),
    "biweekly": ("week", 2),
    "monthly": ("month", 1),
    "yearly": ("year", 1),
}
_CUSTOM = re.compile(r"^(\d+)\s*(d|w|m|y)$", re.IGNORECASE)


def parse_recurrence(spec: Optional[str]) -> Optional[Tuple[str, int]]:
    """Return (unit, count) for a recurrence spec, or None if invalid."""
    if not spec:
        return None
    key = spec.strip().lower()
    if key in _PRESETS:
        return _PRESETS[key]
    match = _CUSTOM.match(key)
    if match:
        count = int(match.group(1))
        if count < 1:
            return None
        return (_UNIT_ALIASES[match.group(2).lower()], count)
    return None


def _add_months(value: datetime, months: int) -> datetime:
    """Advance by whole calendar months, clamping the day of month."""
    month_index = value.year * 12 + (value.month - 1) + months
    year, month0 = divmod(month_index, 12)
    month = month0 + 1
    day = min(value.day, _days_in_month(year, month))
    return value.replace(year=year, month=month, day=day)


def _days_in_month(year: int, month: int) -> int:
    if month == 12:
        next_month = datetime(year + 1, 1, 1)
    else:
        next_month = datetime(year, month + 1, 1)
    return (next_month - datetime(year, month, 1)).days


def advance(value: datetime, unit: str, count: int = 1) -> datetime:
    """Advance a datetime by count of unit, preserving the wall-clock time."""
    if unit == "day":
        return value + timedelta(days=count)
    if unit == "week":
        return value + timedelta(weeks=count)
    if unit == "month":
        return _add_months(value, count)
    if unit == "year":
        return _add_months(value, count * 12)
    raise ValueError(f"未知的循环单位: {unit}")


def next_due(from_dt: datetime, spec: str) -> Optional[datetime]:
    """Return the first occurrence strictly after from_dt, or None if invalid."""
    parsed = parse_recurrence(spec)
    if not parsed:
        return None
    unit, count = parsed
    return advance(from_dt, unit, count)


def occurrences_in_range(
    base_due: datetime,
    spec: str,
    range_start: datetime,
    range_end: datetime,
) -> List[datetime]:
    """Expand base_due by spec, returning occurrence timestamps within [start,end].

    The base itself counts as an occurrence, so a task due today whose schedule
    repeats weekly appears today and each week through range_end.
    """
    parsed = parse_recurrence(spec)
    if not parsed:
        return [base_due] if range_start <= base_due <= range_end else []
    unit, count = parsed
    out: List[datetime] = []
    cursor = base_due
    guard = 0
    while cursor <= range_end and guard < 1000:
        if cursor >= range_start:
            out.append(cursor)
        cursor = advance(cursor, unit, count)
        guard += 1
    return out
