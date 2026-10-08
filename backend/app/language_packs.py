"""Language packs: one JSON file per language in content/language-packs/.

The same files feed the server (Sathi's answers, the packs the phone
downloads) and the phone app (bundled at build time), so a language is added
or corrected in one place. Every pack is checked against the English source:

    python -m app.language_packs check

Release rules: a "preview" pack is hidden from users (the app shows it only in
builds made with SHOW_PREVIEW_LANGUAGES) and is not served by the API. A pack
becomes "public" once a native speaker has reviewed it.
"""

import json
import re
import sys
from functools import lru_cache
from pathlib import Path

from .config import get_settings

SOURCE = "en"
RELEASES = {"public", "preview"}
REVIEW_STATUSES = {"source", "unreviewed", "reviewed"}
INTENTS = ("medicine", "time", "who", "schedule")
SECTIONS = ("language", "version", "meta", "strings", "voice_prompts", "days", "time", "regions", "sathi", "games")
META_FIELDS = ("english_name", "native_name", "script", "release", "review", "tts_locales", "stt_locales", "llm")
KEYED_SECTIONS = ("strings", "voice_prompts", "regions", "sathi.answers", "games.names")
SCRIPT_RANGES = {"Beng": (0x0980, 0x09FF), "Deva": (0x0900, 0x097F), "Mtei": (0xABC0, 0xABFF)}
# The danda and double danda sit in the Devanagari block but are shared by all Indic scripts.
SHARED_PUNCTUATION = {"\u0964", "\u0965"}
DIGITS = {"latin": "0123456789", "beng": "০১২৩৪৫৬৭৮৯", "deva": "०१२३४५६७८९", "mtei": "꯰꯱꯲꯳꯴꯵꯶꯷꯸꯹"}

PLACEHOLDER = re.compile(r"\{(\w+)\}")
TOKEN = re.compile(r"[^\s.,!?।॥꯫\"'()\-:;]+")  # ꯫ is the Meitei Mayek full stop

# Precomposed nukta letters -> base letter + nukta, so text typed with either
# Unicode form (e.g. য় as U+09DF or U+09AF U+09BC) matches the same keywords.
_NUKTA = str.maketrans(
    {
        "ড়": "ড়", "ঢ়": "ঢ়", "য়": "য়",
        "ऩ": "ऩ", "ऱ": "ऱ", "ऴ": "ऴ",
        "क़": "क़", "ख़": "ख़", "ग़": "ग़", "ज़": "ज़",
        "ड़": "ड़", "ढ़": "ढ़", "फ़": "फ़", "य़": "य़",
    }
)


def packs_dir() -> Path:
    configured = get_settings().language_packs_dir
    return Path(configured) if configured else Path(__file__).resolve().parents[2] / "content" / "language-packs"


@lru_cache
def load_packs() -> dict[str, dict]:
    packs: dict[str, dict] = {}
    for path in sorted(packs_dir().glob("*.json")):
        data = json.loads(path.read_text(encoding="utf-8"))
        if data.get("language") != path.stem:
            raise ValueError(f"{path.name}: 'language' must be {path.stem!r}")
        packs[path.stem] = data
    if SOURCE not in packs:
        raise RuntimeError(f"no {SOURCE}.json in {packs_dir()}")
    return packs


def supported() -> set[str]:
    return set(load_packs())


def pack(language: str | None) -> dict:
    packs = load_packs()
    return packs.get(language or SOURCE, packs[SOURCE])


def meta(language: str | None) -> dict:
    return pack(language)["meta"]


def english_name(language: str | None) -> str:
    return meta(language)["english_name"]


def llm_supported(language: str | None) -> bool:
    """Whether the hosted companion model handles this language (Sarvam-M does not cover Assamese, Nepali or Manipuri)."""
    return bool(meta(language).get("llm"))


# --- text helpers (mirrored in mobile/lib/l10n) -------------------------------------


def answer(language: str | None, key: str, **values: str) -> str:
    template = pack(language)["sathi"]["answers"].get(key) or pack(SOURCE)["sathi"]["answers"][key]
    return template.format(**values)


def day_name(language: str | None, weekday: int) -> str:
    """weekday: 0 = Monday."""
    return pack(language)["days"][weekday]


def localize_digits(text: str, style: str) -> str:
    return text.translate(str.maketrans(DIGITS["latin"], DIGITS.get(style, DIGITS["latin"])))


def format_time(language: str | None, hour: int, minute: int) -> str:
    """12-hour time with the language's day-part words and digits, e.g. "8:00 PM", "ৰাতি ৮:০০"."""
    cfg = pack(language)["time"]
    periods = cfg["periods"]
    label = periods[-1]["label"]  # hours before the first period belong to the night
    for period in periods:
        if hour >= period["from"]:
            label = period["label"]
    text = cfg["format"].format(h=(hour + 11) % 12 + 1, mm=f"{minute:02d}", period=label)
    return localize_digits(text, cfg.get("digits", "latin"))


def normalize(text: str) -> str:
    return text.translate(_NUKTA).lower()


def tokens(text: str) -> list[str]:
    return TOKEN.findall(normalize(text))


def keyword_matches(question_tokens: list[str], keyword: str) -> bool:
    """A keyword is a word or phrase; a trailing * lets the last word take suffixes
    (ওষুধ* matches ওষুধের). Matching is by whole tokens, which also works for
    scripts where regex word boundaries do not."""
    prefix = keyword.endswith("*")
    parts = tokens(keyword.rstrip("*"))
    if not parts:
        return False
    n = len(parts)
    for i in range(len(question_tokens) - n + 1):
        window = question_tokens[i : i + n]
        if window[:-1] != parts[:-1]:
            continue
        if window[-1] == parts[-1] or (prefix and window[-1].startswith(parts[-1])):
            return True
    return False


def has_intent(question: str, language: str | None, intent: str) -> bool:
    """The language's own keywords plus English ones (people mix in words like "tablet")."""
    keywords = list(pack(language)["sathi"]["keywords"].get(intent, []))
    if (language or SOURCE) != SOURCE:
        keywords += pack(SOURCE)["sathi"]["keywords"][intent]
    toks = tokens(question)
    return any(keyword_matches(toks, kw) for kw in keywords)


# --- validation -----------------------------------------------------------------------


def _dict_at(doc: dict, dotted: str) -> dict:
    node: object = doc
    for part in dotted.split("."):
        node = node.get(part, {}) if isinstance(node, dict) else {}
    return node if isinstance(node, dict) else {}


def _texts(doc: dict) -> list[tuple[str, object]]:
    """Every user-visible text in a pack, with its location."""
    out: list[tuple[str, object]] = []
    for dotted in KEYED_SECTIONS:
        out += [(f"{dotted}.{k}", v) for k, v in _dict_at(doc, dotted).items()]
    out += [(f"days[{i}]", v) for i, v in enumerate(doc.get("days", []))]
    games = doc.get("games", {})
    out += [(f"games.foods[{i}]", v) for i, v in enumerate(games.get("foods", []))]
    out += [(f"games.routine[{i}]", v) for i, v in enumerate(games.get("routine", []))]
    for i, obj in enumerate(games.get("objects", [])):
        out += [(f"games.objects[{i}].title", obj.get("title")), (f"games.objects[{i}].note", obj.get("note"))]
    out += [(f"time.periods[{i}].label", p.get("label")) for i, p in enumerate(doc.get("time", {}).get("periods", []))]
    return out


def _script_errors(code: str, script: str, where: str, text: str) -> list[str]:
    errors = []
    for other, (lo, hi) in SCRIPT_RANGES.items():
        if other != script and any(lo <= ord(c) <= hi and c not in SHARED_PUNCTUATION for c in text):
            errors.append(f"{where}: contains {other} characters in a {script} pack")
    if script in SCRIPT_RANGES:
        lo, hi = SCRIPT_RANGES[script]
        body = PLACEHOLDER.sub("", text)
        if any(c.isalpha() for c in body) and not any(lo <= ord(c) <= hi for c in body):
            errors.append(f"{where}: has no {script} text (untranslated?)")
    if code == "as" and "র" in text:
        errors.append(f"{where}: Assamese uses ৰ (U+09F0), not the Bengali র (U+09B0)")
    if code == "bn" and ("ৰ" in text or "ৱ" in text):
        errors.append(f"{where}: Bengali uses র and ব, not the Assamese ৰ or ৱ")
    return errors


def validate(doc: dict, reference: dict) -> tuple[list[str], list[str]]:
    """(errors, warnings) for one pack checked against the English reference."""
    missing = [s for s in SECTIONS if s not in doc]
    if missing:
        return [f"missing sections: {', '.join(missing)}"], []
    errors: list[str] = []
    warnings: list[str] = []
    code = doc["language"]
    info = doc["meta"]
    errors += [f"meta.{f} is missing" for f in META_FIELDS if f not in info]
    if errors:
        return errors, warnings

    status = info["review"].get("status")
    if info["release"] not in RELEASES:
        errors.append(f"meta.release must be one of {sorted(RELEASES)}")
    if status not in REVIEW_STATUSES:
        errors.append(f"meta.review.status must be one of {sorted(REVIEW_STATUSES)}")
    if status == "source" and code != SOURCE:
        errors.append("only the English source pack can have review status 'source'")
    if status == "reviewed" and not info["review"].get("reviewers"):
        errors.append("a reviewed pack must list its reviewers")
    if info["release"] == "public" and status == "unreviewed":
        warnings.append("released publicly but not yet reviewed by a native speaker")

    for dotted in KEYED_SECTIONS:
        mine, theirs = _dict_at(doc, dotted), _dict_at(reference, dotted)
        errors += [f"{dotted}.{k} is missing" for k in sorted(theirs.keys() - mine.keys())]
        warnings += [f"{dotted}.{k} is not in the English reference" for k in sorted(mine.keys() - theirs.keys())]
        for k in sorted(mine.keys() & theirs.keys()):
            if isinstance(mine[k], str) and isinstance(theirs[k], str):
                got, want = set(PLACEHOLDER.findall(mine[k])), set(PLACEHOLDER.findall(theirs[k]))
                if got != want:
                    errors.append(f"{dotted}.{k}: placeholders {sorted(got)} differ from English {sorted(want)}")

    if len(doc["days"]) != 7:
        errors.append("days must list 7 names, Monday first")
    games = doc["games"]
    if len(games.get("routine", [])) != len(reference["games"]["routine"]):
        errors.append("games.routine must have the same steps, in the same order, as English")
    if len(games.get("foods", [])) < 10:
        errors.append("games.foods needs at least 10 items")
    if len(games.get("objects", [])) < 4:
        errors.append("games.objects needs at least 4 items")

    time_cfg = doc["time"]
    if not all(f"{{{p}}}" in time_cfg.get("format", "") for p in ("h", "mm", "period")):
        errors.append("time.format must contain {h}, {mm} and {period}")
    hours = [p.get("from") for p in time_cfg.get("periods", [])]
    if not hours or any(not isinstance(h, int) or not 0 <= h <= 23 for h in hours) or hours != sorted(set(hours)):
        errors.append("time.periods need increasing 'from' hours between 0 and 23")
    if time_cfg.get("digits", "latin") not in DIGITS:
        errors.append(f"time.digits must be one of {sorted(DIGITS)}")

    keywords = doc["sathi"].get("keywords", {})
    errors += [f"sathi.keywords.{i} needs at least one keyword" for i in INTENTS if not keywords.get(i)]

    for where, text in _texts(doc):
        if not isinstance(text, str) or not text.strip():
            errors.append(f"{where} is empty")
            continue
        errors += _script_errors(code, info["script"], where, text)
    return errors, warnings


def check() -> int:
    packs = load_packs()
    reference = packs[SOURCE]
    failed = False
    for code, doc in sorted(packs.items()):
        errors, warnings = validate(doc, reference)
        info = doc.get("meta", {})
        state = f"{info.get('release')}, {info.get('review', {}).get('status')}"
        print(f"{code}: {len(errors)} error(s), {len(warnings)} warning(s) [{state}]")
        for e in errors:
            print(f"  ERROR {e}")
        for w in warnings:
            print(f"  warn  {w}")
        failed = failed or bool(errors)
    return 1 if failed else 0


if __name__ == "__main__":
    if sys.argv[1:] != ["check"]:
        sys.exit("usage: python -m app.language_packs check")
    sys.exit(check())
