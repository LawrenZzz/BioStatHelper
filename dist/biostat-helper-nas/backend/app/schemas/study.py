"""Study API and portable JSON contracts (Pydantic 2.5+)."""

import base64
import binascii
import json
import re
from datetime import datetime, timedelta, timezone
from typing import Annotated, Any, ClassVar, Literal

from pydantic import (
    AliasChoices, BaseModel, ConfigDict, Field, StringConstraints, field_validator, model_validator,
)

PositiveID = Annotated[int, Field(gt=0, le=2147483647)]
Seconds = Annotated[int, Field(ge=0, le=2147483647)]
Name = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=200)]
Title = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=500)]
Status = Literal["planned", "learning", "completed"]
Source = Literal["nas", "bilibili"]
SourceFilter = Literal["nas", "bilibili", "up", "collection"]
HomeCard = Literal["continue", "lists", "focus", "updates", "shortcuts"]
HOME_CARDS = ["continue", "lists", "focus", "updates", "shortcuts"]
TapAction = Literal["none", "play_pause", "seek_backward", "seek_forward"]
MAX_IMAGE_BYTES = 2 * 1024 * 1024


def utc(value):
    if value is not None and value.tzinfo is not None:
        return value.astimezone(timezone.utc).replace(tzinfo=None)
    return value


def metadata(value):
    forbidden = {
        "cookie", "cookies", "sessdata", "bilijct", "csrf", "csrftoken",
        "accesstoken", "refreshtoken", "authorization", "password", "sessionid",
        "token", "setcookie", "secret", "apikey",
    }

    def inspect(node, depth=0):
        if depth > 30:
            raise ValueError("source_data nesting is too deep")
        if isinstance(node, dict):
            for key, child in node.items():
                if not isinstance(key, str) or re.sub(r"[^a-z0-9]", "", key.lower()) in forbidden:
                    raise ValueError("source_data must not contain credentials or cookies")
                inspect(child, depth + 1)
        elif isinstance(node, list):
            for child in node:
                inspect(child, depth + 1)
        elif isinstance(node, str) and re.search(r"(?i)(sessdata\s*=|bili_jct\s*=|cookie\s*:|bearer\s+)", node):
            raise ValueError("source_data must not contain credentials or cookies")

    inspect(value)
    try:
        encoded = json.dumps(value, allow_nan=False).encode("utf-8")
    except (TypeError, ValueError, OverflowError) as exc:
        raise ValueError("source_data must be finite JSON") from exc
    if len(encoded) > 128 * 1024:
        raise ValueError("source_data exceeds 128 KiB")
    return value


def source_key(source, video_id, source_data):
    if source == "nas":
        if video_id is None:
            raise ValueError("nas requires video_id")
        return f"nas:{video_id}"
    if video_id is not None:
        raise ValueError("bilibili must not set video_id")
    bvid = source_data.get("bvid")
    if not isinstance(bvid, str) or not re.fullmatch(r"BV[0-9A-Za-z]{10}", bvid):
        raise ValueError("bilibili requires a valid source_data.bvid")
    cid = source_data.get("cid")
    if cid is not None and (isinstance(cid, bool) or not re.fullmatch(r"[1-9][0-9]{0,19}", str(cid))):
        raise ValueError("cid must be a positive integer identifier")
    return f"bilibili:{bvid}:{cid if cid is not None else 'default'}"


class Contract(BaseModel):
    model_config = ConfigDict(extra="forbid", from_attributes=True)


class Patch(Contract):
    nullable: ClassVar[set[str]] = set()

    @model_validator(mode="before")
    @classmethod
    def no_nulls(cls, values):
        if isinstance(values, dict):
            for key, value in values.items():
                if value is None and key not in cls.nullable:
                    raise ValueError(f"{key} must not be null")
        return values


class ListCreate(Contract):
    name: Name
    description: str = Field(default="", max_length=100000)
    sort_order: Seconds = 0
    archived: bool = False


class ListUpdate(Patch):
    name: Name | None = None
    description: str | None = Field(default=None, max_length=100000)
    sort_order: Seconds | None = None
    archived: bool | None = None


class ListResponse(ListCreate):
    id: PositiveID
    created_at: datetime
    updated_at: datetime


class ItemCreate(Contract):
    list_id: PositiveID
    video_id: PositiveID | None = None
    source: Source = "nas"
    source_data: dict[str, Any] = Field(default_factory=dict)
    title: Title
    thumbnail_url: str | None = Field(default=None, max_length=2000)
    status: Status = "planned"
    position_seconds: Seconds = 0
    duration_seconds: Seconds = 0
    favorite: bool = False
    sort_order: Seconds | None = None

    _metadata = field_validator("source_data")(metadata)

    @model_validator(mode="after")
    def valid_target(self):
        source_key(self.source, self.video_id, self.source_data)
        if self.duration_seconds and self.position_seconds > self.duration_seconds:
            raise ValueError("position_seconds exceeds duration_seconds")
        return self


class ItemUpdate(Patch):
    nullable = {"video_id", "thumbnail_url"}
    list_id: PositiveID | None = None
    video_id: PositiveID | None = None
    source: Source | None = None
    source_data: dict[str, Any] | None = None
    title: Title | None = None
    thumbnail_url: str | None = Field(default=None, max_length=2000)
    status: Status | None = None
    position_seconds: Seconds | None = None
    duration_seconds: Seconds | None = None
    favorite: bool | None = None
    sort_order: Seconds | None = None

    _metadata = field_validator("source_data")(metadata)


class ItemResponse(ItemCreate):
    id: PositiveID
    sort_order: Seconds
    last_watched_at: datetime | None = None
    completed_at: datetime | None = None
    created_at: datetime
    updated_at: datetime


class Reorder(Contract):
    list_id: PositiveID
    item_ids: list[PositiveID] = Field(max_length=10000)


class Batch(Contract):
    item_ids: list[PositiveID] = Field(min_length=1, max_length=10000)
    action: Literal["complete", "plan", "remove"]


class Preferences(Contract):
    home_card_order: list[HomeCard] = Field(default_factory=lambda: list(HOME_CARDS), max_length=5)
    home_hidden_cards: list[HomeCard] = Field(default_factory=list, max_length=5)
    notifications_enabled: bool = Field(default=False, strict=True)
    background_refresh_enabled: bool = Field(default=False, strict=True)
    double_tap_left: TapAction = "seek_backward"
    double_tap_center: TapAction = "play_pause"
    double_tap_right: TapAction = "seek_forward"
    double_tap_left_width: float = Field(default=0.35, ge=0.1, le=0.45, allow_inf_nan=False, strict=True)
    double_tap_right_width: float = Field(default=0.35, ge=0.1, le=0.45, allow_inf_nan=False, strict=True)
    double_tap_height: float = Field(default=1.0, ge=0.2, le=1.0, allow_inf_nan=False, strict=True)
    double_tap_seek_seconds: int = Field(default=10, ge=1, le=120, strict=True)
    long_press_action: Literal["none", "speed"] = "speed"
    long_press_speed: float = Field(default=2.0, ge=1, le=4, allow_inf_nan=False, strict=True)
    layout: Literal["auto", "compact", "comfortable"] = "auto"

    @field_validator("home_card_order", "home_hidden_cards")
    @classmethod
    def unique_cards(cls, value, info):
        if len(set(value)) != len(value):
            raise ValueError("home cards must not contain duplicates")
        if info.field_name == "home_card_order" and set(value) != set(HOME_CARDS):
            raise ValueError("home_card_order must contain every home card exactly once")
        return value


class SubscriptionBatch(Contract):
    subscription_ids: list[PositiveID] = Field(min_length=1, max_length=10000)
    action: Literal["pause", "resume", "delete", "read"]


class UpdateBatch(Contract):
    update_ids: list[PositiveID] = Field(min_length=1, max_length=10000)
    action: Literal["read", "unread", "seen", "delete"]


def validate_image(value):
    if value is None:
        return value
    if len(value) > ((MAX_IMAGE_BYTES + 2) // 3) * 4 + 100:
        raise ValueError("image exceeds 2 MiB")
    if value.startswith("data:"):
        header, sep, value = value.partition(",")
        if not sep or header not in {"data:image/png;base64", "data:image/jpeg;base64", "data:image/gif;base64", "data:image/webp;base64"}:
            raise ValueError("unsupported image data URL")
    try:
        raw = base64.b64decode(value, validate=True)
    except (ValueError, binascii.Error) as exc:
        raise ValueError("invalid base64 image") from exc
    if len(raw) > MAX_IMAGE_BYTES:
        raise ValueError("image exceeds 2 MiB")
    if not (raw.startswith(b"\x89PNG\r\n\x1a\n") or raw.startswith(b"\xff\xd8\xff") or raw.startswith((b"GIF87a", b"GIF89a")) or (raw.startswith(b"RIFF") and raw[8:12] == b"WEBP")):
        raise ValueError("only PNG, JPEG, GIF and WebP images are accepted")
    return value


class NoteCreate(Contract):
    item_id: PositiveID
    content: str = Field(default="", max_length=200000)
    position_seconds: Seconds = 0
    image_data: str | None = Field(default=None, validation_alias=AliasChoices("image_data", "image_base64"))

    _image = field_validator("image_data")(validate_image)


class NoteUpdate(Patch):
    nullable = {"image_data", "image_base64"}
    content: str | None = Field(default=None, max_length=200000)
    position_seconds: Seconds | None = None
    image_data: str | None = Field(default=None, validation_alias=AliasChoices("image_data", "image_base64"))

    _image = field_validator("image_data")(validate_image)


class NoteResponse(NoteCreate):
    id: PositiveID
    created_at: datetime
    updated_at: datetime


class FocusCreate(Contract):
    item_id: PositiveID | None = None
    elapsed_seconds: Seconds
    started_at: datetime
    ended_at: datetime | None = None
    completed: bool = False

    _dates = field_validator("started_at", "ended_at")(utc)

    @model_validator(mode="after")
    def valid_interval(self):
        if self.completed and self.ended_at is None:
            raise ValueError("completed sessions require ended_at")
        if self.ended_at is not None and (self.ended_at - self.started_at).total_seconds() < self.elapsed_seconds:
            raise ValueError("elapsed_seconds exceeds the session interval")
        try:
            self.started_at + timedelta(seconds=self.elapsed_seconds)
        except OverflowError as exc:
            raise ValueError("session interval is outside the supported date range") from exc
        return self


class FocusResponse(FocusCreate):
    id: PositiveID
    created_at: datetime


class SubscriptionCreate(Contract):
    source: Source
    kind: Literal["category", "up", "collection"]
    name: str = Field(default="", max_length=200)
    category_id: PositiveID | None = None
    mid: str | None = None
    owner_mid: str | None = None
    season_id: str | None = None
    paused: bool = False
    enabled: bool = True

    @model_validator(mode="before")
    @classmethod
    def source_aliases(cls, values):
        if isinstance(values, dict):
            values = dict(values)
            if "paused" in values and not isinstance(values["paused"], bool):
                raise ValueError("paused must be a boolean")
            if "enabled" in values:
                if not isinstance(values["enabled"], bool):
                    raise ValueError("enabled must be a boolean")
                if "paused" in values and values["paused"] != (not values["enabled"]):
                    raise ValueError("enabled and paused conflict")
                values["paused"] = not values["enabled"]
            elif "paused" in values:
                values["enabled"] = not values["paused"]
            if values.get("source") in ("up", "collection"):
                kind = values["source"]
                if values.get("kind", kind) != kind:
                    raise ValueError("subscription source/kind mismatch")
                values.update(source="bilibili", kind=kind)
            elif values.get("source") == "nas":
                values.setdefault("kind", "category")
        return values

    @field_validator("mid", "owner_mid", "season_id", mode="before")
    @classmethod
    def identifier(cls, value):
        if value is None:
            return None
        if isinstance(value, bool) or not re.fullmatch(r"[1-9][0-9]{0,19}", str(value)):
            raise ValueError("identifier must be a positive integer")
        return str(value)

    @model_validator(mode="after")
    def valid_target(self):
        values = (self.category_id, self.mid, self.owner_mid, self.season_id)
        valid = (
            self.source == "nas" and self.kind == "category" and values[0] is not None and all(v is None for v in values[1:])
        ) or (
            self.source == "bilibili" and self.kind == "up" and self.mid is not None and self.category_id is None and self.owner_mid is None and self.season_id is None
        ) or (
            self.source == "bilibili" and self.kind == "collection" and self.owner_mid is not None and self.season_id is not None and self.category_id is None and self.mid is None
        )
        if not valid:
            raise ValueError("subscription source/kind/target mismatch")
        return self


class SubscriptionUpdate(Patch):
    nullable = {"category_id", "mid", "owner_mid", "season_id"}
    source: Source | None = None
    kind: Literal["category", "up", "collection"] | None = None
    name: str | None = Field(default=None, max_length=200)
    category_id: PositiveID | None = None
    mid: str | int | None = None
    owner_mid: str | int | None = None
    season_id: str | int | None = None
    paused: bool | None = None
    enabled: bool | None = None

    @model_validator(mode="before")
    @classmethod
    def source_aliases(cls, values):
        return SubscriptionCreate.source_aliases(values)


class SubscriptionResponse(SubscriptionCreate):
    id: PositiveID
    last_checked_at: datetime | None = None
    created_at: datetime
    updated_at: datetime


class UpdateCreate(Contract):
    video_id: PositiveID | None = None
    source_data: dict[str, Any] = Field(default_factory=dict)
    title: Title
    thumbnail_url: str | None = Field(default=None, max_length=2000)
    duration_seconds: Seconds = 0
    published_at: datetime

    _metadata = field_validator("source_data")(metadata)
    _date = field_validator("published_at")(utc)


class UpdatesSubmit(Contract):
    subscription_id: PositiveID
    updates: list[UpdateCreate] = Field(max_length=1000)
    historical: bool = Field(default=False, strict=True)


class UpdateFlags(Patch):
    seen: bool | None = None
    read: bool | None = None


class UpdateResponse(UpdateCreate):
    id: PositiveID
    subscription_id: PositiveID
    source: Source
    seen: bool
    read: bool
    created_at: datetime
    deleted: bool = False


class Page(Contract):
    data: list[Any]
    total: int


class UpdateGroup(Page):
    date: str


class UpdatePage(Page):
    groups: list[UpdateGroup] | None = None


class DailySeconds(Contract):
    date: str
    seconds: int


class StatsResponse(Contract):
    today_seconds: int
    total_seconds: int
    sessions: int
    completed_items: int
    streak_days: int
    daily: list[DailySeconds]


class WatchHistory(Contract):
    item_id: PositiveID
    position_seconds: Seconds
    duration_seconds: Seconds
    status: Status
    last_watched_at: datetime | None = None

    _date = field_validator("last_watched_at")(utc)

    @model_validator(mode="after")
    def valid_position(self):
        if self.duration_seconds and self.position_seconds > self.duration_seconds:
            raise ValueError("position_seconds exceeds duration_seconds")
        return self


class StudyArchive(Contract):
    kind: Literal["study-backup"] = "study-backup"
    version: Literal[1] = 1
    exported_at: datetime | None = None
    lists: list[ListResponse] = Field(default_factory=list, max_length=10000)
    items: list[ItemResponse] = Field(default_factory=list, max_length=10000)
    notes: list[NoteResponse] = Field(default_factory=list, max_length=10000)
    focus: list[FocusResponse] = Field(default_factory=list, max_length=10000)
    subscriptions: list[SubscriptionResponse] = Field(default_factory=list, max_length=10000)
    updates: list[UpdateResponse] = Field(default_factory=list, max_length=10000)
    watch_history: list[WatchHistory] = Field(default_factory=list, max_length=10000)
    preferences: Preferences | None = None

    @model_validator(mode="after")
    def local_references(self):
        ids = {}
        for name in ("lists", "items", "notes", "focus", "subscriptions", "updates"):
            rows = getattr(self, name)
            ids[name] = {row.id for row in rows}
            if len(ids[name]) != len(rows):
                raise ValueError(f"duplicate {name} IDs")
        references = (
            [(row.list_id, "lists") for row in self.items]
            + [(row.item_id, "items") for row in self.notes + self.focus if row.item_id is not None]
            + [(row.subscription_id, "subscriptions") for row in self.updates]
            + [(row.item_id, "items") for row in self.watch_history]
        )
        if any(key not in ids[name] for key, name in references):
            raise ValueError("archive contains dangling references")
        if len({row.item_id for row in self.watch_history}) != len(self.watch_history):
            raise ValueError("duplicate watch_history item IDs")
        return self
