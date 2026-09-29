-- NEURO-SATHI schema. Must stay in step with app/models.py
-- (CI runs the API test-suite against this schema on PostgreSQL).

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_user') THEN
    CREATE ROLE app_user NOLOGIN NOSUPERUSER NOBYPASSRLS;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'neuro_service') THEN
    CREATE ROLE neuro_service NOLOGIN NOSUPERUSER BYPASSRLS;
  END IF;
END $$;

CREATE TYPE user_role AS ENUM ('user', 'caregiver', 'health_worker', 'admin');

CREATE TABLE users (
  id          uuid PRIMARY KEY,
  phone       varchar(20) NOT NULL UNIQUE,
  name        varchar(120),
  role        user_role NOT NULL DEFAULT 'user',
  language    varchar(8) NOT NULL DEFAULT 'en',
  region      varchar(40),
  created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE profiles (
  user_id          uuid PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  birth_year       integer,
  familiar_topics  jsonb NOT NULL DEFAULT '[]',
  voice_consent    boolean NOT NULL DEFAULT false,
  font_scale       double precision NOT NULL DEFAULT 1.4,
  updated_at       timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE otp_codes (
  phone       varchar(20) PRIMARY KEY,
  code_hash   varchar(128) NOT NULL,
  expires_at  timestamptz NOT NULL,
  attempts    integer NOT NULL DEFAULT 0
);

CREATE TABLE caregiver_links (
  id            uuid PRIMARY KEY,
  user_id       uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  caregiver_id  uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  relationship  varchar(60),
  active        boolean NOT NULL DEFAULT true,
  created_at    timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, caregiver_id)
);
CREATE INDEX ix_caregiver_links_user_id ON caregiver_links(user_id);
CREATE INDEX ix_caregiver_links_caregiver_id ON caregiver_links(caregiver_id);

CREATE TABLE link_codes (
  code        varchar(12) PRIMARY KEY,
  user_id     uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  expires_at  timestamptz NOT NULL
);

CREATE TABLE games (
  id          uuid PRIMARY KEY,
  slug        varchar(60) NOT NULL UNIQUE,
  name        varchar(120) NOT NULL,
  domain      varchar(40) NOT NULL,
  min_level   integer NOT NULL DEFAULT 1,
  max_level   integer NOT NULL DEFAULT 5,
  config      jsonb NOT NULL DEFAULT '{}',
  active      boolean NOT NULL DEFAULT true,
  updated_at  timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE cultural_content (
  id          uuid PRIMARY KEY,
  region      varchar(40) NOT NULL,
  language    varchar(8) NOT NULL,
  category    varchar(40) NOT NULL,
  title       varchar(160) NOT NULL,
  data        jsonb NOT NULL DEFAULT '{}',
  media_key   varchar(255),
  updated_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ix_cultural_content_region ON cultural_content(region);

CREATE TABLE language_packs (
  id             uuid PRIMARY KEY,
  language       varchar(8) NOT NULL,
  version        integer NOT NULL,
  strings        jsonb NOT NULL DEFAULT '{}',
  voice_prompts  jsonb NOT NULL DEFAULT '{}',
  published      boolean NOT NULL DEFAULT false,
  updated_at     timestamptz NOT NULL DEFAULT now(),
  UNIQUE (language, version)
);

CREATE TABLE game_sessions (
  id               uuid PRIMARY KEY,
  user_id          uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  game_slug        varchar(60) NOT NULL,
  level            integer NOT NULL DEFAULT 1,
  started_at       timestamptz NOT NULL,
  ended_at         timestamptz,
  trials           integer NOT NULL DEFAULT 0,
  correct          integer NOT NULL DEFAULT 0,
  errors           integer NOT NULL DEFAULT 0,
  repeated_errors  integer NOT NULL DEFAULT 0,
  avg_response_ms  double precision,
  completed        boolean NOT NULL DEFAULT false,
  updated_at       timestamptz NOT NULL DEFAULT now(),
  deleted          boolean NOT NULL DEFAULT false
);
CREATE INDEX ix_game_sessions_user_id ON game_sessions(user_id);
CREATE INDEX ix_game_sessions_updated_at ON game_sessions(updated_at);
CREATE INDEX ix_game_sessions_user_started ON game_sessions(user_id, started_at);

CREATE TABLE activity_log (
  id           uuid PRIMARY KEY,
  user_id      uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  kind         varchar(40) NOT NULL,
  payload      jsonb NOT NULL DEFAULT '{}',
  occurred_at  timestamptz NOT NULL,
  updated_at   timestamptz NOT NULL DEFAULT now(),
  deleted      boolean NOT NULL DEFAULT false
);
CREATE INDEX ix_activity_log_user_id ON activity_log(user_id);
CREATE INDEX ix_activity_log_updated_at ON activity_log(updated_at);

CREATE TABLE memory_book (
  id               uuid PRIMARY KEY,
  user_id          uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_by       uuid NOT NULL REFERENCES users(id),
  updated_by_role  user_role NOT NULL DEFAULT 'user',
  kind             varchar(20) NOT NULL DEFAULT 'person',
  title            varchar(160) NOT NULL,
  person_name      varchar(120),
  relationship     varchar(60),
  event_date       date,
  place            varchar(160),
  description      text,
  photo_key        varchar(255),
  updated_at       timestamptz NOT NULL DEFAULT now(),
  deleted          boolean NOT NULL DEFAULT false
);
CREATE INDEX ix_memory_book_user_id ON memory_book(user_id);
CREATE INDEX ix_memory_book_updated_at ON memory_book(updated_at);

CREATE TABLE reminders (
  id            uuid PRIMARY KEY,
  user_id       uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_by    uuid NOT NULL REFERENCES users(id),
  kind          varchar(20) NOT NULL,
  title         varchar(160) NOT NULL,
  time_of_day   time NOT NULL,
  days_of_week  jsonb NOT NULL DEFAULT '[0,1,2,3,4,5,6]',
  note          varchar(255),
  active        boolean NOT NULL DEFAULT true,
  updated_at    timestamptz NOT NULL DEFAULT now(),
  deleted       boolean NOT NULL DEFAULT false
);
CREATE INDEX ix_reminders_user_id ON reminders(user_id);
CREATE INDEX ix_reminders_updated_at ON reminders(updated_at);

CREATE TABLE alerts (
  id               uuid PRIMARY KEY,
  user_id          uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  kind             varchar(40) NOT NULL,
  severity         varchar(10) NOT NULL,
  message          text NOT NULL,
  metrics          jsonb NOT NULL DEFAULT '{}',
  created_at       timestamptz NOT NULL DEFAULT now(),
  acknowledged_at  timestamptz,
  acknowledged_by  uuid REFERENCES users(id)
);
CREATE INDEX ix_alerts_user_id ON alerts(user_id);

CREATE TABLE recommendations (
  user_id     uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  game_slug   varchar(60) NOT NULL,
  level       integer NOT NULL,
  rank        integer NOT NULL,
  reason      varchar(255) NOT NULL,
  updated_at  timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, game_slug)
);

CREATE TABLE sync_batches (
  batch_id     uuid PRIMARY KEY,
  user_id      uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  received_at  timestamptz NOT NULL DEFAULT now(),
  result       jsonb NOT NULL DEFAULT '{}'
);
CREATE INDEX ix_sync_batches_user_id ON sync_batches(user_id);

CREATE TABLE audit_log (
  id              uuid PRIMARY KEY,
  actor_id        uuid,
  action          varchar(60) NOT NULL,
  target_user_id  uuid,
  detail          jsonb NOT NULL DEFAULT '{}',
  at              timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ix_audit_log_at ON audit_log(at);

CREATE TABLE api_spend (
  month       varchar(7) NOT NULL,
  provider    varchar(40) NOT NULL,
  calls       integer NOT NULL DEFAULT 0,
  amount_inr  double precision NOT NULL DEFAULT 0,
  PRIMARY KEY (month, provider)
);

CREATE TABLE device_tokens (
  token       varchar(255) PRIMARY KEY,
  user_id     uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  platform    varchar(10) NOT NULL,
  updated_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ix_device_tokens_user_id ON device_tokens(user_id);
