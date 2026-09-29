import time
import uuid
from datetime import UTC, datetime, timedelta

from tests.conftest import link, signup


def ts(minutes: int = 0) -> str:
    return (datetime.now(UTC) + timedelta(minutes=minutes)).isoformat()


def session(**kw) -> dict:
    return {
        "id": str(uuid.uuid4()), "game_slug": "odd_one_out", "level": 2, "started_at": ts(-5), "ended_at": ts(-1),
        "trials": 10, "correct": 9, "errors": 1, "avg_response_ms": 2100, "completed": True, "updated_at": ts(),
    } | kw


def sync(client, headers, since=None, **changes):
    body = {"batch_id": str(uuid.uuid4()), "device_id": "phone-1", "since": since, "changes": changes}
    r = client.post("/sync", json=body, headers=headers)
    assert r.status_code == 200, r.text
    return body, r.json()


def test_first_sync_returns_recommendations(client):
    h, _ = signup(client)
    _, out = sync(client, h, game_sessions=[session()])
    assert out["applied"] == 1
    assert out["recommendations"], "every seeded game should be ranked"
    assert {r["rank"] for r in out["recommendations"]} == set(range(1, len(out["recommendations"]) + 1))


def test_retried_batch_is_not_applied_twice(client):
    h, u = signup(client)
    body, first = sync(client, h, game_sessions=[session()])
    again = client.post("/sync", json=body, headers=h).json()
    assert again["applied"] == first["applied"] == 1
    trends = client.get(f"/dashboard/users/{u['id']}/trends?days=7", headers=h).json()
    assert sum(d["sessions"] for d in trends) == 1


def test_last_write_wins(client):
    h, u = signup(client)
    mid = str(uuid.uuid4())
    entry = {"id": mid, "title": "Old", "updated_at": ts(-10)}
    sync(client, h, memory_book=[entry])
    _, out = sync(client, h, memory_book=[entry | {"title": "Stale", "updated_at": ts(-20)}])
    assert out["rejected"] == [{"table": "memory_book", "id": mid, "reason": "server_newer"}]
    _, out = sync(client, h, memory_book=[entry | {"title": "New", "updated_at": ts(-1)}])
    assert out["applied"] == 1
    titles = [e["title"] for e in client.get(f"/users/{u['id']}/memory-book", headers=h).json()]
    assert titles == ["New"]


def test_caregiver_memory_edit_wins_until_device_has_seen_it(client):
    user_h, user = signup(client)
    carer_h, _ = signup(client, role="caregiver")
    link(client, user_h, carer_h)
    _, first = sync(client, user_h)
    since = first["server_time"]
    time.sleep(0.02)  # Python 3.11 on Windows has a ~15 ms clock; keep the events in distinct ticks

    body = {"title": "Rina", "relationship": "granddaughter"}
    added = client.post(f"/users/{user['id']}/memory-book", json=body, headers=carer_h).json()
    # The phone, offline, edits the same entry with a later clock before it has pulled the caregiver's version.
    _, out = sync(client, user_h, since=since, memory_book=[{"id": added["id"], "title": "Reena", "updated_at": ts(5)}])
    assert out["rejected"][0]["reason"] == "caregiver_edit_wins"
    assert [e["title"] for e in out["memory_book"]] == ["Rina"]

    # After pulling it, the user's own later edit is accepted.
    time.sleep(0.02)
    edit = [{"id": added["id"], "title": "Reena", "updated_at": ts(6)}]
    _, out = sync(client, user_h, since=out["server_time"], memory_book=edit)
    assert out["applied"] == 1


def test_caregiver_additions_flow_down_and_tombstones_sync(client):
    user_h, user = signup(client)
    carer_h, _ = signup(client, role="caregiver")
    link(client, user_h, carer_h)
    _, first = sync(client, user_h)
    r = client.post(
        f"/users/{user['id']}/reminders",
        json={"kind": "medication", "title": "Amlodipine", "time_of_day": "20:00:00"},
        headers=carer_h,
    ).json()
    _, out = sync(client, user_h, since=first["server_time"])
    assert [x["title"] for x in out["reminders"]] == ["Amlodipine"]
    client.delete(f"/users/{user['id']}/reminders/{r['id']}", headers=carer_h)
    _, out2 = sync(client, user_h, since=out["server_time"])
    assert out2["reminders"][0]["deleted"] is True


def test_cannot_overwrite_another_users_record(client):
    a_h, _ = signup(client)
    b_h, _ = signup(client)
    s = session()
    sync(client, a_h, game_sessions=[s])
    _, out = sync(client, b_h, game_sessions=[s | {"correct": 0, "updated_at": ts(1)}])
    assert out["rejected"] == [{"table": "game_sessions", "id": s["id"], "reason": "not_yours"}]


def test_future_timestamps_are_clamped(client):
    h, u = signup(client)
    mid = str(uuid.uuid4())
    sync(client, h, memory_book=[{"id": mid, "title": "A", "updated_at": ts(60 * 24 * 365)}])
    got = client.get(f"/users/{u['id']}/memory-book", headers=h).json()[0]
    updated = datetime.fromisoformat(got["updated_at"])
    if updated.tzinfo is None:
        updated = updated.replace(tzinfo=UTC)
    assert updated < datetime.now(UTC) + timedelta(minutes=10)
