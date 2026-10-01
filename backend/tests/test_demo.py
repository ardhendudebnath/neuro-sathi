from datetime import datetime

import pytest

from app.config import get_settings
from app.demo import end_sessions, seed_demo
from app.services.sathi_engine import IST


def sign_in(client, phone):
    code = client.post("/auth/otp", json={"phone": phone}).json()["dev_code"]
    body = client.post("/auth/verify", json={"phone": phone, "code": code}).json()
    return {"Authorization": f"Bearer {body['access_token']}"}, body


def test_demo_account_is_ready_to_use(client):
    out = seed_demo("9876511111", caregiver_phone="9876522222", now=datetime(2026, 9, 30, 10, 0, tzinfo=IST))
    assert out["reminder_at"] == "10:03"

    h, body = sign_in(client, "9876511111")
    uid = body["user"]["id"]
    assert uid == out["user_id"]
    people = {e["person_name"] for e in client.get(f"/users/{uid}/memory-book", headers=h).json()}
    assert people == {"Rina", "Bipul", "Mala"}
    reminders = client.get(f"/users/{uid}/reminders", headers=h).json()
    assert [(r["title"], r["time_of_day"]) for r in reminders] == [("Test medicine", "10:03:00")]

    carer_h, _ = sign_in(client, "9876522222")
    assert [p["user"]["id"] for p in client.get("/dashboard/users", headers=carer_h).json()] == [uid]


def test_running_again_adds_a_reminder_but_not_more_people(client):
    seed_demo("9876533333", now=datetime(2026, 9, 30, 10, 0, tzinfo=IST))
    again = seed_demo("9876533333", remind_in=10, now=datetime(2026, 9, 30, 10, 0, tzinfo=IST))
    assert again["people_added"] == []

    h, body = sign_in(client, "9876533333")
    times = [r["time_of_day"] for r in client.get(f"/users/{body['user']['id']}/reminders", headers=h).json()]
    assert times == ["10:03:00", "10:10:00"]


def test_end_sessions_signs_the_account_out_everywhere(client):
    seed_demo("9876544444")
    _, body = sign_in(client, "9876544444")
    assert end_sessions("9876544444") == 1
    assert client.post("/auth/refresh", json={"refresh_token": body["refresh_token"]}).status_code == 401


def test_refuses_to_run_in_production(monkeypatch):
    monkeypatch.setattr(get_settings(), "env", "production")
    with pytest.raises(SystemExit):
        seed_demo("9876555555")
