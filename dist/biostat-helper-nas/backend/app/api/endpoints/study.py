"""Mount with app.include_router(study.router); the API prefix is included."""

from datetime import date
from typing import Annotated, Literal

from fastapi import APIRouter, Depends, HTTPException, Path, Query
from sqlalchemy.orm import Session

from app.api.endpoints.auth import get_current_user
from app.crud import study as crud
from app.db.database import get_db
from app.models.study import StudyItem, StudyList
from app.schemas import study as schema

router = APIRouter(prefix="/api/v1/study", tags=["study"])
RouteID = Annotated[int, Path(gt=0, le=2147483647)]


def study_user(current_user=Depends(get_current_user)):
    if not current_user.is_active:
        raise HTTPException(status_code=403, detail="Inactive user")
    return current_user


def mutate(db, user, function, *args, **kwargs):
    with crud.transaction(db, user.id):
        result = function(db, user.id, *args, **kwargs)
    return result


def page(entries, response):
    return {"data": [response.model_validate(row).model_dump(mode="json") for row in entries], "total": len(entries)}


def update_page(entries, group_by=None):
    result = page(entries, schema.UpdateResponse)
    if group_by == "date":
        groups = {}
        for entry in result["data"]:
            key = entry["published_at"][:10]
            groups.setdefault(key, []).append(entry)
        result["groups"] = [{"date": key, "data": data, "total": len(data)} for key, data in groups.items()]
    return result


@router.get("/preferences", response_model=schema.Preferences)
def get_preferences(db: Session = Depends(get_db), user=Depends(study_user)):
    return crud.get_preferences(db, user.id)


@router.put("/preferences", response_model=schema.Preferences)
def update_preferences(payload: schema.Preferences, db: Session = Depends(get_db), user=Depends(study_user)):
    return mutate(db, user, crud.update_preferences, payload)


@router.get("/lists", response_model=schema.Page)
def list_lists(archived: bool | None = None, db: Session = Depends(get_db), user=Depends(study_user)):
    return page(crud.list_lists(db, user.id, archived), schema.ListResponse)


@router.post("/lists", response_model=schema.ListResponse, status_code=201)
def create_list(payload: schema.ListCreate, db: Session = Depends(get_db), user=Depends(study_user)):
    return mutate(db, user, crud.create_list, payload)


@router.get("/lists/{list_id}", response_model=schema.ListResponse)
def get_list(list_id: RouteID, db: Session = Depends(get_db), user=Depends(study_user)):
    return crud.owned(db, StudyList, user.id, list_id)


@router.put("/lists/{list_id}", response_model=schema.ListResponse)
def update_list(list_id: RouteID, payload: schema.ListUpdate, db: Session = Depends(get_db), user=Depends(study_user)):
    return mutate(db, user, crud.update_list, list_id, payload)


@router.delete("/lists/{list_id}")
def delete_list(list_id: RouteID, db: Session = Depends(get_db), user=Depends(study_user)):
    return mutate(db, user, crud.delete_list, list_id)


@router.get("/items", response_model=schema.Page)
def list_items(
    list_id: int | None = Query(None, gt=0, le=2147483647), status: schema.Status | None = None,
    q: str | None = Query(None, max_length=500), sort: str = "sort_order", favorite: bool | None = None,
    source: schema.Source | None = None,
    db: Session = Depends(get_db), user=Depends(study_user),
):
    return page(crud.list_items(db, user.id, list_id, status, q, sort, favorite, source), schema.ItemResponse)


@router.post("/items", response_model=schema.ItemResponse, status_code=201)
def create_item(payload: schema.ItemCreate, db: Session = Depends(get_db), user=Depends(study_user)):
    return mutate(db, user, crud.create_item, payload)


@router.post("/items/reorder", response_model=schema.Page)
def reorder_items(payload: schema.Reorder, db: Session = Depends(get_db), user=Depends(study_user)):
    return page(mutate(db, user, crud.reorder_items, payload), schema.ItemResponse)


@router.post("/items/batch")
def batch_items(payload: schema.Batch, db: Session = Depends(get_db), user=Depends(study_user)):
    return mutate(db, user, crud.batch_items, payload)


@router.get("/items/{item_id}", response_model=schema.ItemResponse)
def get_item(item_id: RouteID, db: Session = Depends(get_db), user=Depends(study_user)):
    return crud.owned(db, StudyItem, user.id, item_id)


@router.put("/items/{item_id}", response_model=schema.ItemResponse)
def update_item(item_id: RouteID, payload: schema.ItemUpdate, db: Session = Depends(get_db), user=Depends(study_user)):
    return mutate(db, user, crud.update_item, item_id, payload)


@router.delete("/items/{item_id}")
def delete_item(item_id: RouteID, db: Session = Depends(get_db), user=Depends(study_user)):
    return mutate(db, user, crud.delete_item, item_id)


@router.get("/notes", response_model=schema.Page)
def list_notes(item_id: int | None = Query(None, gt=0, le=2147483647), db: Session = Depends(get_db), user=Depends(study_user)):
    return page(crud.list_notes(db, user.id, item_id), schema.NoteResponse)


@router.post("/notes", response_model=schema.NoteResponse, status_code=201)
def create_note(
    payload: schema.NoteCreate, item_id: int | None = Query(None, gt=0, le=2147483647),
    db: Session = Depends(get_db), user=Depends(study_user),
):
    if item_id is not None and item_id != payload.item_id:
        raise HTTPException(status_code=422, detail="Query and body item_id must match")
    return mutate(db, user, crud.create_note, payload)


@router.put("/notes/{note_id}", response_model=schema.NoteResponse)
def update_note(note_id: RouteID, payload: schema.NoteUpdate, db: Session = Depends(get_db), user=Depends(study_user)):
    return mutate(db, user, crud.update_note, note_id, payload)


@router.delete("/notes/{note_id}")
def delete_note(note_id: RouteID, db: Session = Depends(get_db), user=Depends(study_user)):
    return mutate(db, user, crud.delete_note, note_id)


@router.get("/focus", response_model=schema.Page)
def list_focus(item_id: int | None = Query(None, gt=0, le=2147483647), db: Session = Depends(get_db), user=Depends(study_user)):
    return page(crud.list_focus(db, user.id, item_id), schema.FocusResponse)


@router.post("/focus", response_model=schema.FocusResponse, status_code=201)
def create_focus(payload: schema.FocusCreate, db: Session = Depends(get_db), user=Depends(study_user)):
    return mutate(db, user, crud.create_focus, payload)


@router.get("/stats", response_model=schema.StatsResponse)
def stats(days: int = Query(30, ge=1, le=366), db: Session = Depends(get_db), user=Depends(study_user)):
    return crud.stats(db, user.id, days)


@router.get("/subscriptions", response_model=schema.Page)
def list_subscriptions(
    source: schema.SourceFilter | None = None, enabled: bool | None = None,
    db: Session = Depends(get_db), user=Depends(study_user),
):
    return page(crud.list_subscriptions(db, user.id, source, enabled), schema.SubscriptionResponse)


@router.post("/subscriptions", response_model=schema.SubscriptionResponse, status_code=201)
def create_subscription(payload: schema.SubscriptionCreate, db: Session = Depends(get_db), user=Depends(study_user)):
    return mutate(db, user, crud.create_subscription, payload)


@router.post("/subscriptions/batch")
def batch_subscriptions(payload: schema.SubscriptionBatch, db: Session = Depends(get_db), user=Depends(study_user)):
    return mutate(db, user, crud.batch_subscriptions, payload)


@router.put("/subscriptions/{subscription_id}", response_model=schema.SubscriptionResponse)
def update_subscription(
    subscription_id: RouteID, payload: schema.SubscriptionUpdate,
    db: Session = Depends(get_db), user=Depends(study_user),
):
    return mutate(db, user, crud.update_subscription, subscription_id, payload)


@router.delete("/subscriptions/{subscription_id}")
def delete_subscription(subscription_id: RouteID, db: Session = Depends(get_db), user=Depends(study_user)):
    return mutate(db, user, crud.delete_subscription, subscription_id)


@router.get("/updates", response_model=schema.UpdatePage, response_model_exclude_none=True)
def list_updates(
    subscription_id: int | None = Query(None, gt=0, le=2147483647), seen: bool | None = None, read: bool | None = None,
    source: schema.SourceFilter | None = None, date_from: date | None = None, date_to: date | None = None,
    group_by: Literal["date"] | None = None,
    db: Session = Depends(get_db), user=Depends(study_user),
):
    return update_page(mutate(db, user, crud.list_updates, subscription_id, seen, read, source, date_from, date_to), group_by)


@router.post("/updates/batch")
def batch_updates(payload: schema.UpdateBatch, db: Session = Depends(get_db), user=Depends(study_user)):
    return mutate(db, user, crud.batch_updates, payload)


@router.post("/updates", response_model=schema.Page)
def submit_updates(payload: schema.UpdatesSubmit, db: Session = Depends(get_db), user=Depends(study_user)):
    return page(mutate(db, user, crud.submit_updates, payload), schema.UpdateResponse)


@router.post("/updates/check", response_model=schema.Page)
def check_updates(
    subscription_id: int | None = Query(None, gt=0, le=2147483647),
    db: Session = Depends(get_db), user=Depends(study_user),
):
    return page(mutate(db, user, crud.list_updates, subscription_id), schema.UpdateResponse)


@router.put("/updates/{update_id}", response_model=schema.UpdateResponse)
def update_flags(update_id: RouteID, payload: schema.UpdateFlags, db: Session = Depends(get_db), user=Depends(study_user)):
    return mutate(db, user, crud.update_flags, update_id, payload)


@router.get("/export", response_model=schema.StudyArchive)
def export_data(db: Session = Depends(get_db), user=Depends(study_user)):
    return mutate(db, user, crud.export_data)


@router.post("/import")
def import_data(
    payload: schema.StudyArchive, mode: Literal["merge", "replace"] = "merge",
    db: Session = Depends(get_db), user=Depends(study_user),
):
    return mutate(db, user, crud.import_data, payload, mode)
