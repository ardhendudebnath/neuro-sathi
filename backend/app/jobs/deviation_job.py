"""Scheduled deviation check. Run daily (docker-compose `worker` service, or cron):

    python -m app.jobs.deviation_job            # once
    python -m app.jobs.deviation_job --every 24h

Uses the service role because it reads across users; it only writes alerts.
"""

import argparse
import logging
import time
from datetime import UTC, datetime, timedelta

from sqlalchemy import select

from ..db import service_session
from ..models import ActivityLog, Alert, CaregiverLink, DeviceToken, GameSession, Role, User
from ..services import push
from ..services.deviation import BASELINE_DAYS, RECENT_DAYS, alert_message, detect, severity

log = logging.getLogger("neuro_sathi.deviation_job")
DEDUPE_DAYS = 7


def run_once(now: datetime | None = None) -> int:
    now = now or datetime.now(UTC)
    since = now - timedelta(days=RECENT_DAYS + BASELINE_DAYS + 1)
    created = 0
    with service_session() as db:
        user_ids = list(db.scalars(select(User.id).where(User.role == Role.user)))
    for uid in user_ids:
        with service_session() as db:
            sessions = list(db.scalars(select(GameSession).where(GameSession.user_id == uid, GameSession.started_at >= since)))
            activity = list(db.scalars(select(ActivityLog).where(ActivityLog.user_id == uid, ActivityLog.occurred_at >= since)))
            findings = detect(sessions, activity, now)
            if not findings:
                continue
            recent_kinds = set(
                db.scalars(
                    select(Alert.kind).where(Alert.user_id == uid, Alert.created_at >= now - timedelta(days=DEDUPE_DAYS))
                )
            )
            kind = "+".join(sorted(f.kind for f in findings))
            if kind in recent_kinds:
                continue
            db.add(
                Alert(
                    user_id=uid,
                    kind=kind,
                    severity=severity(findings),
                    message=alert_message(findings),
                    metrics={f.kind: {"recent": f.recent, "baseline": f.baseline} for f in findings},
                    created_at=now,
                )
            )
            created += 1
            caregivers = select(CaregiverLink.caregiver_id).where(CaregiverLink.user_id == uid, CaregiverLink.active.is_(True))
            tokens = list(db.scalars(select(DeviceToken.token).where(DeviceToken.user_id.in_(caregivers))))
            name = db.get(User, uid).name or "Your family member"
        push.send(tokens, "NEURO-SATHI check-in suggested", f"{name}: some changes this week. Open the dashboard for details.")
    log.info("deviation job: %d users checked, %d alerts created", len(user_ids), created)
    return created


def _parse_every(s: str) -> int:
    unit = {"m": 60, "h": 3600, "d": 86400}[s[-1]]
    return int(s[:-1]) * unit


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--every", help="repeat interval, e.g. 24h")
    args = p.parse_args()
    while True:
        try:
            run_once()
        except Exception:  # noqa: BLE001 - keep the worker alive; the next run retries
            log.exception("deviation job failed")
        if not args.every:
            break
        time.sleep(_parse_every(args.every))
