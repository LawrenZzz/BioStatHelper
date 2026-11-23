"""Run `python -B tests/test_study.py` from backend for a dotenv-free test run."""

import base64
from concurrent.futures import ThreadPoolExecutor
from copy import deepcopy
from datetime import datetime
from pathlib import Path
import sys
from threading import Barrier
from types import SimpleNamespace


if __name__ == "__main__":
    import os
    from unittest.mock import patch

    os.environ.update(
        DEBUG="false", DATABASE_URL="sqlite://", SECRET_KEY="study-tests-only-not-a-real-secret",
        PYTEST_DISABLE_PLUGIN_AUTOLOAD="1",
    )
    sys.dont_write_bytecode = True
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
    # conftest imports Settings before test modules: block dotenv at the source.
    with patch("pydantic_settings.sources.DotEnvSettingsSource._read_env_files", return_value={}):
        import pytest

        raise SystemExit(pytest.main([__file__, "-q", "-p", "no:cacheprovider", *sys.argv[1:]]))


import pytest
from fastapi import FastAPI
from fastapi import HTTPException
from fastapi.testclient import TestClient
from sqlalchemy import create_engine, event, insert
from sqlalchemy.dialects import postgresql, sqlite
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool
from sqlalchemy.schema import CreateTable

from app.api.endpoints.auth import create_access_token
from app.api.endpoints.study import router
from app.crud import study as crud
from app.db.database import Base, get_db
from app.models.models import LearningProgress, NasVideo, NasVideoCategory, User, Video
from app.models.study import StudyFocusSession, StudyItem, StudyList, StudyNote, StudySubscription, StudyUpdate
from app.schemas import study as schema

PREFIX = "/api/v1/study"
BVID = "BV17x411w7KC"
OTHER_BVID = "BV1xx411c7mD"
PNG = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aOdwAAAAASUVORK5CYII="


@pytest.fixture
def api():
    engine = create_engine("sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool)

    @event.listens_for(engine, "connect")
    def foreign_keys(connection, _):
        connection.execute("PRAGMA foreign_keys=ON")

    Base.metadata.create_all(engine)
    factory = sessionmaker(bind=engine, expire_on_commit=False, autoflush=False)
    with factory() as db:
        first = User(username="study-first", email="study-first@example.com", hashed_password="x")
        second = User(username="study-second", email="study-second@example.com", hashed_password="x")
        root = NasVideoCategory(name="Course", path="Course")
        outside = NasVideoCategory(name="Other", path="Other")
        db.add_all([first, second, root, outside])
        db.flush()
        child = NasVideoCategory(name="Chapter", path="Course/Chapter", parent_id=root.id)
        db.add(child)
        db.flush()
        video_ids = []
        for index, (category, visible, published) in enumerate([
            (root, True, True), (child, True, True), (outside, True, True),
            (root, False, True), (root, True, False),
        ]):
            video = Video(title=f"Video {index}", video_url=f"/videos/{index}", duration_seconds=600, is_published=published)
            db.add(video)
            db.flush()
            db.add(NasVideo(relative_path=f"course/{index}.mp4", file_name=f"{index}.mp4", category_id=category.id,
                            published_video_id=video.id, is_visible=visible))
            video_ids.append(video.id)
        db.commit()
        identifiers = (first.id, second.id, root.id, child.id, outside.id)
    app = FastAPI()
    app.include_router(router)

    def override_db():
        with factory() as db:
            yield db

    app.dependency_overrides[get_db] = override_db
    headers = [{"Authorization": f"Bearer {create_access_token({'sub': name})}"}
               for name in ("study-first", "study-second")]
    with TestClient(app) as client:
        def call(method, path, expected=200, other=False, **kwargs):
            kwargs.setdefault("headers", headers[int(other)])
            response = client.request(method, PREFIX + path, **kwargs)
            assert response.status_code == expected, response.text
            return response.json()

        yield SimpleNamespace(
            call=call, client=client, app=app, factory=factory, engine=engine,
            headers=headers, user_id=identifiers[0], other_id=identifiers[1], category_id=identifiers[2],
            child_id=identifiers[3], outside_id=identifiers[4], videos=video_ids,
        )
    engine.dispose()


def make_list(api, name="Study", other=False):
    return api.call("POST", "/lists", 201, other=other, json={"name": name})


def make_item(api, list_id=None, other=False, **changes):
    if list_id is None:
        list_id = make_list(api, other=other)["id"]
    payload = {"list_id": list_id, "source": "nas", "video_id": api.videos[0], "title": "Lesson", **changes}
    return api.call("POST", "/items", 201, other=other, json=payload)


def make_subscription(api, other=False, **changes):
    return api.call("POST", "/subscriptions", 201, other=other,
                    json={"source": "nas", "kind": "category", "category_id": api.category_id, **changes})


def bili_update(bvid=BVID, **metadata):
    return {"title": "Online lesson", "published_at": "2026-10-20T02:00:00Z",
            "source_data": {"bvid": bvid, "cid": 123, **metadata}, "duration_seconds": 60}


@pytest.mark.parametrize("method,path", [
    ("GET", "/lists"), ("POST", "/lists"), ("GET", "/lists/1"), ("PUT", "/lists/1"), ("DELETE", "/lists/1"),
    ("GET", "/items"), ("POST", "/items"), ("GET", "/items/1"), ("PUT", "/items/1"), ("DELETE", "/items/1"),
    ("POST", "/items/reorder"), ("POST", "/items/batch"), ("GET", "/notes"), ("POST", "/notes"),
    ("PUT", "/notes/1"), ("DELETE", "/notes/1"), ("GET", "/focus"), ("POST", "/focus"), ("GET", "/stats"),
    ("GET", "/subscriptions"), ("POST", "/subscriptions"), ("PUT", "/subscriptions/1"), ("DELETE", "/subscriptions/1"),
    ("GET", "/updates"), ("POST", "/updates"), ("POST", "/updates/check"), ("PUT", "/updates/1"), ("GET", "/export"), ("POST", "/import"),
    ("GET", "/preferences"), ("PUT", "/preferences"), ("POST", "/subscriptions/batch"), ("POST", "/updates/batch"),
])
def test_every_route_requires_authentication(api, method, path):
    response = api.client.request(method, PREFIX + path, json={} if method in ("POST", "PUT") else None)
    assert response.status_code == 401


def test_preferences_persist_merge_and_isolate_users(api):
    defaults = api.call("GET", "/preferences")
    assert defaults == schema.Preferences().model_dump()
    assert not defaults["notifications_enabled"] and not defaults["background_refresh_enabled"]
    changed = api.call("PUT", "/preferences", json={
        "home_card_order": list(reversed(defaults["home_card_order"])), "home_hidden_cards": ["focus"],
        "notifications_enabled": True, "double_tap_left": "none", "layout": "compact",
    })
    assert api.call("GET", "/preferences") == changed
    assert api.call("GET", "/preferences", other=True) == defaults
    assert api.call("PUT", "/preferences", json={"layout": "comfortable"})["notifications_enabled"]
    with api.factory() as db:
        assert db.get(crud.StudyPreferences, api.user_id).data["home_hidden_cards"] == ["focus"]


@pytest.mark.parametrize("payload", [
    {"cookie": "SESSDATA=secret"}, {"unknown": True}, {"layout": "invalid"}, {"layout": None},
    {"home_card_order": ["continue"]}, {"home_hidden_cards": ["focus", "focus"]},
    {"home_hidden_cards": ["unknown"]}, {"notifications_enabled": "true"},
    {"double_tap_seek_seconds": 121}, {"double_tap_seek_seconds": True},
    {"long_press_speed": 0.5}, {"long_press_speed": True}, {"double_tap_right": "cookie"},
    {"double_tap_left_width": 0.09}, {"double_tap_left_width": 0.46}, {"double_tap_left_width": True},
    {"double_tap_right_width": 0.09}, {"double_tap_right_width": 0.46}, {"double_tap_right_width": True},
    {"double_tap_height": 0.19}, {"double_tap_height": 1.01}, {"double_tap_height": True},
    {"double_tap_height": None}, {"double_tap_left_width": "0.35"},
])
def test_preferences_whitelist_and_validation_are_atomic(api, payload):
    defaults = api.call("GET", "/preferences")
    api.call("PUT", "/preferences", 422, json=payload)
    assert api.call("GET", "/preferences") == defaults


@pytest.mark.parametrize("left,right,height", [(0.1, 0.45, 0.2), (0.45, 0.1, 1)])
def test_double_tap_region_bounds_persist_and_isolate_users(api, left, right, height):
    defaults = api.call("GET", "/preferences")
    assert {key: defaults[key] for key in ("double_tap_left_width", "double_tap_right_width", "double_tap_height")} == {
        "double_tap_left_width": 0.35, "double_tap_right_width": 0.35, "double_tap_height": 1.0,
    }
    assert defaults["double_tap_center"] == "play_pause"
    dimensions = {"double_tap_left_width": left, "double_tap_right_width": right, "double_tap_height": height}
    saved = api.call("PUT", "/preferences", json={**dimensions, "double_tap_center": "none"})
    assert all(saved[key] == value for key, value in dimensions.items())
    assert api.call("GET", "/preferences") == saved
    assert api.call("GET", "/preferences", other=True) == defaults
    assert api.call("PUT", "/preferences", json={"layout": "compact"})["double_tap_center"] == "none"
    with api.factory() as db:
        assert all(db.get(crud.StudyPreferences, api.user_id).data[key] == value for key, value in dimensions.items())
    archive = api.call("GET", "/export")
    assert all(archive["preferences"][key] == value for key, value in dimensions.items())
    api.call("POST", "/import", other=True, json=archive)
    assert api.call("GET", "/preferences", other=True) == api.call("GET", "/preferences")


def test_legacy_preferences_and_archives_supply_region_defaults_without_resetting_custom_sizes(api):
    legacy = {"layout": "compact", "double_tap_center": "seek_forward"}
    with api.factory() as db:
        db.add(crud.StudyPreferences(user_id=api.user_id, data=legacy))
        db.commit()
    expected = schema.Preferences(**legacy).model_dump(mode="json")
    assert api.call("GET", "/preferences") == expected
    archive = api.call("GET", "/export")
    assert archive["preferences"] == expected
    for field in ("double_tap_left_width", "double_tap_right_width", "double_tap_height"):
        del archive["preferences"][field]
    api.call("POST", "/import", other=True, json=archive)
    assert api.call("GET", "/preferences", other=True) == expected
    custom = {"double_tap_left_width": 0.2, "double_tap_right_width": 0.4, "double_tap_height": 0.75}
    saved = api.call("PUT", "/preferences", json=custom)
    for mode in ("merge", "replace"):
        api.call("POST", f"/import?mode={mode}", json=archive)
        assert api.call("GET", "/preferences") == saved


@pytest.mark.parametrize("field", ["double_tap_left_width", "double_tap_right_width", "double_tap_height"])
@pytest.mark.parametrize("value", [float("nan"), float("inf"), float("-inf")])
def test_double_tap_regions_reject_nonfinite_values(field, value):
    with pytest.raises(ValueError):
        schema.Preferences.model_validate({field: value})


def test_preferences_archive_roundtrip_old_backup_and_rollback(api):
    make_item(api)
    prefs = api.call("PUT", "/preferences", json={"layout": "compact", "home_hidden_cards": ["updates"]})
    archive = api.call("GET", "/export")
    assert archive["preferences"] == prefs
    api.call("POST", "/import", other=True, json=archive)
    assert api.call("GET", "/preferences", other=True) == prefs
    old = {key: value for key, value in archive.items() if key != "preferences"}
    api.call("PUT", "/preferences", json={"layout": "comfortable"})
    for mode in ("merge", "replace"):
        api.call("POST", f"/import?mode={mode}", json=old)
        assert api.call("GET", "/preferences")["layout"] == "comfortable"
    invalid = deepcopy(archive)
    invalid["items"][0]["video_id"] = 2147483647
    api.call("POST", "/import?mode=replace", 404, json=invalid)
    assert api.call("GET", "/preferences")["layout"] == "comfortable"
    assert api.call("GET", "/items")["total"] == 1


def test_paused_subscriptions_and_enabled_alias_block_discovery_and_submission(api):
    nas = make_subscription(api, paused=True)
    assert nas["paused"] and not nas["enabled"]
    assert api.call("GET", "/updates")["total"] == 0
    assert api.call("POST", f"/updates/check?subscription_id={nas['id']}")["total"] == 0
    api.call("PUT", f"/subscriptions/{nas['id']}", json={"enabled": True})
    assert api.call("GET", "/updates")["total"] == 2
    online = make_subscription(api, source="up", kind="up", category_id=None, mid=123, enabled=False)
    api.call("POST", "/updates", 409, json={"subscription_id": online["id"], "updates": [bili_update(mid=123)]})
    assert api.call("GET", "/subscriptions?enabled=false")["data"][0]["id"] == online["id"]
    api.call("POST", "/subscriptions/batch", json={"subscription_ids": [online["id"]], "action": "resume"})
    assert api.call("POST", "/updates", json={"subscription_id": online["id"], "updates": [bili_update(mid=123)]})["total"] == 1
    api.call("PUT", f"/subscriptions/{nas['id']}", 422, json={"enabled": True, "paused": True})


def test_historical_updates_only_mark_new_records_and_preserve_detection_time(api):
    sub = make_subscription(api, source="up", kind="up", category_id=None, mid=123)
    body = {"subscription_id": sub["id"], "updates": [bili_update(mid=123)]}
    first = api.call("POST", "/updates", json=body)["data"][0]
    assert not first["read"] and not first["seen"]
    repeated = api.call("POST", "/updates", json={**body, "historical": True})["data"][0]
    assert not repeated["read"] and not repeated["seen"]
    assert repeated["created_at"] == first["created_at"]
    history = api.call("POST", "/updates", json={**body, "historical": True, "updates": [bili_update(OTHER_BVID, mid=123)]})["data"][0]
    assert history["read"] and history["seen"]
    current = api.call("POST", "/updates", json={**body, "updates": [bili_update(OTHER_BVID, mid=123)]})["data"][0]
    assert current["read"] and current["seen"]
    assert current["created_at"] == history["created_at"]


def test_subscription_batches_are_atomic_and_delete_owned_dependents(api):
    sub = make_subscription(api)
    foreign = make_subscription(api, other=True)
    updates = api.call("GET", "/updates")["data"]
    for action in ("pause", "resume", "delete", "read"):
        api.call("POST", "/subscriptions/batch", 404, json={"subscription_ids": [sub["id"], foreign["id"]], "action": action})
    assert api.call("GET", "/subscriptions")["data"][0]["enabled"]
    assert not any(row["read"] for row in api.call("GET", "/updates")["data"])
    api.call("POST", "/subscriptions/batch", 422, json={"subscription_ids": [sub["id"], sub["id"]], "action": "pause"})
    api.call("POST", "/subscriptions/batch", json={"subscription_ids": [sub["id"]], "action": "pause"})
    assert not api.call("GET", "/subscriptions")["data"][0]["enabled"]
    api.call("POST", "/subscriptions/batch", json={"subscription_ids": [sub["id"]], "action": "read"})
    assert all(row["read"] and row["seen"] for row in api.call("GET", "/updates")["data"])
    api.call("POST", "/updates/batch", json={"update_ids": [updates[0]["id"]], "action": "delete"})
    api.call("POST", "/subscriptions/batch", json={"subscription_ids": [sub["id"]], "action": "delete"})
    assert api.call("GET", "/subscriptions")["total"] == 0
    assert api.call("GET", "/subscriptions", other=True)["total"] == 1
    replacement = make_subscription(api)
    assert replacement["enabled"] and api.call("GET", "/updates")["total"] == 2


def test_update_batches_isolate_users_and_tombstones_survive_refresh_and_archives(api):
    make_subscription(api)
    make_subscription(api, other=True)
    updates = api.call("GET", "/updates")["data"]
    foreign = api.call("GET", "/updates", other=True)["data"][0]
    ids = [entry["id"] for entry in updates]
    for action in ("read", "unread", "seen", "delete"):
        api.call("POST", "/updates/batch", 404, json={"update_ids": [ids[0], foreign["id"]], "action": action})
    api.call("POST", "/updates/batch", 422, json={"update_ids": [ids[0], ids[0]], "action": "delete"})
    api.call("POST", "/updates/batch", json={"update_ids": ids, "action": "read"})
    assert all(row["read"] and row["seen"] for row in api.call("GET", "/updates")["data"])
    api.call("POST", "/updates/batch", json={"update_ids": ids, "action": "unread"})
    assert all(not row["read"] and row["seen"] for row in api.call("GET", "/updates")["data"])
    api.call("POST", "/updates/batch", json={"update_ids": ids, "action": "delete"})
    assert api.call("GET", "/updates")["total"] == 0
    assert api.call("POST", "/updates/check")["total"] == 0
    api.call("PUT", f"/updates/{ids[0]}", 404, json={"read": True})
    archive = api.call("GET", "/export")
    assert len(archive["updates"]) == 2 and all(row["deleted"] for row in archive["updates"])
    for mode in ("merge", "replace"):
        api.call("POST", f"/import?mode={mode}", json=archive)
        assert api.call("GET", "/updates")["total"] == 0
    assert api.call("GET", "/updates", other=True)["total"] == 2


def test_source_filters_and_utc_date_groups_preserve_envelope(api):
    make_subscription(api)
    up = make_subscription(api, source="up", kind="up", category_id=None, mid=123)
    collection = make_subscription(api, source="collection", kind="collection", category_id=None, owner_mid=123, season_id=456)
    for sub, metadata in ((up, {"mid": 123}), (collection, {"owner_mid": 123, "season_id": 456})):
        api.call("POST", "/updates", json={"subscription_id": sub["id"], "updates": [
            {**bili_update(**metadata), "published_at": "2026-10-20T00:01:00+08:00"},
            {**bili_update(OTHER_BVID, **metadata), "published_at": "2026-10-20T23:59:59.999999Z"},
        ]})
    for source, count in (("nas", 1), ("bilibili", 2), ("up", 1), ("collection", 1)):
        assert api.call("GET", f"/subscriptions?source={source}")["total"] == count
    response = api.call("GET", "/updates?source=up&date_from=2026-10-19&date_to=2026-10-20&group_by=date")
    assert response["total"] == 2
    assert [row["date"] for row in response["groups"]] == ["2026-10-20", "2026-10-19"]
    assert sum(row["total"] for row in response["groups"]) == 2
    assert all(row["subscription_id"] == up["id"] and row["published_at"] for row in response["data"])
    assert api.call("GET", "/updates?source=collection&date_from=2026-10-20&date_to=2026-10-20")["total"] == 1
    assert "groups" not in api.call("GET", "/updates?source=bilibili")
    api.call("GET", "/updates?date_from=2026-10-21&date_to=2026-10-20", 422)
    api.call("GET", "/updates?source=unknown", 422)
    api.call("GET", "/updates?group_by=unknown", 422)
    make_item(api)
    assert api.call("GET", "/items?source=bilibili")["total"] == 0
    assert api.call("GET", "/items?source=nas")["total"] == 1


def test_sidecar_tables_upgrade_existing_database_idempotently(api):
    from app.models.study import StudyPreferences, StudySubscriptionState, StudyUpdateState

    original = make_subscription(api)
    for model in (StudyPreferences, StudySubscriptionState, StudyUpdateState):
        model.__table__.drop(api.engine)
    for _ in range(2):
        Base.metadata.create_all(api.engine)
    assert api.call("GET", "/subscriptions")["data"][0]["id"] == original["id"]
    assert api.call("GET", "/subscriptions")["data"][0]["enabled"]
    api.call("PUT", f"/subscriptions/{original['id']}", json={"enabled": False})
    assert api.call("GET", "/updates")["total"] == 0
    for model in (StudyPreferences, StudySubscriptionState, StudyUpdateState):
        assert "CREATE TABLE" in str(CreateTable(model.__table__).compile(dialect=postgresql.dialect()))


def test_invalid_token_and_inactive_user(api):
    api.call("GET", "/lists", 401, headers={"Authorization": "Bearer invalid"})
    with api.factory() as db:
        db.get(User, api.user_id).is_active = False
        db.commit()
    api.call("GET", "/lists", 403)


def test_lists_crud_unique_names_and_envelopes(api):
    first = make_list(api)
    make_list(api, other=True)
    api.call("POST", "/lists", 409, json={"name": "Study"})
    second = api.call("POST", "/lists", 201, json={"name": "Archived", "description": "Later", "sort_order": 2, "archived": True})
    assert api.call("GET", "/lists")["total"] == 2
    assert api.call("GET", "/lists?archived=true")["data"][0]["id"] == second["id"]
    assert api.call("GET", f"/lists/{first['id']}")["name"] == "Study"
    api.call("PUT", f"/lists/{first['id']}", json={"name": "Renamed", "description": "Read", "sort_order": 1})
    api.call("PUT", f"/lists/{first['id']}", 422, json={"name": None})
    assert api.call("DELETE", f"/lists/{first['id']}") == {"deleted": 1}
    api.call("GET", f"/lists/{first['id']}", 404)
    assert api.call("GET", "/lists", other=True)["total"] == 1


def test_items_preserve_json_identity_and_filters(api):
    listing = make_list(api)["id"]
    nas = make_item(api, listing, source_data={"label": "local", "nested": {"chapter": 1}})
    online = make_item(api, listing, source="bilibili", video_id=None, source_data={"bvid": BVID, "cid": 123, "owner": {"mid": 99}}, title="Alpha")
    assert online["source_data"] == {"bvid": BVID, "cid": 123, "owner": {"mid": 99}}
    assert nas["source_data"]["nested"]["chapter"] == 1
    assert nas["duration_seconds"] == 600
    api.call("POST", "/items", 409, json={"list_id": listing, "source": "bilibili", "source_data": {"bvid": BVID, "cid": "123"}, "title": "Duplicate"})
    api.call("POST", "/items", 409, json={"list_id": listing, "video_id": nas["video_id"], "title": "Duplicate"})
    third = make_item(api, listing, source="bilibili", video_id=None, source_data={"bvid": BVID, "cid": 124})
    updated = api.call("PUT", f"/items/{online['id']}", json={"status": "learning", "position_seconds": 25, "duration_seconds": 60, "favorite": True})
    assert updated["position_seconds"] == 25 and updated["last_watched_at"]
    assert api.call("GET", f"/items?list_id={listing}&status=learning&q=Alp&sort=title&favorite=true")["data"][0]["id"] == online["id"]
    assert api.call("GET", "/items?sort=title")["data"][0]["id"] == online["id"]
    for sort in ("manual", "newest", "oldest", "duration", "recent", "updated"):
        assert api.call("GET", f"/items?sort={sort}")["total"] == 3
    api.call("GET", "/items?sort=unsafe", 422)
    api.call("PUT", f"/items/{third['id']}", 409, json={"source_data": {"bvid": BVID, "cid": 123}})
    assert api.call("GET", f"/items/{third['id']}")["source_data"]["cid"] == 124


@pytest.mark.parametrize("changes", [
    {"source": "bilibili", "video_id": None, "source_data": {}},
    {"source": "bilibili", "source_data": {"bvid": BVID}},
    {"source": "bilibili", "video_id": None, "source_data": {"bvid": BVID, "cid": 0}},
    {"video_id": None}, {"status": "invalid"}, {"position_seconds": -1},
    {"duration_seconds": 5, "position_seconds": 6}, {"source_data": "{}"},
    {"source_data": {"headers": {"Cookie": "secret"}}},
    {"source_data": {"owner": {"SESSDATA": "secret"}}},
    {"source_data": {"url": "https://x/?SESSDATA=secret"}},
])
def test_item_validation_and_no_credentials(api, changes):
    listing = make_list(api)["id"]
    api.call("POST", "/items", 422, json={"list_id": listing, "source": "nas", "video_id": api.videos[0], "title": "Lesson", **changes})
    assert api.call("GET", "/items")["total"] == 0


@pytest.mark.parametrize("index", [3, 4, 99])
def test_nas_targets_must_be_visible_and_published(api, index):
    listing = make_list(api)["id"]
    api.call("POST", "/items", 404, json={"list_id": listing, "video_id": api.videos[index] if index < 5 else 9999, "title": "Hidden"})


def test_user_isolation_for_resources_and_target_queries(api):
    item = make_item(api)
    foreign = make_item(api, other=True)
    note = api.call("POST", "/notes", 201, json={"item_id": item["id"], "content": "Private"})
    subscription = make_subscription(api)
    updates = api.call("GET", "/updates")["data"]
    for method, path, payload in [
        ("GET", f"/lists/{item['list_id']}", None), ("PUT", f"/lists/{item['list_id']}", {"name": "Hacked"}),
        ("DELETE", f"/lists/{item['list_id']}", None), ("GET", f"/items/{item['id']}", None),
        ("PUT", f"/items/{item['id']}", {"title": "Hacked"}), ("DELETE", f"/items/{item['id']}", None),
        ("PUT", f"/notes/{note['id']}", {"content": "Hacked"}), ("DELETE", f"/notes/{note['id']}", None),
        ("PUT", f"/subscriptions/{subscription['id']}", {"name": "Hacked"}),
        ("DELETE", f"/subscriptions/{subscription['id']}", None),
        ("PUT", f"/updates/{updates[0]['id']}", {"read": True}),
        ("GET", f"/items?list_id={item['list_id']}", None), ("GET", f"/notes?item_id={item['id']}", None),
        ("GET", f"/focus?item_id={item['id']}", None), ("GET", f"/updates?subscription_id={subscription['id']}", None),
        ("POST", "/items", {"list_id": item["list_id"], "video_id": api.videos[0], "title": "Hacked"}),
        ("POST", "/notes", {"item_id": item["id"], "content": "Hacked"}),
        ("POST", "/focus", {"item_id": item["id"], "elapsed_seconds": 0, "started_at": "2026-10-20T00:00:00"}),
        ("PUT", f"/items/{foreign['id']}", {"list_id": item["list_id"]}),
        ("POST", "/updates", {"subscription_id": subscription["id"], "updates": []}),
    ]:
        api.call(method, path, 404, other=True, **({"json": payload} if payload is not None else {}))
    assert api.call("GET", "/notes", other=True) == {"data": [], "total": 0}
    assert api.call("GET", "/updates", other=True) == {"data": [], "total": 0}
    assert api.call("GET", "/items", other=True)["total"] == 1


def test_reorder_requires_exact_permutation_and_batch_is_atomic(api):
    first = make_item(api)
    second = make_item(api, first["list_id"], video_id=api.videos[1])
    foreign = make_item(api, other=True)
    for ids in ([first["id"]], [first["id"], first["id"]], [first["id"], foreign["id"]], [first["id"], second["id"], 9999]):
        api.call("POST", "/items/reorder", 422, json={"list_id": first["list_id"], "item_ids": ids})
    reordered = api.call("POST", "/items/reorder", json={"list_id": first["list_id"], "item_ids": [second["id"], first["id"]]})
    assert [(row["id"], row["sort_order"]) for row in reordered["data"]] == [(second["id"], 0), (first["id"], 1)]
    for action in ("complete", "plan", "remove"):
        api.call("POST", "/items/batch", 404, json={"item_ids": [first["id"], foreign["id"]], "action": action})
    assert api.call("GET", f"/items/{first['id']}")["status"] == "planned"
    ids = [first["id"], second["id"]]
    assert api.call("POST", "/items/batch", json={"item_ids": ids, "action": "complete"}) == {"updated": 2}
    assert api.call("GET", "/items?status=completed")["total"] == 2
    api.call("POST", "/items/batch", json={"item_ids": ids, "action": "plan"})
    api.call("POST", "/items/batch", 422, json={"item_ids": [first["id"], first["id"]], "action": "remove"})
    assert api.call("POST", "/items/batch", json={"item_ids": ids, "action": "remove"}) == {"deleted": 2}
    assert api.call("POST", "/items/reorder", json={"list_id": first["list_id"], "item_ids": []})["total"] == 0
    assert api.call("GET", "/items", other=True)["total"] == 1


def test_notes_image_alias_crud_and_size_limit(api):
    item = make_item(api)
    note = api.call("POST", "/notes", 201, json={"item_id": item["id"], "content": "Remember", "position_seconds": 15, "image_data": "data:image/png;base64," + PNG})
    assert note["image_data"] == PNG and "image_base64" not in note
    updated = api.call("PUT", f"/notes/{note['id']}", json={"content": "Updated", "position_seconds": 20, "image_base64": PNG})
    assert updated["image_data"] == PNG
    assert api.call("GET", f"/notes?item_id={item['id']}")["total"] == 1
    api.call("PUT", f"/notes/{note['id']}", json={"image_data": None})
    exact = base64.b64encode(b"\x89PNG\r\n\x1a\n" + b"x" * (schema.MAX_IMAGE_BYTES - 8)).decode()
    api.call("PUT", f"/notes/{note['id']}", json={"image_data": exact})
    oversized = base64.b64encode(b"\x89PNG\r\n\x1a\n" + b"x" * (schema.MAX_IMAGE_BYTES - 7)).decode()
    for image in (oversized, "not base64", base64.b64encode(b"not an image").decode(), "data:image/svg+xml;base64," + PNG):
        api.call("PUT", f"/notes/{note['id']}", 422, json={"image_data": image})
    api.call("POST", f"/notes?item_id={item['id'] + 1}", 422, json={"item_id": item["id"], "content": "Mismatch"})
    assert api.call("DELETE", f"/notes/{note['id']}") == {"deleted": 1}


@pytest.mark.parametrize("delete_list", [False, True])
def test_delete_material_cascades_notes_but_keeps_focus(api, delete_list):
    item = make_item(api)
    api.call("POST", "/notes", 201, json={"item_id": item["id"], "content": "Note"})
    api.call("POST", "/focus", 201, json={"item_id": item["id"], "elapsed_seconds": 60, "started_at": "2026-10-20T00:00:00", "ended_at": "2026-10-20T00:01:00", "completed": True})
    api.call("DELETE", f"/lists/{item['list_id']}" if delete_list else f"/items/{item['id']}")
    assert api.call("GET", "/notes")["total"] == 0
    focus = api.call("GET", "/focus")
    assert focus["total"] == 1 and focus["data"][0]["item_id"] is None
    assert api.call("GET", "/stats")["total_seconds"] == 60


@pytest.mark.parametrize("changes", [
    {"elapsed_seconds": -1}, {"elapsed_seconds": 61}, {"ended_at": "2026-10-19T23:59:59"},
    {"ended_at": None, "completed": True},
])
def test_focus_rejects_invalid_intervals(api, changes):
    api.call("POST", "/focus", 422, json={"elapsed_seconds": 60, "started_at": "2026-10-20T00:00:00", "ended_at": "2026-10-20T00:01:00", "completed": True, **changes})


def test_focus_stats_timezone_midnight_streak_and_user_isolation(api):
    item = make_item(api, status="completed")
    for payload in [
        {"started_at": "2026-10-18T08:00:00+08:00", "ended_at": "2026-10-18T08:02:00+08:00", "elapsed_seconds": 120},
        {"started_at": "2026-10-19T23:59:00Z", "ended_at": "2026-10-20T00:01:00Z", "elapsed_seconds": 120},
    ]:
        api.call("POST", "/focus", 201, json={"item_id": item["id"], "completed": True, **payload})
    api.call("POST", "/focus", 201, other=True, json={"started_at": "2026-10-20T00:00:00Z", "elapsed_seconds": 10000})
    focus = api.call("GET", f"/focus?item_id={item['id']}")
    assert focus["total"] == 2 and focus["data"][1]["started_at"].startswith("2026-10-18T00:00:00")
    with api.factory() as db:
        result = crud.stats(db, api.user_id, days=3, now=datetime(2026, 10, 20, 12))
    assert result == {"today_seconds": 60, "total_seconds": 240, "sessions": 2, "completed_items": 1, "streak_days": 3,
                      "daily": [{"date": "2026-10-18", "seconds": 120}, {"date": "2026-10-19", "seconds": 60}, {"date": "2026-10-20", "seconds": 60}]}
    assert api.call("GET", "/stats?days=3")["total_seconds"] == 240
    api.call("GET", "/stats?days=0", 422)


def test_subscription_contract_aliases_targets_uniqueness_and_delete(api):
    nas = make_subscription(api)
    api.call("POST", "/subscriptions", 409, json={"source": "nas", "category_id": api.category_id})
    make_subscription(api, other=True)
    up = api.call("POST", "/subscriptions", 201, json={"source": "up", "mid": 42})
    assert up["source"] == "bilibili" and up["kind"] == "up" and up["mid"] == "42"
    collection = api.call("POST", "/subscriptions", 201, json={"source": "collection", "owner_mid": 42, "season_id": "7"})
    assert collection["source"] == "bilibili" and collection["season_id"] == "7"
    api.call("POST", "/subscriptions", 422, json={"source": "bilibili", "kind": "collection", "owner_mid": "42"})
    api.call("POST", "/subscriptions", 422, json={"source": "nas", "kind": "up", "mid": "42"})
    api.call("POST", "/subscriptions", 404, json={"source": "nas", "category_id": 99999})
    api.call("PUT", f"/subscriptions/{nas['id']}", json={"name": "Renamed"})
    api.call("PUT", f"/subscriptions/{up['id']}", json={"source": "up", "mid": 43})
    assert api.call("GET", "/subscriptions")["total"] == 3
    api.call("DELETE", f"/subscriptions/{collection['id']}")
    assert api.call("GET", "/subscriptions")["total"] == 2


def test_nas_updates_discovery_is_idempotent_and_includes_late_commits(api):
    subscription = make_subscription(api)
    first = api.call("GET", "/updates")
    assert first["total"] == 2
    assert {row["video_id"] for row in first["data"]} == set(api.videos[:2])
    flagged = first["data"][0]
    api.call("PUT", f"/updates/{flagged['id']}", json={"seen": True, "read": True})
    assert api.call("GET", "/updates?read=true")["total"] == 1
    assert api.call("GET", "/updates?seen=false")["total"] == 1
    with api.factory() as db:
        video = Video(title="Late video", video_url="/late", is_published=True, created_at=datetime(2020, 1, 1))
        db.add(video)
        db.flush()
        db.add(NasVideo(relative_path="late.mp4", file_name="late.mp4", category_id=api.child_id,
                        published_video_id=video.id, is_visible=True, created_at=datetime(2020, 1, 1)))
        db.commit()
    assert api.call("GET", f"/updates?subscription_id={subscription['id']}")["total"] == 3
    assert api.call("GET", "/updates")["total"] == 3
    assert api.call("POST", "/updates/check")["total"] == 3
    assert api.call("POST", f"/updates/check?subscription_id={subscription['id']}")["total"] == 3
    api.call("POST", f"/updates/check?subscription_id={subscription['id']}", 404, other=True)
    api.call("POST", "/updates", 422, json={"subscription_id": subscription["id"], "updates": []})
    api.call("DELETE", f"/subscriptions/{subscription['id']}")
    assert api.call("GET", "/updates")["total"] == 0


def test_bili_update_batch_validation_rollback_and_flags_survive_refresh(api):
    subscription = api.call("POST", "/subscriptions", 201, json={"source": "bilibili", "kind": "up", "mid": "42"})
    body = {"subscription_id": subscription["id"], "updates": [bili_update(mid=42)]}
    first = api.call("POST", "/updates", json=body)
    row_id = first["data"][0]["id"]
    api.call("PUT", f"/updates/{row_id}", json={"seen": True, "read": True})
    assert api.call("POST", "/updates", json=body)["data"][0]["read"]
    assert api.call("GET", "/updates")["total"] == 1
    api.call("POST", "/updates", 422, json={"subscription_id": subscription["id"], "updates": [bili_update(OTHER_BVID, mid=42), bili_update(mid=99)]})
    assert api.call("GET", "/updates")["total"] == 1
    api.call("POST", "/updates", 422, json={"subscription_id": subscription["id"], "updates": [bili_update(mid=42, cookies="secret")]})
    api.call("PUT", f"/subscriptions/{subscription['id']}", json={"mid": "43"})
    assert api.call("GET", "/updates")["total"] == 0
    collection = api.call("POST", "/subscriptions", 201, json={"source": "bilibili", "kind": "collection", "owner_mid": 42, "season_id": 7})
    api.call("POST", "/updates", json={"subscription_id": collection["id"], "updates": [bili_update(owner_mid=42, season_id=7)]})
    api.call("POST", "/updates", 422, json={"subscription_id": collection["id"], "updates": [bili_update(owner_mid=42, season_id=8)]})


def test_nas_progress_seed_sync_and_favorite_does_not_change_progress(api):
    with api.factory() as db:
        db.add_all([
            LearningProgress(user_id=api.user_id, video_id=api.videos[0], progress_percent=25, completed=False),
            LearningProgress(user_id=api.other_id, video_id=api.videos[0], progress_percent=90, completed=False),
        ])
        db.commit()
    item = make_item(api)
    assert item["position_seconds"] == 150 and item["status"] == "learning"
    api.call("PUT", f"/items/{item['id']}", json={"position_seconds": 300, "status": "learning"})
    with api.factory() as db:
        own = db.query(LearningProgress).filter_by(user_id=api.user_id, video_id=api.videos[0]).one()
        assert own.progress_percent == 50 and not own.completed
        timestamp = own.last_accessed
        assert db.query(LearningProgress).filter_by(user_id=api.other_id).one().progress_percent == 90
    api.call("PUT", f"/items/{item['id']}", json={"favorite": True})
    with api.factory() as db:
        assert db.query(LearningProgress).filter_by(user_id=api.user_id).one().last_accessed == timestamp
    api.call("POST", "/items/batch", json={"item_ids": [item["id"]], "action": "complete"})
    with api.factory() as db:
        assert db.query(LearningProgress).filter_by(user_id=api.user_id).one().completed


def test_progress_explicit_values_override_seed_and_batch_does_not_duplicate_legacy_progress(api):
    first = make_item(api)
    second = make_item(api, make_list(api, "Second list")["id"])
    api.call("POST", "/items/batch", json={"item_ids": [first["id"], second["id"]], "action": "complete"})
    with api.factory() as db:
        assert db.query(LearningProgress).filter_by(user_id=api.user_id, video_id=api.videos[0]).count() == 1
    explicit = make_item(api, make_list(api, "Explicit")["id"], position_seconds=0, status="planned")
    assert explicit["position_seconds"] == 0 and explicit["status"] == "planned"
    api.call("POST", "/items", 422, json={"list_id": first["list_id"], "video_id": api.videos[1], "title": "Beyond video", "position_seconds": 1000})


@pytest.mark.parametrize("path", ["/items/999999999999999999999", "/items?list_id=999999999999999999999", "/notes?item_id=999999999999999999999"])
def test_oversized_identifiers_are_validation_errors(api, path):
    api.call("GET", path, 422)


def test_focus_at_date_boundary_does_not_break_stats(api):
    api.call("POST", "/focus", 201, json={"started_at": "9999-12-31T23:59:58", "elapsed_seconds": 1})
    assert api.call("GET", "/stats")["total_seconds"] == 1
    api.call("POST", "/focus", 422, json={"started_at": "9999-12-31T23:59:59", "elapsed_seconds": 2})


def test_concurrent_duplicate_creates_have_one_winner():
    engine = create_engine("sqlite:///file:study-concurrency?mode=memory&cache=shared&uri=true",
                           connect_args={"check_same_thread": False})
    Base.metadata.create_all(engine)
    factory = sessionmaker(bind=engine, autoflush=False)
    with factory() as db:
        user = User(username="concurrent-study", email="concurrent@example.com", hashed_password="x")
        db.add(user)
        db.commit()
        user_id = user.id
    barrier = Barrier(2)

    def create():
        with factory() as db:
            barrier.wait(timeout=10)
            try:
                with crud.transaction(db, user_id):
                    crud.create_list(db, user_id, schema.ListCreate(name="One list"))
                return 201
            except HTTPException as exc:
                return exc.status_code

    try:
        with ThreadPoolExecutor(max_workers=2) as executor:
            results = list(executor.map(lambda _: create(), range(2)))
        assert sorted(results) == [201, 409]
        with factory() as db:
            assert db.query(StudyList).count() == 1
    finally:
        engine.dispose()


def populated_archive(api):
    item = make_item(api, position_seconds=120, status="learning", favorite=True)
    make_item(api, item["list_id"], source="bilibili", video_id=None, source_data={"bvid": BVID, "cid": 123})
    api.call("POST", "/notes", 201, json={"item_id": item["id"], "position_seconds": 30, "content": "Note", "image_data": PNG})
    api.call("POST", "/focus", 201, json={"item_id": item["id"], "started_at": "2026-10-20T00:00:00Z", "ended_at": "2026-10-20T00:01:00Z", "elapsed_seconds": 60, "completed": True})
    make_subscription(api)
    api.call("GET", "/updates")
    return api.call("GET", "/export")


def test_export_import_roundtrip_maps_ids_and_preserves_watch_history(api):
    archive = populated_archive(api)
    assert archive["kind"] == "study-backup" and archive["version"] == 1
    assert len(archive["watch_history"]) == 1 and archive["watch_history"][0]["position_seconds"] == 120
    assert "user_id" not in str(archive)
    sentinel = make_item(api, other=True, title="Existing private item")
    result = api.call("POST", "/import", other=True, json=archive)
    assert result["imported"] == {"lists": 0, "items": 1, "notes": 1, "focus": 1, "subscriptions": 1, "updates": 2}
    assert result["id_map"]["items"][str(archive["items"][0]["id"])] == sentinel["id"]
    imported = api.call("GET", "/export", other=True)
    assert imported["notes"][0]["image_data"] == PNG
    assert imported["notes"][0]["item_id"] == sentinel["id"]
    assert imported["focus"][0]["item_id"] == sentinel["id"]
    assert api.call("POST", "/import", other=True, json=archive)["imported"] == {key: 0 for key in crud.ARCHIVE_TABLES}
    assert api.call("GET", "/items")["total"] == 2
    assert api.call("GET", "/notes")["total"] == 1
    api.call("POST", "/import?mode=replace", other=True, json={"version": 1})
    assert api.call("GET", "/items", other=True)["total"] == 0
    assert api.call("GET", "/items")["total"] == 2


def test_import_rejects_dangling_foreign_ids_credentials_and_rolls_back_replace(api):
    archive = populated_archive(api)
    baseline = api.call("GET", "/export")
    for mutate_payload in (
        lambda doc: doc["notes"][0].update(item_id=9999),
        lambda doc: doc["items"][0].update(user_id=api.other_id),
        lambda doc: doc["items"][1]["source_data"].update(cookie="secret"),
        lambda doc: doc["watch_history"][0].update(item_id=9999),
        lambda doc: doc["items"].append(deepcopy(doc["items"][0])),
    ):
        invalid = deepcopy(archive)
        mutate_payload(invalid)
        api.call("POST", "/import?mode=replace", 422, json=invalid)
    invalid = deepcopy(archive)
    invalid["items"][1].update(source="nas", video_id=9999, source_data={})
    api.call("POST", "/import?mode=replace", 404, json=invalid)
    after = api.call("GET", "/export")
    for key in crud.ARCHIVE_TABLES:
        assert after[key] == baseline[key]
    with api.factory() as db:
        assert db.query(LearningProgress).filter_by(user_id=api.user_id).one().progress_percent == 20


def test_import_watch_history_validates_progress_and_is_transactional(api):
    archive = populated_archive(api)
    archive["watch_history"][0].update(position_seconds=420, status="completed")
    api.call("POST", "/import", json=archive)
    item_id = archive["watch_history"][0]["item_id"]
    assert api.call("GET", f"/items/{item_id}")["position_seconds"] == 420
    with api.factory() as db:
        assert db.query(LearningProgress).filter_by(user_id=api.user_id).one().completed
    invalid = deepcopy(archive)
    invalid["watch_history"][0]["position_seconds"] = 9999
    api.call("POST", "/import", 422, json=invalid)


def test_database_ownership_and_uniqueness_constraints_are_real(api):
    item = make_item(api)
    with api.factory() as db:
        with pytest.raises(IntegrityError):
            db.execute(insert(StudyNote).values(user_id=api.other_id, item_id=item["id"], content="Cross-user"))
            db.commit()
        db.rollback()
        with pytest.raises(IntegrityError):
            db.execute(insert(StudyList).values(user_id=api.user_id, name="Study"))
            db.commit()
        db.rollback()
        with pytest.raises(IntegrityError):
            db.execute(insert(StudyItem).values(user_id=api.user_id, list_id=item["list_id"], source="nas",
                                               source_key=f"nas:{item['video_id']}", video_id=item["video_id"], title="Duplicate"))
            db.commit()
        db.rollback()


@pytest.mark.parametrize("dialect", [sqlite.dialect(), postgresql.dialect()], ids=["sqlite", "postgresql"])
def test_all_study_tables_compile_for_supported_databases(dialect):
    for model in (StudyList, StudyItem, StudyNote, StudyFocusSession, StudySubscription, StudyUpdate):
        ddl = str(CreateTable(model.__table__).compile(dialect=dialect))
        assert "CREATE TABLE study_" in ddl
        assert "user_id" in ddl


def test_openapi_has_one_prefix_and_the_canonical_image_field(api):
    document = api.app.openapi()
    assert all(path.startswith(PREFIX + "/") and path.count(PREFIX) == 1 for path in document["paths"])
    assert "image_data" in document["components"]["schemas"]["NoteCreate"]["properties"]
    assert len(document["paths"][PREFIX + "/lists"]) == 2
