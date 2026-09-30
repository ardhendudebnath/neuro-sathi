-- Full language-pack document (strings, voice prompts, day names, time format,
-- Sathi answers and keywords, game content) as downloaded by the phone app.
-- Existing grants on language_packs cover the new column.
ALTER TABLE language_packs ADD COLUMN document jsonb NOT NULL DEFAULT '{}';
