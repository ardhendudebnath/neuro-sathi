"""Per-route rate limits.

Built on `limits` (the engine behind SlowAPI) so a limit can be keyed by user id,
IP or phone number from inside a dependency. Counters live in Redis in
production and in memory in development and tests. Every router is mounted with
a RateLimit dependency; tests/test_ratelimit.py fails if a route has none.
"""

import logging
import time

from fastapi import HTTPException, Request
from limits import RateLimitItem, parse_many
from limits.storage import Storage, storage_from_string
from limits.strategies import FixedWindowRateLimiter

from .config import get_settings
from .security import decode_access_token

log = logging.getLogger("neuro_sathi.ratelimit")

# Starting values from the design doc; tune after testing.
LIMITS: dict[str, str] = {
    "otp_phone": "3/15 minutes",
    "otp_ip": "10/hour",
    "login_fail": "10/hour",
    "refresh": "30/hour",
    "sathi": "20/minute;200/day",
    "speech": "30/minute;500/day",
    "upload": "20/hour",
    "sync": "60/hour",
    "read": "120/minute",
    "default": "60/minute",
}

_ABUSE = parse_many("20/hour")[0]  # repeated 429s from one key within an hour
_ABUSE_NOTIFY = parse_many("1/hour")[0]

_storage: Storage | None = None
_limiter: FixedWindowRateLimiter | None = None


def get_limiter() -> FixedWindowRateLimiter:
    global _storage, _limiter
    if _limiter is None:
        redis_url = get_settings().redis_url
        _storage = storage_from_string(redis_url.get_secret_value() if redis_url else "memory://")
        _limiter = FixedWindowRateLimiter(_storage)
    return _limiter


def reset_limits() -> None:
    get_limiter()
    assert _storage is not None
    _storage.reset()


def client_ip(request: Request) -> str:
    # Behind the reverse proxy, uvicorn --proxy-headers fills request.client from X-Forwarded-For.
    return request.client.host if request.client else "unknown"


def _retry_after(item: RateLimitItem, group: str, key: str) -> int:
    stats = get_limiter().get_window_stats(item, group, key)
    return max(1, int(stats.reset_time - time.time()))


def _record_abuse(group: str, key: str) -> None:
    limiter = get_limiter()
    if not limiter.hit(_ABUSE, "abuse", key) and limiter.hit(_ABUSE_NOTIFY, "abuse_notified", key):
        log.warning("repeated 429s: key=%s group=%s", key, group)
        from .audit import record_security_event

        record_security_event("rate_limit_abuse", {"key": key, "group": group})


def check_limit(group: str, key: str) -> None:
    """Count one request for (group, key); raise 429 with Retry-After when over."""
    limiter = get_limiter()
    for item in parse_many(LIMITS[group]):
        if not limiter.hit(item, group, key):
            _record_abuse(group, key)
            raise HTTPException(
                status_code=429,
                detail="Too many requests. Please try again later.",
                headers={"Retry-After": str(_retry_after(item, group, key))},
            )


def request_key(request: Request) -> str:
    """User id when a valid bearer token is present, otherwise the client IP."""
    auth = request.headers.get("authorization", "")
    if auth.lower().startswith("bearer "):
        try:
            user_id, _ = decode_access_token(auth[7:])
            return f"user:{user_id}"
        except Exception:  # noqa: BLE001 - an invalid token is limited by IP
            pass
    return f"ip:{client_ip(request)}"


class RateLimit:
    """Router/route dependency: RateLimit("read")."""

    def __init__(self, group: str):
        if group not in LIMITS:
            raise ValueError(f"unknown rate-limit group {group}")
        self.group = group

    def __call__(self, request: Request) -> None:
        check_limit(self.group, request_key(request))
