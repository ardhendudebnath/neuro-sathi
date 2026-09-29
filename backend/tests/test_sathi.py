from datetime import datetime, time

import pytest
from pydantic import SecretStr

from app.config import get_settings
from app.services import nvidia
from app.services.sathi_engine import IST, answer_locally
from tests.conftest import signup


class R:  # minimal reminder stand-in
    def __init__(self, title, kind, at, days=range(7)):
        self.title, self.kind, self.time_of_day, self.days_of_week = title, kind, at, list(days)
        self.active, self.deleted = True, False


class M:
    def __init__(self, name, relationship, description=None):
        self.person_name, self.relationship, self.title, self.description, self.deleted = name, relationship, name, description, False


NOW = datetime(2026, 9, 30, 10, 0, tzinfo=IST)  # a Wednesday


def test_next_medicine_today_and_tomorrow():
    rs = [R("Metformin", "medication", time(8, 0)), R("Amlodipine", "medication", time(20, 0))]
    assert "Amlodipine" in answer_locally("when is my medicine?", "en", rs, [], NOW).text
    late = NOW.replace(hour=21)
    ans = answer_locally("which tablet next", "en", rs, [], late).text
    assert "Metformin" in ans and "Thursday" in ans


def test_who_is_uses_memory_book():
    people = [M("Rina", "granddaughter", "She lives in Guwahati."), M("Bipul", "son")]
    assert answer_locally("Who is Rina?", "en", [], people, NOW).text == "Rina is your granddaughter. She lives in Guwahati."
    assert "Bipul" in answer_locally("who is my son", "en", [], people, NOW).text


def test_hindi_intents():
    rs = [R("मेटफॉर्मिन", "medication", time(20, 0))]
    assert "मेटफॉर्मिन" in answer_locally("मेरी दवा कब है?", "hi", rs, [], NOW).text
    people = [M("रीना", "पोती")]
    assert "रीना" in answer_locally("रीना कौन है?", "hi", [], people, NOW).text


def test_schedule_only_lists_remaining_items_today():
    rs = [R("Breakfast", "meal", time(8, 0)), R("Walk", "activity", time(17, 0)), R("Weekend only", "activity", time(18, 0), days=[5, 6])]
    text = answer_locally("what is my plan for today", "en", rs, [], NOW).text
    assert "Walk" in text and "Breakfast" not in text and "Weekend" not in text


def test_offline_fallback_without_key(client):
    h, _ = signup(client)
    r = client.post("/sathi/ask", json={"question": "Tell me a story about Majuli"}, headers=h).json()
    assert r["source"] == "offline_fallback"


@pytest.fixture
def with_key(monkeypatch):
    monkeypatch.setattr(get_settings(), "nvidia_api_key", SecretStr("nvapi-test"))
    yield


def test_llm_path_with_safety(client, with_key, monkeypatch):
    seen = {}
    monkeypatch.setattr(nvidia, "is_safe", lambda q, reply=None: True)
    monkeypatch.setattr(nvidia, "companion_reply", lambda q, lang: seen.setdefault("q", q) and "Majuli is a river island.")
    h, _ = signup(client)
    r = client.post("/sathi/ask", json={"question": "Tell me about Majuli"}, headers=h).json()
    assert r == {"answer": "Majuli is a river island.", "source": "llm", "speak": True}
    assert seen["q"] == "Tell me about Majuli"  # only the question is sent


def test_unsafe_reply_blocked(client, with_key, monkeypatch):
    monkeypatch.setattr(nvidia, "is_safe", lambda q, reply=None: reply is None)
    monkeypatch.setattr(nvidia, "companion_reply", lambda q, lang: "something unsafe")
    h, _ = signup(client)
    assert client.post("/sathi/ask", json={"question": "hello there"}, headers=h).json()["source"] == "safety_block"


def test_budget_cap_switches_to_offline(client, with_key, monkeypatch):
    monkeypatch.setattr(get_settings(), "paid_api_monthly_budget_inr", 1.0)  # one call costs 1.5
    monkeypatch.setattr(nvidia, "is_safe", lambda q, reply=None: True)
    monkeypatch.setattr(nvidia, "companion_reply", lambda q, lang: "ok")
    h, _ = signup(client)
    assert client.post("/sathi/ask", json={"question": "hello there"}, headers=h).json()["source"] == "llm"
    assert client.post("/sathi/ask", json={"question": "hello again"}, headers=h).json()["source"] == "offline_fallback"


def test_voice_needs_consent(client, with_key):
    h, _ = signup(client)
    r = client.post("/speech/stt", files={"audio": ("a.wav", b"RIFF0000WAVE", "audio/wav")}, headers=h)
    assert r.status_code == 403
    client.patch("/me/profile", json={"voice_consent": True}, headers=h)
    r = client.post("/speech/stt", files={"audio": ("a.wav", b"RIFF0000WAVE", "audio/wav")}, headers=h)
    assert r.status_code == 503  # no function id configured in tests -> app uses on-device voice
