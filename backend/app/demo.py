"""Demo data for trying the app on a phone. Development and testing only.

    python -m app.demo --phone 9876543210
    python -m app.demo --phone 9876543210 --caregiver-phone 9876500000
    python -m app.demo --phone 9876543210 --remind-in 5     # add another reminder
    python -m app.demo --phone 9876543210 --end-sessions    # test "sign in again"

Creates (or reuses) the elderly user with that number, adds three people to
their memory book (once), and adds a daily "test medicine" reminder due a few
minutes from now, so you can watch it ring with the app closed. Sign in on the
phone with the same number; with OTP_DEV_ECHO=true the code is shown on screen.
See docs/testing-on-a-phone.md.
"""

import argparse
import uuid
from datetime import UTC, datetime, timedelta

from sqlalchemy import select, update

from .config import get_settings
from .db import service_session, user_session
from .models import CaregiverLink, MemoryBookEntry, Profile, RefreshToken, Reminder, Role, User, utcnow
from .security import normalise_phone
from .services.sathi_engine import IST

PEOPLE = [
    ("Rina", "granddaughter", "She studies in Guwahati and calls every Sunday."),
    ("Bipul", "son", None),
    ("Mala", "daughter", "She lives in Jorhat."),
]


def _ensure_user(phone: str, role: Role, name: str) -> uuid.UUID:
    with service_session() as db:
        user = db.scalar(select(User).where(User.phone == phone))
        if user is None:
            user = User(phone=phone, role=role, name=name)
            db.add(user)
            db.flush()
            db.add(Profile(user_id=user.id))
        return user.id


def seed_demo(phone: str, caregiver_phone: str | None = None, remind_in: int = 3, now: datetime | None = None) -> dict:
    """Returns what was created, for printing."""
    if get_settings().is_production:
        raise SystemExit("Demo data is for development and testing only.")
    phone = normalise_phone(phone)
    user_id = _ensure_user(phone, Role.user, "Demo user")
    added_by = user_id
    if caregiver_phone:
        carer_id = _ensure_user(normalise_phone(caregiver_phone), Role.caregiver, "Demo caregiver")
        with service_session() as db:
            link = db.scalar(select(CaregiverLink).where(CaregiverLink.user_id == user_id, CaregiverLink.caregiver_id == carer_id))
            if link is None:
                db.add(CaregiverLink(user_id=user_id, caregiver_id=carer_id, relationship="son"))
            else:
                link.active = True
        added_by = carer_id

    due = ((now or datetime.now(IST)).astimezone(IST) + timedelta(minutes=remind_in)).time().replace(second=0, microsecond=0)
    # Written as the user, through row-level security, exactly as the dashboard or the phone would.
    with user_session(user_id, Role.user.value) as db:
        known = {e.person_name for e in db.scalars(select(MemoryBookEntry).where(MemoryBookEntry.user_id == user_id))}
        people = [p for p in PEOPLE if p[0] not in known]
        for name, relationship, description in people:
            db.add(
                MemoryBookEntry(
                    id=uuid.uuid4(), user_id=user_id, created_by=added_by, updated_by_role=Role.caregiver, kind="person",
                    title=name, person_name=name, relationship=relationship, description=description, updated_at=utcnow(),
                )
            )
        db.add(
            Reminder(
                id=uuid.uuid4(), user_id=user_id, created_by=added_by, kind="medication", title="Test medicine",
                time_of_day=due, days_of_week=[0, 1, 2, 3, 4, 5, 6], note="Demo reminder", updated_at=utcnow(),
            )
        )
    return {"phone": phone, "user_id": str(user_id), "people_added": [p[0] for p in people], "reminder_at": due.strftime("%H:%M")}


def end_sessions(phone: str) -> int:
    """Revoke every session of this account, to try the "sign in again" flow. The
    phone notices once its current access token runs out (within the hour)."""
    with service_session() as db:
        user = db.scalar(select(User).where(User.phone == normalise_phone(phone)))
        if user is None:
            return 0
        result = db.execute(
            update(RefreshToken)
            .where(RefreshToken.user_id == user.id, RefreshToken.revoked_at.is_(None))
            .values(revoked_at=datetime.now(UTC))
        )
        return result.rowcount or 0


if __name__ == "__main__":
    p = argparse.ArgumentParser(description="Demo data for trying the app on a phone (development only).")
    p.add_argument("--phone", required=True, help="the elderly user's mobile number")
    p.add_argument("--caregiver-phone", help="also create a caregiver linked to them")
    p.add_argument("--remind-in", type=int, default=3, help="minutes until the test reminder (default 3)")
    p.add_argument("--end-sessions", action="store_true", help="sign this account out everywhere instead")
    args = p.parse_args()
    if args.end_sessions:
        print(f"ended {end_sessions(args.phone)} session(s)")
    else:
        out = seed_demo(args.phone, args.caregiver_phone, args.remind_in)
        print(f"user {out['phone']} ({out['user_id']})")
        print(f"memory book: {', '.join(out['people_added']) or 'already there'}")
        print(f"test reminder at {out['reminder_at']} India time, daily")
