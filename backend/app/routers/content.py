"""Games, NER cultural content and language packs. Admins add or update them
without an app release; the phone downloads them as packs per language and region."""

from datetime import datetime
from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import or_, select

from .. import language_packs
from ..audit import record_audit
from ..deps import Actor, ActorDep, DbDep, require_roles
from ..models import AuditLog, CulturalContent, Game, LanguagePack, Role, utcnow
from ..ratelimit import RateLimit
from ..schemas import (
    CulturalOut,
    CulturalUpsert,
    GameOut,
    GameUpsert,
    LanguageOut,
    LanguagePackOut,
    LanguagePackUpsert,
)
from ..security import as_utc

router = APIRouter(prefix="/content", tags=["content"])
admin = APIRouter(prefix="/admin", tags=["admin"])
READ = [Depends(RateLimit("read"))]
WRITE = [Depends(RateLimit("default"))]
Admin = Annotated[Actor, Depends(require_roles(Role.admin))]


@router.get("/games", response_model=list[GameOut], dependencies=READ)
def games(_: ActorDep, db: DbDep) -> list[Game]:
    return list(db.scalars(select(Game).where(Game.active.is_(True)).order_by(Game.domain, Game.slug)))


@router.get("/cultural", response_model=list[CulturalOut], dependencies=READ)
def cultural(
    _: ActorDep,
    db: DbDep,
    region: Annotated[str, Query(max_length=40)],
    language: Annotated[str, Query(max_length=8)] = "en",
    updated_after: datetime | None = None,
) -> list[CulturalContent]:
    q = select(CulturalContent).where(
        or_(CulturalContent.region == region, CulturalContent.region == "all"),
        CulturalContent.language == language,
    )
    if updated_after:
        q = q.where(CulturalContent.updated_at > as_utc(updated_after))
    return list(db.scalars(q.order_by(CulturalContent.category, CulturalContent.title)))


@router.get("/languages", response_model=list[LanguageOut], dependencies=READ)
def languages(_: ActorDep, db: DbDep) -> list[LanguageOut]:
    """Published languages (latest version of each)."""
    latest: dict[str, LanguagePack] = {}
    for pack in db.scalars(select(LanguagePack).where(LanguagePack.published.is_(True))):
        if pack.language not in latest or pack.version > latest[pack.language].version:
            latest[pack.language] = pack
    out = []
    for code, pack in sorted(latest.items()):
        info = pack.document.get("meta", {})
        out.append(
            LanguageOut(
                code=code,
                english_name=info.get("english_name", code),
                native_name=info.get("native_name", code),
                script=info.get("script", ""),
                version=pack.version,
            )
        )
    return out


@router.get("/language-packs/{language}", response_model=LanguagePackOut, dependencies=READ)
def language_pack(language: str, _: ActorDep, db: DbDep) -> LanguagePack:
    pack = db.scalar(
        select(LanguagePack)
        .where(LanguagePack.language == language, LanguagePack.published.is_(True))
        .order_by(LanguagePack.version.desc())
        .limit(1)
    )
    if pack is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "No pack for this language yet")
    return pack


# --- admin -----------------------------------------------------------------------------------


@admin.put("/games/{slug}", response_model=GameOut, dependencies=WRITE)
def upsert_game(slug: str, body: GameUpsert, actor: Admin, db: DbDep) -> Game:
    if slug != body.slug:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Slug mismatch")
    if body.min_level > body.max_level:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "min_level must be <= max_level")
    game = db.scalar(select(Game).where(Game.slug == slug))
    if game is None:
        game = Game(**body.model_dump())
        db.add(game)
    else:
        for k, v in body.model_dump().items():
            setattr(game, k, v)
    game.updated_at = utcnow()
    db.flush()
    record_audit(db, actor.id, "upsert_game", slug=slug)
    return game


@admin.post("/cultural", response_model=CulturalOut, status_code=201, dependencies=WRITE)
def add_cultural(body: CulturalUpsert, actor: Admin, db: DbDep) -> CulturalContent:
    item = CulturalContent(**body.model_dump(), updated_at=utcnow())
    db.add(item)
    db.flush()
    record_audit(db, actor.id, "add_cultural", id=str(item.id))
    return item


@admin.put("/cultural/{item_id}", response_model=CulturalOut, dependencies=WRITE)
def update_cultural(item_id: UUID, body: CulturalUpsert, actor: Admin, db: DbDep) -> CulturalContent:
    item = db.get(CulturalContent, item_id)
    if item is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Not found")
    for k, v in body.model_dump().items():
        setattr(item, k, v)
    item.updated_at = utcnow()
    record_audit(db, actor.id, "update_cultural", id=str(item_id))
    return item


@admin.put("/language-packs", response_model=LanguagePackOut, dependencies=WRITE)
def upsert_language_pack(body: LanguagePackUpsert, actor: Admin, db: DbDep) -> LanguagePack:
    """Add or replace one pack version. It must pass the same checks as the files in
    content/language-packs (complete, same placeholders as English, right script)."""
    doc = body.document
    errors, _ = language_packs.validate(doc, language_packs.pack(language_packs.SOURCE))
    if errors:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_CONTENT, {"message": "Language pack is not valid", "errors": errors[:50]})
    code, version = doc["language"], doc["version"]
    if not isinstance(code, str) or not 2 <= len(code) <= 8 or not isinstance(version, int) or version < 1:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_CONTENT, "language must be a 2-8 character code and version a positive integer")
    fields = {"strings": doc["strings"], "voice_prompts": doc["voice_prompts"], "document": doc, "published": body.published}
    pack = db.scalar(select(LanguagePack).where(LanguagePack.language == code, LanguagePack.version == version))
    if pack is None:
        pack = LanguagePack(language=code, version=version, **fields)
        db.add(pack)
    else:
        for k, v in fields.items():
            setattr(pack, k, v)
    pack.updated_at = utcnow()
    db.flush()
    record_audit(db, actor.id, "upsert_language_pack", language=code, version=version, published=body.published)
    return pack


@admin.get("/security-events", dependencies=READ)
def security_events(actor: Admin, db: DbDep, limit: Annotated[int, Query(ge=1, le=500)] = 100) -> list[dict]:
    rows = db.scalars(
        select(AuditLog)
        .where(AuditLog.action.in_(["rate_limit_abuse", "login_failed"]))
        .order_by(AuditLog.at.desc())
        .limit(limit)
    )
    return [{"action": r.action, "detail": r.detail, "at": r.at} for r in rows]
