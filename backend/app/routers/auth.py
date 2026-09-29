from datetime import UTC, datetime, timedelta

from fastapi import APIRouter, Depends, HTTPException, Request, status
from sqlalchemy import select

from ..audit import record_audit, record_security_event
from ..config import get_settings
from ..db import service_session
from ..models import OtpCode, Profile, Role, User
from ..ratelimit import RateLimit, check_limit, client_ip
from ..schemas import OtpRequest, OtpResponse, OtpVerify, TokenResponse, UserOut
from ..security import as_utc, create_access_token, hash_otp, new_otp, otp_matches
from ..services import sms

router = APIRouter(prefix="/auth", tags=["auth"])


def _normalise(phone: str) -> str:
    """Store Indian numbers as +91XXXXXXXXXX."""
    digits = phone.lstrip("+")
    if len(digits) == 10:
        digits = "91" + digits
    return "+" + digits


@router.post("/otp", response_model=OtpResponse, dependencies=[Depends(RateLimit("otp_ip"))])
def request_otp(body: OtpRequest) -> OtpResponse:
    s = get_settings()
    phone = _normalise(body.phone)
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
    phone = _normalise(body.phone)
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
            user = db.scalar(select(User).where(User.phone == phone))
            if user is None:
                user = User(phone=phone, name=body.name, role=Role(body.role))
                db.add(user)
                db.flush()
                db.add(Profile(user_id=user.id))
                record_audit(db, user.id, "signup", user.id, role=user.role.value)
            record_audit(db, user.id, "login", user.id)
            token = create_access_token(user.id, user.role)
            out = UserOut.model_validate(user)
    if failed:
        # Committed above (attempt counter); failures are rate limited per phone and logged.
        record_security_event("login_failed", {"phone_suffix": phone[-4:], "ip": client_ip(request)})
        check_limit("login_fail", phone)
        raise bad
    return TokenResponse(access_token=token, user=out)
