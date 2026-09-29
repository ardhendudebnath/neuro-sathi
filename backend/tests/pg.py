"""PostgreSQL test mode (CI). Rebuilds the schema from db/migrations for each
test and points the API at the restricted app_user role, so every API test also
runs under the real RLS policies.

Env: TEST_OWNER_DATABASE_URL (table owner), TEST_APP_DATABASE_URL (app_user),
TEST_SERVICE_DATABASE_URL (neuro_service). The roles must already exist with LOGIN.
"""

import os

from sqlalchemy import create_engine

from app import db as app_db
from app.migrate import migrate

_app_engine = None
_service_engine = None


def reset_postgres() -> None:
    global _app_engine, _service_engine
    owner_url = os.environ["TEST_OWNER_DATABASE_URL"]
    if _app_engine is not None:
        _app_engine.dispose()
        _service_engine.dispose()
    owner = create_engine(owner_url, isolation_level="AUTOCOMMIT")
    with owner.connect() as c:
        c.exec_driver_sql("DROP SCHEMA public CASCADE")
        c.exec_driver_sql("CREATE SCHEMA public")
    owner.dispose()
    migrate(owner_url)
    _app_engine = app_db._make_engine(os.environ["TEST_APP_DATABASE_URL"])
    _service_engine = app_db._make_engine(os.environ["TEST_SERVICE_DATABASE_URL"])
    app_db.set_engines(_app_engine, _service_engine)
