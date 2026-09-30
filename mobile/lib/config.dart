/// Public build-time settings only. No secret ever goes into --dart-define,
/// assets or source: an APK can be unpacked by anyone. Paid services are
/// reached through our backend, which holds the keys.
class AppConfig {
  static const apiBaseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: 'http://10.0.2.2:8000');

  /// How often to try syncing while the app is open.
  static const syncInterval = Duration(minutes: 15);

  /// How often the background worker syncs while the app is closed. Android
  /// runs it only when there is a connection, and may delay it to save battery.
  static const backgroundSyncInterval = Duration(hours: 1);

  /// A sync lock older than this belongs to a run that was killed; take it over.
  static const syncLockTtl = Duration(minutes: 10);

  /// A reminder not marked done within this window is logged as missed.
  static const reminderGrace = Duration(hours: 2);
}
