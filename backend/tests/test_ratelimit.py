from fastapi.routing import APIRoute

from app.main import app
from app.ratelimit import RateLimit
from tests.conftest import signup


def _has_rate_limit(route: APIRoute) -> bool:
    return any(isinstance(d.call, RateLimit) for d in route.dependant.dependencies)


def test_every_route_is_rate_limited():
    missing = [
        f"{sorted(r.methods)} {r.path}"
        for r in app.routes
        if isinstance(r, APIRoute) and not _has_rate_limit(r)
    ]
    assert missing == [], f"routes without a RateLimit dependency: {missing}"


def test_otp_limited_per_phone_with_retry_after(client):
    phone = "+919811100000"
    for _ in range(3):
        assert client.post("/auth/otp", json={"phone": phone}).status_code == 200
    r = client.post("/auth/otp", json={"phone": phone})
    assert r.status_code == 429
    assert int(r.headers["Retry-After"]) > 0


def test_sathi_limited_per_user(client):
    headers, _ = signup(client)
    codes = [client.post("/sathi/ask", json={"question": "what time is it"}, headers=headers).status_code for _ in range(21)]
    assert codes[:20] == [200] * 20
    assert codes[20] == 429


def test_limits_are_per_user_not_global(client):
    a, _ = signup(client)
    b, _ = signup(client)
    for _ in range(20):
        client.post("/sathi/ask", json={"question": "what time is it"}, headers=a)
    assert client.post("/sathi/ask", json={"question": "what time is it"}, headers=a).status_code == 429
    assert client.post("/sathi/ask", json={"question": "what time is it"}, headers=b).status_code == 200
