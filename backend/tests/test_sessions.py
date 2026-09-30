import time
from datetime import UTC, datetime, timedelta

import jwt
from sqlalchemy import select

from app.config import get_settings
from app.db import service_session
from app.models import RefreshToken, Role
from app.security import as_utc, hash_refresh_token
from tests.conftest import make_role

_phones = iter(range(10_000))


def sign_in(client, phone=None, **extra):
    phone = phone or f"+9197{next(_phones):08d}"
    code = client.post("/auth/otp", json={"phone": phone}).json()["dev_code"]
    r = client.post("/auth/verify", json={"phone": phone, "code": code, **extra})
    assert r.status_code == 200, r.text
    return r.json() | {"phone": phone}


def bearer(token):
    return {"Authorization": f"Bearer {token}"}


def refresh(client, token):
    return client.post("/auth/refresh", json={"refresh_token": token})


def test_sign_in_issues_a_short_access_token_and_a_refresh_token(client):
    s = sign_in(client, device="phone")
    assert s["expires_in"] == 3600
    assert len(s["refresh_token"]) >= 40
    claims = jwt.decode(s["access_token"], options={"verify_signature": False})
    assert claims["exp"] - claims["iat"] == 3600


def test_only_a_hash_of_the_refresh_token_is_stored(client):
    s = sign_in(client, device="phone")
    with service_session() as db:
        rows = list(db.scalars(select(RefreshToken)))
    assert [r.token_hash for r in rows] == [hash_refresh_token(s["refresh_token"])]
    assert rows[0].token_hash != s["refresh_token"]
    assert rows[0].device == "phone"


def test_refresh_gives_a_working_access_token(client):
    s = sign_in(client)
    r = refresh(client, s["refresh_token"])
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["refresh_token"] is None  # not rotated: the device keeps the one it has
    assert body["user"]["id"] == s["user"]["id"]
    assert client.get("/me", headers=bearer(body["access_token"])).status_code == 200


def test_expired_access_token_is_rejected_and_refresh_recovers(client, monkeypatch):
    monkeypatch.setattr(get_settings(), "access_token_minutes", -1)
    s = sign_in(client)  # its access token is already expired
    assert client.get("/me", headers=bearer(s["access_token"])).status_code == 401

    monkeypatch.setattr(get_settings(), "access_token_minutes", 60)
    fresh = refresh(client, s["refresh_token"]).json()["access_token"]
    assert client.get("/me", headers=bearer(fresh)).status_code == 200


def test_unknown_refresh_token_is_rejected(client):
    assert refresh(client, "x" * 64).status_code == 401


def test_logout_ends_only_that_session(client):
    first = sign_in(client)
    second = sign_in(client, phone=first["phone"])
    assert client.post("/auth/logout", json={"refresh_token": first["refresh_token"]}).status_code == 204
    assert refresh(client, first["refresh_token"]).status_code == 401
    assert refresh(client, second["refresh_token"]).status_code == 200
    # Logging out twice is harmless.
    assert client.post("/auth/logout", json={"refresh_token": first["refresh_token"]}).status_code == 204


def test_logout_all_ends_every_session(client):
    first = sign_in(client)
    second = sign_in(client, phone=first["phone"])
    assert client.post("/auth/logout-all", headers=bearer(second["access_token"])).status_code == 204
    assert refresh(client, first["refresh_token"]).status_code == 401
    assert refresh(client, second["refresh_token"]).status_code == 401
    assert client.post("/auth/logout-all").status_code == 401  # needs a valid access token


def test_session_expires_after_long_inactivity_and_use_extends_it(client):
    s = sign_in(client)
    token_hash = hash_refresh_token(s["refresh_token"])

    assert refresh(client, s["refresh_token"]).status_code == 200
    with service_session() as db:
        row = db.scalar(select(RefreshToken).where(RefreshToken.token_hash == token_hash))
        remaining = as_utc(row.expires_at) - datetime.now(UTC)
        assert timedelta(days=89) < remaining <= timedelta(days=90)
        row.expires_at = datetime.now(UTC) - timedelta(minutes=1)  # unused for longer than the limit

    assert refresh(client, s["refresh_token"]).status_code == 401


def test_refresh_picks_up_a_role_change(client):
    s = sign_in(client, role="caregiver")
    make_role(s["user"]["id"], Role.health_worker)
    body = refresh(client, s["refresh_token"]).json()
    assert body["user"]["role"] == "health_worker"
    assert jwt.decode(body["access_token"], options={"verify_signature": False})["role"] == "health_worker"


def test_oldest_sessions_are_dropped_beyond_the_limit(client, monkeypatch):
    monkeypatch.setattr(get_settings(), "max_sessions_per_user", 2)
    first = sign_in(client)
    time.sleep(0.02)  # Python 3.11 on Windows has a ~15 ms clock; keep the sign-ins in distinct ticks
    second = sign_in(client, phone=first["phone"])
    time.sleep(0.02)
    third = sign_in(client, phone=first["phone"])
    assert refresh(client, first["refresh_token"]).status_code == 401
    assert refresh(client, second["refresh_token"]).status_code == 200
    assert refresh(client, third["refresh_token"]).status_code == 200


def test_renewals_are_rate_limited_per_session(client):
    s = sign_in(client)
    codes = [refresh(client, s["refresh_token"]).status_code for _ in range(31)]
    assert codes[:30] == [200] * 30
    assert codes[30] == 429


def test_repeated_bad_refresh_attempts_are_limited(client):
    codes = [refresh(client, "y" * 64).status_code for _ in range(11)]
    assert codes[:10] == [401] * 10
    assert codes[10] == 429
