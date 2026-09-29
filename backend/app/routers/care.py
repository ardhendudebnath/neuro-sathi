"""Memory book and reminders for one elderly user, managed by the user or a
linked caregiver / health worker (used by the dashboard). The phone app itself
writes through /sync."""

import uuid
from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, File, HTTPException, Query, UploadFile, status
from fastapi.responses import FileResponse, RedirectResponse
from sqlalchemy import select

from ..audit import record_audit
from ..config import get_settings
from ..deps import ActorDep, DbDep, assert_can_access
from ..models import MemoryBookEntry, Reminder, utcnow
from ..ratelimit import RateLimit
from ..schemas import (
    MemoryBookFields,
    MemoryBookOut,
    MemoryBookPatch,
    ReminderFields,
    ReminderOut,
    ReminderPatch,
)
from ..services import storage

router = APIRouter(prefix="/users/{user_id}", tags=["care"])
READ = [Depends(RateLimit("read"))]
WRITE = [Depends(RateLimit("default"))]


class MemoryBookCreate(MemoryBookFields):
    photo_key: str | None = None


def _check_photo_key(key: str | None, user_id: UUID) -> None:
    if key is not None and storage.key_owner(key) != user_id:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Photo does not belong to this memory book")


# --- memory book --------------------------------------------------------------------------


@router.get("/memory-book", response_model=list[MemoryBookOut], dependencies=READ)
def list_memory_book(user_id: UUID, actor: ActorDep, db: DbDep) -> list[MemoryBookEntry]:
    assert_can_access(db, actor, user_id)
    if actor.id != user_id:
        record_audit(db, actor.id, "view_memory_book", user_id)
    return list(
        db.scalars(
            select(MemoryBookEntry)
            .where(MemoryBookEntry.user_id == user_id, MemoryBookEntry.deleted.is_(False))
            .order_by(MemoryBookEntry.updated_at.desc())
        )
    )


@router.post("/memory-book", response_model=MemoryBookOut, status_code=201, dependencies=WRITE)
def add_memory(user_id: UUID, body: MemoryBookCreate, actor: ActorDep, db: DbDep) -> MemoryBookEntry:
    assert_can_access(db, actor, user_id)
    _check_photo_key(body.photo_key, user_id)
    entry = MemoryBookEntry(
        id=uuid.uuid4(), user_id=user_id, created_by=actor.id, updated_by_role=actor.role, updated_at=utcnow(), **body.model_dump()
    )
    db.add(entry)
    db.flush()
    record_audit(db, actor.id, "add_memory", user_id, entry_id=str(entry.id))
    return entry


def _entry(db, user_id: UUID, entry_id: UUID) -> MemoryBookEntry:  # noqa: ANN001
    entry = db.get(MemoryBookEntry, entry_id)
    if entry is None or entry.user_id != user_id or entry.deleted:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Not found")
    return entry


@router.patch("/memory-book/{entry_id}", response_model=MemoryBookOut, dependencies=WRITE)
def edit_memory(user_id: UUID, entry_id: UUID, body: MemoryBookPatch, actor: ActorDep, db: DbDep) -> MemoryBookEntry:
    assert_can_access(db, actor, user_id)
    entry = _entry(db, user_id, entry_id)
    changes = body.model_dump(exclude_unset=True)
    _check_photo_key(changes.get("photo_key"), user_id)
    for k, v in changes.items():
        setattr(entry, k, v)
    entry.updated_at, entry.updated_by_role = utcnow(), actor.role
    record_audit(db, actor.id, "edit_memory", user_id, entry_id=str(entry_id))
    return entry


@router.delete("/memory-book/{entry_id}", status_code=204, dependencies=WRITE)
def delete_memory(user_id: UUID, entry_id: UUID, actor: ActorDep, db: DbDep) -> None:
    assert_can_access(db, actor, user_id)
    entry = _entry(db, user_id, entry_id)
    entry.deleted, entry.updated_at, entry.updated_by_role = True, utcnow(), actor.role  # tombstone, synced to the phone
    record_audit(db, actor.id, "delete_memory", user_id, entry_id=str(entry_id))


@router.post("/memory-book/upload", dependencies=[Depends(RateLimit("upload"))])
async def upload_photo(user_id: UUID, actor: ActorDep, db: DbDep, file: UploadFile = File(...)) -> dict:
    assert_can_access(db, actor, user_id)
    limit = get_settings().max_upload_bytes
    data = await file.read(limit + 1)
    if len(data) > limit:
        raise HTTPException(status.HTTP_413_CONTENT_TOO_LARGE, "Photo must be 10 MB or smaller")
    ctype = storage.sniff_image_type(data[:16])
    if ctype is None:
        raise HTTPException(status.HTTP_415_UNSUPPORTED_MEDIA_TYPE, "Only JPEG, PNG or WebP photos")
    key = storage.new_photo_key(user_id, ctype)
    storage.put_object(key, data, ctype)
    record_audit(db, actor.id, "upload_photo", user_id, key=key)
    return {"photo_key": key}


@router.get("/memory-book/{entry_id}/photo", dependencies=READ)
def photo_url(user_id: UUID, entry_id: UUID, actor: ActorDep, db: DbDep, redirect: bool = False):  # noqa: ANN201
    """Short-lived signed URL, issued only after the ownership check."""
    assert_can_access(db, actor, user_id)
    entry = _entry(db, user_id, entry_id)
    if not entry.photo_key:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "No photo")
    url = storage.signed_url(entry.photo_key)
    return RedirectResponse(url) if redirect else {"url": url, "expires_in": get_settings().signed_url_seconds}


# --- reminders --------------------------------------------------------------------------------


@router.get("/reminders", response_model=list[ReminderOut], dependencies=READ)
def list_reminders(user_id: UUID, actor: ActorDep, db: DbDep) -> list[Reminder]:
    assert_can_access(db, actor, user_id)
    return list(
        db.scalars(select(Reminder).where(Reminder.user_id == user_id, Reminder.deleted.is_(False)).order_by(Reminder.time_of_day))
    )


@router.post("/reminders", response_model=ReminderOut, status_code=201, dependencies=WRITE)
def add_reminder(user_id: UUID, body: ReminderFields, actor: ActorDep, db: DbDep) -> Reminder:
    assert_can_access(db, actor, user_id)
    r = Reminder(id=uuid.uuid4(), user_id=user_id, created_by=actor.id, updated_at=utcnow(), **body.model_dump())
    db.add(r)
    db.flush()
    record_audit(db, actor.id, "add_reminder", user_id, reminder_id=str(r.id))
    return r


def _reminder(db, user_id: UUID, rid: UUID) -> Reminder:  # noqa: ANN001
    r = db.get(Reminder, rid)
    if r is None or r.user_id != user_id or r.deleted:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Not found")
    return r


@router.patch("/reminders/{reminder_id}", response_model=ReminderOut, dependencies=WRITE)
def edit_reminder(user_id: UUID, reminder_id: UUID, body: ReminderPatch, actor: ActorDep, db: DbDep) -> Reminder:
    assert_can_access(db, actor, user_id)
    r = _reminder(db, user_id, reminder_id)
    changes = body.model_dump(exclude_unset=True)
    if "days_of_week" in changes:
        changes["days_of_week"] = ReminderFields.model_validate(
            {"kind": r.kind, "title": r.title, "time_of_day": r.time_of_day, "days_of_week": changes["days_of_week"]}
        ).days_of_week
    for k, v in changes.items():
        setattr(r, k, v)
    r.updated_at = utcnow()
    record_audit(db, actor.id, "edit_reminder", user_id, reminder_id=str(reminder_id))
    return r


@router.delete("/reminders/{reminder_id}", status_code=204, dependencies=WRITE)
def delete_reminder(user_id: UUID, reminder_id: UUID, actor: ActorDep, db: DbDep) -> None:
    assert_can_access(db, actor, user_id)
    r = _reminder(db, user_id, reminder_id)
    r.deleted, r.updated_at = True, utcnow()
    record_audit(db, actor.id, "delete_reminder", user_id, reminder_id=str(reminder_id))


# --- signed local files (development storage backend only) ------------------------------------

files_router = APIRouter(tags=["files"])


@files_router.get("/files/{key:path}", dependencies=READ)
def serve_file(key: str, expires: Annotated[int, Query()], sig: Annotated[str, Query()]) -> FileResponse:
    if get_settings().storage_backend != "local" or not storage.verify_local_signature(key, expires, sig):
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Link expired")
    try:
        path = storage.local_path(key)
    except ValueError:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Not found") from None
    if not path.is_file():
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Not found")
    return FileResponse(path, headers={"Cache-Control": "private, max-age=60"})
