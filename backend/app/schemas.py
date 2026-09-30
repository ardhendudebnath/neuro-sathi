from datetime import date, datetime, time
from typing import Annotated, Literal
from uuid import UUID

from pydantic import AfterValidator, BaseModel, ConfigDict, Field, field_validator

from . import language_packs
from .models import Role

PHONE_PATTERN = r"^\+?[1-9]\d{9,14}$"


def _known_language(code: str) -> str:
    if code not in language_packs.supported():
        raise ValueError(f"unsupported language '{code}'")
    return code


# Any language with a pack in content/language-packs (preview packs included, for testing).
Lang = Annotated[str, AfterValidator(_known_language)]


class ORM(BaseModel):
    model_config = ConfigDict(from_attributes=True)


# --- auth ------------------------------------------------------------------------


class OtpRequest(BaseModel):
    phone: str = Field(pattern=PHONE_PATTERN)


class OtpResponse(BaseModel):
    sent: bool = True
    expires_in: int
    dev_code: str | None = None  # only when OTP_DEV_ECHO is on in development


class OtpVerify(BaseModel):
    phone: str = Field(pattern=PHONE_PATTERN)
    code: str = Field(pattern=r"^\d{6}$")
    # Only used the first time a phone signs in. Health worker / admin roles are granted by an admin.
    name: str | None = Field(default=None, max_length=120)
    role: Literal["user", "caregiver"] = "user"
    device: str | None = Field(default=None, max_length=80)  # a label for this session, e.g. "phone" or "dashboard"


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    expires_in: int  # seconds until the access token expires
    refresh_token: str | None = None  # issued at sign-in only; renew the access token with POST /auth/refresh
    user: "UserOut"


class RefreshRequest(BaseModel):
    refresh_token: str = Field(min_length=20, max_length=200)


class UserOut(ORM):
    id: UUID
    phone: str
    name: str | None
    role: Role
    language: str
    region: str | None


class UserPatch(BaseModel):
    name: str | None = Field(default=None, max_length=120)
    language: Lang | None = None
    region: str | None = Field(default=None, max_length=40)


class ProfileOut(ORM):
    birth_year: int | None
    familiar_topics: list[str]
    voice_consent: bool
    font_scale: float


class ProfilePatch(BaseModel):
    birth_year: int | None = Field(default=None, ge=1900, le=2020)
    familiar_topics: list[str] | None = Field(default=None, max_length=30)
    voice_consent: bool | None = None
    font_scale: float | None = Field(default=None, ge=1.0, le=2.5)


# --- caregiver links ------------------------------------------------------------------


class LinkCodeOut(BaseModel):
    code: str
    expires_at: datetime


class LinkRedeem(BaseModel):
    code: str = Field(min_length=6, max_length=12)
    relationship: str | None = Field(default=None, max_length=60)


class LinkOut(ORM):
    id: UUID
    user_id: UUID
    caregiver_id: UUID
    relationship: str | None
    active: bool
    created_at: datetime


# --- synced records --------------------------------------------------------------------


class GameSessionIn(BaseModel):
    id: UUID
    game_slug: str = Field(max_length=60)
    level: int = Field(ge=1, le=10)
    started_at: datetime
    ended_at: datetime | None = None
    trials: int = Field(ge=0, le=1000)
    correct: int = Field(ge=0, le=1000)
    errors: int = Field(ge=0, le=1000)
    repeated_errors: int = Field(default=0, ge=0, le=1000)
    avg_response_ms: float | None = Field(default=None, ge=0, le=600_000)
    completed: bool = False
    updated_at: datetime
    deleted: bool = False


class ActivityIn(BaseModel):
    id: UUID
    kind: str = Field(max_length=40)
    payload: dict = Field(default_factory=dict)
    occurred_at: datetime
    updated_at: datetime
    deleted: bool = False


class MemoryBookFields(BaseModel):
    kind: Literal["person", "place", "date", "memory"] = "person"
    title: str = Field(min_length=1, max_length=160)
    person_name: str | None = Field(default=None, max_length=120)
    relationship: str | None = Field(default=None, max_length=60)
    event_date: date | None = None
    place: str | None = Field(default=None, max_length=160)
    description: str | None = Field(default=None, max_length=2000)


class MemoryBookIn(MemoryBookFields):
    id: UUID
    photo_key: str | None = Field(default=None, max_length=255)
    updated_at: datetime
    deleted: bool = False


class MemoryBookOut(ORM, MemoryBookFields):
    id: UUID
    user_id: UUID
    photo_key: str | None
    updated_by_role: Role
    updated_at: datetime
    deleted: bool


class MemoryBookPatch(BaseModel):
    kind: Literal["person", "place", "date", "memory"] | None = None
    title: str | None = Field(default=None, min_length=1, max_length=160)
    person_name: str | None = Field(default=None, max_length=120)
    relationship: str | None = Field(default=None, max_length=60)
    event_date: date | None = None
    place: str | None = Field(default=None, max_length=160)
    description: str | None = Field(default=None, max_length=2000)
    photo_key: str | None = Field(default=None, max_length=255)


ReminderKind = Literal["medication", "hydration", "meal", "activity", "appointment", "custom"]


class ReminderFields(BaseModel):
    kind: ReminderKind
    title: str = Field(min_length=1, max_length=160)
    time_of_day: time
    days_of_week: list[int] = Field(default_factory=lambda: [0, 1, 2, 3, 4, 5, 6])
    note: str | None = Field(default=None, max_length=255)
    active: bool = True

    @field_validator("days_of_week")
    @classmethod
    def _days(cls, v: list[int]) -> list[int]:
        if not v or any(d not in range(7) for d in v):
            raise ValueError("days_of_week must be 0 (Mon) .. 6 (Sun)")
        return sorted(set(v))


class ReminderIn(ReminderFields):
    id: UUID
    updated_at: datetime
    deleted: bool = False


class ReminderOut(ORM, ReminderFields):
    id: UUID
    user_id: UUID
    updated_at: datetime
    deleted: bool


class ReminderPatch(BaseModel):
    kind: ReminderKind | None = None
    title: str | None = Field(default=None, min_length=1, max_length=160)
    time_of_day: time | None = None
    days_of_week: list[int] | None = None
    note: str | None = Field(default=None, max_length=255)
    active: bool | None = None


class SyncChanges(BaseModel):
    game_sessions: list[GameSessionIn] = Field(default_factory=list, max_length=500)
    activity_log: list[ActivityIn] = Field(default_factory=list, max_length=500)
    memory_book: list[MemoryBookIn] = Field(default_factory=list, max_length=200)
    reminders: list[ReminderIn] = Field(default_factory=list, max_length=200)


class SyncRequest(BaseModel):
    batch_id: UUID
    device_id: str = Field(max_length=80)
    since: datetime | None = None  # server_time from the previous successful sync
    changes: SyncChanges = Field(default_factory=SyncChanges)


class RecommendationOut(ORM):
    game_slug: str
    level: int
    rank: int
    reason: str


class SyncResponse(BaseModel):
    batch_id: UUID
    applied: int
    rejected: list[dict]  # [{table, id, reason}] - the server copy won the conflict
    server_time: datetime
    memory_book: list[MemoryBookOut]
    reminders: list[ReminderOut]
    recommendations: list[RecommendationOut]


# --- content -----------------------------------------------------------------------------


class GameOut(ORM):
    slug: str
    name: str
    domain: str
    min_level: int
    max_level: int
    config: dict
    updated_at: datetime


class GameUpsert(BaseModel):
    slug: str = Field(pattern=r"^[a-z0-9_]{2,60}$")
    name: str = Field(max_length=120)
    domain: Literal["memory_recall", "attention", "pattern", "language", "speed", "routine"]
    min_level: int = Field(default=1, ge=1, le=10)
    max_level: int = Field(default=5, ge=1, le=10)
    config: dict = Field(default_factory=dict)
    active: bool = True


class CulturalOut(ORM):
    id: UUID
    region: str
    language: str
    category: str
    title: str
    data: dict
    media_key: str | None
    updated_at: datetime


class CulturalUpsert(BaseModel):
    region: str = Field(max_length=40)
    language: str = Field(max_length=8)
    category: Literal["food", "festival", "music", "object", "place", "craft", "animal", "daily_life"]
    title: str = Field(max_length=160)
    data: dict = Field(default_factory=dict)
    media_key: str | None = None


class LanguagePackOut(ORM):
    language: str
    version: int
    strings: dict
    voice_prompts: dict
    document: dict  # the full pack: strings, voice prompts, days, time format, Sathi, game content
    updated_at: datetime


class LanguageOut(BaseModel):
    code: str
    english_name: str
    native_name: str
    script: str
    version: int


class LanguagePackUpsert(BaseModel):
    document: dict  # same format as content/language-packs/*.json
    published: bool = False


# --- sathi / speech ---------------------------------------------------------------------------


class SathiAsk(BaseModel):
    question: str = Field(min_length=1, max_length=500)
    language: Lang = "en"


class SathiAnswer(BaseModel):
    answer: str
    source: Literal["local", "llm", "offline_fallback", "safety_block"]
    speak: bool = True


class TtsRequest(BaseModel):
    text: str = Field(min_length=1, max_length=500)
    language: Lang = "en"


# --- dashboard ---------------------------------------------------------------------------------


class AlertOut(ORM):
    id: UUID
    user_id: UUID
    kind: str
    severity: str
    message: str
    metrics: dict
    created_at: datetime
    acknowledged_at: datetime | None


class DailyTrend(BaseModel):
    day: date
    sessions: int
    completion_rate: float | None
    accuracy: float | None
    avg_response_ms: float | None
    reminders_done: int
    reminders_missed: int


class LinkedUserSummary(BaseModel):
    user: UserOut
    relationship: str | None
    last_active: datetime | None
    sessions_7d: int
    open_alerts: int


class DeviceTokenIn(BaseModel):
    token: str = Field(max_length=255)
    platform: Literal["android", "web"]


TokenResponse.model_rebuild()
