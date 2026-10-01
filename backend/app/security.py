import hashlib
import hmac
import secrets
from datetime import UTC, datetime, timedelta
from uuid import UUID

import jwt

from .config import get_settings
from .models import Role


def create_access_token(user_id: UUID, role: Role) -> str:
    s = get_settings()
    now = datetime.now(UTC)
    payload = {
        "sub": str(user_id),
        "role": role.value,
        "iat": now,
        "exp": now + timedelta(minutes=s.access_token_minutes),
    }
    return jwt.encode(payload, s.jwt_secret.get_secret_value(), algorithm=s.jwt_algorithm)


def decode_access_token(token: str) -> tuple[UUID, Role]:
    """Raises jwt.PyJWTError or ValueError on a bad token."""
    s = get_settings()
    payload = jwt.decode(
        token,
        s.jwt_secret.get_secret_value(),
        algorithms=[s.jwt_algorithm],
        options={"require": ["sub", "exp", "role"]},
    )
    return UUID(payload["sub"]), Role(payload["role"])


def access_token_seconds() -> int:
    return get_settings().access_token_minutes * 60


def new_refresh_token() -> str:
    return secrets.token_urlsafe(48)


def hash_refresh_token(token: str) -> str:
    """Only this hash is stored. The token is 384 random bits, so a keyed SHA-256 is enough."""
    key = get_settings().jwt_secret.get_secret_value().encode()
    return hmac.new(key, f"refresh:{token}".encode(), hashlib.sha256).hexdigest()


def normalise_phone(phone: str) -> str:
    """Store Indian numbers as +91XXXXXXXXXX."""
    digits = phone.strip().lstrip("+")
    if len(digits) == 10:
        digits = "91" + digits
    return "+" + digits


def new_otp() -> str:
    return f"{secrets.randbelow(1_000_000):06d}"


def hash_otp(phone: str, code: str) -> str:
    key = get_settings().jwt_secret.get_secret_value().encode()
    return hmac.new(key, f"{phone}:{code}".encode(), hashlib.sha256).hexdigest()


def otp_matches(phone: str, code: str, code_hash: str) -> bool:
    return hmac.compare_digest(hash_otp(phone, code), code_hash)


def new_link_code() -> str:
    alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"  # no 0/O/1/I, easy to read aloud
    return "".join(secrets.choice(alphabet) for _ in range(8))


def as_utc(dt: datetime | None) -> datetime | None:
    """SQLite drops tzinfo; treat naive datetimes as UTC."""
    if dt is None:
        return None
    return dt.replace(tzinfo=UTC) if dt.tzinfo is None else dt.astimezone(UTC)
