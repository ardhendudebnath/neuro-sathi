import copy
from datetime import datetime, time

import pytest
from pydantic import SecretStr

from app import language_packs as lp
from app.config import get_settings
from app.models import Role
from app.services import nvidia
from app.services.sathi_engine import IST, answer_locally
from tests.conftest import login_again, make_role, signup

NOW = datetime(2026, 9, 30, 10, 0, tzinfo=IST)  # a Wednesday morning
EN = lp.pack("en")


class R:  # minimal reminder stand-in
    def __init__(self, title, kind, at, days=range(7)):
        self.title, self.kind, self.time_of_day, self.days_of_week = title, kind, at, list(days)
        self.active, self.deleted = True, False


class M:  # minimal memory-book entry stand-in
    def __init__(self, name, relationship, description=None):
        self.person_name, self.relationship, self.title, self.description, self.deleted = name, relationship, name, description, False


# --- the pack files ------------------------------------------------------------------


@pytest.mark.parametrize("code", sorted(lp.supported()))
def test_every_pack_is_valid(code):
    errors, _ = lp.validate(lp.pack(code), EN)
    assert errors == []


def test_first_wave_languages_are_present():
    assert {"en", "hi", "as", "bn", "ne"} <= lp.supported()


@pytest.mark.parametrize("code", ["as", "bn", "ne", "mni-Beng", "mni-Mtei"])
def test_regional_drafts_stay_hidden_until_reviewed(code):
    info = lp.meta(code)
    assert info["release"] == "preview"
    assert info["review"]["status"] == "unreviewed"


def test_validator_catches_common_mistakes():
    bad = copy.deepcopy(lp.pack("as"))
    bad["strings"]["play"] = "খেলাৰ আগত আবার"  # Bengali র in an Assamese pack
    bad["strings"]["ask"] = "पूछें"  # Devanagari in an Assamese pack
    bad["strings"]["later"] = "Later"  # left in English
    del bad["strings"]["tap"]
    bad["strings"]["score"] = "{correct}টা শুদ্ধ"  # dropped {total}
    bad["days"] = bad["days"][:6]
    bad["meta"]["review"] = {"status": "reviewed", "reviewers": []}
    errors, _ = lp.validate(bad, EN)
    text = "\n".join(errors)
    assert "strings.play: Assamese uses ৰ" in text
    assert "strings.ask: contains Deva characters" in text
    assert "strings.later: has no Beng text" in text
    assert "strings.tap is missing" in text
    assert "strings.score: placeholders" in text
    assert "days must list 7" in text
    assert "must list its reviewers" in text


def test_bengali_pack_rejects_assamese_letters():
    bad = copy.deepcopy(lp.pack("bn"))
    bad["strings"]["play"] = "খেলক ৰ"
    errors, _ = lp.validate(bad, EN)
    assert any("Bengali uses র and ব" in e for e in errors)


def test_meitei_mayek_pack_rejects_other_scripts():
    bad = copy.deepcopy(lp.pack("mni-Mtei"))
    bad["strings"]["play"] = "শান্নবা"  # the Bengali-script spelling
    bad["strings"]["later"] = "Later"
    text = "\n".join(lp.validate(bad, EN)[0])
    assert "strings.play: contains Beng characters in a Mtei pack" in text
    assert "strings.later: has no Mtei text" in text


def test_the_two_manipuri_packs_stay_in_step():
    # Same wording in two scripts: a reviewer who changes one has to change the other.
    beng, mtei = lp.pack("mni-Beng"), lp.pack("mni-Mtei")
    for dotted in lp.KEYED_SECTIONS:
        assert lp._dict_at(beng, dotted).keys() == lp._dict_at(mtei, dotted).keys(), dotted
    for key in ("foods", "routine", "objects"):
        assert len(beng["games"][key]) == len(mtei["games"][key]), key
    for intent in lp.INTENTS:
        assert len(beng["sathi"]["keywords"][intent]) == len(mtei["sathi"]["keywords"][intent]), intent
    assert [p["from"] for p in beng["time"]["periods"]] == [p["from"] for p in mtei["time"]["periods"]]


# --- localized formatting and intents -----------------------------------------------------


@pytest.mark.parametrize(
    ("code", "hour", "minute", "expected"),
    [
        ("en", 20, 0, "8:00 PM"),
        ("en", 0, 5, "12:05 AM"),
        ("hi", 20, 0, "रात 8:00"),
        ("hi", 2, 0, "रात 2:00"),  # before the first day-part: still night
        ("as", 20, 0, "ৰাতি ৮:০০"),
        ("bn", 7, 30, "সকাল ৭:৩০"),
        ("ne", 10, 0, "बिहान १०:००"),
        ("mni-Beng", 20, 0, "অহিং ৮:০০"),
        ("mni-Mtei", 20, 0, "ꯑꯍꯤꯡ ꯸:꯰꯰"),
        ("mni-Mtei", 2, 5, "ꯑꯍꯤꯡ ꯲:꯰꯵"),
    ],
)
def test_format_time(code, hour, minute, expected):
    assert lp.format_time(code, hour, minute) == expected


def test_both_unicode_forms_of_nukta_letters_match():
    precomposed, decomposed = "সময়", "সময়"  # সময় typed two ways
    assert lp.has_intent(precomposed, "as", "time")
    assert lp.has_intent(decomposed, "as", "time")


def test_suffixes_match_only_prefix_keywords():
    assert lp.has_intent("ওষুধটা কখন খাব?", "bn", "medicine")  # ওষুধ* takes the -টা suffix
    assert lp.has_intent("আজকে কী আছে?", "bn", "schedule")
    assert not lp.has_intent("আজকে কী আছে?", "bn", "who")  # "কে" must be a whole word


# --- Sathi in the new languages -------------------------------------------------------------


def test_assamese_next_medicine():
    answer = answer_locally("মোৰ ঔষধ কেতিয়া?", "as", [R("Metformin", "medication", time(20, 0))], [], NOW)
    assert answer.text == "আপোনাৰ পৰৱৰ্তী ঔষধ Metformin, ৰাতি ৮:০০ বজাত।"


def test_bengali_who_is():
    answer = answer_locally("Rina কে?", "bn", [], [M("Rina", "নাতনি")], NOW)
    assert answer.text == "Rina আপনার নাতনি।"


def test_nepali_time():
    answer = answer_locally("अहिले कति बज्यो?", "ne", [], [], NOW)
    assert answer.text == "अहिले बुधबार, बिहान १०:०० बज्यो।"


def test_assamese_schedule_uses_assamese_time():
    answer = answer_locally("আজিৰ কাম কি?", "as", [R("খোজ কঢ়া", "activity", time(17, 0))], [], NOW)
    assert answer.text == "আজিৰ বাকী কামবোৰ: আবেলি ৫:০০ খোজ কঢ়া।"


def test_manipuri_in_bengali_script():
    med = [R("Metformin", "medication", time(20, 0))]
    assert answer_locally("ঐগি হিদাক চাবা মতম করমবা?", "mni-Beng", med, [], NOW).text == "নহাক্কি মথংগি হিদাক Metformin, অহিং ৮:০০দা।"
    assert answer_locally("Rina কনানো?", "mni-Beng", [], [M("Rina", "ইচানুপি")], NOW).text == "Rina নহাক্কি ইচানুপিনি।"


def test_manipuri_in_meitei_mayek():
    med = [R("Metformin", "medication", time(20, 0))]
    assert answer_locally("ꯑꯩꯒꯤ ꯍꯤꯗꯥꯛ ꯆꯥꯕ ꯃꯇꯝ ꯀꯔꯝꯕ?", "mni-Mtei", med, [], NOW).text == "ꯅꯍꯥꯛꯀꯤ ꯃꯊꯪꯒꯤ ꯍꯤꯗꯥꯛ Metformin, ꯑꯍꯤꯡ ꯸:꯰꯰ꯗ꯫"
    # ꯫ is the Meitei Mayek full stop: "ꯅꯨꯃꯤꯠꯅꯣ꯫" is still the word "ꯅꯨꯃꯤꯠꯅꯣ".
    assert answer_locally("ꯉꯁꯤ ꯀꯔꯤ ꯅꯨꯃꯤꯠꯅꯣ꯫", "mni-Mtei", [], [], NOW).text == "ꯍꯧꯖꯤꯛ ꯌꯨꯝꯁꯀꯩꯁ, ꯑꯌꯨꯛ ꯱꯰:꯰꯰ꯅꯤ꯫"


def test_english_words_work_in_other_languages():
    answer = answer_locally("tablet কখন?", "bn", [R("Metformin", "medication", time(20, 0))], [], NOW)
    assert "Metformin" in answer.text


def test_hindi_which_day_is_a_time_question():
    # "कौन सा दिन" contains "कौन" (who); it used to be answered as a who-question.
    answer = answer_locally("आज कौन सा दिन है?", "hi", [], [], NOW)
    assert "बुधवार" in answer.text


# --- API: release gating, language settings, admin uploads ---------------------------------------


def test_only_public_packs_are_served(client):
    h, _ = signup(client)
    assert client.get("/content/language-packs/as", headers=h).status_code == 404
    hi = client.get("/content/language-packs/hi", headers=h).json()
    assert hi["document"]["days"][2] == "बुधवार"
    codes = [lang["code"] for lang in client.get("/content/languages", headers=h).json()]
    assert codes == ["en", "hi"]


def test_language_setting_accepts_known_packs_only(client):
    h, _ = signup(client)
    assert client.patch("/me", json={"language": "as"}, headers=h).json()["language"] == "as"
    assert client.patch("/me", json={"language": "mni-Mtei"}, headers=h).json()["language"] == "mni-Mtei"
    assert client.patch("/me", json={"language": "xx"}, headers=h).status_code == 422


def test_sathi_skips_llm_for_languages_it_does_not_support(client, monkeypatch):
    monkeypatch.setattr(get_settings(), "nvidia_api_key", SecretStr("nvapi-test"))

    def must_not_call(*_):
        raise AssertionError("the hosted model does not support Assamese")

    monkeypatch.setattr(nvidia, "companion_reply", must_not_call)
    h, _ = signup(client)
    r = client.post("/sathi/ask", json={"question": "মাজুলীৰ বিষয়ে কওক", "language": "as"}, headers=h).json()
    assert r == {"answer": lp.answer("as", "fallback"), "source": "offline_fallback", "speak": True}


def test_admin_upload_is_validated_then_published(client):
    h, user = signup(client)
    make_role(user["id"], Role.admin)
    admin = login_again(client, user["phone"])

    broken = copy.deepcopy(lp.pack("as"))
    del broken["strings"]["tap"]
    r = client.put("/admin/language-packs", json={"document": broken, "published": True}, headers=admin)
    assert r.status_code == 422
    assert "strings.tap is missing" in r.json()["detail"]["errors"]

    reviewed = copy.deepcopy(lp.pack("as"))
    reviewed["version"] = lp.pack("as")["version"] + 1
    reviewed["meta"]["release"] = "public"
    reviewed["meta"]["review"] = {"status": "reviewed", "reviewers": ["Test Reviewer"]}
    r = client.put("/admin/language-packs", json={"document": reviewed, "published": True}, headers=admin)
    assert r.status_code == 200, r.text
    served = client.get("/content/language-packs/as", headers=h).json()
    assert served["version"] == reviewed["version"]
