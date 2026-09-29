"""Sathi's answering pipeline.

1. Local intents first (schedule, next medicine, "who is ...", date and time).
   These are answered from the user's own rows and nothing leaves the server.
   The phone app ships the same intents so they also work offline.
2. Anything else goes to the LLM, if configured and under budget, with safety
   checks on the question and on the reply.
3. Otherwise a kind scripted fallback.
"""

import re
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone

from ..models import MemoryBookEntry, Reminder

IST = timezone(timedelta(hours=5, minutes=30))  # India has no DST

T = {
    "en": {
        "today_none": "You have nothing scheduled for the rest of today. Enjoy your day!",
        "today": "Here is the rest of today: {items}.",
        "med_none": "I don't have any medicine reminders for you. Please ask your family if you are unsure.",
        "med_next": "Your next medicine is {title} at {time}.",
        "who": "{name} is your {relationship}.",
        "who_desc": "{name} is your {relationship}. {description}",
        "who_unknown": "I'm not sure who that is. Let's look at your memory book together, or ask your family.",
        "time": "It is {time} on {day}.",
        "fallback": "I'm here with you. I can tell you today's plan, your next medicine, or about the people in your memory book.",
        "blocked": "Let's talk about something else. If you need help, please call your family or a doctor.",
    },
    "hi": {
        "today_none": "आज के लिए और कुछ तय नहीं है। अपना दिन अच्छे से बिताइए!",
        "today": "आज का बाकी कार्यक्रम: {items}।",
        "med_none": "आपकी दवा का कोई रिमाइंडर नहीं है। संदेह हो तो परिवार से पूछिए।",
        "med_next": "आपकी अगली दवा {title} है, {time} बजे।",
        "who": "{name} आपके {relationship} हैं।",
        "who_desc": "{name} आपके {relationship} हैं। {description}",
        "who_unknown": "मुझे पक्का नहीं पता वह कौन हैं। चलिए मेमोरी बुक देखते हैं, या परिवार से पूछिए।",
        "time": "अभी {day}, {time} बजे हैं।",
        "fallback": "मैं आपके साथ हूँ। मैं आज का कार्यक्रम, अगली दवा, या मेमोरी बुक के लोगों के बारे में बता सकता हूँ।",
        "blocked": "चलिए किसी और बात पर बात करते हैं। मदद चाहिए तो परिवार या डॉक्टर को फोन कीजिए।",
    },
}
DAYS = {
    "en": ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"],
    "hi": ["सोमवार", "मंगलवार", "बुधवार", "गुरुवार", "शुक्रवार", "शनिवार", "रविवार"],
}

_SCHEDULE = re.compile(r"\b(today|schedule|plan|aaj|karyakram)\b|आज|कार्यक्रम", re.I)
_MEDICINE = re.compile(r"\b(medicine|medication|tablet|pill|dawa|dawai)\b|दवा|दवाई|गोली", re.I)
_WHO = re.compile(r"\bwho\s+is\b|\bkaun\b|कौन", re.I)
_TIME = re.compile(r"\b(what\s+(time|day)|which\s+day|samay|din)\b|समय|कौन सा दिन|क्या दिन", re.I)


def t(lang: str, key: str, **kw: str) -> str:
    return T.get(lang, T["en"]).get(key, T["en"][key]).format(**kw)


def fmt_time(tm) -> str:  # noqa: ANN001
    return tm.strftime("%I:%M %p").lstrip("0")


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
    # Split on spaces/punctuation rather than \w: Devanagari vowel signs are not \w.
    return {w for w in re.findall(r"[^\s.,!?।\"'()\-]+", text.lower()) if len(w) > 2}


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
    if _MEDICINE.search(question):
        nxt = next_medicine(reminders, now)
        if nxt is None:
            return LocalAnswer(t(lang, "med_none"))
        r, ahead = nxt
        when = fmt_time(r.time_of_day)
        if ahead > 0:
            when += ", " + DAYS.get(lang, DAYS["en"])[(now.weekday() + ahead) % 7]
        return LocalAnswer(t(lang, "med_next", title=r.title, time=when))
    if _WHO.search(question):
        e = find_person(question, entries)
        if e is None:
            return LocalAnswer(t(lang, "who_unknown"))
        name = e.person_name or e.title
        rel = e.relationship or ("family" if lang == "en" else "परिवार")
        if e.description:
            return LocalAnswer(t(lang, "who_desc", name=name, relationship=rel, description=e.description))
        return LocalAnswer(t(lang, "who", name=name, relationship=rel))
    if _TIME.search(question):
        return LocalAnswer(t(lang, "time", time=fmt_time(now.time()), day=DAYS.get(lang, DAYS["en"])[now.weekday()]))
    if _SCHEDULE.search(question):
        items = todays_remaining(reminders, now)
        if not items:
            return LocalAnswer(t(lang, "today_none"))
        return LocalAnswer(t(lang, "today", items="; ".join(f"{fmt_time(r.time_of_day)} {r.title}" for r in items)))
    return None
