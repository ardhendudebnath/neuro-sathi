-- Signed-in devices. The access token is short-lived and is renewed with a
-- long-lived, revocable refresh token; only its keyed hash is stored here.
CREATE TABLE refresh_tokens (
  id            uuid PRIMARY KEY,
  user_id       uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  token_hash    varchar(64) NOT NULL UNIQUE,
  device        varchar(80),
  created_at    timestamptz NOT NULL DEFAULT now(),
  last_used_at  timestamptz NOT NULL DEFAULT now(),
  expires_at    timestamptz NOT NULL,
  revoked_at    timestamptz
);
CREATE INDEX ix_refresh_tokens_user_id ON refresh_tokens(user_id);

ALTER TABLE refresh_tokens ENABLE ROW LEVEL SECURITY;
ALTER TABLE refresh_tokens FORCE ROW LEVEL SECURITY;

-- Like otp_codes: no app_user grants at all. Sessions are created, renewed and
-- revoked only by the auth routes, through the service role.
GRANT SELECT, INSERT, UPDATE, DELETE ON refresh_tokens TO neuro_service;
