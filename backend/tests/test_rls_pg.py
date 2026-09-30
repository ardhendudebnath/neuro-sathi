"""Direct RLS checks, PostgreSQL only (CI). These bypass the API's own checks and
query the tables as app_user with no WHERE clause: the database itself must
hide other people's rows."""

import uuid

import pytest
from sqlalchemy import text
from sqlalchemy.exc import DBAPIError

from app.db import get_engine, user_session
from tests.conftest import PG_URL, link, signup

pytestmark = pytest.mark.skipif(not PG_URL, reason="needs PostgreSQL (TEST_APP_DATABASE_URL)")


def _rows(user_id, role, sql):
    with user_session(uuid.UUID(user_id), role) as s:
        return list(s.execute(text(sql)))


def _add_memory(client, headers, user_id):
    r = client.post(f"/users/{user_id}/memory-book", json={"title": "private"}, headers=headers)
    assert r.status_code == 201


def test_unfiltered_select_only_returns_own_rows(client):
    a_h, a = signup(client)
    b_h, b = signup(client)
    _add_memory(client, a_h, a["id"])
    _add_memory(client, b_h, b["id"])
    rows = _rows(a["id"], "user", "SELECT user_id FROM memory_book")
    assert {str(r.user_id) for r in rows} == {a["id"]}
    assert {str(r.id) for r in _rows(a["id"], "user", "SELECT id FROM users")} == {a["id"]}


def test_no_identity_means_no_rows(client):
    a_h, a = signup(client)
    _add_memory(client, a_h, a["id"])
    with get_engine().begin() as conn:
        assert list(conn.execute(text("SELECT * FROM memory_book"))) == []
        assert list(conn.execute(text("SELECT * FROM users"))) == []


def test_caregiver_reads_only_when_linked(client):
    u_h, u = signup(client)
    c_h, c = signup(client, role="caregiver")
    _add_memory(client, u_h, u["id"])
    assert _rows(c["id"], "caregiver", "SELECT id FROM memory_book") == []
    link(client, u_h, c_h)
    assert len(_rows(c["id"], "caregiver", "SELECT id FROM memory_book")) == 1


def test_caregiver_cannot_write_activity(client):
    u_h, u = signup(client)
    c_h, c = signup(client, role="caregiver")
    link(client, u_h, c_h)
    with pytest.raises(DBAPIError):
        with user_session(uuid.UUID(c["id"]), "caregiver") as s:
            s.execute(
                text(
                    "INSERT INTO activity_log (id, user_id, kind, payload, occurred_at, updated_at, deleted) "
                    "VALUES (:id, :uid, 'x', '{}', now(), now(), false)"
                ),
                {"id": str(uuid.uuid4()), "uid": u["id"]},
            )


def test_app_user_cannot_change_own_role(client):
    a_h, a = signup(client)
    with pytest.raises(DBAPIError):
        with user_session(uuid.UUID(a["id"]), "user") as s:
            s.execute(text("UPDATE users SET role = 'admin' WHERE id = :id"), {"id": a["id"]})


def test_app_user_cannot_read_otp_codes(client):
    a_h, a = signup(client)
    with pytest.raises(DBAPIError):
        _rows(a["id"], "user", "SELECT * FROM otp_codes")


def test_app_user_cannot_read_sessions(client):
    a_h, a = signup(client)  # signing in created a refresh-token row for this user
    with pytest.raises(DBAPIError):
        _rows(a["id"], "user", "SELECT * FROM refresh_tokens")


def test_admin_cannot_read_personal_rows(client):
    from app.models import Role
    from tests.conftest import make_role

    u_h, u = signup(client)
    _add_memory(client, u_h, u["id"])
    _, adm = signup(client)
    make_role(adm["id"], Role.admin)
    assert _rows(adm["id"], "admin", "SELECT id FROM memory_book") == []
