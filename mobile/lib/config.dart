/// Public build-time settings only. No secret ever goes into --dart-define,
/// assets or source: an APK can be unpacked by anyone. Paid services are
/// reached through our backend, which holds the keys.
class AppConfig {
  static const apiBaseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: 'http://10.0.2.2:8000');

  /// The APK that CI publishes for testing on real phones: it can be pointed at
  /// any backend (e.g. a laptop on the same Wi-Fi) and has a few tester tools.
  /// Normal builds have none of this.
  static const testerBuild = bool.fromEnvironment('TESTER_BUILD');

  /// How often to try syncing while the app is open.
  static const syncInterval = Duration(minutes: 15);

  /// How often the background worker syncs while the app is closed. Android
  /// runs it only when there is a connection, and may delay it to save battery.
  static const backgroundSyncInterval = Duration(hours: 1);

  /// A sync lock older than this belongs to a run that was killed; take it over.
  static const syncLockTtl = Duration(minutes: 10);

  /// A reminder not marked done within this window is logged as missed.
  static const reminderGrace = Duration(hours: 2);

  /// A backend address typed by a tester: "192.168.1.5:8000" becomes
  /// "http://192.168.1.5:8000"; a trailing slash is dropped. Null if unusable.
  static String? normalizeServerUrl(String input) {
    var url = input.trim();
    if (url.isEmpty) return null;
    if (!url.contains('://')) url = 'http://$url';
    final uri = Uri.tryParse(url);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https') || uri.host.isEmpty) return null;
    return '${uri.scheme}://${uri.authority}${uri.path.replaceFirst(RegExp(r'/+$'), '')}';
  }
}
