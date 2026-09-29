"""Apply db/migrations/*.sql in order, once each. Run as the table owner
(MIGRATION_DATABASE_URL), never as app_user:

    python -m app.migrate
"""

import os
import sys
from pathlib import Path

from sqlalchemy import create_engine, text

MIGRATIONS = Path(__file__).resolve().parent.parent / "db" / "migrations"


def migrate(url: str) -> list[str]:
    engine = create_engine(url)
    applied_now = []
    with engine.begin() as conn:
        conn.execute(text("CREATE TABLE IF NOT EXISTS schema_migrations (name text PRIMARY KEY, applied_at timestamptz DEFAULT now())"))
        done = set(conn.scalars(text("SELECT name FROM schema_migrations")))
    for path in sorted(MIGRATIONS.glob("*.sql")):
        if path.name in done:
            continue
        with engine.begin() as conn:
            # no_parameters: otherwise psycopg parses "%" placeholders and rejects format('%I', ...).
            conn.exec_driver_sql(path.read_text(encoding="utf-8"), execution_options={"no_parameters": True})
            conn.execute(text("INSERT INTO schema_migrations (name) VALUES (:n)"), {"n": path.name})
        applied_now.append(path.name)
    engine.dispose()
    return applied_now


if __name__ == "__main__":
    url = os.environ.get("MIGRATION_DATABASE_URL")
    if not url:
        sys.exit("MIGRATION_DATABASE_URL is required (the table-owner connection)")
    print("applied:", migrate(url) or "nothing new")
