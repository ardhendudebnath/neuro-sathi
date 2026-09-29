#!/bin/sh
# Runs once when the Postgres container is first created (docker-entrypoint-initdb.d).
# Creates the two login roles the API uses. Passwords come from the environment.
set -eu
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<SQL
CREATE ROLE app_user LOGIN PASSWORD '${APP_DB_PASSWORD}' NOSUPERUSER NOBYPASSRLS;
CREATE ROLE neuro_service LOGIN PASSWORD '${SERVICE_DB_PASSWORD}' NOSUPERUSER BYPASSRLS;
SQL
