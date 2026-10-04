from datetime import UTC, datetime, timedelta

from fastapi import APIRouter, Depends, HTTPException, Request, status
from sqlalchemy import select, update
from sqlalchemy.orm import Session

from ..audit import record_audit, record_security_event
from ..config import get_settings
from ..db import service_session
from ..deps import ActorDep
from ..models import OtpCode, Profile, RefreshToken, Role, User
from ..ratelimit import RateLimit, check_limit, client_ip
from ..schemas import OtpRequest, OtpResponse, OtpVerify, RefreshRequest, TokenResponse, UserOut
from ..security import (
    access_token_seconds,
    as_utc,
    create_access_token,
    hash_otp,
    hash_refresh_token,
    new_otp,
    new_refresh_token,
    normalise_phone,
    otp_matches,
)
from ..services import sms

router = APIRouter(prefix="/auth", tags=["auth"])


def _start_session(db: Session, user: User, device: str | None) -> str:
    """Create a session for this device and return its refresh token (only a hash is stored)."""
    s = get_settings()
    now = datetime.now(UTC)
    sessions = list(db.scalars(select(RefreshToken).where(RefreshToken.user_id == user.id)))
    live = []
    for old in sessions:  # tidy up: drop this user's revoked and expired sessions
        if old.revoked_at is not None or as_utc(old.expires_at) < now:
            db.delete(old)
        else:
            live.append(old)
    live.sort(key=lambda r: as_utc(r.last_used_at), reverse=True)
    for extra in live[max(s.max_sessions_per_user - 1, 0) :]:  # keep only the most recently used
        db.delete(extra)
    token = new_refresh_token()
    db.add(
        RefreshToken(
            user_id=user.id,
            token_hash=hash_refresh_token(token),
            device=device,
            created_at=now,
            last_used_at=now,
            expires_at=now + timedelta(days=s.refresh_token_days),
        )
    )
    return token


@router.post("/otp", response_model=OtpResponse, dependencies=[Depends(RateLimit("otp_ip"))])
def request_otp(body: OtpRequest) -> OtpResponse:
    s = get_settings()
    phone = normalise_phone(body.phone)
    check_limit("otp_phone", phone)
    code = new_otp()
    with service_session() as db:
        row = db.get(OtpCode, phone)
        expires = datetime.now(UTC) + timedelta(seconds=s.otp_ttl_seconds)
        if row is None:
            db.add(OtpCode(phone=phone, code_hash=hash_otp(phone, code), expires_at=expires, attempts=0))
        else:
            row.code_hash, row.expires_at, row.attempts = hash_otp(phone, code), expires, 0
    sms.send_otp(phone, code)
    dev = code if (s.otp_dev_echo and not s.is_production) else None
    return OtpResponse(expires_in=s.otp_ttl_seconds, dev_code=dev)


@router.post("/verify", response_model=TokenResponse, dependencies=[Depends(RateLimit("otp_ip"))])
def verify_otp(body: OtpVerify, request: Request) -> TokenResponse:
    s = get_settings()
    phone = normalise_phone(body.phone)
    bad = HTTPException(status.HTTP_401_UNAUTHORIZED, "Wrong or expired code")
    with service_session() as db:
        row = db.get(OtpCode, phone, with_for_update=True)
        if row is None or as_utc(row.expires_at) < datetime.now(UTC) or row.attempts >= s.otp_max_attempts:
            raise bad
        if not otp_matches(phone, body.code, row.code_hash):
            row.attempts += 1
            failed = True
        else:
            db.delete(row)
            failed = False
            name = (body.name or "").strip() or None
            user = db.scalar(select(User).where(User.phone == phone))
            if user is None:
                user = User(phone=phone, name=name, role=Role(body.role))
                db.add(user)
                db.flush()
                db.add(Profile(user_id=user.id))
                record_audit(db, user.id, "signup", user.id, role=user.role.value)
            elif name and name != user.name:
                # The app asks for a name whenever it is set up, also on a new phone or
                # after a reinstall: what the person types is what they want to be
                # called. Left empty, the stored name stays.
                user.name = name
            record_audit(db, user.id, "login", user.id)
            token = create_access_token(user.id, user.role)
            refresh_token = _start_session(db, user, body.device)
            out = UserOut.model_validate(user)
    if failed:
        # Committed above (attempt counter); failures are rate limited per phone and logged.
        record_security_event("login_failed", {"phone_suffix": phone[-4:], "ip": client_ip(request)})
        check_limit("login_fail", phone)
        raise bad
    return TokenResponse(access_token=token, expires_in=access_token_seconds(), refresh_token=refresh_token, user=out)


@router.post("/refresh", response_model=TokenResponse, dependencies=[Depends(RateLimit("default"))])
def refresh(body: RefreshRequest, request: Request) -> TokenResponse:
    """Renew the access token with the session's refresh token.

    The refresh token is deliberately not rotated. On a weak connection a lost
    reply would leave the device holding a dead token and sign the user out.
    Instead it is revocable, and expires after `refresh_token_days` without use
    (each renewal pushes the expiry forward).
    """
    s = get_settings()
    now = datetime.now(UTC)
    with service_session() as db:
        row = db.scalar(select(RefreshToken).where(RefreshToken.token_hash == hash_refresh_token(body.refresh_token)))
        valid = row is not None and row.revoked_at is None and as_utc(row.expires_at) >= now
        if valid:
            check_limit("refresh", str(row.id))
            user = db.get(User, row.user_id)
            row.last_used_at = now
            row.expires_at = now + timedelta(days=s.refresh_token_days)
            token = create_access_token(user.id, user.role)  # also picks up a role change
            out = UserOut.model_validate(user)
    if not valid:
        check_limit("login_fail", f"refresh:{client_ip(request)}")
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Session expired. Please sign in again.")
    return TokenResponse(access_token=token, expires_in=access_token_seconds(), user=out)


@router.post("/logout", status_code=204, dependencies=[Depends(RateLimit("default"))])
def logout(body: RefreshRequest) -> None:
    """End this session. Takes the refresh token, so it works even after the access token has expired."""
    with service_session() as db:
        row = db.scalar(select(RefreshToken).where(RefreshToken.token_hash == hash_refresh_token(body.refresh_token)))
        if row is not None and row.revoked_at is None:
            row.revoked_at = datetime.now(UTC)
            record_audit(db, row.user_id, "logout", row.user_id)


@router.post("/logout-all", status_code=204, dependencies=[Depends(RateLimit("default"))])
def logout_all(actor: ActorDep) -> None:
    """End every session of this account, for example after a phone is lost. Access
    tokens already issued stay valid until they expire (at most an hour)."""
    with service_session() as db:
        db.execute(
            update(RefreshToken)
            .where(RefreshToken.user_id == actor.id, RefreshToken.revoked_at.is_(None))
            .values(revoked_at=datetime.now(UTC))
        )
        record_audit(db, actor.id, "logout_all", actor.id)
