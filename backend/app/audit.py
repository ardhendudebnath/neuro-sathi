"""Audit log: who viewed or changed whose data, plus security events for admins."""

import logging
from uuid import UUID

from sqlalchemy.orm import Session

from .models import AuditLog

log = logging.getLogger("neuro_sathi.audit")


def record_audit(
    session: Session,
    actor_id: UUID | None,
    action: str,
    target_user_id: UUID | None = None,
    **detail: object,
) -> None:
    session.add(AuditLog(actor_id=actor_id, action=action, target_user_id=target_user_id, detail=detail))


def record_security_event(action: str, detail: dict) -> None:
    """Written with the service role so it is recorded even for anonymous callers."""
    from .db import service_session

    try:
        with service_session() as s:
            s.add(AuditLog(actor_id=None, action=action, detail=detail))
    except Exception:  # noqa: BLE001 - never fail a request because auditing failed
        log.exception("could not record security event %s", action)
