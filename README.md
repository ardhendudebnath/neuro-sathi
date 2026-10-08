# NEURO-SATHI

Offline-first, multilingual AI companion for elderly cognitive care in North-East India: adaptive memory games, the **Sathi** voice companion, a personal memory book, medicine and routine reminders, and a caregiver dashboard with baseline-deviation alerts.

> NEURO-SATHI is a cognitive-support and monitoring platform. It does **not** diagnose. Clinical validation, usability studies and regulatory assessment are required before any clinical use.

```mermaid
flowchart LR
  subgraph Phone["Elderly user · Flutter app (offline-first)"]
    UI[Games · Sathi · Memory book · Reminders]
    DB[(SQLite + SQLCipher)]
    Q[Sync queue]
    N[Local notifications]
    V[On-device TTS / STT]
    UI --> DB --> Q
  end
  subgraph Web["Caregiver · Next.js dashboard"]
    D[Trends · Alerts · Memory-book uploads]
  end
  subgraph Cloud["Backend (India region)"]
    API[FastAPI · JWT · rate limits]
    PG[(PostgreSQL + RLS)]
    S3[(Private photo storage)]
    ML[Personalisation + deviation job]
    NV[NVIDIA models · server-side key]
  end
  Q -- "/sync (batched, idempotent)" --> API
  D -- "httpOnly-cookie proxy" --> API
  API --> PG
  API --> S3
  ML --> PG
  API --> NV
```

## Repository layout

| Path | What it is |
| --- | --- |
| [`backend/`](backend) | FastAPI API: OTP/JWT auth, roles, `/sync`, memory book, reminders, content, Sathi, speech, dashboard, admin. PostgreSQL schema and RLS in [`backend/db/migrations`](backend/db/migrations). |
| [`dashboard/`](dashboard) | Next.js caregiver and health-worker dashboard. |
| [`mobile/`](mobile) | Flutter app for elderly users (Android first). |
| [`content/language-packs/`](content/language-packs) | One JSON file per language, shared by the backend and the app, with a [guide for translators and reviewers](content/language-packs/README.md). |
| [`docker-compose.yml`](docker-compose.yml) | Local stack: Postgres, Redis, MinIO, API, deviation worker, dashboard. |
| [`.github/workflows/ci.yml`](.github/workflows/ci.yml) | gitleaks, backend on SQLite and on PostgreSQL + RLS, dashboard build + bundle scan, Flutter analyze/test/APK + APK scan. |

## Quick start

### Everything with Docker

```bash
cp .env.example .env   # fill in passwords and JWT_SECRET
docker compose up --build
```

API docs: http://localhost:8000/docs · Dashboard: http://localhost:3000. With `OTP_DEV_ECHO=true` the sign-in code is shown on screen (development only).

### Backend only (no Docker, SQLite)

```bash
cd backend
python -m venv .venv && .venv/bin/pip install -r requirements-dev.txt   # Windows: .venv\Scripts\pip
.venv/bin/python -m app.seed --admin +919800000000
OTP_DEV_ECHO=true .venv/bin/uvicorn app.main:app --reload
.venv/bin/pytest
```

### Dashboard

```bash
cd dashboard
npm install
API_BASE_URL=http://localhost:8000 npm run dev
```

### Mobile app

**To try it on a phone without installing Flutter**, use the tester APK that every CI run publishes, with the backend running on your computer: see [docs/testing-on-a-phone.md](docs/testing-on-a-phone.md). `python -m app.demo --phone <number>` creates a ready-to-use account with sample memories and a reminder due in a few minutes.

To build it yourself you need the Flutter SDK (stable) and Android SDK.

```bash
cd mobile
./tool/bootstrap.sh     # generates android/, patches permissions, pub get, Drift codegen
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000
```

## How the pieces fit

- **Offline first.** The app writes every action to its encrypted local database and a sync queue. Games, reminders, the memory book and everyday Sathi questions work with no signal. When online, queued changes are sent to `/sync` in batches. Each batch has a `batch_id` that is kept until the server acknowledges it, so an interrupted batch is retried without being applied twice. Conflicts are resolved by the latest `updated_at`, except that a caregiver's memory-book edit the phone hasn't seen yet wins.
- **Background sync.** The app syncs when opened, when the connection returns and every 15 minutes while open. While it is closed, an Android WorkManager job runs about once an hour when there is a connection: it uploads queued activity, pulls the caregiver's changes and reschedules the reminder alarms, so a medicine reminder added on the dashboard starts ringing without the phone's owner opening the app. A lock in the shared database keeps the app and the job from syncing at the same time.
- **Reminders** are scheduled on the phone (weekly, IST) and fire without network. Marking one done, or missing it past a 2-hour grace window, is logged for adherence trends; missed reminders are recorded by the background job too, so this does not depend on the app being opened.
- **Sathi** answers today's plan, the next medicine, "who is …" (from the memory book) and the date and time, both on the phone and on the server. Nothing needs to leave the device for these. Other questions go to the backend. There, the NVIDIA Safety Guard checks the question and the reply, and a Sarvam-M call receives only the question text.
- **A home screen that feels alive.** The header shows the hills of the North-East at the time of day, and its layers shift as the phone tilts. Tiles look raised and lit by the same light, and grow into their screens when tapped. Sathi is a glowing ball drawn by a GPU shader that swirls faster while it listens. Text and buttons stay large, and all motion stops when the phone's "Remove animations" setting is on.
- **Languages.** All wording lives in [language packs](content/language-packs): app text, reminder announcements, Sathi's answers and the words it listens for, day names, local time wording and digits, and game word lists. English and Hindi are offered to users. Assamese, Bengali, Nepali, Manipuri (in both Bengali script and Meitei Mayek) and Bodo are drafted and wait for native-speaker review; until then they appear only in reviewer builds (`--dart-define=SHOW_PREVIEW_LANGUAGES=true`). Packs are bundled with the app so they work offline, and a newer published version is downloaded at sync.
- **Personalisation (v1, explainable).** Per-game features (accuracy, completion, response time, repeated errors) set the difficulty and rank activities with a plain-language reason. The same rules run on the phone for offline play.
- **Deviation detection.** A daily job compares each user's last 7 days with their own previous 28 days. A metric is flagged only when the change is beyond 2 SD of their daily values *and* practically large. Alerts recommend a check-in and are never framed as a diagnosis.

## Security

- **Row-level security.** Every user-owned table has RLS enabled and forced. The API connects as `app_user` (not the owner, no BYPASSRLS) and sets `app.user_id` / `app.user_role` per transaction from the verified JWT. Caregivers read a user's rows only through an active link and write only that user's memory book and reminders. Admins manage content, never personal rows. CI runs the whole API suite on PostgreSQL under these policies, plus direct SQL tests ([`test_rls_pg.py`](backend/tests/test_rls_pg.py)).
- **Rate limits on every route**, keyed by user id (or IP / phone before login), returning 429 with `Retry-After`. Starting values: OTP 3 per phone per 15 min and 10 per IP per hour, Sathi 20/min and 200/day, speech 30/min and 500/day, uploads 20/hour, sync 60/hour, session renewals 30/hour per session, reads 120/min, default 60/min. A test fails if any route lacks a limit. Repeated 429s and failed logins are recorded as security events.
- **Paid-API budget cap.** Once the monthly cap is reached, Sathi falls back to offline answers and cloud speech returns 503, so the phone uses on-device voice.
- **Sessions.** Signing in with an OTP gives a one-hour access token and a session token. The session token only renews the access token, is stored on the server as a hash, can be revoked (sign out, or sign out everywhere after a lost phone) and expires after 90 days without use. It is not rotated on each use: on a weak connection a lost reply would leave the phone holding a dead token. The app and its background job renew silently. If a session does end, the app keeps every piece of local data, goes on working offline and asks the user to verify their number again; queued activity is uploaded after that. Local data is removed only on an explicit sign-out (which first tries to upload and warns if it cannot) or when a different person signs in on the phone.
- **Secrets stay on the server.** The apps never call NVIDIA, SMS or storage providers directly. The dashboard keeps both tokens in httpOnly, SameSite=Strict cookies behind a server-side proxy with a CSRF header check. `.env` is git-ignored and only `.env.example` is committed. gitleaks runs in CI, and the built JS bundle and APK are scanned for key patterns.
- **Photos** sit in a private bucket and are served only through short-lived signed URLs after the ownership check. Uploads are sniffed for JPEG/PNG/WebP and capped at 10 MB.
- **On the phone**, SQLCipher encrypts the database with a random 256-bit key held in Keystore-backed secure storage. Cloud voice is off until the user consents.
- **Audit log** of who viewed or changed whose data.

## Status

Built so far: everything above. Not yet done:

- Native-speaker review of the Hindi, Assamese, Bengali, Nepali, Manipuri and Bodo packs (all AI-drafted, Manipuri and Bodo with the least confidence). All but Hindi stay hidden from users until reviewed. Reviewers work in a spreadsheet; see [Reviewing a pack](content/language-packs/README.md#reviewing-a-pack).
- More NER languages: Khasi, Mizo and others.
- Voice for regional languages. Phones often have no Assamese voice, so the app falls back to a Bengali one; phones have no Manipuri voice at all, and no Bodo voice (the app falls back to a Hindi one); the hosted companion model does not cover Assamese, Nepali, Manipuri or Bodo, so Sathi gives scripted answers there. See [docs/nvidia-models.md](docs/nvidia-models.md).
- Trained tree-based models (scikit-learn / XGBoost) replacing the v1 rules once there is real data. The same goes for a TFLite model on the phone.
- Clinical validation and usability studies with elderly users and caregivers in the NER.
