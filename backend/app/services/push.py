"""Caregiver push alerts via Firebase Cloud Messaging (server-side Admin SDK).
Disabled, with a log line, when no Firebase credentials are configured."""

import logging

from ..config import get_settings

log = logging.getLogger("neuro_sathi.push")
_app = None


def _messaging():
    global _app
    path = get_settings().firebase_credentials_file
    if not path:
        return None
    import firebase_admin  # optional dependency
    from firebase_admin import credentials, messaging

    if _app is None:
        _app = firebase_admin.initialize_app(credentials.Certificate(path))
    return messaging


def send(tokens: list[str], title: str, body: str, data: dict[str, str] | None = None) -> None:
    if not tokens:
        return
    messaging = _messaging()
    if messaging is None:
        log.info("push disabled; would notify %d device(s): %s", len(tokens), title)
        return
    try:
        messaging.send_each_for_multicast(
            messaging.MulticastMessage(
                tokens=tokens, notification=messaging.Notification(title=title, body=body), data=data or {}
            )
        )
    except Exception:  # noqa: BLE001 - an alert is still stored even if push fails
        log.exception("push failed")
