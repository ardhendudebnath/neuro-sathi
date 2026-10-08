"""Review sheets: a native speaker checks a language pack in a spreadsheet.

    python -m app.pack_review export bn                      # writes bn-review.csv
    python -m app.pack_review import bn bn-review.csv --reviewer "Name" [--reviewed] [--publish]

The sheet (CSV, for Excel or Google Sheets) has one row per text: the English,
the current translation, empty Correction and Comment columns for the reviewer,
and what to look out for. Medicine and reminder wording comes first.

Import applies only the filled-in corrections. It refuses a sheet whose
translations have changed since it was exported, runs the same checks as
`python -m app.language_packs check`, raises the pack's version so phones
download it, and records the reviewer. The pack keeps its layout, so the pull
request shows only the corrected lines.
"""

import argparse
import csv
import json
import re
import sys
from dataclasses import dataclass, field
from fnmatch import fnmatchcase
from pathlib import Path

from . import language_packs as lp

KEY, ENGLISH, CURRENT, CORRECTION, COMMENT, CHECK = (
    "Key (do not change)",
    "English",
    "Current translation",
    "Correction",
    "Comment",
    "What to check",
)
COLUMNS = (KEY, ENGLISH, CURRENT, CORRECTION, COMMENT, CHECK)
# Reviewed first and with extra care: a misread medicine reminder can cause real harm.
CAREFUL = ("strings.medicine_time", "strings.reminders_may_be_late", "strings.ring_on_time", "voice_prompts.*", "sathi.answers.med_*")
# Chosen for the region rather than translated, so the sheet shows no English for them.
LOCAL = ("games.objects[", "time.periods[")
TOPICS = {
    "medicine": "asking about their medicine",
    "time": "asking the time or the day",
    "who": "asking who someone is",
    "schedule": "asking about today's plan",
}
# Pack file layout: these are written on one line; other objects get a line per key, lists of objects a line per item.
ONE_LINE = {"meta.review", "time.periods"}


class SheetError(Exception):
    """A problem with the sheet or the pack, explained for the person running the command."""


@dataclass
class Review:
    changes: list[tuple[str, str, str]] = field(default_factory=list)  # (key, old text, new text)
    comments: list[tuple[str, str]] = field(default_factory=list)  # (key, comment)
    errors: list[str] = field(default_factory=list)


# --- pack files -----------------------------------------------------------------------


def pack_json(doc: dict) -> str:
    """A pack as JSON in the layout of the files in content/language-packs."""
    return _layout(doc, "", 0) + "\n"


def _layout(value: object, path: str, depth: int) -> str:
    inner, outer = "  " * (depth + 1), "  " * depth
    if path not in ONE_LINE and isinstance(value, dict) and value:
        items = []
        for k, v in value.items():
            child = f"{path}.{k}" if path else k
            items.append(f"{inner}{json.dumps(k, ensure_ascii=False)}: {_layout(v, child, depth + 1)}")
        return "{\n" + ",\n".join(items) + f"\n{outer}}}"
    if path not in ONE_LINE and isinstance(value, list) and any(isinstance(v, dict) for v in value):
        return "[\n" + ",\n".join(inner + json.dumps(v, ensure_ascii=False) for v in value) + f"\n{outer}]"
    return json.dumps(value, ensure_ascii=False)


def _path(code: str) -> Path:
    return lp.packs_dir() / f"{code}.json"


def _load(code: str) -> dict:
    path = _path(code)
    if not path.is_file():
        raise SheetError(f"there is no language pack {code!r} in {lp.packs_dir()}")
    return json.loads(path.read_text(encoding="utf-8"))


def twins(code: str) -> list[str]:
    """Packs of the same language in another script (mni-Beng, mni-Mtei), which share their wording."""
    if "-" not in code:
        return []
    language = code.split("-")[0]
    return sorted(p.stem for p in lp.packs_dir().glob("*.json") if p.stem != code and p.stem.split("-")[0] == language)


# --- sheet rows -----------------------------------------------------------------------


def _slots(doc: dict) -> list[tuple[str, dict | list, str | int]]:
    """lp.text_slots plus Sathi's keywords, which a reviewer edits as one comma-separated cell per topic."""
    keywords = doc["sathi"]["keywords"]
    return lp.text_slots(doc) + [(f"sathi.keywords.{topic}", keywords, topic) for topic in keywords]


def _value(box: dict | list, key: str | int) -> object:
    return box.get(key) if isinstance(box, dict) else box[key]


def _cell(box: dict | list, key: str | int) -> str:
    value = _value(box, key)
    return ", ".join(value) if isinstance(value, list) else str(value or "")


def is_careful(key: str) -> bool:
    return any(fnmatchcase(key, pattern) for pattern in CAREFUL)


def _listing(items: list[str]) -> str:
    return items[0] if len(items) == 1 else ", ".join(items[:-1]) + " and " + items[-1]


def _period_note(doc: dict, index: int) -> str:
    cfg = doc["time"]
    periods = cfg["periods"]
    start, end = periods[index]["from"], periods[(index + 1) % len(periods)]["from"]  # the last one runs into the morning
    example = cfg["format"].format(h=(start + 11) % 12 + 1, mm="00", period=periods[index]["label"])
    example = lp.localize_digits(example, cfg.get("digits", "latin"))
    return f"The word for this part of the day, said before times from {start:02d}:00 to {(end - 1) % 24:02d}:59, as in {example}."


def _guidance(doc: dict, where: str, box: dict | list, english: str) -> str:
    notes = []
    if is_careful(where):
        notes.append("MEDICINE OR REMINDER: check with extra care that it is clear and cannot be misread.")
    placeholders = list(dict.fromkeys(lp.PLACEHOLDER.findall(english)))
    if placeholders:
        them = "them" if len(placeholders) > 1 else "it"
        notes.append(f"Keep {_listing(['{' + p + '}' for p in placeholders])} exactly as written: the app fills {them} in.")
    if where.startswith("sathi.keywords."):
        topic = where.rsplit(".", 1)[1]
        notes.append(
            f"Words people use when {TOPICS.get(topic, f'asking about {topic}')}, separated by commas. "
            "End a word with * to also match it with endings. The English words always work too."
        )
    elif where.startswith("games.foods["):
        notes.append("A food familiar locally; it need not be the English one.")
    elif where.startswith("games.routine["):
        notes.append("A step of the daily routine: the same step as the English.")
    elif where.startswith("games.objects[") and where.endswith(".title"):
        notes.append("A familiar local object, shown in a picture game.")
    elif where.startswith("games.objects["):
        notes.append(f"One line about {_value(box, 'title')}.")
    elif where.startswith("time.periods["):
        notes.append(_period_note(doc, int(re.search(r"\[(\d+)\]", where).group(1))))
    return " ".join(notes)


def sheet_rows(doc: dict, reference: dict) -> list[dict[str, str]]:
    """One row per text in the pack, medicine and reminder wording first."""
    english = {where: _cell(box, key) for where, box, key in _slots(reference)}
    rows = []
    for where, box, key in _slots(doc):
        source = "" if where.startswith(LOCAL) else english.get(where, "")
        row = {KEY: where, ENGLISH: source, CURRENT: _cell(box, key), CORRECTION: "", COMMENT: ""}
        rows.append(row | {CHECK: _guidance(doc, where, box, source)})
    return sorted(rows, key=lambda row: not is_careful(row[KEY]))


def write_sheet(rows: list[dict[str, str]], path: Path) -> None:
    with path.open("w", encoding="utf-8-sig", newline="") as f:  # the byte-order mark makes Excel read UTF-8
        writer = csv.DictWriter(f, fieldnames=COLUMNS)
        writer.writeheader()
        writer.writerows(rows)


def read_sheet(path: Path) -> list[dict[str, str]]:
    try:
        with path.open(encoding="utf-8-sig", newline="") as f:
            reader = csv.DictReader(f)
            missing = [c for c in (KEY, CURRENT, CORRECTION, COMMENT) if c not in (reader.fieldnames or [])]
            if missing:
                raise SheetError(f"{path.name} has no {_listing(missing)} column; keep the first row as exported")
            return [{c: (row.get(c) or "").strip() for c in COLUMNS} for row in reader]
    except UnicodeDecodeError:
        raise SheetError(f"{path.name} is not UTF-8: in Excel, save it as 'CSV UTF-8 (Comma delimited)'") from None


def apply_sheet(doc: dict, rows: list[dict[str, str]]) -> Review:
    """Apply the filled-in corrections to doc, in place. A correction is applied only while its
    Current translation still matches the pack, so an old sheet cannot undo newer fixes."""
    review = Review()
    slots = {where: (box, key) for where, box, key in _slots(doc)}
    corrected: set[str] = set()
    for number, row in enumerate(rows, start=2):  # row 1 is the header
        where, correction = row[KEY], row[CORRECTION]
        if row[COMMENT]:
            review.comments.append((where or f"row {number}", row[COMMENT]))
        if not correction:
            continue
        if where not in slots:
            review.errors.append(f"row {number}: {where or 'a row with no key'} is not a text in this pack")
            continue
        if where in corrected:
            review.errors.append(f"row {number}: a second correction for {where}")
            continue
        corrected.add(where)
        box, key = slots[where]
        current = _cell(box, key)
        if row[CURRENT] != current.strip():
            review.errors.append(f"row {number}: {where} has changed since the sheet was exported; it is now {current!r}")
            continue
        if isinstance(_value(box, key), list):
            words = [word.strip() for word in correction.split(",") if word.strip()]
            new, text = words, ", ".join(words)
        else:
            new = text = correction
        if text != current:
            box[key] = new
            review.changes.append((where, current, text))
    return review


# --- commands -------------------------------------------------------------------------


def export(code: str, out: Path | None = None, force: bool = False) -> int:
    if code == lp.SOURCE:
        raise SheetError(f"{lp.SOURCE} is the English source; review sheets are for translations")
    doc = _load(code)
    out = out or Path(f"{code}-review.csv")
    if out.exists() and not force:
        raise SheetError(f"{out} already exists and may hold a reviewer's corrections; move it or add --force")
    rows = sheet_rows(doc, _load(lp.SOURCE))
    write_sheet(rows, out)
    careful = sum(is_careful(row[KEY]) for row in rows)
    print(f"Wrote {out}: {len(rows)} texts from {code} version {doc['version']}, the {careful} medicine and reminder texts first.")
    print("The reviewer fills in Correction only where the text is wrong, and Comment for anything else.")
    for twin in twins(code):
        print(f"{twin} has the same wording in another script: send its sheet to the same reviewer.")
    return 0


def import_sheet(code: str, sheet: Path, reviewers: list[str], reviewed: bool = False, publish: bool = False, dry_run: bool = False) -> int:
    if code == lp.SOURCE:
        raise SheetError(f"{lp.SOURCE} is the English source; review sheets are for translations")
    reviewers = [name.strip() for name in reviewers if name.strip()]
    if not reviewers:
        raise SheetError("give the reviewer's name with --reviewer")
    doc, reference = _load(code), _load(lp.SOURCE)
    review = apply_sheet(doc, read_sheet(sheet))
    info = doc["meta"]
    if publish and not (reviewed or info["review"]["status"] == "reviewed"):
        review.errors.append("--publish needs a full review: add --reviewed once the reviewer has checked every row")
    if review.errors:
        return _fail(f"{sheet.name} was not applied, and {code}.json is unchanged:", review.errors)

    updates = []
    if reviewed and info["review"]["status"] != "reviewed":
        info["review"]["status"] = "reviewed"
        updates.append("meta.review.status: reviewed")
    if publish and info["release"] != "public":
        info["release"] = "public"
        updates.append("meta.release: public (users can pick it)")
    if not review.changes and not updates:
        print(f"{sheet.name} has no corrections, so {code}.json is unchanged.")
        _print_comments(review.comments)
        if not reviewed:
            print(f"If {_listing(reviewers)} checked every row and found nothing to fix, run this again with --reviewed.")
        return 0

    listed = info["review"].setdefault("reviewers", [])
    listed += [name for name in reviewers if name not in listed]
    doc["version"] += 1
    errors, _ = lp.validate(doc, reference)
    if errors:
        return _fail(f"The corrected pack fails the language checks, so {code}.json is unchanged:", errors)

    comments = dict(review.comments)
    print(f"{code}: {len(review.changes)} correction(s) from {sheet.name}")
    for where, old, new in review.changes:
        print(f"  {where}\n    was: {old}\n    now: {new}")
        if where in comments:
            print(f"    comment: {comments.pop(where)}")
    _print_comments(list(comments.items()))
    for update in updates + [f"meta.review.reviewers: {', '.join(listed)}", f"version: {doc['version'] - 1} -> {doc['version']}"]:
        print(f"  {update}")
    if dry_run:
        print(f"Dry run: {code}.json is unchanged.")
    else:
        _path(code).write_text(pack_json(doc), encoding="utf-8", newline="\n")
        print(f"Saved {code}.json. Run the tests, then open a pull request.")
    for twin in twins(code):
        keys = ", ".join(where for where, _, _ in review.changes) or "none"
        print(
            f"\n{twin} has the same wording in another script. Make the same changes there: export its sheet, "
            f"fill in Correction for these rows ({keys}) and import it with the same options."
        )
    return 0


def _print_comments(comments: list[tuple[str, str]]) -> None:
    if comments:
        print("Comments with no correction (for you to act on):")
        for where, comment in comments:
            print(f"  {where}: {comment}")


def _fail(heading: str, errors: list[str]) -> int:
    print(heading, file=sys.stderr)
    for error in errors:
        print(f"  {error}", file=sys.stderr)
    if any("changed since the sheet was exported" in e for e in errors):
        print("Export a new sheet and copy the reviewer's corrections into it.", file=sys.stderr)
    return 1


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="python -m app.pack_review", description="Native-speaker review of a language pack.")
    commands = parser.add_subparsers(dest="command", required=True)
    out = commands.add_parser("export", help="write a review sheet (CSV) for a pack")
    out.add_argument("code", help="the pack's language code, such as bn or mni-Mtei")
    out.add_argument("-o", "--output", type=Path, help="the sheet to write (default: <code>-review.csv)")
    out.add_argument("--force", action="store_true", help="overwrite an existing sheet")
    back = commands.add_parser("import", help="apply a filled-in review sheet to its pack")
    back.add_argument("code", help="the pack's language code")
    back.add_argument("sheet", type=Path, help="the filled-in sheet, saved as CSV UTF-8")
    back.add_argument("--reviewer", action="append", required=True, help="the reviewer's name (repeat for several)")
    back.add_argument("--reviewed", action="store_true", help="the reviewer checked every row: mark the pack reviewed")
    back.add_argument("--publish", action="store_true", help="release the pack to users (needs a reviewed pack)")
    back.add_argument("--dry-run", action="store_true", help="show the changes without saving the pack")
    args = parser.parse_args(argv)
    try:
        if args.command == "export":
            return export(args.code, args.output, args.force)
        return import_sheet(args.code, args.sheet, args.reviewer, args.reviewed, args.publish, args.dry_run)
    except SheetError as e:
        print(f"error: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    for stream in (sys.stdout, sys.stderr):  # pack text is not in the Windows code page
        stream.reconfigure(encoding="utf-8")
    sys.exit(main())
