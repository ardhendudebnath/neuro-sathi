"""ORM models. The PostgreSQL schema and RLS policies live in db/migrations/*.sql;
the CI Postgres job checks that the two stay in step."""

import enum
import uuid
from datetime import UTC, date, datetime, time

from sqlalchemy import (
    JSON,
    Boolean,
    Date,
    DateTime,
    Enum,
    Float,
    ForeignKey,
    Integer,
    String,
    Text,
    Time,
    UniqueConstraint,
    Uuid,
)
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column


def utcnow() -> datetime:
    return datetime.now(UTC)


class Base(DeclarativeBase):
    type_annotation_map = {
        datetime: DateTime(timezone=True),
        dict: JSON().with_variant(JSONB(), "postgresql"),
        list: JSON().with_variant(JSONB(), "postgresql"),
    }


class Role(str, enum.Enum):
    user = "user"
    caregiver = "caregiver"
    health_worker = "health_worker"
    admin = "admin"


CARE_ROLES = {Role.caregiver, Role.health_worker}


def _role_enum() -> Enum:
    return Enum(Role, name="user_role", values_callable=lambda e: [m.value for m in e])


# --- identity -----------------------------------------------------------------


class User(Base):
    __tablename__ = "users"
    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    phone: Mapped[str] = mapped_column(String(20), unique=True)
    name: Mapped[str | None] = mapped_column(String(120))
    role: Mapped[Role] = mapped_column(_role_enum(), default=Role.user)
    language: Mapped[str] = mapped_column(String(8), default="en")
    region: Mapped[str | None] = mapped_column(String(40))  # e.g. assam, manipur, meghalaya
    created_at: Mapped[datetime] = mapped_column(default=utcnow)


class Profile(Base):
    __tablename__ = "profiles"
    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), primary_key=True)
    birth_year: Mapped[int | None] = mapped_column(Integer)
    familiar_topics: Mapped[list] = mapped_column(default=list)  # e.g. ["bihu", "tea garden", "rice"]
    voice_consent: Mapped[bool] = mapped_column(Boolean, default=False)
    font_scale: Mapped[float] = mapped_column(Float, default=1.4)
    updated_at: Mapped[datetime] = mapped_column(default=utcnow)


class OtpCode(Base):
    __tablename__ = "otp_codes"
    phone: Mapped[str] = mapped_column(String(20), primary_key=True)
    code_hash: Mapped[str] = mapped_column(String(128))
    expires_at: Mapped[datetime]
    attempts: Mapped[int] = mapped_column(Integer, default=0)


class RefreshToken(Base):
    """A signed-in device. Only a hash of the token is stored; the token itself is on
    the device (Keystore-backed storage) or in the dashboard's httpOnly cookie."""

    __tablename__ = "refresh_tokens"
    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    token_hash: Mapped[str] = mapped_column(String(64), unique=True)
    device: Mapped[str | None] = mapped_column(String(80))
    created_at: Mapped[datetime] = mapped_column(default=utcnow)
    last_used_at: Mapped[datetime] = mapped_column(default=utcnow)
    expires_at: Mapped[datetime]
    revoked_at: Mapped[datetime | None]


class CaregiverLink(Base):
    __tablename__ = "caregiver_links"
    __table_args__ = (UniqueConstraint("user_id", "caregiver_id"),)
    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    caregiver_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    relationship: Mapped[str | None] = mapped_column(String(60))
    active: Mapped[bool] = mapped_column(Boolean, default=True)
    created_at: Mapped[datetime] = mapped_column(default=utcnow)


class LinkCode(Base):
    """Short code the elderly user's app shows; a caregiver enters it to link."""

    __tablename__ = "link_codes"
    code: Mapped[str] = mapped_column(String(12), primary_key=True)
    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    expires_at: Mapped[datetime]


# --- content (admin-managed, readable by everyone) ------------------------------


class Game(Base):
    __tablename__ = "games"
    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    slug: Mapped[str] = mapped_column(String(60), unique=True)
    name: Mapped[str] = mapped_column(String(120))
    domain: Mapped[str] = mapped_column(String(40))  # memory_recall, attention, pattern, language, speed, routine
    min_level: Mapped[int] = mapped_column(Integer, default=1)
    max_level: Mapped[int] = mapped_column(Integer, default=5)
    config: Mapped[dict] = mapped_column(default=dict)
    active: Mapped[bool] = mapped_column(Boolean, default=True)
    updated_at: Mapped[datetime] = mapped_column(default=utcnow)


class CulturalContent(Base):
    __tablename__ = "cultural_content"
    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    region: Mapped[str] = mapped_column(String(40), index=True)  # "all" for pan-NER items
    language: Mapped[str] = mapped_column(String(8))
    category: Mapped[str] = mapped_column(String(40))  # food, festival, music, object, place
    title: Mapped[str] = mapped_column(String(160))
    data: Mapped[dict] = mapped_column(default=dict)
    media_key: Mapped[str | None] = mapped_column(String(255))
    updated_at: Mapped[datetime] = mapped_column(default=utcnow)


class LanguagePack(Base):
    __tablename__ = "language_packs"
    __table_args__ = (UniqueConstraint("language", "version"),)
    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    language: Mapped[str] = mapped_column(String(8))
    version: Mapped[int] = mapped_column(Integer)
    strings: Mapped[dict] = mapped_column(default=dict)
    voice_prompts: Mapped[dict] = mapped_column(default=dict)
    document: Mapped[dict] = mapped_column(default=dict)  # the full pack as in content/language-packs
    published: Mapped[bool] = mapped_column(Boolean, default=False)
    updated_at: Mapped[datetime] = mapped_column(default=utcnow)


# --- user-owned rows (RLS on every one) -----------------------------------------


class SyncedMixin:
    """Rows created on the phone carry a client-generated UUID so a retried batch
    upserts instead of duplicating. `updated_at` drives last-write-wins."""

    updated_at: Mapped[datetime] = mapped_column(default=utcnow, index=True)
    deleted: Mapped[bool] = mapped_column(Boolean, default=False)


class GameSession(SyncedMixin, Base):
    __tablename__ = "game_sessions"
    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True)
    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    game_slug: Mapped[str] = mapped_column(String(60))
    level: Mapped[int] = mapped_column(Integer, default=1)
    started_at: Mapped[datetime]
    ended_at: Mapped[datetime | None]
    trials: Mapped[int] = mapped_column(Integer, default=0)
    correct: Mapped[int] = mapped_column(Integer, default=0)
    errors: Mapped[int] = mapped_column(Integer, default=0)
    repeated_errors: Mapped[int] = mapped_column(Integer, default=0)
    avg_response_ms: Mapped[float | None] = mapped_column(Float)
    completed: Mapped[bool] = mapped_column(Boolean, default=False)


class ActivityLog(SyncedMixin, Base):
    __tablename__ = "activity_log"
    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True)
    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    kind: Mapped[str] = mapped_column(String(40))  # app_open, reminder_done, reminder_missed, sathi_ask, ...
    payload: Mapped[dict] = mapped_column(default=dict)
    occurred_at: Mapped[datetime]


class MemoryBookEntry(SyncedMixin, Base):
    __tablename__ = "memory_book"
    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True)
    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    created_by: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id"))
    updated_by_role: Mapped[Role] = mapped_column(_role_enum(), default=Role.user)
    kind: Mapped[str] = mapped_column(String(20), default="person")  # person, place, date, memory
    title: Mapped[str] = mapped_column(String(160))
    person_name: Mapped[str | None] = mapped_column(String(120))
    relationship: Mapped[str | None] = mapped_column(String(60))
    event_date: Mapped[date | None] = mapped_column(Date)
    place: Mapped[str | None] = mapped_column(String(160))
    description: Mapped[str | None] = mapped_column(Text)
    photo_key: Mapped[str | None] = mapped_column(String(255))


class Reminder(SyncedMixin, Base):
    __tablename__ = "reminders"
    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True)
    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    created_by: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id"))
    kind: Mapped[str] = mapped_column(String(20))  # medication, hydration, meal, activity, appointment, custom
    title: Mapped[str] = mapped_column(String(160))
    time_of_day: Mapped[time] = mapped_column(Time)
    days_of_week: Mapped[list] = mapped_column(default=lambda: [0, 1, 2, 3, 4, 5, 6])  # Mon=0
    note: Mapped[str | None] = mapped_column(String(255))
    active: Mapped[bool] = mapped_column(Boolean, default=True)


class Alert(Base):
    __tablename__ = "alerts"
    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    kind: Mapped[str] = mapped_column(String(40))  # slower_responses, more_errors, less_activity, lower_completion
    severity: Mapped[str] = mapped_column(String(10))  # info, watch, check_in
    message: Mapped[str] = mapped_column(Text)
    metrics: Mapped[dict] = mapped_column(default=dict)
    created_at: Mapped[datetime] = mapped_column(default=utcnow)
    acknowledged_at: Mapped[datetime | None]
    acknowledged_by: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("users.id"))


class Recommendation(Base):
    __tablename__ = "recommendations"
    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), primary_key=True)
    game_slug: Mapped[str] = mapped_column(String(60), primary_key=True)
    level: Mapped[int] = mapped_column(Integer)
    rank: Mapped[int] = mapped_column(Integer)
    reason: Mapped[str] = mapped_column(String(255))
    updated_at: Mapped[datetime] = mapped_column(default=utcnow)


class SyncBatch(Base):
    """Remembers applied batch ids so a batch retried after a dropped connection is not re-applied."""

    __tablename__ = "sync_batches"
    batch_id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True)
    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    received_at: Mapped[datetime] = mapped_column(default=utcnow)
    result: Mapped[dict] = mapped_column(default=dict)


# --- operations --------------------------------------------------------------------


class AuditLog(Base):
    __tablename__ = "audit_log"
    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    actor_id: Mapped[uuid.UUID | None] = mapped_column(Uuid)
    action: Mapped[str] = mapped_column(String(60))
    target_user_id: Mapped[uuid.UUID | None] = mapped_column(Uuid)
    detail: Mapped[dict] = mapped_column(default=dict)
    at: Mapped[datetime] = mapped_column(default=utcnow)


class ApiSpend(Base):
    __tablename__ = "api_spend"
    month: Mapped[str] = mapped_column(String(7), primary_key=True)  # YYYY-MM
    provider: Mapped[str] = mapped_column(String(40), primary_key=True)
    calls: Mapped[int] = mapped_column(Integer, default=0)
    amount_inr: Mapped[float] = mapped_column(Float, default=0.0)


class DeviceToken(Base):
    __tablename__ = "device_tokens"
    token: Mapped[str] = mapped_column(String(255), primary_key=True)
    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    platform: Mapped[str] = mapped_column(String(10))  # android, web
    updated_at: Mapped[datetime] = mapped_column(default=utcnow)
