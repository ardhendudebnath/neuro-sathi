# Language packs

One JSON file per language. The same files are used by the backend (Sathi's answers, the packs the phone downloads) and by the phone app (bundled at build time), so a language is added or corrected here and nowhere else.

| File | Language | Script | Release | Review |
| --- | --- | --- | --- | --- |
| `en.json` | English | Latin | public | source language |
| `hi.json` | Hindi | Devanagari | public | **not yet reviewed** |
| `as.json` | Assamese | Bengali-Assamese | preview | not yet reviewed |
| `bn.json` | Bengali | Bengali | preview | not yet reviewed |
| `ne.json` | Nepali | Devanagari | preview | not yet reviewed |
| `mni-Beng.json` | Manipuri (Meiteilon) | Bengali | preview | not yet reviewed |
| `mni-Mtei.json` | Manipuri (Meiteilon) | Meitei Mayek | preview | not yet reviewed |
| `brx.json` | Bodo (Boro) | Devanagari | preview | not yet reviewed |

All non-English packs were drafted by an AI model. A mistranslated medicine reminder can cause real harm, so each pack needs a native speaker's review before users see it.

## Manipuri

Manipuri comes in two packs with the same wording, one per script, and the user picks one: many older readers learned the Bengali script at school, while Meitei Mayek is the script taught since the 2000s. A reviewer who changes one pack changes the other in the same way; a test checks that both keep the same keys, list lengths and keywords.

The Manipuri drafts are less certain than the other packs and need an especially careful review. Phones have no Manipuri voice, so the Bengali-script pack falls back to a Bengali voice and the Meitei Mayek pack has none (the app says so). The hosted companion model does not support Manipuri, so Sathi answers from the pack (`llm: false`). Android has shipped a Meitei Mayek font since version 5.1, so none is bundled.

## Bodo

Bodo is written in Devanagari, the script the Bodo Sahitya Sabha adopted, with `’` after a letter for the o-vowel and tone, as in `बर’` (Boro). Times use Latin digits (`हर नि 8:00`), as in Unicode's locale data for Bodo.

The Bodo draft is the least certain of all the packs. Key words (medicine, time, day names, family, the foods and objects) were checked against [Bihung](https://bihung.org), the Bodo Sahitya Sabha's dictionary, and against Unicode's locale data for Bodo, but the sentences were not. The polite instructions ending in `-दो` especially need a native speaker's eye. Phones have no Bodo voice, so the app falls back to a Hindi voice, which reads Devanagari but not with Bodo pronunciation. The hosted companion model does not support Bodo, so Sathi answers from the pack (`llm: false`). Sathi's keywords avoid the `’` mark, so questions match however a keyboard types it.

## Release rules

- **`preview`**: hidden from users. The app shows it only in a reviewer build (`flutter run --dart-define=SHOW_PREVIEW_LANGUAGES=true`), and the API does not serve it.
- **`public`**: offered in the app's language picker and served by `/content/language-packs/{code}`.

Hindi is `public` because it was in the first version's scope, but it has had no native-speaker review either. The validator prints a warning for it until it is reviewed.

## Reviewing a pack

Native speakers review a pack in a spreadsheet, so they need no JSON or GitHub.

1. Export a review sheet:

   ```bash
   cd backend
   python -m app.pack_review export bn
   ```

   This writes `bn-review.csv`, which opens in Excel or Google Sheets. It has a row per text with the English, the current translation, empty **Correction** and **Comment** columns, and what to check. Medicine and reminder wording comes first.
2. Send it to the reviewer. They fill in Correction only where a text is wrong, and use Comment for anything else, such as a food that is not eaten locally. They save it as CSV again (in Excel, **CSV UTF-8**). Things to check:
   - **Reminders and medicine wording** (`medicine_time`, `voice_prompts`, `sathi.answers.med_*`): clear, polite and unambiguous.
   - **Respectful address** for elderly users throughout.
   - **`sathi.keywords`**: the words people really use when asking about medicine, the time or day, a person, and today's plan. See the keyword rules below.
   - **`games`**: food names, the daily routine and object descriptions should be familiar locally.
   - **`time.periods`**: the day-part words and the hours each covers.

   To see the texts in the app, build it with `--dart-define=SHOW_PREVIEW_LANGUAGES=true` and pick the language.
3. Import the filled-in sheet:

   ```bash
   python -m app.pack_review import bn bn-review.csv --reviewer "Reviewer Name" --reviewed --publish
   ```

   Import applies only the filled-in corrections and keeps the file's layout. It raises `version` by one (phones download a pack only when its version is newer than the bundled one) and adds the reviewer to `meta.review.reviewers`. It changes nothing if a correction fails the language checks, such as a missing `{placeholder}`, or if a translation has changed since the sheet was exported. Comments without a correction are printed for you to act on. Add `--dry-run` to see the changes first.
   - `--reviewed` marks the pack `reviewed`: use it once the reviewer has checked every row, and leave it out for a partial review.
   - `--publish` sets `meta.release` to `public`, so users can pick the language. It needs a reviewed pack.
4. Run the validator and the tests (below), then open a pull request. Don't commit the sheets: they are ignored by git.

For Manipuri, import lists the rows to change in the other script's pack too: export that pack's sheet, fill in the same rows and import it with the same options.

## Adding a language

1. Copy `en.json` to `<code>.json` (a BCP-47 code of at most 8 characters, such as `kha` or `mni-Beng`) and set `"language"` to the same code.
2. Fill in `meta`: names, `script` (`Latn`, `Beng`, `Deva` or `Mtei`), `release: "preview"`, review status `unreviewed`, the phone voice locales to try in order (`tts_locales`, `stt_locales`), and whether the hosted companion model supports the language (`llm`).
3. Translate every section. Keep the `{placeholders}` exactly as in English.
4. Run the validator.

A new script needs one line in `SCRIPT_RANGES` in `backend/app/language_packs.py` so the script checks cover it, and its digits in `DIGITS` there and in `mobile/lib/l10n/language_pack.dart` if it has its own. A script with its own full stop (like Meitei Mayek's ꯫) also needs it in the word-splitting pattern in both files.

## What a pack contains

| Section | Used for |
| --- | --- |
| `strings` | All app text. |
| `voice_prompts` | Sentences read aloud, such as reminder announcements. |
| `days` | Seven day names, Monday first. |
| `time` | 12-hour time: `format` with `{h}`, `{mm}`, `{period}`; `periods` (day-part word and the hour it starts; hours before the first one use the last, for the night); `digits` (`latin`, `beng`, `deva` or `mtei`). |
| `regions` | Names of the eight North-Eastern states. |
| `sathi.answers` | Sathi's scripted answers. |
| `sathi.keywords` | Words that tell Sathi what a question is about. |
| `games` | Game names, a food list (10 or more), the daily routine (same steps and order as English) and familiar objects with a one-line description. |

### Keyword rules

- A keyword is one word or a phrase. It must match whole words: Bengali `কে` (who) does not match inside `আজকে` (today).
- End a keyword with `*` to allow suffixes: `ওষুধ*` also matches `ওষুধের` and `ওষুধটা`.
- English keywords always apply too, because people mix in words like "tablet".
- Questions are checked in this order: medicine, time, who, today's plan.

## Checking packs

```bash
cd backend
python -m app.language_packs check
```

```bash
cd backend
pytest tests/test_language_packs.py
```

The validator fails a pack that is missing a key, changes a placeholder, has the wrong number of days or routine steps, contains text in another script, or mixes up look-alike letters (Bengali `র` in an Assamese pack, Assamese `ৰ` or `ৱ` in a Bengali pack). CI runs it on every pull request.

## How the app gets them

`mobile/tool/sync_language_packs.py` (run by `tool/bootstrap.sh`) copies these files into the app's assets, so choosing a language and everything else works with no internet. When the server publishes a newer version of the user's pack, the app downloads it at the next sync and uses it instead.
