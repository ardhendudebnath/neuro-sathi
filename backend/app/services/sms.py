import logging

import httpx

from ..config import get_settings

log = logging.getLogger("neuro_sathi.sms")


def send_otp(phone: str, code: str) -> None:
    s = get_settings()
    if s.sms_provider == "console":
        if s.is_production:
            raise RuntimeError("SMS_PROVIDER=console is not allowed in production")
        log.info("OTP for %s: %s (console provider, development only)", phone, code)
        return
    if s.sms_provider == "msg91":
        if not s.sms_api_key or not s.sms_template_id:
            raise RuntimeError("MSG91 needs SMS_API_KEY and SMS_TEMPLATE_ID")
        resp = httpx.post(
            "https://control.msg91.com/api/v5/otp",
            params={"template_id": s.sms_template_id, "mobile": phone.lstrip("+"), "otp": code},
            headers={"authkey": s.sms_api_key.get_secret_value()},
            timeout=10,
        )
        resp.raise_for_status()
        return
    raise RuntimeError(f"unknown SMS provider {s.sms_provider}")
