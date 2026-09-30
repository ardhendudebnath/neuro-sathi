"""Sathi's answering pipeline.

1. Local intents first (next medicine, date and time, "who is ...", today's
   plan). These are answered from the user's own rows and nothing leaves the
   server. Wording and the words Sathi listens for come from the user's
   language pack; the phone app ships the same packs so this also works offline.
2. Anything else goes to the LLM, if configured, under budget and the model
   supports the language, with safety checks on the question and the reply.
3. Otherwise a kind scripted fallback in the user's language.
"""

from dataclasses import dataclass
from datetime import datetime, timedelta, timezone

from .. import language_packs as lp
from ..models import MemoryBookEntry, Reminder

IST = timezone(timedelta(hours=5, minutes=30))  # India has no DST


def t(lang: str, key: str, **kw: str) -> str:
    return lp.answer(lang, key, **kw)


def fmt_time(tm, lang: str = lp.SOURCE) -> str:  # noqa: ANN001
    return lp.format_time(lang, tm.hour, tm.minute)


@dataclass
class LocalAnswer:
    text: str


def todays_remaining(reminders: list[Reminder], now: datetime) -> list[Reminder]:
    wd = now.weekday()
    return sorted(
        (r for r in reminders if r.active and not r.deleted and wd in r.days_of_week and r.time_of_day >= now.time()),
        key=lambda r: r.time_of_day,
    )


def next_medicine(reminders: list[Reminder], now: datetime) -> tuple[Reminder, int] | None:
    """(reminder, days_ahead) for the next active medication reminder within a week."""
    meds = [r for r in reminders if r.active and not r.deleted and r.kind == "medication"]
    for ahead in range(8):
        day = (now + timedelta(days=ahead)).weekday()
        todays = sorted(
            (r for r in meds if day in r.days_of_week and (ahead > 0 or r.time_of_day >= now.time())),
            key=lambda r: r.time_of_day,
        )
        if todays:
            return todays[0], ahead
    return None


def _words(text: str) -> set[str]:
    return {w for w in lp.tokens(text) if len(w) > 2}


def find_person(question: str, entries: list[MemoryBookEntry]) -> MemoryBookEntry | None:
    q = _words(question)
    best, best_score = None, 0
    for e in entries:
        if e.deleted:
            continue
        fields = _words(" ".join(filter(None, [e.person_name, e.relationship, e.title])))
        score = len(q & fields)
        if score > best_score:
            best, best_score = e, score
    return best


def answer_locally(
    question: str, lang: str, reminders: list[Reminder], entries: list[MemoryBookEntry], now: datetime | None = None
) -> LocalAnswer | None:
    now = now or datetime.now(IST)
    if lp.has_intent(question, lang, "medicine"):
        nxt = next_medicine(reminders, now)
        if nxt is None:
            return LocalAnswer(t(lang, "med_none"))
        r, ahead = nxt
        when = fmt_time(r.time_of_day, lang)
        if ahead > 0:
            when += ", " + lp.day_name(lang, (now.weekday() + ahead) % 7)
        return LocalAnswer(t(lang, "med_next", title=r.title, time=when))
    # Time before "who": "कौन सा दिन" (which day) contains "कौन" (who).
    if lp.has_intent(question, lang, "time"):
        return LocalAnswer(t(lang, "time", time=fmt_time(now.time(), lang), day=lp.day_name(lang, now.weekday())))
    if lp.has_intent(question, lang, "who"):
        e = find_person(question, entries)
        if e is None:
            return LocalAnswer(t(lang, "who_unknown"))
        name = e.person_name or e.title
        rel = e.relationship or t(lang, "family")
        if e.description:
            return LocalAnswer(t(lang, "who_desc", name=name, relationship=rel, description=e.description))
        return LocalAnswer(t(lang, "who", name=name, relationship=rel))
    if lp.has_intent(question, lang, "schedule"):
        items = todays_remaining(reminders, now)
        if not items:
            return LocalAnswer(t(lang, "today_none"))
        return LocalAnswer(t(lang, "today", items="; ".join(f"{fmt_time(r.time_of_day, lang)} {r.title}" for r in items)))
    return None
