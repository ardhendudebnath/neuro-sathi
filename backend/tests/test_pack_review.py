import json
import shutil

import pytest

from app import language_packs as lp
from app import pack_review as pr


@pytest.fixture
def packs(tmp_path, monkeypatch):
    """A copy of the language packs for the review commands to change."""
    folder = tmp_path / "packs"
    shutil.copytree(lp.packs_dir(), folder)
    lp.load_packs()  # cache the real packs first: lp.pack() below must not see the copy's changes
    monkeypatch.setattr(lp, "packs_dir", lambda: folder)
    monkeypatch.chdir(tmp_path)
    return folder


def export(code):
    assert pr.main(["export", code]) == 0
    return pr.read_sheet(pr.Path(f"{code}-review.csv"))


def fill(code, corrections=None, comments=None):
    """Export a sheet for code and fill it in as a reviewer would."""
    rows = export(code)
    for row in rows:
        row[pr.CORRECTION] = (corrections or {}).get(row[pr.KEY], "")
        row[pr.COMMENT] = (comments or {}).get(row[pr.KEY], "")
    sheet = pr.Path(f"{code}-review.csv")
    pr.write_sheet(rows, sheet)
    return str(sheet)


def load(packs, code):
    return json.loads((packs / f"{code}.json").read_text(encoding="utf-8"))


@pytest.mark.parametrize("code", sorted(lp.supported()))
def test_pack_files_keep_their_layout(code):
    text = (lp.packs_dir() / f"{code}.json").read_text(encoding="utf-8")
    assert pr.pack_json(json.loads(text)) == text


def test_sheet_lists_every_text_medicine_first(packs):
    rows = export("bn")
    keys = [row[pr.KEY] for row in rows]
    bn = load(packs, "bn")
    assert sorted(keys) == sorted([where for where, _ in lp._texts(bn)] + [f"sathi.keywords.{t}" for t in lp.INTENTS])

    careful = [k for k in keys if pr.is_careful(k)]
    assert {"strings.medicine_time", "voice_prompts.reminder_medication", "sathi.answers.med_next"} <= set(careful)
    assert keys[: len(careful)] == careful

    by_key = {row[pr.KEY]: row for row in rows}
    medication = by_key["voice_prompts.reminder_medication"]
    assert medication[pr.ENGLISH] == lp.pack("en")["voice_prompts"]["reminder_medication"]
    assert medication[pr.CURRENT] == bn["voice_prompts"]["reminder_medication"]
    assert medication[pr.CHECK].startswith("MEDICINE OR REMINDER")
    assert "Keep {title} exactly as written" in medication[pr.CHECK]
    assert by_key["sathi.keywords.medicine"][pr.CURRENT] == ", ".join(bn["sathi"]["keywords"]["medicine"])
    assert by_key["games.objects[0].title"][pr.ENGLISH] == ""  # chosen locally, not translated
    assert pr.Path("bn-review.csv").read_bytes().startswith(b"\xef\xbb\xbf")  # so Excel reads it as UTF-8


def test_sheet_explains_day_parts():
    by_key = {row[pr.KEY]: row for row in pr.sheet_rows(lp.pack("mni-Mtei"), lp.pack("en"))}
    assert "from 19:00 to 03:59, as in ꯑꯍꯤꯡ ꯷:꯰꯰" in by_key["time.periods[3].label"][pr.CHECK]


def test_export_does_not_overwrite_a_sheet(packs, capsys):
    export("bn")
    assert pr.main(["export", "bn"]) == 1
    assert "already exists" in capsys.readouterr().err
    assert pr.main(["export", "bn", "--force"]) == 0
    assert pr.main(["export", "en"]) == 1  # the English source is not reviewed this way


def test_import_applies_only_the_filled_in_corrections(packs, capsys):
    before = (packs / "bn.json").read_text(encoding="utf-8")
    old = load(packs, "bn")
    sheet = fill(
        "bn",
        corrections={
            "strings.done": "সম্পন্ন",
            "sathi.keywords.medicine": " ওষুধ*,ঔষধ* , ",
            "strings.later": old["strings"]["later"],  # the same text: not a change
        },
        comments={"strings.done": "Shorter on the button", "games.foods[0]": "Add muri"},
    )
    assert pr.main(["import", "bn", sheet, "--reviewer", "Rina Das"]) == 0

    after = (packs / "bn.json").read_text(encoding="utf-8")
    new = load(packs, "bn")
    assert new["strings"]["done"] == "সম্পন্ন"
    assert new["sathi"]["keywords"]["medicine"] == ["ওষুধ*", "ঔষধ*"]
    assert new["version"] == old["version"] + 1
    assert new["meta"]["review"]["reviewers"] == ["Rina Das"]
    assert (new["meta"]["review"]["status"], new["meta"]["release"]) == ("unreviewed", "preview")
    # The layout is kept: only the version, review, and two corrected lines differ.
    lines = list(zip(before.splitlines(), after.splitlines(), strict=True))
    assert sum(a != b for a, b in lines) == 4
    assert lp.validate(new, lp.pack("en"))[0] == []

    out = capsys.readouterr().out
    assert "2 correction(s)" in out and "Shorter on the button" in out
    assert "games.foods[0]: Add muri" in out  # a comment with no correction is passed on


def test_import_refuses_a_stale_sheet(packs, capsys):
    sheet = fill("bn", corrections={"strings.done": "সম্পন্ন"})
    newer = load(packs, "bn")
    newer["strings"]["done"] = "শেষ"  # someone fixed it after the sheet was sent out
    (packs / "bn.json").write_text(pr.pack_json(newer), encoding="utf-8")
    before = (packs / "bn.json").read_text(encoding="utf-8")

    assert pr.main(["import", "bn", sheet, "--reviewer", "Rina Das"]) == 1
    assert (packs / "bn.json").read_text(encoding="utf-8") == before
    assert "strings.done has changed since the sheet was exported" in capsys.readouterr().err


@pytest.mark.parametrize(
    ("key", "correction", "error"),
    [
        ("voice_prompts.reminder_medication", "ওষুধ খাওয়ার সময় হয়েছে।", "placeholders"),  # {title} dropped
        ("strings.done", "Done", "no Beng text"),
        ("strings.no_such_key", "সম্পন্ন", "not a text in this pack"),
    ],
)
def test_import_refuses_corrections_that_fail_the_checks(packs, capsys, key, correction, error):
    before = (packs / "bn.json").read_text(encoding="utf-8")
    sheet = fill("bn")
    rows = pr.read_sheet(pr.Path(sheet))
    rows = [row | {pr.CORRECTION: correction} if row[pr.KEY] == key else row for row in rows]
    if key not in {row[pr.KEY] for row in rows}:
        rows.append({c: "" for c in pr.COLUMNS} | {pr.KEY: key, pr.CORRECTION: correction})
    pr.write_sheet(rows, pr.Path(sheet))

    assert pr.main(["import", "bn", sheet, "--reviewer", "Rina Das"]) == 1
    assert (packs / "bn.json").read_text(encoding="utf-8") == before
    assert error in capsys.readouterr().err


def test_a_full_review_can_publish_the_pack(packs, capsys):
    before = (packs / "bn.json").read_text(encoding="utf-8")
    sheet = fill("bn")
    assert pr.main(["import", "bn", sheet, "--reviewer", "Rina Das", "--publish"]) == 1
    assert "--publish needs a full review" in capsys.readouterr().err

    assert pr.main(["import", "bn", sheet, "--reviewer", "Rina Das"]) == 0
    assert "run this again with --reviewed" in capsys.readouterr().out
    assert (packs / "bn.json").read_text(encoding="utf-8") == before  # nothing to fix, nothing claimed

    old = load(packs, "bn")
    assert pr.main(["import", "bn", sheet, "--reviewer", "Rina Das", "--reviewer", "Arup Nath", "--reviewed", "--publish"]) == 0
    new = load(packs, "bn")
    assert new["meta"]["review"]["status"] == "reviewed"
    assert new["meta"]["review"]["reviewers"] == ["Rina Das", "Arup Nath"]
    assert new["meta"]["release"] == "public"
    assert new["version"] == old["version"] + 1
    assert lp.validate(new, lp.pack("en")) == ([], [])


def test_dry_run_changes_nothing(packs, capsys):
    before = (packs / "bn.json").read_text(encoding="utf-8")
    sheet = fill("bn", corrections={"strings.done": "সম্পন্ন"})
    assert pr.main(["import", "bn", sheet, "--reviewer", "Rina Das", "--dry-run"]) == 0
    assert (packs / "bn.json").read_text(encoding="utf-8") == before
    assert "now: সম্পন্ন" in capsys.readouterr().out


def test_manipuri_corrections_are_flagged_for_the_other_script(packs, capsys):
    sheet = fill("mni-Beng", corrections={"strings.done": "লোইরবা"})
    assert pr.main(["import", "mni-Beng", sheet, "--reviewer", "Tomba Singh"]) == 0
    out = capsys.readouterr().out
    assert "mni-Mtei has the same wording in another script" in out
    assert "(strings.done)" in out
    assert load(packs, "mni-Mtei") == lp.pack("mni-Mtei")  # left for the reviewer to change


def test_sheet_encodings(packs, capsys):
    sheet = pr.Path(fill("bn", corrections={"strings.done": "সম্পন্ন"}))
    sheet.write_text(sheet.read_text(encoding="utf-8-sig"), encoding="utf-8")  # saved without the byte-order mark
    assert pr.main(["import", "bn", str(sheet), "--reviewer", "Rina Das", "--dry-run"]) == 0

    sheet.write_bytes(b"Key (do not change),Current translation,Correction,Comment\nstrings.done,\xe9,x,\n")  # a Windows code page
    assert pr.main(["import", "bn", str(sheet), "--reviewer", "Rina Das"]) == 1
    assert "save it as 'CSV UTF-8" in capsys.readouterr().err
