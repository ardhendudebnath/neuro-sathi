import uuid
from typing import Annotated

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile, status
from fastapi.responses import Response
from sqlalchemy import select
from sqlalchemy.orm import Session

from .. import language_packs
from ..config import get_settings
from ..deps import Actor, DbDep, require_roles
from ..models import ActivityLog, MemoryBookEntry, Profile, Reminder, Role, utcnow
from ..ratelimit import RateLimit
from ..schemas import SathiAnswer, SathiAsk, TtsRequest
from ..services import budget, nvidia
from ..services.sathi_engine import answer_locally, t

router = APIRouter(tags=["sathi"])
ElderlyUser = Annotated[Actor, Depends(require_roles(Role.user))]


@router.post("/sathi/ask", response_model=SathiAnswer, dependencies=[Depends(RateLimit("sathi"))])
def ask(body: SathiAsk, actor: ElderlyUser, db: DbDep) -> SathiAnswer:
    reminders = list(db.scalars(select(Reminder).where(Reminder.user_id == actor.id, Reminder.deleted.is_(False))))
    entries = list(db.scalars(select(MemoryBookEntry).where(MemoryBookEntry.user_id == actor.id, MemoryBookEntry.deleted.is_(False))))
    local = answer_locally(body.question, body.language, reminders, entries)
    if local is not None:
        answer = SathiAnswer(answer=local.text, source="local")
    elif not nvidia.enabled() or not language_packs.llm_supported(body.language) or budget.over_budget(db):
        answer = SathiAnswer(answer=t(body.language, "fallback"), source="offline_fallback")
    else:
        answer = _ask_llm(body, db)
    db.add(
        ActivityLog(
            id=uuid.uuid4(), user_id=actor.id, kind="sathi_ask", occurred_at=utcnow(), updated_at=utcnow(),
            payload={"source": answer.source, "language": body.language},  # the question itself is not stored
        )
    )
    return answer


def _ask_llm(body: SathiAsk, db: Session) -> SathiAnswer:
    # Counted up front (safety in + reply + safety out) so failed calls still count toward the cap.
    budget.record_spend(db, "nvidia_llm", get_settings().llm_cost_per_call_inr * 3)
    try:
        if not nvidia.is_safe(body.question):
            return SathiAnswer(answer=t(body.language, "blocked"), source="safety_block")
        reply = nvidia.companion_reply(body.question, body.language)
        if not reply or not nvidia.is_safe(body.question, reply):
            return SathiAnswer(answer=t(body.language, "blocked"), source="safety_block")
        return SathiAnswer(answer=reply, source="llm")
    except nvidia.NvidiaUnavailable:
        return SathiAnswer(answer=t(body.language, "fallback"), source="offline_fallback")


def _require_voice_consent(actor: Actor, db) -> None:  # noqa: ANN001
    profile = db.get(Profile, actor.id)
    if profile is None or not profile.voice_consent:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Voice consent is needed before audio leaves the phone")


def _speech_available(db: Session) -> None:
    if not nvidia.enabled() or budget.over_budget(db):
        # The app falls back to on-device speech.
        raise HTTPException(status.HTTP_503_SERVICE_UNAVAILABLE, "Cloud speech unavailable; use on-device voice")


@router.post("/speech/stt", dependencies=[Depends(RateLimit("speech"))])
def speech_to_text(
    actor: ElderlyUser, db: DbDep, audio: UploadFile = File(...), language: Annotated[str, Form()] = "en"
) -> dict:
    _require_voice_consent(actor, db)
    _speech_available(db)
    data = audio.file.read(2 * 1024 * 1024 + 1)
    if len(data) > 2 * 1024 * 1024:
        raise HTTPException(status.HTTP_413_CONTENT_TOO_LARGE, "Audio clip too long")
    try:
        text = nvidia.speech_to_text(data, language)
    except nvidia.NvidiaUnavailable:
        raise HTTPException(status.HTTP_503_SERVICE_UNAVAILABLE, "Cloud speech unavailable; use on-device voice") from None
    budget.record_spend(db, "nvidia_speech", get_settings().speech_cost_per_call_inr)
    return {"text": text}


@router.post("/speech/tts", dependencies=[Depends(RateLimit("speech"))])
def text_to_speech(body: TtsRequest, actor: ElderlyUser, db: DbDep) -> Response:
    _speech_available(db)
    try:
        wav = nvidia.text_to_speech(body.text, body.language)
    except nvidia.NvidiaUnavailable:
        raise HTTPException(status.HTTP_503_SERVICE_UNAVAILABLE, "Cloud speech unavailable; use on-device voice") from None
    budget.record_spend(db, "nvidia_speech", get_settings().speech_cost_per_call_inr)
    return Response(content=wav, media_type="audio/wav")
