"""Original study workflow implementation, with explicit ownership and transactions."""

from collections import defaultdict
from contextlib import contextmanager
from datetime import datetime, time, timedelta

from fastapi import HTTPException
from pydantic import ValidationError
from sqlalchemy import text
from sqlalchemy.exc import IntegrityError, OperationalError

from app.models.models import LearningProgress, NasVideo, NasVideoCategory, User, Video
from app.models.study import (
    StudyFocusSession, StudyItem, StudyList, StudyNote, StudyPreferences,
    StudySubscription, StudySubscriptionState, StudyUpdate, StudyUpdateState, utcnow,
)
from app.schemas import study as schema


def fail(detail, code=422):
    raise HTTPException(status_code=code, detail=detail)


@contextmanager
def transaction(db, user_id):
    """Serialize a user's mutations; SQLite needs a write lock before reading."""
    try:
        if db.bind.dialect.name == "sqlite":
            connection = db.connection()
            if not connection.connection.driver_connection.in_transaction:
                connection.exec_driver_sql("BEGIN IMMEDIATE")
        elif db.bind.dialect.name == "postgresql":
            # Bound lock contention from simultaneous sync/import requests.
            # SET LOCAL does not leak the timeout into pooled connections.
            db.execute(text("SET LOCAL lock_timeout = '5s'"))
        user = db.query(User).filter(User.id == user_id).with_for_update().first()
        if user is None:
            fail("User not found", 404)
        yield
        db.flush()
        db.commit()
    except IntegrityError as exc:
        db.rollback()
        raise HTTPException(status_code=409, detail="Duplicate resource or invalid related target") from exc
    except OperationalError as exc:
        db.rollback()
        code = getattr(exc.orig, "sqlstate", None) or getattr(exc.orig, "pgcode", None)
        if code == "55P03":
            raise HTTPException(status_code=503, detail="学习数据正在同步，暂时无法取得保存锁，请稍后重试。",
                                headers={"Retry-After": "2"}) from exc
        if db.bind.dialect.name == "sqlite" and "locked" in str(exc).lower():
            raise HTTPException(status_code=409, detail="Study data is busy; retry the request") from exc
        raise
    except ValidationError as exc:
        db.rollback()
        raise HTTPException(status_code=422, detail=exc.errors(include_context=False, include_url=False)) from exc
    except ValueError as exc:
        db.rollback()
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    except Exception:
        db.rollback()
        raise


def owned(db, model, user_id, row_id):
    row = db.query(model).filter(model.user_id == user_id, model.id == row_id).first()
    if row is None:
        fail("Study resource not found", 404)
    return row


def ensure_videos_unused(db, video_ids):
    if not video_ids:
        return
    if db.query(StudyItem).filter(StudyItem.video_id.in_(video_ids)).first():
        fail("视频仍被学习清单引用。请先导出备份并从学习清单移出相关课程，再删除视频库记录；不会删除本地文件。", 409)
    if db.query(StudyUpdate).filter(StudyUpdate.video_id.in_(video_ids)).first():
        fail("视频仍被课程订阅更新引用。请先取消相关订阅，再删除视频库记录；不会删除本地文件。", 409)


def ensure_categories_unused(db, category_ids):
    if category_ids and db.query(StudySubscription).filter(StudySubscription.category_id.in_(category_ids)).first():
        fail("分类仍被学习订阅引用。请先取消相关订阅，再删除分类；不会删除本地文件。", 409)


def rows(db, model, user_id):
    return db.query(model).filter(model.user_id == user_id)


def assign(row, values):
    for key, value in values.items():
        setattr(row, key, value)
    return row


def nas_video(db, video_id):
    video = db.query(Video).filter(Video.id == video_id, Video.is_published.is_(True)).first()
    if video is None:
        fail("Published NAS video not found", 404)
    nas = db.query(NasVideo).filter(NasVideo.published_video_id == video_id).all()
    if nas and not any(entry.is_visible for entry in nas):
        fail("Published NAS video not found", 404)
    return video


def validate_item(db, user_id, values):
    item = schema.ItemCreate.model_validate(values)
    owned(db, StudyList, user_id, item.list_id)
    if item.source == "nas":
        nas_video(db, item.video_id)
    return item


def list_lists(db, user_id, archived=None):
    query = rows(db, StudyList, user_id)
    if archived is not None:
        query = query.filter(StudyList.archived == archived)
    return query.order_by(StudyList.sort_order, StudyList.id).all()


def create_list(db, user_id, payload):
    row = StudyList(user_id=user_id, **payload.model_dump())
    db.add(row)
    db.flush()
    return row


def update_list(db, user_id, row_id, payload):
    return assign(owned(db, StudyList, user_id, row_id), payload.model_dump(exclude_unset=True))


def remove_items(db, user_id, item_ids):
    if not item_ids:
        return
    rows(db, StudyNote, user_id).filter(StudyNote.item_id.in_(item_ids)).delete(synchronize_session="fetch")
    # Keep focus statistics after removing learning material.
    rows(db, StudyFocusSession, user_id).filter(StudyFocusSession.item_id.in_(item_ids)).update(
        {StudyFocusSession.item_id: None}, synchronize_session="fetch",
    )
    rows(db, StudyItem, user_id).filter(StudyItem.id.in_(item_ids)).delete(synchronize_session="fetch")


def delete_list(db, user_id, row_id):
    row = owned(db, StudyList, user_id, row_id)
    remove_items(db, user_id, [item.id for item in rows(db, StudyItem, user_id).filter(StudyItem.list_id == row_id)])
    db.delete(row)
    return {"deleted": 1}


def list_items(db, user_id, list_id=None, status=None, q=None, sort="sort_order", favorite=None, source=None):
    query = rows(db, StudyItem, user_id)
    if list_id is not None:
        owned(db, StudyList, user_id, list_id)
        query = query.filter(StudyItem.list_id == list_id)
    if status is not None:
        query = query.filter(StudyItem.status == status)
    if favorite is not None:
        query = query.filter(StudyItem.favorite == favorite)
    if source is not None:
        query = query.filter(StudyItem.source == source)
    if q:
        query = query.filter(StudyItem.title.ilike(f"%{q}%"))
    orders = {
        "sort_order": StudyItem.sort_order.asc(), "manual": StudyItem.sort_order.asc(),
        "newest": StudyItem.created_at.desc(), "oldest": StudyItem.created_at.asc(),
        "title": StudyItem.title.asc(), "duration": StudyItem.duration_seconds.asc(),
        "recent": StudyItem.last_watched_at.desc().nullslast(),
        "updated": StudyItem.updated_at.desc(),
    }
    if sort not in orders:
        fail("Unsupported item sort")
    return query.order_by(orders[sort], StudyItem.id).all()


def create_item(db, user_id, payload):
    explicit = payload.model_fields_set
    payload = validate_item(db, user_id, payload.model_dump())
    values = payload.model_dump()
    previous = None
    if payload.source == "nas":
        video = nas_video(db, payload.video_id)
        if not values["duration_seconds"]:
            values["duration_seconds"] = video.duration_seconds or 0
        previous = db.query(LearningProgress).filter(
            LearningProgress.user_id == user_id, LearningProgress.video_id == payload.video_id,
            LearningProgress.concept_id.is_(None),
        ).order_by(LearningProgress.last_accessed.desc(), LearningProgress.id.desc()).first()
        if previous:
            if "position_seconds" not in explicit:
                percent = max(0, min(previous.progress_percent or 0, 100))
                values["position_seconds"] = int(values["duration_seconds"] * percent / 100)
            if "status" not in explicit:
                values["status"] = "completed" if previous.completed else ("learning" if values["position_seconds"] else "planned")
    if values["sort_order"] is None:
        last = rows(db, StudyItem, user_id).filter(StudyItem.list_id == payload.list_id).order_by(StudyItem.sort_order.desc()).first()
        values["sort_order"] = last.sort_order + 1 if last else 0
    schema.ItemCreate.model_validate(values)
    now = utcnow()
    if values["status"] == "completed":
        values["completed_at"] = now
    if values["position_seconds"]:
        values["last_watched_at"] = previous.last_accessed if previous and "position_seconds" not in explicit else now
    row = StudyItem(user_id=user_id, source_key=schema.source_key(payload.source, payload.video_id, payload.source_data), **values)
    db.add(row)
    db.flush()
    if explicit & {"position_seconds", "status"}:
        sync_nas_progress(db, user_id, row)
    return row


def sync_nas_progress(db, user_id, row):
    if row.source != "nas":
        return
    progress_rows = db.query(LearningProgress).filter(
        LearningProgress.user_id == user_id, LearningProgress.video_id == row.video_id,
        LearningProgress.concept_id.is_(None),
    ).all()
    if not progress_rows:
        progress_rows = [LearningProgress(user_id=user_id, video_id=row.video_id)]
        db.add(progress_rows[0])
    percent = min(100, row.position_seconds * 100 / row.duration_seconds) if row.duration_seconds else 0
    for progress in progress_rows:
        progress.progress_percent = 100 if row.status == "completed" else percent
        progress.completed = row.status == "completed"
        progress.last_accessed = utcnow()
    db.flush()


def update_item(db, user_id, row_id, payload):
    row = owned(db, StudyItem, user_id, row_id)
    patch = payload.model_dump(exclude_unset=True)
    values = {key: getattr(row, key) for key in schema.ItemCreate.model_fields}
    values.update(patch)
    valid = validate_item(db, user_id, values)
    if "list_id" in patch and patch["list_id"] != row.list_id and "sort_order" not in patch:
        last = rows(db, StudyItem, user_id).filter(StudyItem.list_id == valid.list_id).order_by(StudyItem.sort_order.desc()).first()
        values["sort_order"] = last.sort_order + 1 if last else 0
    assign(row, values)
    row.source_key = schema.source_key(valid.source, valid.video_id, valid.source_data)
    if "position_seconds" in patch:
        row.last_watched_at = utcnow()
    if "status" in patch:
        row.completed_at = (row.completed_at or utcnow()) if row.status == "completed" else None
    if patch.keys() & {"position_seconds", "duration_seconds", "status"}:
        sync_nas_progress(db, user_id, row)
    db.flush()
    return row


def delete_item(db, user_id, row_id):
    owned(db, StudyItem, user_id, row_id)
    remove_items(db, user_id, [row_id])
    return {"deleted": 1}


def reorder_items(db, user_id, payload):
    owned(db, StudyList, user_id, payload.list_id)
    entries = rows(db, StudyItem, user_id).filter(StudyItem.list_id == payload.list_id).all()
    if len(set(payload.item_ids)) != len(payload.item_ids):
        fail("item_ids must not contain duplicates")
    if set(payload.item_ids) != {row.id for row in entries}:
        fail("item_ids must be an exact permutation of this list")
    by_id = {row.id: row for row in entries}
    for index, key in enumerate(payload.item_ids):
        by_id[key].sort_order = index
    db.flush()
    return [by_id[key] for key in payload.item_ids]


def batch_items(db, user_id, payload):
    if len(set(payload.item_ids)) != len(payload.item_ids):
        fail("item_ids must not contain duplicates")
    entries = rows(db, StudyItem, user_id).filter(StudyItem.id.in_(payload.item_ids)).all()
    if len(entries) != len(payload.item_ids):
        fail("Study resource not found", 404)
    if payload.action == "remove":
        remove_items(db, user_id, payload.item_ids)
        return {"deleted": len(entries)}
    for row in entries:
        row.status = "completed" if payload.action == "complete" else "planned"
        row.completed_at = utcnow() if payload.action == "complete" else None
        sync_nas_progress(db, user_id, row)
    return {"updated": len(entries)}


def list_notes(db, user_id, item_id=None):
    query = rows(db, StudyNote, user_id)
    if item_id is not None:
        owned(db, StudyItem, user_id, item_id)
        query = query.filter(StudyNote.item_id == item_id)
    return query.order_by(StudyNote.position_seconds, StudyNote.id).all()


def create_note(db, user_id, payload):
    owned(db, StudyItem, user_id, payload.item_id)
    row = StudyNote(user_id=user_id, **payload.model_dump())
    db.add(row)
    db.flush()
    return row


def update_note(db, user_id, row_id, payload):
    return assign(owned(db, StudyNote, user_id, row_id), payload.model_dump(exclude_unset=True))


def delete_note(db, user_id, row_id):
    db.delete(owned(db, StudyNote, user_id, row_id))
    return {"deleted": 1}


def list_focus(db, user_id, item_id=None):
    query = rows(db, StudyFocusSession, user_id)
    if item_id is not None:
        owned(db, StudyItem, user_id, item_id)
        query = query.filter(StudyFocusSession.item_id == item_id)
    return query.order_by(StudyFocusSession.started_at.desc(), StudyFocusSession.id).all()


def create_focus(db, user_id, payload):
    if payload.item_id is not None:
        owned(db, StudyItem, user_id, payload.item_id)
    row = StudyFocusSession(user_id=user_id, **payload.model_dump())
    db.add(row)
    db.flush()
    return row


def stats(db, user_id, days=30, now=None):
    now = now or utcnow()
    daily = defaultdict(int)
    sessions = list_focus(db, user_id)
    for session in sessions:
        cursor, remaining = session.started_at, session.elapsed_seconds
        # Pauses have no timestamp, so allocate reported active time from the start.
        while remaining:
            until_midnight = 86400 - (cursor.hour * 3600 + cursor.minute * 60 + cursor.second)
            amount = min(remaining, until_midnight)
            daily[cursor.date()] += amount
            remaining -= amount
            cursor += timedelta(seconds=amount)
    today = now.date()
    cursor = today if daily[today] else today - timedelta(days=1)
    streak = 0
    while daily[cursor] > 0:
        streak += 1
        cursor -= timedelta(days=1)
    return {
        "today_seconds": daily[today],
        "total_seconds": sum(session.elapsed_seconds for session in sessions),
        "sessions": len(sessions),
        "completed_items": rows(db, StudyItem, user_id).filter(StudyItem.status == "completed").count(),
        "streak_days": streak,
        "daily": [
            {"date": (today - timedelta(days=offset)).isoformat(), "seconds": daily[today - timedelta(days=offset)]}
            for offset in range(days - 1, -1, -1)
        ],
    }


def subscription_key(payload):
    if payload.source == "nas":
        return f"nas:category:{payload.category_id}"
    if payload.kind == "up":
        return f"bilibili:up:{payload.mid}"
    return f"bilibili:collection:{payload.owner_mid}:{payload.season_id}"


def validate_subscription(db, payload):
    if payload.source == "nas" and db.query(NasVideoCategory).filter(NasVideoCategory.id == payload.category_id).first() is None:
        fail("NAS category not found", 404)


def get_preferences(db, user_id):
    row = db.get(StudyPreferences, user_id)
    return schema.Preferences.model_validate(row.data if row else {})


def update_preferences(db, user_id, payload):
    values = get_preferences(db, user_id).model_dump()
    values.update(payload.model_dump(exclude_unset=True))
    valid = schema.Preferences.model_validate(values)
    row = db.get(StudyPreferences, user_id)
    if row is None:
        row = StudyPreferences(user_id=user_id)
        db.add(row)
    row.data = valid.model_dump(mode="json")
    return valid


def filter_source(query, source, model):
    if source in ("up", "collection"):
        return query.filter(model.source == "bilibili", StudySubscription.kind == source)
    return query.filter(model.source == source) if source else query


def list_subscriptions(db, user_id, source=None, enabled=None):
    query = filter_source(rows(db, StudySubscription, user_id), source, StudySubscription)
    if enabled is not None:
        paused = StudySubscription.state.has(StudySubscriptionState.paused.is_(True))
        query = query.filter(~paused if enabled else paused)
    return query.order_by(StudySubscription.id).all()


def set_paused(row, paused):
    if row.state is None:
        row.state = StudySubscriptionState(user_id=row.user_id, paused=paused)
    else:
        row.state.paused = paused


def set_deleted(row):
    if row.state is None:
        row.state = StudyUpdateState()


def create_subscription(db, user_id, payload):
    validate_subscription(db, payload)
    row = StudySubscription(user_id=user_id, target_key=subscription_key(payload), **payload.model_dump(exclude={"paused", "enabled"}))
    set_paused(row, payload.paused)
    db.add(row)
    db.flush()
    return row


def update_subscription(db, user_id, row_id, payload):
    row = owned(db, StudySubscription, user_id, row_id)
    values = {key: getattr(row, key) for key in schema.SubscriptionCreate.model_fields}
    patch = payload.model_dump(exclude_unset=True)
    values.update(patch)
    valid = schema.SubscriptionCreate.model_validate(values)
    validate_subscription(db, valid)
    key = subscription_key(valid)
    if row.target_key != key:
        remove_updates(db, user_id, row.id)
        row.last_checked_at = None
    assign(row, valid.model_dump(exclude={"paused", "enabled"}))
    set_paused(row, valid.paused)
    row.target_key = key
    db.flush()
    return row


def delete_subscription(db, user_id, row_id):
    row = owned(db, StudySubscription, user_id, row_id)
    remove_updates(db, user_id, row_id)
    db.delete(row)
    return {"deleted": 1}


def remove_updates(db, user_id, subscription_id=None):
    query = rows(db, StudyUpdate, user_id)
    if subscription_id is not None:
        query = query.filter(StudyUpdate.subscription_id == subscription_id)
    db.query(StudyUpdateState).filter(StudyUpdateState.update_id.in_(query.with_entities(StudyUpdate.id))).delete(synchronize_session=False)
    query.delete(synchronize_session="fetch")


def batch_owned(db, model, user_id, ids):
    if len(set(ids)) != len(ids):
        fail("IDs must not contain duplicates")
    entries = rows(db, model, user_id).filter(model.id.in_(ids)).all()
    if len(entries) != len(ids):
        fail("Study resource not found", 404)
    return entries


def batch_subscriptions(db, user_id, payload):
    entries = batch_owned(db, StudySubscription, user_id, payload.subscription_ids)
    for row in entries:
        if payload.action == "delete":
            delete_subscription(db, user_id, row.id)
        elif payload.action == "read":
            rows(db, StudyUpdate, user_id).filter(StudyUpdate.subscription_id == row.id).update(
                {StudyUpdate.read: True, StudyUpdate.seen: True}, synchronize_session="fetch",
            )
        else:
            set_paused(row, payload.action == "pause")
    return {"deleted" if payload.action == "delete" else "updated": len(entries)}


def batch_updates(db, user_id, payload):
    entries = batch_owned(db, StudyUpdate, user_id, payload.update_ids)
    for row in entries:
        if payload.action == "delete":
            set_deleted(row)
        elif payload.action == "seen":
            row.seen = True
        else:
            row.read = payload.action == "read"
            if row.read:
                row.seen = True
    return {"deleted" if payload.action == "delete" else "updated": len(entries)}


def category_ids(db, root_id):
    children = defaultdict(list)
    for key, parent in db.query(NasVideoCategory.id, NasVideoCategory.parent_id):
        children[parent].append(key)
    found, queue = set(), [root_id]
    while queue:
        key = queue.pop()
        if key not in found:
            found.add(key)
            queue.extend(children[key])
    return found


def validate_update_target(db, subscription, payload):
    key = schema.source_key(subscription.source, payload.video_id, payload.source_data)
    if subscription.source == "nas":
        nas_video(db, payload.video_id)
        target = db.query(NasVideo).filter(
            NasVideo.published_video_id == payload.video_id,
            NasVideo.category_id.in_(category_ids(db, subscription.category_id)),
            NasVideo.is_visible.is_(True),
        ).first()
        if target is None:
            fail("Video is outside the subscribed category", 404)
    else:
        data = payload.source_data
        owner = data.get("owner")
        mid = data.get("mid", data.get("owner_mid", owner.get("mid") if isinstance(owner, dict) else None))
        if subscription.kind == "up" and str(mid) != subscription.mid:
            fail("Update mid does not match subscription")
        if subscription.kind == "collection" and (
            str(data.get("owner_mid", mid)) != subscription.owner_mid
            or str(data.get("season_id")) != subscription.season_id
        ):
            fail("Update collection does not match subscription")
    return key


def upsert_update(db, user_id, subscription, payload):
    key = validate_update_target(db, subscription, payload)
    row = rows(db, StudyUpdate, user_id).filter(
        StudyUpdate.subscription_id == subscription.id, StudyUpdate.source_key == key,
    ).first()
    if row is None:
        row = StudyUpdate(user_id=user_id, subscription_id=subscription.id, source=subscription.source, source_key=key, **payload.model_dump())
        db.add(row)
    else:
        assign(row, payload.model_dump())
    db.flush()
    return row


def submit_updates(db, user_id, payload):
    subscription = owned(db, StudySubscription, user_id, payload.subscription_id)
    if subscription.source != "bilibili":
        fail("NAS updates are discovered by the server")
    if subscription.paused:
        fail("Subscription is paused", 409)
    result = []
    for entry in payload.updates:
        key = validate_update_target(db, subscription, entry)
        existing = rows(db, StudyUpdate, user_id).filter(
            StudyUpdate.subscription_id == subscription.id, StudyUpdate.source_key == key,
        ).first()
        row = upsert_update(db, user_id, subscription, entry)
        if existing is None and payload.historical:
            row.read = row.seen = True
        if not row.deleted and row not in result:
            result.append(row)
    subscription.last_checked_at = utcnow()
    return result


def refresh_nas(db, user_id, subscription):
    if subscription.paused:
        return
    entries = db.query(Video, NasVideo).join(NasVideo, NasVideo.published_video_id == Video.id).filter(
        NasVideo.category_id.in_(category_ids(db, subscription.category_id)),
        NasVideo.is_visible.is_(True), Video.is_published.is_(True),
    ).order_by(Video.created_at, Video.id).all()
    known = {key for (key,) in rows(db, StudyUpdate, user_id).filter(StudyUpdate.subscription_id == subscription.id).with_entities(StudyUpdate.source_key)}
    # Scan identities rather than advancing a timestamp cursor that can miss late commits.
    for video, nas in entries:
        key = schema.source_key("nas", video.id, {})
        if key in known:
            continue
        upsert_update(db, user_id, subscription, schema.UpdateCreate(
            video_id=video.id, source_data={"nas_video_id": nas.id, "category_id": nas.category_id},
            title=video.title, thumbnail_url=video.thumbnail_url,
            duration_seconds=video.duration_seconds or 0,
            published_at=nas.created_at or video.created_at,
        ))
        known.add(key)
    subscription.last_checked_at = utcnow()


def list_updates(db, user_id, subscription_id=None, seen=None, read=None, source=None, date_from=None, date_to=None):
    if date_from and date_to and date_from > date_to:
        fail("date_from must not be after date_to")
    subscriptions = [owned(db, StudySubscription, user_id, subscription_id)] if subscription_id is not None else list_subscriptions(db, user_id)
    for subscription in subscriptions:
        if subscription.source == "nas" and not subscription.paused and source in (None, "nas"):
            refresh_nas(db, user_id, subscription)
    db.flush()
    query = rows(db, StudyUpdate, user_id).join(StudySubscription, (
        (StudySubscription.id == StudyUpdate.subscription_id) & (StudySubscription.user_id == StudyUpdate.user_id)
    )).filter(~StudyUpdate.state.has())
    query = filter_source(query, source, StudyUpdate)
    if subscription_id is not None:
        query = query.filter(StudyUpdate.subscription_id == subscription_id)
    if seen is not None:
        query = query.filter(StudyUpdate.seen == seen)
    if read is not None:
        query = query.filter(StudyUpdate.read == read)
    if date_from:
        query = query.filter(StudyUpdate.published_at >= datetime.combine(date_from, time.min))
    if date_to:
        query = query.filter(StudyUpdate.published_at <= datetime.combine(date_to, time.max))
    return query.order_by(StudyUpdate.published_at.desc(), StudyUpdate.id.desc()).all()


def update_flags(db, user_id, row_id, payload):
    row = owned(db, StudyUpdate, user_id, row_id)
    if row.deleted:
        fail("Study resource not found", 404)
    return assign(row, payload.model_dump(exclude_unset=True))


ARCHIVE_TABLES = {
    "lists": (StudyList, schema.ListResponse), "items": (StudyItem, schema.ItemResponse),
    "notes": (StudyNote, schema.NoteResponse), "focus": (StudyFocusSession, schema.FocusResponse),
    "subscriptions": (StudySubscription, schema.SubscriptionResponse), "updates": (StudyUpdate, schema.UpdateResponse),
}


def export_data(db, user_id):
    payload = {"kind": "study-backup", "version": 1, "exported_at": utcnow()}
    payload["preferences"] = get_preferences(db, user_id).model_dump()
    for name, (model, response) in ARCHIVE_TABLES.items():
        payload[name] = [response.model_validate(row).model_dump() for row in rows(db, model, user_id).order_by(model.id)]
    payload["watch_history"] = [
        {"item_id": entry["id"], **{key: entry[key] for key in schema.WatchHistory.model_fields if key != "item_id"}}
        for entry in payload["items"]
        if entry["last_watched_at"] is not None or entry["position_seconds"] or entry["status"] == "completed"
    ]
    return schema.StudyArchive.model_validate(payload)


def stamp(row, record, created):
    if created:
        row.created_at = schema.utc(record.created_at)
    if hasattr(record, "updated_at"):
        row.updated_at = schema.utc(record.updated_at)


def import_data(db, user_id, archive, mode="merge"):
    if mode == "replace":
        remove_updates(db, user_id)
        rows(db, StudySubscriptionState, user_id).delete(synchronize_session="fetch")
        for model in (StudyNote, StudyFocusSession, StudyItem, StudySubscription, StudyList):
            rows(db, model, user_id).delete(synchronize_session="fetch")
        db.flush()
    mapping = {name: {} for name in ARCHIVE_TABLES}
    counts = {name: 0 for name in ARCHIVE_TABLES}
    for entry in archive.lists:
        row = rows(db, StudyList, user_id).filter(StudyList.name == entry.name).first()
        created = row is None
        values = {key: getattr(entry, key) for key in schema.ListCreate.model_fields}
        row = create_list(db, user_id, schema.ListCreate(**values)) if created else assign(row, values)
        stamp(row, entry, created)
        mapping["lists"][entry.id] = row.id
        counts["lists"] += int(created)
    for entry in archive.items:
        values = {key: getattr(entry, key) for key in schema.ItemCreate.model_fields}
        values["list_id"] = mapping["lists"][entry.list_id]
        valid = validate_item(db, user_id, values)
        key = schema.source_key(valid.source, valid.video_id, valid.source_data)
        row = rows(db, StudyItem, user_id).filter(StudyItem.list_id == valid.list_id, StudyItem.source_key == key).first()
        created = row is None
        row = create_item(db, user_id, valid) if created else update_item(db, user_id, row.id, schema.ItemUpdate(**values))
        row.last_watched_at = schema.utc(entry.last_watched_at)
        row.completed_at = schema.utc(entry.completed_at)
        stamp(row, entry, created)
        mapping["items"][entry.id] = row.id
        counts["items"] += int(created)
    for entry in archive.notes:
        values = {key: getattr(entry, key) for key in schema.NoteCreate.model_fields}
        values["item_id"] = mapping["items"][entry.item_id]
        row = rows(db, StudyNote, user_id).filter_by(**values).first()
        created = row is None
        row = create_note(db, user_id, schema.NoteCreate(**values)) if created else row
        stamp(row, entry, created)
        mapping["notes"][entry.id] = row.id
        counts["notes"] += int(created)
    for entry in archive.focus:
        values = {key: schema.utc(getattr(entry, key)) if key.endswith("_at") else getattr(entry, key) for key in schema.FocusCreate.model_fields}
        values["item_id"] = mapping["items"][entry.item_id] if entry.item_id is not None else None
        row = rows(db, StudyFocusSession, user_id).filter_by(**values).first()
        created = row is None
        row = create_focus(db, user_id, schema.FocusCreate(**values)) if created else row
        stamp(row, entry, created)
        mapping["focus"][entry.id] = row.id
        counts["focus"] += int(created)
    for entry in archive.subscriptions:
        valid = schema.SubscriptionCreate(**{key: getattr(entry, key) for key in schema.SubscriptionCreate.model_fields})
        validate_subscription(db, valid)
        row = rows(db, StudySubscription, user_id).filter(StudySubscription.target_key == subscription_key(valid)).first()
        created = row is None
        row = create_subscription(db, user_id, valid) if created else update_subscription(
            db, user_id, row.id, schema.SubscriptionUpdate(**valid.model_dump()),
        )
        row.last_checked_at = schema.utc(entry.last_checked_at)
        stamp(row, entry, created)
        mapping["subscriptions"][entry.id] = row.id
        counts["subscriptions"] += int(created)
    db.flush()
    for entry in archive.updates:
        subscription = owned(db, StudySubscription, user_id, mapping["subscriptions"][entry.subscription_id])
        if entry.source != subscription.source:
            fail("Archive update source does not match its subscription")
        valid = schema.UpdateCreate(**{key: getattr(entry, key) for key in schema.UpdateCreate.model_fields})
        key = validate_update_target(db, subscription, valid)
        existing = rows(db, StudyUpdate, user_id).filter(StudyUpdate.subscription_id == subscription.id, StudyUpdate.source_key == key).first()
        created = existing is None
        row = upsert_update(db, user_id, subscription, valid)
        row.seen, row.read = entry.seen, entry.read
        if entry.deleted:
            set_deleted(row)
        stamp(row, entry, created)
        mapping["updates"][entry.id] = row.id
        counts["updates"] += int(created)
    for entry in archive.watch_history:
        row = owned(db, StudyItem, user_id, mapping["items"][entry.item_id])
        assign(row, entry.model_dump(exclude={"item_id"}))
        row.completed_at = (row.completed_at or utcnow()) if row.status == "completed" else None
        sync_nas_progress(db, user_id, row)
    if archive.preferences is not None:
        update_preferences(db, user_id, archive.preferences)
    return {"imported": counts, "id_map": mapping}
