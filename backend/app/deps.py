from collections.abc import Iterator
from dataclasses import dataclass
from typing import Annotated
from uuid import UUID

import jwt
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy import select
from sqlalchemy.orm import Session

from .db import user_session
from .models import CARE_ROLES, CaregiverLink, Role
from .security import decode_access_token

_bearer = HTTPBearer(auto_error=False)


@dataclass(frozen=True)
class Actor:
    id: UUID
    role: Role

    @property
    def is_care(self) -> bool:
        return self.role in CARE_ROLES


def current_actor(creds: Annotated[HTTPAuthorizationCredentials | None, Depends(_bearer)]) -> Actor:
    if creds is None:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Not signed in", headers={"WWW-Authenticate": "Bearer"})
    try:
        user_id, role = decode_access_token(creds.credentials)
    except (jwt.PyJWTError, ValueError, KeyError):
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Invalid token", headers={"WWW-Authenticate": "Bearer"}) from None
    return Actor(user_id, role)


ActorDep = Annotated[Actor, Depends(current_actor)]


def db_session(actor: ActorDep) -> Iterator[Session]:
    """One transaction per request with the caller's identity bound for RLS.
    scope="function" commits before the response is sent, so a failed commit is a 500."""
    with user_session(actor.id, actor.role.value) as session:
        yield session


DbDep = Annotated[Session, Depends(db_session, scope="function")]


def require_roles(*roles: Role):
    def check(actor: ActorDep) -> Actor:
        if actor.role not in roles:
            raise HTTPException(status.HTTP_403_FORBIDDEN, "Not allowed for this role")
        return actor

    return check


def assert_can_access(session: Session, actor: Actor, user_id: UUID) -> None:
    """App-level twin of the RLS policies (defence in depth; also what protects SQLite dev)."""
    if actor.id == user_id:
        return
    if actor.is_care:
        linked = session.scalar(
            select(CaregiverLink.id).where(
                CaregiverLink.user_id == user_id,
                CaregiverLink.caregiver_id == actor.id,
                CaregiverLink.active.is_(True),
            )
        )
        if linked:
            return
    raise HTTPException(status.HTTP_404_NOT_FOUND, "Not found")
