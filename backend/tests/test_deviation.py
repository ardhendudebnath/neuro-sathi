import random
import uuid
from datetime import UTC, datetime, timedelta

from app.db import user_session
from app.jobs.deviation_job import run_once
from app.models import Game, GameSession
from app.services.deviation import detect
from app.services.personalisation import decide_level, extract_features
from tests.conftest import link, signup

NOW = datetime(2026, 9, 30, 12, 0, tzinfo=UTC)


def make_sessions(user_id, days_ago_range, per_day, resp_ms, acc, completed=True, seed=1):
    rnd = random.Random(seed)
    out = []
    for d in days_ago_range:
        for i in range(per_day):
            start = NOW - timedelta(days=d, hours=2 + i)
            out.append(
                GameSession(
                    id=uuid.uuid4(), user_id=user_id, game_slug="odd_one_out", level=2, started_at=start,
                    ended_at=start + timedelta(minutes=5), trials=20, correct=round(20 * acc), errors=20 - round(20 * acc),
                    repeated_errors=0, avg_response_ms=resp_ms * rnd.uniform(0.95, 1.05), completed=completed,
                    updated_at=start, deleted=False,
                )
            )
    return out


def test_stable_user_has_no_findings():
    uid = uuid.uuid4()
    s = make_sessions(uid, range(0, 35), 2, 2000, 0.85)
    assert detect(s, [], NOW) == []


def test_slower_and_less_accurate_week_is_flagged():
    uid = uuid.uuid4()
    s = make_sessions(uid, range(7, 35), 2, 2000, 0.85) + make_sessions(uid, range(0, 7), 2, 3200, 0.55, seed=2)
    kinds = {f.kind for f in detect(s, [], NOW)}
    assert {"slower_responses", "lower_accuracy"} <= kinds


def test_reduced_activity_is_flagged():
    uid = uuid.uuid4()
    s = make_sessions(uid, range(7, 35), 2, 2000, 0.85) + make_sessions(uid, [1], 1, 2000, 0.85)
    assert "less_activity" in {f.kind for f in detect(s, [], NOW)}


def test_not_enough_history_means_no_alert():
    uid = uuid.uuid4()
    s = make_sessions(uid, range(7, 10), 1, 2000, 0.85) + make_sessions(uid, range(0, 7), 2, 5000, 0.3)
    assert detect(s, [], NOW) == []


def test_job_creates_one_alert_and_caregiver_can_ack(client):
    user_h, user = signup(client, name="Anima")
    carer_h, _ = signup(client, role="caregiver")
    link(client, user_h, carer_h)
    uid = uuid.UUID(user["id"])
    with user_session(uid, "user") as db:  # the user's own rows, as the phone would sync them
        db.add_all(make_sessions(uid, range(7, 35), 2, 2000, 0.85) + make_sessions(uid, range(0, 7), 2, 3500, 0.5, seed=3))
    assert run_once(NOW) == 1
    assert run_once(NOW) == 0  # deduplicated
    alerts = client.get(f"/dashboard/users/{user['id']}/alerts", headers=carer_h).json()
    assert len(alerts) == 1
    assert alerts[0]["severity"] == "check_in"
    assert "not a diagnosis" in alerts[0]["message"]
    r = client.post(f"/dashboard/alerts/{alerts[0]['id']}/ack", headers=carer_h)
    assert r.status_code == 200 and r.json()["acknowledged_at"]
    assert client.get(f"/dashboard/users/{user['id']}/alerts", headers=carer_h).json() == []


def test_difficulty_moves_up_and_down():
    game = Game(slug="odd_one_out", name="x", domain="attention", min_level=1, max_level=5)
    uid = uuid.uuid4()
    good = make_sessions(uid, range(0, 3), 1, 1500, 0.95)
    assert decide_level(extract_features(game, good, NOW), game)[0] == 3
    poor = make_sessions(uid, range(0, 3), 1, 4000, 0.4)
    assert decide_level(extract_features(game, poor, NOW), game)[0] == 1
