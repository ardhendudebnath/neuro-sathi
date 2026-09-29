-- Row-level security. Enforced in the database, so even a buggy API query
-- cannot return another person's rows.
--
-- The API connects as app_user (not the table owner, not a superuser, no
-- BYPASSRLS). For each request FastAPI verifies the JWT and then, inside the
-- transaction, runs set_config('app.user_id', <id>, true) and
-- set_config('app.user_role', <role>, true). Tables with no matching policy
-- deny everything by default.
--
-- neuro_service (BYPASSRLS) is used only for OTP login, caregiver link
-- redemption, spend tracking and the deviation job, and only has the grants below.

CREATE FUNCTION app_uid() RETURNS uuid LANGUAGE sql STABLE AS
$$ SELECT nullif(current_setting('app.user_id', true), '')::uuid $$;

CREATE FUNCTION app_role() RETURNS text LANGUAGE sql STABLE AS
$$ SELECT coalesce(current_setting('app.user_role', true), '') $$;

-- SECURITY DEFINER so policies can consult caregiver_links without recursing
-- through caregiver_links' own RLS.
CREATE FUNCTION is_linked_caregiver(target uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS
$$ SELECT EXISTS (
     SELECT 1 FROM caregiver_links cl
     WHERE cl.user_id = target AND cl.caregiver_id = app_uid() AND cl.active) $$;

CREATE FUNCTION is_my_caregiver(target uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS
$$ SELECT EXISTS (
     SELECT 1 FROM caregiver_links cl
     WHERE cl.caregiver_id = target AND cl.user_id = app_uid() AND cl.active) $$;

-- FORCE RLS applies to the table owner too, so the helpers are owned by the
-- BYPASSRLS service role (which has SELECT on caregiver_links, granted below).
-- The migrating user must be a superuser or a member of neuro_service.
ALTER FUNCTION is_linked_caregiver(uuid) OWNER TO neuro_service;
ALTER FUNCTION is_my_caregiver(uuid) OWNER TO neuro_service;
REVOKE ALL ON FUNCTION is_linked_caregiver(uuid), is_my_caregiver(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION app_uid(), app_role(), is_linked_caregiver(uuid), is_my_caregiver(uuid) TO app_user;

-- Enable and force RLS on every table.
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'users','profiles','otp_codes','caregiver_links','link_codes','games','cultural_content',
    'language_packs','game_sessions','activity_log','memory_book','reminders','alerts',
    'recommendations','sync_batches','audit_log','api_spend','device_tokens']
  LOOP
    EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format('ALTER TABLE %I FORCE ROW LEVEL SECURITY', t);
  END LOOP;
END $$;

GRANT USAGE ON SCHEMA public TO app_user, neuro_service;

-- users: see yourself, the people you care for, and your own caregivers' names.
GRANT SELECT ON users TO app_user;
GRANT UPDATE (name, language, region) ON users TO app_user;  -- never role or phone
CREATE POLICY users_select ON users FOR SELECT TO app_user
  USING (id = app_uid() OR is_linked_caregiver(id) OR is_my_caregiver(id));
CREATE POLICY users_update ON users FOR UPDATE TO app_user
  USING (id = app_uid()) WITH CHECK (id = app_uid());

-- profiles
GRANT SELECT, INSERT, UPDATE ON profiles TO app_user;
CREATE POLICY profiles_own ON profiles FOR ALL TO app_user
  USING (user_id = app_uid()) WITH CHECK (user_id = app_uid());
CREATE POLICY profiles_caregiver_read ON profiles FOR SELECT TO app_user
  USING (is_linked_caregiver(user_id));

-- caregiver_links: both sides can see and end (active=false) a link; creation is via the service role.
GRANT SELECT ON caregiver_links TO app_user;
GRANT UPDATE (active) ON caregiver_links TO app_user;
CREATE POLICY links_select ON caregiver_links FOR SELECT TO app_user
  USING (user_id = app_uid() OR caregiver_id = app_uid());
CREATE POLICY links_end ON caregiver_links FOR UPDATE TO app_user
  USING (user_id = app_uid() OR caregiver_id = app_uid())
  WITH CHECK ((user_id = app_uid() OR caregiver_id = app_uid()) AND active = false);

-- link_codes: the elderly user creates their own codes.
GRANT SELECT, INSERT, DELETE ON link_codes TO app_user;
CREATE POLICY link_codes_own ON link_codes FOR ALL TO app_user
  USING (user_id = app_uid()) WITH CHECK (user_id = app_uid());

-- Content tables: everyone reads, only admins write. Admins get no access to personal rows.
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['games','cultural_content','language_packs'] LOOP
    EXECUTE format('GRANT SELECT, INSERT, UPDATE ON %I TO app_user', t);
    EXECUTE format('CREATE POLICY %I ON %I FOR SELECT TO app_user USING (app_uid() IS NOT NULL)', t || '_read', t);
    EXECUTE format('CREATE POLICY %I ON %I FOR INSERT TO app_user WITH CHECK (app_role() = ''admin'')', t || '_admin_insert', t);
    EXECUTE format('CREATE POLICY %I ON %I FOR UPDATE TO app_user USING (app_role() = ''admin'') WITH CHECK (app_role() = ''admin'')', t || '_admin_update', t);
  END LOOP;
END $$;

-- Activity data: owner reads and writes; linked caregivers read, never write.
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['game_sessions','activity_log','recommendations','sync_batches'] LOOP
    EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE ON %I TO app_user', t);
    EXECUTE format('CREATE POLICY own_rows ON %I FOR ALL TO app_user USING (user_id = app_uid()) WITH CHECK (user_id = app_uid())', t);
  END LOOP;
  FOREACH t IN ARRAY ARRAY['game_sessions','activity_log','recommendations'] LOOP
    EXECUTE format('CREATE POLICY caregiver_read ON %I FOR SELECT TO app_user USING (is_linked_caregiver(user_id))', t);
  END LOOP;
END $$;

-- Memory book and reminders: owner reads and writes; linked caregivers read and write.
-- Deletes are tombstones (deleted = true) so they sync to the phone.
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['memory_book','reminders'] LOOP
    EXECUTE format('GRANT SELECT, INSERT, UPDATE ON %I TO app_user', t);
    EXECUTE format('CREATE POLICY own_rows ON %I FOR ALL TO app_user USING (user_id = app_uid()) WITH CHECK (user_id = app_uid())', t);
    EXECUTE format('CREATE POLICY caregiver_read ON %I FOR SELECT TO app_user USING (is_linked_caregiver(user_id))', t);
    EXECUTE format('CREATE POLICY caregiver_insert ON %I FOR INSERT TO app_user WITH CHECK (is_linked_caregiver(user_id) AND created_by = app_uid())', t);
    EXECUTE format('CREATE POLICY caregiver_update ON %I FOR UPDATE TO app_user USING (is_linked_caregiver(user_id)) WITH CHECK (is_linked_caregiver(user_id))', t);
  END LOOP;
END $$;

-- Alerts: written by the deviation job (service role). Owner and linked caregivers read; caregivers acknowledge.
GRANT SELECT ON alerts TO app_user;
GRANT UPDATE (acknowledged_at, acknowledged_by) ON alerts TO app_user;
CREATE POLICY alerts_read ON alerts FOR SELECT TO app_user
  USING (user_id = app_uid() OR is_linked_caregiver(user_id));
CREATE POLICY alerts_ack ON alerts FOR UPDATE TO app_user
  USING (is_linked_caregiver(user_id)) WITH CHECK (is_linked_caregiver(user_id) AND acknowledged_by = app_uid());

-- Audit log: anyone may append their own entries; only admins read.
GRANT SELECT, INSERT ON audit_log TO app_user;
CREATE POLICY audit_append ON audit_log FOR INSERT TO app_user WITH CHECK (actor_id = app_uid());
CREATE POLICY audit_admin_read ON audit_log FOR SELECT TO app_user USING (app_role() = 'admin');

-- Device tokens: own rows only.
GRANT SELECT, INSERT, UPDATE, DELETE ON device_tokens TO app_user;
CREATE POLICY own_rows ON device_tokens FOR ALL TO app_user
  USING (user_id = app_uid()) WITH CHECK (user_id = app_uid());

-- api_spend: aggregate monthly counters for the paid-API budget cap (no user data).
GRANT SELECT, INSERT, UPDATE ON api_spend TO app_user;
CREATE POLICY api_spend_all ON api_spend FOR ALL TO app_user USING (app_uid() IS NOT NULL) WITH CHECK (app_uid() IS NOT NULL);

-- otp_codes: no app_user grants at all (service role only).

-- Service role: narrow grants for login, link redemption, spend tracking, seeding and the deviation job.
GRANT SELECT, INSERT, UPDATE ON users, profiles TO neuro_service;
GRANT SELECT, INSERT, UPDATE, DELETE ON otp_codes, link_codes TO neuro_service;
GRANT SELECT, INSERT, UPDATE ON caregiver_links TO neuro_service;
GRANT SELECT, INSERT, UPDATE ON games, cultural_content, language_packs TO neuro_service;
GRANT SELECT ON game_sessions, activity_log, device_tokens TO neuro_service;
GRANT SELECT, INSERT ON alerts TO neuro_service;
GRANT SELECT, INSERT, UPDATE ON api_spend TO neuro_service;
GRANT INSERT ON audit_log TO neuro_service;
