"""Patch the generated Android project for NEURO-SATHI's plugins. Idempotent.

- permissions: internet, microphone (on-device speech), notifications, boot,
  exact alarms (so reminders ring on the minute once the user allows it)
- flutter_local_notifications receivers so reminders survive a reboot
- <queries> for the speech recogniser and text-to-speech engines
- core library desugaring (required by flutter_local_notifications)
- minSdk at least 23 (flutter_secure_storage), app label
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent / "android" / "app"
MANIFEST = ROOT / "src" / "main" / "AndroidManifest.xml"

PERMISSIONS = [
    "android.permission.INTERNET",
    "android.permission.ACCESS_NETWORK_STATE",
    "android.permission.RECORD_AUDIO",
    "android.permission.POST_NOTIFICATIONS",
    "android.permission.RECEIVE_BOOT_COMPLETED",
    "android.permission.VIBRATE",
    "android.permission.SCHEDULE_EXACT_ALARM",
]

RECEIVERS = """
        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver" />
        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver">
            <intent-filter>
                <action android:name="android.intent.action.BOOT_COMPLETED"/>
                <action android:name="android.intent.action.MY_PACKAGE_REPLACED"/>
                <action android:name="android.intent.action.QUICKBOOT_POWERON" />
                <action android:name="com.htc.intent.action.QUICKBOOT_POWERON"/>
            </intent-filter>
        </receiver>
"""

INTENTS = """
        <intent><action android:name="android.speech.RecognitionService" /></intent>
        <intent><action android:name="android.intent.action.TTS_SERVICE" /></intent>
"""


def patch_manifest() -> None:
    xml = MANIFEST.read_text(encoding="utf-8")
    for p in PERMISSIONS:
        if p not in xml:
            xml = xml.replace("<application", f'<uses-permission android:name="{p}" />\n    <application', 1)
    if "ScheduledNotificationReceiver" not in xml:
        xml = xml.replace("</application>", RECEIVERS + "    </application>", 1)
    if "android.speech.RecognitionService" not in xml:
        if "<queries>" in xml:  # recent Flutter templates already declare a <queries> block
            xml = xml.replace("<queries>", "<queries>" + INTENTS, 1)
        else:
            xml = xml.replace("</manifest>", "    <queries>" + INTENTS + "    </queries>\n</manifest>", 1)
    xml = re.sub(r'android:label="[^"]*"', 'android:label="NEURO-SATHI"', xml, count=1)
    MANIFEST.write_text(xml, encoding="utf-8")


def patch_gradle() -> None:
    kts = ROOT / "build.gradle.kts"
    groovy = ROOT / "build.gradle"
    path = kts if kts.exists() else groovy
    g = path.read_text(encoding="utf-8")
    is_kts = path.suffix == ".kts"

    if "desugar" not in g.lower():
        flag = "isCoreLibraryDesugaringEnabled = true" if is_kts else "coreLibraryDesugaringEnabled true"
        g, n = re.subn(r"compileOptions\s*\{", "compileOptions {\n        " + flag, g, count=1)
        if n == 0:
            sys.exit("patch_android: compileOptions block not found")
        dep = (
            'coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")'
            if is_kts
            else "coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'"
        )
        if re.search(r"^dependencies\s*\{", g, flags=re.M):
            g = re.sub(r"^dependencies\s*\{", "dependencies {\n    " + dep, g, count=1, flags=re.M)
        else:
            g += "\ndependencies {\n    " + dep + "\n}\n"

    g = re.sub(r"minSdk\s*=\s*flutter\.minSdkVersion", "minSdk = maxOf(flutter.minSdkVersion, 23)", g)
    g = re.sub(r"minSdkVersion\s+flutter\.minSdkVersion", "minSdkVersion Math.max(flutter.minSdkVersion, 23)", g)
    path.write_text(g, encoding="utf-8")


def patch_debug_manifest() -> None:
    """Debug builds only: allow plain HTTP to a local development API. Release stays HTTPS-only."""
    debug = ROOT / "src" / "debug" / "AndroidManifest.xml"
    if not debug.exists():
        return
    xml = debug.read_text(encoding="utf-8")
    if "usesCleartextTraffic" not in xml:
        xml = xml.replace("</manifest>", '    <application android:usesCleartextTraffic="true" />\n</manifest>', 1)
        debug.write_text(xml, encoding="utf-8")


if __name__ == "__main__":
    patch_manifest()
    patch_debug_manifest()
    patch_gradle()
    print("android project patched")
