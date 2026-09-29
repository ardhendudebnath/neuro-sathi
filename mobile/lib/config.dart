/// Public build-time settings only. No secret ever goes into --dart-define,
/// assets or source: an APK can be unpacked by anyone. Paid services are
/// reached through our backend, which holds the keys.
class AppConfig {
  static const apiBaseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: 'http://10.0.2.2:8000');

  /// How often to try syncing while the app is open.
  static const syncInterval = Duration(minutes: 15);

  /// A reminder not marked done within this window is logged as missed.
  static const reminderGrace = Duration(hours: 2);
}
