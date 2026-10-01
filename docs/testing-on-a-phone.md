# Testing on a phone

Every CI run builds a **tester APK** that installs on any Android phone without Flutter. It is a debug build of the app with three extras: you can point it at any backend (such as your laptop on the same Wi-Fi), it offers the preview languages (Assamese, Bengali, Nepali) awaiting review, and Settings has a button that runs the background sync on demand. Normal builds have none of these.

## 1. Get the APK

The CI run attaches it as **neuro-sathi-tester-apk**, kept for 14 days.

- **On GitHub:** open the repository's **Actions** tab, then the latest **CI** run on `main`. Scroll to **Artifacts**, download `neuro-sathi-tester-apk` and unzip it.
- **From a terminal** in the repository folder:

  ```bash
  gh run download $(gh run list --workflow CI --branch main --status success --limit 1 --json databaseId --jq '.[0].databaseId') --name neuro-sathi-tester-apk --dir apk
  ```

There are two files. Use `app-arm64-v8a-debug.apk` for most phones from the last several years. If Android says the app is not compatible, use `app-armeabi-v7a-debug.apk`, which is for older or low-cost phones.

Copy the file to the phone (USB, Google Drive, or email it to yourself) and open it. Allow **Install unknown apps** for whichever app you opened it from. Android may warn about an unknown developer; that is expected for a test build.

## 2. Run the backend on your computer

In PowerShell, from the `backend` folder:

```powershell
python -m venv .venv
```

```powershell
.venv\Scripts\pip install -r requirements.txt
```

```powershell
.venv\Scripts\python -m app.seed
```

```powershell
.venv\Scripts\python -m app.demo --phone 9876543210 --caregiver-phone 9876500000
```

```powershell
$env:OTP_DEV_ECHO="true"; .venv\Scripts\uvicorn app.main:app --host 0.0.0.0 --port 8000
```

- Any 10-digit numbers will do: no SMS is sent. With `OTP_DEV_ECHO=true` the sign-in code is shown on the phone's screen.
- `app.demo` creates the user with three people in their memory book, a caregiver linked to them, and a daily **Test medicine** reminder due 3 minutes after you run it.
- Data is kept in `backend\neuro_sathi_dev.db`.
- When Windows asks whether Python may use the network, allow it on **private networks**.
- Find your computer's address with `ipconfig`: look for **IPv4 Address** under the Wi-Fi adapter, for example `192.168.1.5`.
- Check from the phone's browser that `http://192.168.1.5:8000/health` shows `{"status":"ok"}`.

## 3. Sign in on the phone

1. Connect the phone to the same Wi-Fi as the computer.
2. Open NEURO-SATHI and choose a language.
3. In the yellow **Tester build** box, tap **Change server**, enter `http://192.168.1.5:8000` (your address) and save.
4. Enter the demo number, tap **Send code**, and type the code shown under "Development code".

## 4. What to check

| What | How |
| --- | --- |
| Reminder rings with the app closed | The home screen shows **Test medicine** as the next reminder. Close the app and wait: the alarm should ring at that time. Run `app.demo` again (it adds a new reminder each time, `--remind-in 3` by default) and reopen the app to try again. |
| Background sync | On the computer run `.venv\Scripts\python -m app.demo --phone 9876543210 --remind-in 5`. In the app, open Settings, tap **Background sync in 1 minute**, and close the app. The job pulls the new reminder by itself and it rings about 5 minutes later, without the app being opened. **Last synced** in Settings shows when the job ran. |
| Memory book | **Memories** shows Rina, Bipul and Mala; the speaker button reads each one aloud. |
| Games | Play a few rounds of several games. Levels adjust after a couple of sessions. |
| Sathi | Ask "when is my medicine?", "who is Rina?" and "what day is it?", by voice and by typing. Turn on airplane mode: these still work. |
| Offline | In airplane mode, play a game and mark a reminder done. Reconnect: it uploads at the next sync and **Last synced** updates. |
| Languages | Switch language in Settings. Voice uses the phone's own voices; Assamese may fall back to a Bengali voice, and if a language has none the app says so. |
| Sign in again | Run `.venv\Scripts\python -m app.demo --phone 9876543210 --end-sessions`. Within the hour (when the phone's current access token runs out) the home screen shows **Sign in again**. Everything on the phone is still there; after signing in, syncing resumes. |
| Caregiver view (optional) | The dashboard needs Node.js 20. From `dashboard`: `npm install`, then `$env:API_BASE_URL="http://localhost:8000"; npm run dev`, open `http://localhost:3000` and sign in with the caregiver number. Add a reminder or a memory with a photo and watch it reach the phone. |

## Troubleshooting

- **The phone cannot reach the server.** Check that both are on the same Wi-Fi, that Windows allowed Python on private networks, and that `/health` opens in the phone's browser. Some office and public Wi-Fi networks keep devices apart; connect the computer to the phone's hotspot instead.
- **No code on screen.** `OTP_DEV_ECHO` must be set in the same PowerShell window that runs `uvicorn`.
- **A reminder rang late or not at all.** Allow notifications for NEURO-SATHI, and set its battery usage to **Unrestricted** (Settings, Apps, NEURO-SATHI, Battery). Reminders use inexact alarms, so a few minutes' delay is normal.
- **The APK will not install.** Try the other file, or uninstall an older copy of the app first.

The tester APK allows plain `http://` so it can reach a server on your network. Normal builds only use HTTPS.
