"""Cognitive performance deviation detection.

Compares each user's last 7 days with their own baseline (the 28 days before
that). A metric is flagged only when the change is both statistically large
(beyond 2 standard deviations of the user's daily values) and practically large
(a minimum relative change), so normal day-to-day variation does not alert.
Alerts suggest a check-in; they never diagnose.
"""

from collections import defaultdict
from dataclasses import dataclass, field
from datetime import date, datetime, timedelta
from statistics import mean, pstdev

from ..models import ActivityLog, GameSession
from ..security import as_utc
from .sathi_engine import IST

RECENT_DAYS = 7
BASELINE_DAYS = 28
MIN_BASELINE_SESSIONS = 10
MIN_BASELINE_DAYS = 7
Z = 2.0


@dataclass
class Day:
    sessions: int = 0
    trials: int = 0
    correct: int = 0
    completed: int = 0
    repeated_errors: int = 0
    response_ms: list[float] = field(default_factory=list)
    reminders_done: int = 0
    reminders_missed: int = 0


@dataclass
class Finding:
    kind: str
    recent: float
    baseline: float
    detail: str


def daily(sessions: list[GameSession], activity: list[ActivityLog]) -> dict[date, Day]:
    days: dict[date, Day] = defaultdict(Day)
    for s in sessions:
        if s.deleted:
            continue
        d = days[as_utc(s.started_at).astimezone(IST).date()]
        d.sessions += 1
        d.trials += s.trials
        d.correct += s.correct
        d.completed += int(s.completed)
        d.repeated_errors += s.repeated_errors
        if s.avg_response_ms is not None:
            d.response_ms.append(s.avg_response_ms)
    for a in activity:
        if a.deleted:
            continue
        d = days[as_utc(a.occurred_at).astimezone(IST).date()]
        if a.kind == "reminder_done":
            d.reminders_done += 1
        elif a.kind == "reminder_missed":
            d.reminders_missed += 1
    return days


def _series(days: dict[date, Day], start: date, n: int, fn) -> list[float]:  # noqa: ANN001
    out = []
    for i in range(n):
        d = days.get(start + timedelta(days=i))
        v = fn(d) if d else None
        if v is not None:
            out.append(v)
    return out


def _acc(d: Day) -> float | None:
    return d.correct / d.trials if d.trials else None


def _resp(d: Day) -> float | None:
    return mean(d.response_ms) if d.response_ms else None


def _completion(d: Day) -> float | None:
    return d.completed / d.sessions if d.sessions else None


def _rep_err(d: Day) -> float | None:
    return d.repeated_errors / d.trials if d.trials else None


def detect(sessions: list[GameSession], activity: list[ActivityLog], now: datetime) -> list[Finding]:
    days = daily(sessions, activity)
    today = as_utc(now).astimezone(IST).date()
    recent_start = today - timedelta(days=RECENT_DAYS - 1)
    base_start = recent_start - timedelta(days=BASELINE_DAYS)

    base_sessions = sum(days[d].sessions for d in list(days) if base_start <= d < recent_start)
    base_active_days = sum(1 for d in days if base_start <= d < recent_start and days[d].sessions)
    if base_sessions < MIN_BASELINE_SESSIONS or base_active_days < MIN_BASELINE_DAYS:
        return []  # not enough history for a fair personal baseline

    findings: list[Finding] = []

    def compare(kind, fn, higher_is_worse, min_rel, fmt, detail):  # noqa: ANN001
        base = _series(days, base_start, BASELINE_DAYS, fn)
        rec = _series(days, recent_start, RECENT_DAYS, fn)
        if len(base) < MIN_BASELINE_DAYS or len(rec) < 2:
            return
        b, r, sd = mean(base), mean(rec), pstdev(base)
        if b == 0:
            return
        change = (r - b) / b if higher_is_worse else (b - r) / b
        z = abs(r - b) / sd if sd > 0 else float("inf")
        if change >= min_rel and z >= Z:
            findings.append(Finding(kind, round(r, 3), round(b, 3), detail.format(r=fmt(r), b=fmt(b))))

    secs = lambda v: f"{v / 1000:.1f}s"  # noqa: E731
    pct = lambda v: f"{v * 100:.0f}%"  # noqa: E731
    compare("slower_responses", _resp, True, 0.20, secs, "Answers have been slower this week ({r} on average, usually {b}).")
    compare("lower_accuracy", _acc, False, 0.15, pct, "Fewer correct answers this week ({r}, usually {b}).")
    compare("lower_completion", _completion, False, 0.20, pct, "Fewer activities finished this week ({r}, usually {b}).")
    compare("more_repeated_errors", _rep_err, True, 0.50, pct, "The same mistakes are repeating more often ({r}, usually {b}).")

    # Reduced activity: compare sessions per calendar day, counting inactive days as zero.
    base_rate = base_sessions / BASELINE_DAYS
    recent_rate = sum(days[d].sessions for d in days if d >= recent_start) / RECENT_DAYS
    if base_rate >= 0.5 and recent_rate <= base_rate * 0.5:
        findings.append(
            Finding(
                "less_activity",
                round(recent_rate, 2),
                round(base_rate, 2),
                f"Much less activity this week ({recent_rate:.1f} sessions a day, usually {base_rate:.1f}).",
            )
        )
    return findings


def severity(findings: list[Finding]) -> str:
    return "check_in" if len(findings) >= 2 else "watch"


def alert_message(findings: list[Finding]) -> str:
    lines = " ".join(f.detail for f in findings)
    advice = (
        "A friendly check-in is recommended. If the changes continue, consider asking a doctor for an evaluation."
        if len(findings) >= 2
        else "This may be a passing change; a friendly check-in is a good idea."
    )
    return f"{lines} {advice} (This is not a diagnosis.)"
