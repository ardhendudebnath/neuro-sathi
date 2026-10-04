# Testing on a phone

Every CI run builds a **tester APK** that installs on any Android phone without Flutter. It is a debug build of the app with three extras: you can point it at any backend (such as your laptop, over Wi-Fi or a USB cable), it offers the preview languages (Assamese, Bengali, Nepali) awaiting review, and Settings has a button that runs the background sync on demand. Normal builds have none of these.

## 1. Get the APK

The CI run attaches it as **neuro-sathi-tester-apk**, kept for 14 days.

- **On GitHub:** open the repository's **Actions** tab, then the latest **CI** run on `main`. Scroll to **Artifacts**, download `neuro-sathi-tester-apk` and unzip it.
- **From a terminal** in the repository folder:

  ```bash
  gh run download $(gh run list --workflow CI --branch main --status success --limit 1 --json databaseId --jq '.[0].databaseId') --name neuro-sathi-tester-apk --dir apk
  ```

There are two files. Use `app-arm64-v8a-debug.apk` for most phones from the last several years. If Android says the app is not compatible, use `app-armeabi-v7a-debug.apk`, which is for older or low-cost phones.

Copy the file to the phone (USB, Google Drive, or email it to yourself) and open it. Allow **Install unknown apps** for whichever app you opened it from. Android may warn about an unknown developer; that is expected for a test build.

A newer tester APK installs over the old one and keeps the app's data, as long as both were signed with the repository's tester key (see [One signing key for all tester APKs](#one-signing-key-for-all-tester-apks)). If Android refuses because the signatures do not match, uninstall the old copy first.

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

## 3. Connect the phone

The app on the phone has to reach the backend on your computer, over Wi-Fi or over a USB cable. Wi-Fi needs no setup on the phone. The cable works on any network and whatever firewall the computer runs.

### Over Wi-Fi

1. Connect the phone to the same Wi-Fi as the computer.
2. When Windows asks whether Python may use the network, allow it on **private networks**.
3. Find your computer's address with `ipconfig`: look for **IPv4 Address** under the Wi-Fi adapter, for example `192.168.1.5`.
4. Check from the phone's browser that `http://192.168.1.5:8000/health` shows `{"status":"ok"}`.

The server address for the app is `http://192.168.1.5:8000` (your address).

### Over a USB cable

1. On the phone, turn on developer options: in Settings, About phone, Software information, tap **Build number** seven times. Then in Settings, **Developer options**, turn on **USB debugging**.
2. Download Android's [SDK Platform-Tools](https://developer.android.com/tools/releases/platform-tools) for Windows and unzip them.
3. Connect the phone with a cable that carries data. If the phone asks what the connection is for, choose **Transferring files**. Then allow USB debugging for this computer: that prompt shows the computer's RSA key fingerprint.
4. In PowerShell, from the `platform-tools` folder, `.\adb devices` should list the phone as `device`. Then send the phone's port 8000 to the computer:

   ```powershell
   .\adb reverse tcp:8000 tcp:8000
   ```

The server address for the app is `http://localhost:8000`. The backend can then run with `--host 127.0.0.1` instead of `0.0.0.0`, which keeps it off the network.

The forwarding ends whenever the phone's USB connection resets, and some phones reset it by themselves (Samsung phones, for example, when unlocked). To restore it automatically, leave this running in a second PowerShell window:

```powershell
while ($true) { .\adb reverse tcp:8000 tcp:8000 *> $null; Start-Sleep 3 }
```

`.\adb install app-arm64-v8a-debug.apk` installs the APK over the same cable. When you have finished, turn **USB debugging** off again: it lets a connected computer control the phone.

## 4. Sign in on the phone

1. Open NEURO-SATHI and choose a language.
2. In the yellow **Tester build** box at the top, tap **Change server**, enter the server address from step 3 and save. A fresh install points at `http://10.0.2.2:8000`, which only works in the Android emulator.
3. Enter the demo number, tap **Send code**, and type the code shown under "Development code". Use the number you gave `app.demo`: any other number signs in to a new, empty account.

## 5. What to check

| What | How |
| --- | --- |
| Reminder rings with the app closed | The home screen shows **Test medicine** as the next reminder. If it also says reminders may ring late, tap **Ring on time** and turn on the switch Android shows. Close the app and wait: the alarm should ring at that minute. Run `app.demo` again (it adds a new reminder each time, `--remind-in 3` by default) and reopen the app to try again. |
| Your name | Change it in Settings and tap **Save**: the home screen greets you with it. Signing in on another phone with a name also changes it. |
| Background sync | On the computer run `.venv\Scripts\python -m app.demo --phone 9876543210 --remind-in 5`. In the app, open Settings, tap **Background sync in 1 minute**, and close the app. The job pulls the new reminder by itself and it rings about 5 minutes later, without the app being opened. **Last synced** in Settings shows when the job ran. |
| Memory book | **Memories** shows Rina, Bipul and Mala; the speaker button reads each one aloud. |
| Games | Play a few rounds of several games. Levels adjust after a couple of sessions. |
| Sathi | Ask "when is my medicine?", "who is Rina?" and "what day is it?", by voice and by typing. Turn on airplane mode: these still work. |
| Offline | In airplane mode, play a game and mark a reminder done. Reconnect: it uploads at the next sync and **Last synced** updates. Over the USB cable, unplug it instead: airplane mode does not cut the cable. |
| Languages | Switch language in Settings. Voice uses the phone's own voices; Assamese may fall back to a Bengali voice, and if a language has none the app says so. |
| Sign in again | Run `.venv\Scripts\python -m app.demo --phone 9876543210 --end-sessions`. Within the hour (when the phone's current access token runs out) the home screen shows **Sign in again**. Everything on the phone is still there; after signing in, syncing resumes. |
| Caregiver view (optional) | The dashboard needs Node.js 20. From `dashboard`: `npm install`, then `$env:API_BASE_URL="http://localhost:8000"; npm run dev`, open `http://localhost:3000` and sign in with the caregiver number. Add a reminder or a memory with a photo and watch it reach the phone. |

## Troubleshooting

- **"Cannot reach the server at …"** The message names the address the app tried. Correct it in the Tester build box, then check the connection: `/health` in the phone's browser over Wi-Fi, or `.\adb reverse --list` showing `tcp:8000` over the cable.
- **The phone cannot reach the server over Wi-Fi.** Check that both are on the same Wi-Fi, that Windows allowed Python on private networks, and that `/health` opens in the phone's browser. Security software such as McAfee or Norton can replace the Windows firewall with its own, which then blocks the phone even though Windows allows Python: allow Python there too, or use the USB cable. Some office and public Wi-Fi networks keep devices apart; use the cable, or connect the computer to the phone's hotspot.
- **Seeing what the app does.** With the cable connected, `.\adb logcat -s flutter` shows the app's log. Tester builds write a line for every sync, such as `NEURO-SATHI sync with http://localhost:8000: offline (...)`. After a sync that does not finish, the app tries again after 30 seconds and 2 minutes, then every 15 minutes while it is open.
- **No code on screen.** `OTP_DEV_ECHO` must be set in the same PowerShell window that runs `uvicorn`.
- **A reminder rang late or not at all.** Allow notifications for NEURO-SATHI, and set its battery usage to **Unrestricted** (Settings, Apps, NEURO-SATHI, Battery). Reminders ring on the minute only if NEURO-SATHI may set exact alarms: the home screen offers it, or allow it in Settings, Apps, NEURO-SATHI, **Alarms & reminders**. Without that, Android may hold a reminder back by up to an hour (Android 14 and later leave it off at first).
- **The APK will not install.** Try the other file. If the signatures do not match, uninstall the older copy of the app first.

The tester APK allows plain `http://` so it can reach a server on your network. Normal builds only use HTTPS.

## One signing key for all tester APKs

For maintainers. Android installs an update only if it is signed with the same key as the app already on the phone. CI signs the tester APK with the key in the repository secret `TESTER_KEYSTORE_BASE64`, so each new build installs over the last one. A repository secret is used because workflows started from forks cannot read it. Without the secret, each run signs with a new key, and testers have to uninstall before every update.

To create the secret once, on a computer with a JDK (`keytool` comes with it) and the GitHub CLI, in PowerShell:

```powershell
keytool -genkeypair -keystore tester.keystore -storepass android -keypass android -alias androiddebugkey -keyalg RSA -keysize 2048 -validity 10950 -dname "CN=Android Debug,O=Android,C=US"
```

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("$PWD\tester.keystore")) | gh secret set TESTER_KEYSTORE_BASE64
```

Then delete `tester.keystore`: the secret is the copy CI uses. The CI step "Use the tester signing key" prints the key's SHA-256 fingerprint. Replacing the key means testers uninstall once more.
