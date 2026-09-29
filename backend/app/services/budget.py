"""Global monthly budget cap on paid APIs. Once spending crosses the cap, Sathi
switches to offline answers and speech routes return 503 so the app uses on-device voice.

Uses the request's own session. api_spend holds only aggregate counters (no user data)."""

from datetime import UTC, datetime

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from ..config import get_settings
from ..models import ApiSpend


def _month() -> str:
    return datetime.now(UTC).strftime("%Y-%m")


def spent_this_month(db: Session) -> float:
    return float(db.scalar(select(func.coalesce(func.sum(ApiSpend.amount_inr), 0.0)).where(ApiSpend.month == _month())))


def over_budget(db: Session) -> bool:
    return spent_this_month(db) >= get_settings().paid_api_monthly_budget_inr


def record_spend(db: Session, provider: str, amount_inr: float) -> None:
    row = db.get(ApiSpend, (_month(), provider), with_for_update=True)
    if row is None:
        db.add(ApiSpend(month=_month(), provider=provider, calls=1, amount_inr=amount_inr))
    else:
        row.calls += 1
        row.amount_inr += amount_inr
    db.flush()
