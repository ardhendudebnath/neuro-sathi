"""The signed-in person's own account, profile, device tokens and caregiver links."""

from datetime import UTC, datetime, timedelta
from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import or_, select

from ..audit import record_audit
from ..db import service_session
from ..deps import Actor, ActorDep, DbDep, require_roles
from ..models import CaregiverLink, DeviceToken, LinkCode, Profile, Role, User, utcnow
from ..ratelimit import RateLimit
from ..schemas import (
    DeviceTokenIn,
    LinkCodeOut,
    LinkOut,
    LinkRedeem,
    ProfileOut,
    ProfilePatch,
    UserOut,
    UserPatch,
)
from ..security import as_utc, new_link_code

router = APIRouter(tags=["account"])
READ = [Depends(RateLimit("read"))]
WRITE = [Depends(RateLimit("default"))]


@router.get("/me", response_model=UserOut, dependencies=READ)
def get_me(actor: ActorDep, db: DbDep) -> User:
    user = db.get(User, actor.id)
    if user is None:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Account not found")
    return user


@router.patch("/me", response_model=UserOut, dependencies=WRITE)
def patch_me(body: UserPatch, actor: ActorDep, db: DbDep) -> User:
    user = db.get(User, actor.id)
    for k, v in body.model_dump(exclude_unset=True).items():
        setattr(user, k, v)
    return user


@router.get("/me/profile", response_model=ProfileOut, dependencies=READ)
def get_profile(actor: ActorDep, db: DbDep) -> Profile:
    profile = db.get(Profile, actor.id)
    if profile is None:
        profile = Profile(user_id=actor.id)
        db.add(profile)
        db.flush()
    return profile


@router.patch("/me/profile", response_model=ProfileOut, dependencies=WRITE)
def patch_profile(body: ProfilePatch, actor: ActorDep, db: DbDep) -> Profile:
    profile = get_profile(actor, db)
    for k, v in body.model_dump(exclude_unset=True).items():
        setattr(profile, k, v)
    profile.updated_at = utcnow()
    if body.voice_consent is not None:
        record_audit(db, actor.id, "voice_consent", actor.id, value=body.voice_consent)
    return profile


@router.post("/me/devices", status_code=204, dependencies=WRITE)
def register_device(body: DeviceTokenIn, actor: ActorDep, db: DbDep) -> None:
    row = db.get(DeviceToken, body.token)
    if row is None:
        db.add(DeviceToken(token=body.token, user_id=actor.id, platform=body.platform))
    elif row.user_id == actor.id:
        row.updated_at = utcnow()
    # A token owned by someone else is left alone (RLS hides it anyway).


# --- caregiver links -------------------------------------------------------------------


@router.post("/links/code", response_model=LinkCodeOut, dependencies=WRITE)
def create_link_code(actor: Annotated[Actor, Depends(require_roles(Role.user))], db: DbDep) -> LinkCodeOut:
    """The elderly user's app shows this code; a caregiver types it in to link."""
    code = new_link_code()
    expires = datetime.now(UTC) + timedelta(hours=24)
    db.add(LinkCode(code=code, user_id=actor.id, expires_at=expires))
    return LinkCodeOut(code=code, expires_at=expires)


@router.post("/links/redeem", response_model=LinkOut, dependencies=WRITE)
def redeem_link_code(
    body: LinkRedeem, actor: Annotated[Actor, Depends(require_roles(Role.caregiver, Role.health_worker))]
) -> CaregiverLink:
    # The code belongs to another user, so RLS would hide it: use the service role, narrowly.
    with service_session() as db:
        lc = db.get(LinkCode, body.code.strip().upper(), with_for_update=True)
        if lc is None or as_utc(lc.expires_at) < datetime.now(UTC):
            raise HTTPException(status.HTTP_404_NOT_FOUND, "Code not found or expired")
        user_id = lc.user_id
        db.delete(lc)
        link = db.scalar(select(CaregiverLink).where(CaregiverLink.user_id == user_id, CaregiverLink.caregiver_id == actor.id))
        if link is None:
            link = CaregiverLink(user_id=user_id, caregiver_id=actor.id, relationship=body.relationship)
            db.add(link)
        else:
            link.active, link.relationship = True, body.relationship or link.relationship
        db.flush()
        record_audit(db, actor.id, "link_created", user_id, relationship=body.relationship)
        return link


@router.get("/links", response_model=list[LinkOut], dependencies=READ)
def list_links(actor: ActorDep, db: DbDep) -> list[CaregiverLink]:
    return list(
        db.scalars(
            select(CaregiverLink)
            .where(or_(CaregiverLink.user_id == actor.id, CaregiverLink.caregiver_id == actor.id))
            .order_by(CaregiverLink.created_at)
        )
    )


@router.delete("/links/{link_id}", status_code=204, dependencies=WRITE)
def end_link(link_id: UUID, actor: ActorDep, db: DbDep) -> None:
    """Either side can end a link; access stops immediately."""
    link = db.get(CaregiverLink, link_id)
    if link is None or actor.id not in (link.user_id, link.caregiver_id):
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Not found")
    link.active = False
    record_audit(db, actor.id, "link_ended", link.user_id)
