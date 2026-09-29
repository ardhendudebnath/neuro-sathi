import os
import uuid
from datetime import UTC, datetime

os.environ.setdefault("ENV", "test")
os.environ.setdefault("OTP_DEV_ECHO", "true")
os.environ.setdefault("DATABASE_URL", "sqlite+pysqlite:///:memory:")
os.environ.setdefault("STORAGE_LOCAL_DIR", os.path.join(os.path.dirname(__file__), ".uploads"))

import pytest  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402

from app import db as app_db  # noqa: E402
from app.db import service_session  # noqa: E402
from app.main import app  # noqa: E402
from app.models import Base, Role, User  # noqa: E402
from app.ratelimit import reset_limits  # noqa: E402
from app.seed import seed_content  # noqa: E402

PG_URL = os.environ.get("TEST_APP_DATABASE_URL")  # set in CI to run against PostgreSQL + RLS


@pytest.fixture(autouse=True)
def fresh_db():
    if PG_URL:
        from tests.pg import reset_postgres

        reset_postgres()
    else:
        engine = app_db._make_engine("sqlite+pysqlite:///:memory:")
        Base.metadata.create_all(engine)
        app_db.set_engines(engine)
    reset_limits()
    with service_session() as s:
        seed_content(s)
    yield


@pytest.fixture
def client():
    with TestClient(app) as c:
        yield c


_phone_counter = iter(range(10_000))


def signup(client: TestClient, role: str = "user", name: str = "Test") -> tuple[dict, dict]:
    """Sign up via OTP; returns (auth headers, user json)."""
    phone = f"+9198{next(_phone_counter):08d}"
    r = client.post("/auth/otp", json={"phone": phone})
    assert r.status_code == 200, r.text
    code = r.json()["dev_code"]
    r = client.post("/auth/verify", json={"phone": phone, "code": code, "name": name, "role": role})
    assert r.status_code == 200, r.text
    body = r.json()
    return {"Authorization": f"Bearer {body['access_token']}"}, body["user"]


def make_role(user_id: str, role: Role) -> None:
    with service_session() as s:
        s.get(User, uuid.UUID(user_id)).role = role


def login_again(client: TestClient, phone: str) -> dict:
    code = client.post("/auth/otp", json={"phone": phone}).json()["dev_code"]
    tok = client.post("/auth/verify", json={"phone": phone, "code": code}).json()["access_token"]
    return {"Authorization": f"Bearer {tok}"}


def link(client: TestClient, user_headers: dict, carer_headers: dict, relationship: str = "daughter") -> dict:
    code = client.post("/links/code", headers=user_headers).json()["code"]
    r = client.post("/links/redeem", json={"code": code, "relationship": relationship}, headers=carer_headers)
    assert r.status_code == 200, r.text
    return r.json()


def now_iso() -> str:
    return datetime.now(UTC).isoformat()
