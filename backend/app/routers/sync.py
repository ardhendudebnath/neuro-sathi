"""Offline-first sync.

1. The app sends its queued changes in a batch with a client-generated batch_id.
2. Each record is upserted by id; conflicts are resolved by the latest updated_at,
   except that a caregiver's memory-book edit the device has not yet seen wins.
3. The server recomputes recommendations and returns memory-book entries,
   reminders and recommendations changed since the device's last sync.
4. The app clears the batch from its queue only after this response arrives; a
   retried batch_id is recognised and not applied twice.
"""

from datetime import UTC, datetime, timedelta
from typing import Annotated

from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from ..deps import Actor, DbDep, require_roles
from ..models import (
    CARE_ROLES,
    ActivityLog,
    Game,
    GameSession,
    MemoryBookEntry,
    Recommendation,
    Reminder,
    Role,
    SyncBatch,
)
from ..ratelimit import RateLimit
from ..schemas import MemoryBookOut, RecommendationOut, ReminderOut, SyncRequest, SyncResponse
from ..security import as_utc
from ..services.personalisation import recommend

router = APIRouter(tags=["sync"])
ElderlyUser = Annotated[Actor, Depends(require_roles(Role.user))]
MAX_CLOCK_SKEW = timedelta(minutes=5)


def _apply(db: Session, model, items, actor: Actor, since: datetime | None, now: datetime, rejected: list) -> set:  # noqa: ANN001
    applied = set()
    for item in items:
        data = item.model_dump()
        data["updated_at"] = min(as_utc(item.updated_at), now + MAX_CLOCK_SKEW)
        existing = db.get(model, item.id)
        if existing is None:
            row = model(**data, user_id=actor.id)
            if model in (MemoryBookEntry, Reminder):
                row.created_by = actor.id
            if model is MemoryBookEntry:
                row.updated_by_role = Role.user
            try:
                # Savepoint: on PostgreSQL, RLS hides other users' rows, so an id that
                # belongs to someone else shows up here as a primary-key clash.
                with db.begin_nested():
                    db.add(row)
            except IntegrityError:
                rejected.append({"table": model.__tablename__, "id": str(item.id), "reason": "not_yours"})
                continue
            applied.add(item.id)
            continue
        if existing.user_id != actor.id:
            rejected.append({"table": model.__tablename__, "id": str(item.id), "reason": "not_yours"})
            continue
        if (
            model is MemoryBookEntry
            and existing.updated_by_role in CARE_ROLES
            and (since is None or as_utc(existing.updated_at) > since)  # strictly after the device's last sync
        ):
            rejected.append({"table": model.__tablename__, "id": str(item.id), "reason": "caregiver_edit_wins"})
            continue
        if data["updated_at"] <= as_utc(existing.updated_at):
            rejected.append({"table": model.__tablename__, "id": str(item.id), "reason": "server_newer"})
            continue
        for k, v in data.items():
            if k != "id":
                setattr(existing, k, v)
        if model is MemoryBookEntry:
            existing.updated_by_role = Role.user
        applied.add(item.id)
    return applied


def refresh_recommendations(db: Session, user_id, now: datetime) -> list[Recommendation]:  # noqa: ANN001
    games = list(db.scalars(select(Game).where(Game.active.is_(True))))
    sessions = list(
        db.scalars(select(GameSession).where(GameSession.user_id == user_id, GameSession.started_at >= now - timedelta(days=90)))
    )
    for old in db.scalars(select(Recommendation).where(Recommendation.user_id == user_id)):
        db.delete(old)
    db.flush()
    rows = [Recommendation(user_id=user_id, updated_at=now, **r) for r in recommend(games, sessions, now)]
    db.add_all(rows)
    return rows


@router.post("/sync", response_model=SyncResponse, dependencies=[Depends(RateLimit("sync"))])
def sync(body: SyncRequest, actor: ElderlyUser, db: DbDep) -> SyncResponse:
    now = datetime.now(UTC)
    since = as_utc(body.since)
    rejected: list[dict] = []
    applied_ids: set = set()

    prior = db.get(SyncBatch, body.batch_id)
    if prior is not None and prior.user_id == actor.id:
        applied_count = prior.result.get("applied", 0)
        rejected = prior.result.get("rejected", [])
    else:
        c = body.changes
        for model, items in (
            (GameSession, c.game_sessions),
            (ActivityLog, c.activity_log),
            (MemoryBookEntry, c.memory_book),
            (Reminder, c.reminders),
        ):
            applied_ids |= _apply(db, model, items, actor, since, now, rejected)
        applied_count = len(applied_ids)
        db.add(SyncBatch(batch_id=body.batch_id, user_id=actor.id, result={"applied": applied_count, "rejected": rejected}))
        db.flush()

    recs = refresh_recommendations(db, actor.id, now) if (applied_ids or since is None) else list(
        db.scalars(select(Recommendation).where(Recommendation.user_id == actor.id))
    )

    def changed(model):  # noqa: ANN001, ANN202
        q = select(model).where(model.user_id == actor.id)
        # >= not >: an edit in the same clock tick as the last server_time must still be sent.
        q = q.where(model.updated_at >= since) if since else q.where(model.deleted.is_(False))
        return [r for r in db.scalars(q) if r.id not in applied_ids]

    return SyncResponse(
        batch_id=body.batch_id,
        applied=applied_count,
        rejected=rejected,
        server_time=now,
        memory_book=[MemoryBookOut.model_validate(r) for r in changed(MemoryBookEntry)],
        reminders=[ReminderOut.model_validate(r) for r in changed(Reminder)],
        recommendations=[RecommendationOut.model_validate(r) for r in sorted(recs, key=lambda r: r.rank)],
    )
