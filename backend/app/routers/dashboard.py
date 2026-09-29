"""Caregiver and health-worker dashboard: trends and alerts against each user's
own baseline. Shows understandable trends; never a diagnosis. Every view of
another person's data is written to the audit log."""

from datetime import UTC, datetime, timedelta
from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import func, select

from ..audit import record_audit
from ..deps import Actor, ActorDep, DbDep, assert_can_access, require_roles
from ..models import ActivityLog, Alert, CaregiverLink, GameSession, Recommendation, Role, User, utcnow
from ..ratelimit import RateLimit
from ..schemas import AlertOut, DailyTrend, LinkedUserSummary, RecommendationOut, UserOut
from ..services.deviation import daily
from ..services.sathi_engine import IST

router = APIRouter(prefix="/dashboard", tags=["dashboard"])
READ = [Depends(RateLimit("read"))]
CareActor = Annotated[Actor, Depends(require_roles(Role.caregiver, Role.health_worker))]


@router.get("/users", response_model=list[LinkedUserSummary], dependencies=READ)
def linked_users(actor: CareActor, db: DbDep) -> list[LinkedUserSummary]:
    week_ago = datetime.now(UTC) - timedelta(days=7)
    out = []
    links = db.scalars(select(CaregiverLink).where(CaregiverLink.caregiver_id == actor.id, CaregiverLink.active.is_(True)))
    for link in links:
        user = db.get(User, link.user_id)
        if user is None:
            continue
        last_session = db.scalar(select(func.max(GameSession.started_at)).where(GameSession.user_id == user.id))
        last_activity = db.scalar(select(func.max(ActivityLog.occurred_at)).where(ActivityLog.user_id == user.id))
        last = max((d for d in (last_session, last_activity) if d is not None), default=None)
        out.append(
            LinkedUserSummary(
                user=UserOut.model_validate(user),
                relationship=link.relationship,
                last_active=last,
                sessions_7d=db.scalar(
                    select(func.count()).where(GameSession.user_id == user.id, GameSession.started_at >= week_ago)
                )
                or 0,
                open_alerts=db.scalar(
                    select(func.count()).where(Alert.user_id == user.id, Alert.acknowledged_at.is_(None))
                )
                or 0,
            )
        )
    record_audit(db, actor.id, "view_dashboard")
    return out


@router.get("/users/{user_id}/trends", response_model=list[DailyTrend], dependencies=READ)
def trends(user_id: UUID, actor: ActorDep, db: DbDep, days: Annotated[int, Query(ge=7, le=180)] = 30) -> list[DailyTrend]:
    assert_can_access(db, actor, user_id)
    start = datetime.now(IST).date() - timedelta(days=days - 1)
    since = datetime.combine(start, datetime.min.time(), IST).astimezone(UTC)
    sessions = list(db.scalars(select(GameSession).where(GameSession.user_id == user_id, GameSession.started_at >= since)))
    activity = list(db.scalars(select(ActivityLog).where(ActivityLog.user_id == user_id, ActivityLog.occurred_at >= since)))
    by_day = daily(sessions, activity)
    if actor.id != user_id:
        record_audit(db, actor.id, "view_trends", user_id, days=days)
    out = []
    for i in range(days):
        d = start + timedelta(days=i)
        x = by_day.get(d)
        if x is None:
            out.append(
                DailyTrend(
                    day=d, sessions=0, completion_rate=None, accuracy=None, avg_response_ms=None, reminders_done=0, reminders_missed=0
                )
            )
            continue
        out.append(
            DailyTrend(
                day=d,
                sessions=x.sessions,
                completion_rate=round(x.completed / x.sessions, 3) if x.sessions else None,
                accuracy=round(x.correct / x.trials, 3) if x.trials else None,
                avg_response_ms=round(sum(x.response_ms) / len(x.response_ms), 1) if x.response_ms else None,
                reminders_done=x.reminders_done,
                reminders_missed=x.reminders_missed,
            )
        )
    return out


@router.get("/users/{user_id}/alerts", response_model=list[AlertOut], dependencies=READ)
def user_alerts(user_id: UUID, actor: ActorDep, db: DbDep, include_acknowledged: bool = False) -> list[Alert]:
    assert_can_access(db, actor, user_id)
    q = select(Alert).where(Alert.user_id == user_id)
    if not include_acknowledged:
        q = q.where(Alert.acknowledged_at.is_(None))
    if actor.id != user_id:
        record_audit(db, actor.id, "view_alerts", user_id)
    return list(db.scalars(q.order_by(Alert.created_at.desc()).limit(100)))


@router.get("/users/{user_id}/recommendations", response_model=list[RecommendationOut], dependencies=READ)
def user_recommendations(user_id: UUID, actor: ActorDep, db: DbDep) -> list[Recommendation]:
    assert_can_access(db, actor, user_id)
    return list(db.scalars(select(Recommendation).where(Recommendation.user_id == user_id).order_by(Recommendation.rank)))


@router.post("/alerts/{alert_id}/ack", response_model=AlertOut, dependencies=[Depends(RateLimit("default"))])
def acknowledge(alert_id: UUID, actor: CareActor, db: DbDep) -> Alert:
    alert = db.get(Alert, alert_id)
    if alert is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Not found")
    assert_can_access(db, actor, alert.user_id)
    alert.acknowledged_at, alert.acknowledged_by = utcnow(), actor.id
    record_audit(db, actor.id, "ack_alert", alert.user_id, alert_id=str(alert_id))
    return alert
