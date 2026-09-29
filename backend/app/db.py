"""Database engines and per-request sessions.

On PostgreSQL every request runs in one transaction that first sets
`app.user_id` and `app.user_role` with set_config(..., is_local => true)
(the parameterised form of SET LOCAL). The RLS policies read them back, so
even a buggy query cannot return another person's rows.
"""

from collections.abc import Iterator
from contextlib import contextmanager
from uuid import UUID

from sqlalchemy import create_engine, event, text
from sqlalchemy.engine import Engine
from sqlalchemy.orm import Session, sessionmaker
from sqlalchemy.pool import StaticPool

from .config import get_settings


def _make_engine(url: str) -> Engine:
    if url.startswith("sqlite"):
        kwargs: dict = {"connect_args": {"check_same_thread": False}}
        if ":memory:" in url or url.endswith("sqlite://"):
            kwargs["poolclass"] = StaticPool
        engine = create_engine(url, **kwargs)

        # SQLAlchemy's recipe so pysqlite honours SAVEPOINT (used by /sync).
        @event.listens_for(engine, "connect")
        def _on_connect(dbapi_conn, _):  # noqa: ANN001
            dbapi_conn.isolation_level = None
            dbapi_conn.execute("PRAGMA foreign_keys=ON")

        @event.listens_for(engine, "begin")
        def _on_begin(conn):  # noqa: ANN001
            conn.exec_driver_sql("BEGIN")

        return engine
    return create_engine(url, pool_pre_ping=True)


_engine: Engine | None = None
_service_engine: Engine | None = None


def get_engine() -> Engine:
    global _engine
    if _engine is None:
        _engine = _make_engine(get_settings().database_url.get_secret_value())
    return _engine


def get_service_engine() -> Engine:
    global _service_engine
    if _service_engine is None:
        s = get_settings()
        url = s.service_database_url or s.database_url
        svc = url.get_secret_value()
        _service_engine = get_engine() if svc == s.database_url.get_secret_value() else _make_engine(svc)
    return _service_engine


def set_engines(engine: Engine, service_engine: Engine | None = None) -> None:
    """Used by tests to point the app at a throwaway database."""
    global _engine, _service_engine
    _engine = engine
    _service_engine = service_engine or engine


def _is_postgres(session: Session) -> bool:
    return session.get_bind().dialect.name == "postgresql"


def bind_identity(session: Session, user_id: UUID | None, role: str | None) -> None:
    if _is_postgres(session):
        session.execute(
            text("SELECT set_config('app.user_id', :uid, true), set_config('app.user_role', :role, true)"),
            {"uid": str(user_id) if user_id else "", "role": role or ""},
        )


@contextmanager
def user_session(user_id: UUID | None, role: str | None) -> Iterator[Session]:
    """Session bound to one user's identity for the whole transaction."""
    session = sessionmaker(bind=get_engine(), expire_on_commit=False)()
    try:
        with session.begin():
            bind_identity(session, user_id, role)
            yield session
    finally:
        session.close()


@contextmanager
def service_session() -> Iterator[Session]:
    """Privileged session (login, link redemption, scheduled jobs). Keep usage narrow."""
    session = sessionmaker(bind=get_service_engine(), expire_on_commit=False)()
    try:
        with session.begin():
            yield session
    finally:
        session.close()
