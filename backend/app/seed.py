"""Seed starter content (games, NER cultural items, en/hi language packs).

    python -m app.seed                      # content only, safe to re-run
    python -m app.seed --admin +91XXXXXXXXXX  # also make that phone an admin
"""

import argparse

from sqlalchemy import select
from sqlalchemy.orm import Session

from .db import service_session
from .models import CulturalContent, Game, LanguagePack, Profile, Role, User, utcnow

GAMES = [
    {"slug": "photo_recall", "name": "Who Is This?", "domain": "memory_recall",
     "config": {"source": "memory_book", "choices_by_level": [2, 3, 3, 4, 4]}},
    {"slug": "market_list", "name": "Market List", "domain": "memory_recall",
     "config": {"items_by_level": [3, 4, 5, 6, 7], "source": "cultural:food"}},
    {"slug": "odd_one_out", "name": "Odd One Out", "domain": "attention",
     "config": {"grid_by_level": [3, 4, 4, 5, 6]}},
    {"slug": "gamosa_patterns", "name": "Weaving Patterns", "domain": "pattern",
     "config": {"sequence_by_level": [3, 4, 5, 6, 7]}},
    {"slug": "name_it", "name": "Name It", "domain": "language",
     "config": {"source": "cultural:object", "hints_by_level": [2, 2, 1, 1, 0]}},
    {"slug": "quick_tap", "name": "Quick Tap", "domain": "speed",
     "config": {"targets_by_level": [8, 10, 12, 14, 16], "window_ms_by_level": [2500, 2000, 1700, 1400, 1200]}},
    {"slug": "my_day", "name": "My Day in Order", "domain": "routine",
     "config": {"steps_by_level": [3, 4, 5, 6, 6]}},
]

# region "all" = shown in every NER state
CULTURAL = [
    ("assam", "festival", "Bihu", {"note": "Harvest festival with dance and songs", "months": ["Apr", "Jan", "Oct"]}),
    ("assam", "object", "Gamosa", {"note": "White cloth with red woven border, given as a mark of respect"}),
    ("assam", "object", "Xorai", {"note": "Bell-metal tray on a stand used for offerings"}),
    ("assam", "object", "Japi", {"note": "Traditional bamboo and palm-leaf hat"}),
    ("assam", "food", "Pitha", {"note": "Rice cakes made for Bihu"}),
    ("assam", "place", "Tea garden", {"note": "Rows of tea bushes and plucking baskets"}),
    ("assam", "place", "Majuli", {"note": "River island on the Brahmaputra"}),
    ("manipur", "place", "Ima Keithel", {"note": "The women's market in Imphal"}),
    ("manipur", "place", "Loktak Lake", {"note": "Lake with floating phumdis"}),
    ("manipur", "object", "Phanek", {"note": "Traditional wrap-around skirt"}),
    ("manipur", "food", "Chak-hao", {"note": "Black rice, often made into kheer"}),
    ("meghalaya", "place", "Living root bridge", {"note": "Bridges grown from rubber-tree roots"}),
    ("meghalaya", "food", "Jadoh", {"note": "Rice cooked with meat and spices"}),
    ("nagaland", "festival", "Hornbill Festival", {"note": "Festival of festivals held in December"}),
    ("mizoram", "music", "Cheraw", {"note": "Bamboo dance"}),
    ("tripura", "object", "Risa", {"note": "Handwoven cloth worn by women"}),
    ("arunachal", "festival", "Losar", {"note": "New Year festival of the Monpa people"}),
    ("sikkim", "food", "Momo", {"note": "Steamed dumplings"}),
    ("all", "food", "Rice", {"note": "Rice with dal and vegetables"}),
    ("all", "daily_life", "Morning tea", {"note": "A cup of tea to start the day"}),
    ("all", "object", "Umbrella", {"note": "Needed in the rainy season"}),
]

EN = {
    "app_name": "NEURO-SATHI", "greeting_morning": "Good morning", "greeting_evening": "Good evening",
    "play": "Play", "memories": "Memories", "reminders": "Reminders", "talk_to_sathi": "Talk to Sathi",
    "done": "Done", "later": "Later", "well_done": "Well done!", "try_again": "Let's try again",
    "next": "Next", "back": "Back", "yes": "Yes", "no": "No", "offline": "Offline - everything is saved",
}
HI = {
    "app_name": "न्यूरो-साथी", "greeting_morning": "सुप्रभात", "greeting_evening": "शुभ संध्या",
    "play": "खेलें", "memories": "यादें", "reminders": "याद दिलाना", "talk_to_sathi": "साथी से बात करें",
    "done": "हो गया", "later": "बाद में", "well_done": "बहुत बढ़िया!", "try_again": "फिर से कोशिश करें",
    "next": "आगे", "back": "पीछे", "yes": "हाँ", "no": "नहीं", "offline": "ऑफ़लाइन - सब कुछ सुरक्षित है",
}
VOICE_EN = {"reminder_medication": "It is time for your medicine: {title}.", "reminder_generic": "Reminder: {title}."}
VOICE_HI = {"reminder_medication": "दवा का समय हो गया है: {title}।", "reminder_generic": "याद दिलाना: {title}।"}


def seed_content(db: Session) -> None:
    for g in GAMES:
        if db.scalar(select(Game).where(Game.slug == g["slug"])) is None:
            db.add(Game(**g, updated_at=utcnow()))
    existing = {(c.region, c.title) for c in db.scalars(select(CulturalContent))}
    for region, category, title, data in CULTURAL:
        if (region, title) not in existing:
            db.add(CulturalContent(region=region, language="en", category=category, title=title, data=data, updated_at=utcnow()))
    for lang, strings, voice in (("en", EN, VOICE_EN), ("hi", HI, VOICE_HI)):
        if db.scalar(select(LanguagePack).where(LanguagePack.language == lang, LanguagePack.version == 1)) is None:
            db.add(LanguagePack(language=lang, version=1, strings=strings, voice_prompts=voice, published=True))


def make_admin(db: Session, phone: str) -> None:
    user = db.scalar(select(User).where(User.phone == phone))
    if user is None:
        user = User(phone=phone, role=Role.admin, name="Admin")
        db.add(user)
        db.flush()
        db.add(Profile(user_id=user.id))
    else:
        user.role = Role.admin


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--admin", help="phone number (+91...) to grant the admin role")
    args = p.parse_args()
    with service_session() as db:
        seed_content(db)
        if args.admin:
            make_admin(db, args.admin)
    print("seeded")
