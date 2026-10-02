import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config.dart';
import '../data/api_client.dart';
import '../data/database.dart';
import '../data/repository.dart';
import '../data/secure_store.dart';
import '../data/sync_retry.dart';
import '../data/sync_service.dart';
import '../l10n.dart';
import '../l10n/load.dart';
import '../services/background_sync.dart';
import '../services/notifications.dart';
import '../services/reminders.dart' as reminders;
import '../services/voice.dart';

/// Overridden in main() with the opened, encrypted database.
final dbProvider = Provider<AppDb>((ref) => throw UnimplementedError('dbProvider must be overridden'));
final repoProvider = Provider<Repository>((ref) => Repository(ref.watch(dbProvider)));
final apiProvider = Provider<ApiClient>((ref) => ApiClient());
final voiceProvider = Provider<Voice>((ref) => Voice());
final notificationsProvider = Provider<ReminderNotifications>((ref) => ReminderNotifications());

class AppState {
  const AppState({
    this.ready = false,
    this.signedIn = false,
    this.sessionExpired = false,
    this.userId,
    this.name,
    this.language = 'en',
    this.region,
    this.fontScale = 1.4,
    this.online = false,
    this.catalog = LanguageCatalog.none,
  });

  final bool ready;

  /// This phone holds someone's account and data.
  final bool signedIn;

  /// The server ended the session. The app keeps working offline with the data on
  /// the phone; syncing resumes once the user verifies their number again.
  final bool sessionExpired;
  final String? userId;
  final String? name;
  final String language;
  final String? region;
  final double fontScale;
  final bool online;
  final LanguageCatalog catalog;

  LanguagePack get currentPack => catalog.pack(language);
  Strings get strings => Strings(currentPack, catalog.english);

  AppState copyWith({
    bool? ready,
    bool? signedIn,
    bool? sessionExpired,
    String? userId,
    String? name,
    String? language,
    String? region,
    double? fontScale,
    bool? online,
    LanguageCatalog? catalog,
  }) =>
      AppState(
        ready: ready ?? this.ready,
        signedIn: signedIn ?? this.signedIn,
        sessionExpired: sessionExpired ?? this.sessionExpired,
        userId: userId ?? this.userId,
        name: name ?? this.name,
        language: language ?? this.language,
        region: region ?? this.region,
        fontScale: fontScale ?? this.fontScale,
        online: online ?? this.online,
        catalog: catalog ?? this.catalog,
      );
}

final appProvider = StateNotifierProvider<AppController, AppState>((ref) => AppController(ref));
final stringsProvider = Provider<Strings>((ref) => ref.watch(appProvider).strings);

class AppController extends StateNotifier<AppState> {
  AppController(this.ref) : super(const AppState());

  final Ref ref;
  final _secure = SecureStore();
  final _retry = SyncRetry();
  Timer? _timer;
  StreamSubscription<List<ConnectivityResult>>? _conn;
  late final SyncService _sync = SyncService(
    ref.read(dbProvider),
    ref.read(repoProvider),
    ref.read(apiProvider),
    onRemindersChanged: rescheduleReminders,
  );

  AppDb get _db => ref.read(dbProvider);

  Future<void> start() async {
    final api = ref.read(apiProvider)
      ..token = await _secure.token()
      ..accessExpiresAt = await _secure.accessExpiresAt()
      ..refreshToken = await _secure.refreshToken()
      ..onAccessRenewed = _secure.saveAccess
      ..onSessionExpired = _onSessionExpired;
    if (AppConfig.testerBuild) {
      final server = await _db.getValue('api_base_url');
      if (server != null) api.baseUrl = server;
    }
    final hasAccount = await _db.getValue('user_id') != null;
    final catalog = await loadCatalog(_db);
    final language = await storedLanguage(_db, catalog);
    state = state.copyWith(
      ready: true,
      signedIn: hasAccount,
      sessionExpired: hasAccount && !api.hasSession,
      userId: await _db.getValue('user_id'),
      name: await _db.getValue('name'),
      language: language,
      region: await _db.getValue('region'),
      fontScale: double.tryParse(await _db.getValue('font_scale') ?? '') ?? 1.4,
      catalog: catalog,
    );
    await ref.read(voiceProvider).setLanguage(state.currentPack);
    await ref.read(notificationsProvider).init((_) {});

    final connectivity = Connectivity();
    _setOnline(await connectivity.checkConnectivity());
    _conn = connectivity.onConnectivityChanged.listen(_setOnline);
    _timer = Timer.periodic(AppConfig.syncInterval, (_) => syncNow());
    if (state.signedIn) {
      unawaited(BackgroundSync.schedule());
      await rescheduleReminders();
      await logMissedReminders();
      unawaited(syncNow());
    }
  }

  void _setOnline(List<ConnectivityResult> results) {
    final online = results.any((r) => r != ConnectivityResult.none);
    final cameOnline = online && !state.online;
    state = state.copyWith(online: online);
    if (cameOnline && state.signedIn) unawaited(syncNow());
  }

  /// [retry] marks the retries scheduled by [SyncRetry]; any other call is a new
  /// reason to sync and starts a fresh series of retries.
  Future<void> syncNow({bool retry = false}) async {
    if (!state.signedIn || state.sessionExpired) return;
    if (!retry) _retry.restart();
    final outcome = await _sync.syncNow();
    if (AppConfig.testerBuild) debugPrint('NEURO-SATHI sync ${_sync.describe(outcome)}');
    if (outcome == SyncOutcome.sessionExpired) {
      await _onSessionExpired();
      return;
    }
    if (mounted) _retry.after(outcome, () => unawaited(syncNow(retry: true)));
    final downloaded = parseDownloadedPack(await _db.getValue('language_pack'));
    if (downloaded != null) state = state.copyWith(catalog: state.catalog.withDownloaded(downloaded));
    refreshScreens();
  }

  /// The server would not renew the session (unused for months, or ended from
  /// another device). Everything stays on the phone and the app keeps working
  /// offline; the home screen asks the user to sign in again, and the queued
  /// activity is uploaded after that.
  Future<void> _onSessionExpired() async {
    await _secure.clearSession();
    ref.read(apiProvider).clearSession();
    if (mounted) state = state.copyWith(sessionExpired: true);
  }

  /// The backend this app talks to.
  String get serverUrl => ref.read(apiProvider).baseUrl;

  /// Tester builds only: point the app at another backend, such as a laptop on
  /// the same Wi-Fi. Returns false if the address is not usable.
  Future<bool> setServer(String input) async {
    if (!AppConfig.testerBuild) return false;
    final url = AppConfig.normalizeServerUrl(input);
    if (url == null) return false;
    await _db.setValue('api_base_url', url);
    ref.read(apiProvider).baseUrl = url;
    return true;
  }

  /// Wipes this person's data but keeps device settings that are not personal.
  Future<void> _wipeKeepingDeviceSettings() async {
    final server = await _db.getValue('api_base_url');
    await _db.wipe();
    await _db.setValue('language', state.language);
    await _db.setValue('font_scale', '${state.fontScale}');
    if (server != null) await _db.setValue('api_base_url', server);
  }

  /// Changes recorded on this phone that the server does not have yet.
  Future<int> unsyncedCount() => ref.read(repoProvider).queuedCount();

  /// The background sync worker writes through its own database connection, which
  /// this isolate's live queries do not see. Re-run them.
  void refreshScreens() => _db.markTablesUpdated(_db.allTables);

  /// The app came back to the foreground.
  Future<void> onResumed() async {
    refreshScreens();
    await logMissedReminders();
    await syncNow();
  }

  /// Called after the code is verified: a first sign-in, or signing in again after
  /// the session expired (the data on the phone is kept and syncing resumes).
  Future<void> signedIn(Map<String, dynamic> tokenResponse) async {
    final user = tokenResponse['user'] as Map<String, dynamic>;
    final userId = user['id'] as String;
    final previous = await _db.getValue('user_id');
    if (previous != null && previous != userId) {
      // A different person is signing in: this phone keeps only the signed-in user's data.
      await _wipeKeepingDeviceSettings();
      state = AppState(ready: true, language: state.language, online: state.online, fontScale: state.fontScale, catalog: state.catalog);
    }
    final access = tokenResponse['access_token'] as String;
    final expiresAt = DateTime.now().add(Duration(seconds: tokenResponse['expires_in'] as int));
    final refresh = tokenResponse['refresh_token'] as String?;
    await _secure.saveSession(access: access, expiresAt: expiresAt, refresh: refresh);
    ref.read(apiProvider)
      ..token = access
      ..accessExpiresAt = expiresAt
      ..refreshToken = refresh;
    await _db.setValue('user_id', userId);
    await _db.setValue('phone', user['phone'] as String);
    if (user['name'] != null) await _db.setValue('name', user['name'] as String);
    if (user['region'] != null) await _db.setValue('region', user['region'] as String);
    state = state.copyWith(
      signedIn: true,
      sessionExpired: false,
      userId: userId,
      name: user['name'] as String?,
      region: user['region'] as String?,
    );
    await ref.read(apiProvider).updateMe({'language': state.language}).catchError((_) {});
    unawaited(BackgroundSync.schedule());
    await syncNow();
    await rescheduleReminders();
  }

  Future<void> setLanguage(String language) async {
    await _db.setValue('language', language);
    await _db.removeValue('language_pack');
    await _db.removeValue('content_refreshed_at');
    state = state.copyWith(language: language);
    await ref.read(voiceProvider).setLanguage(state.currentPack);
    if (state.signedIn) {
      unawaited(ref.read(apiProvider).updateMe({'language': language}).catchError((_) {}));
      await rescheduleReminders();
    }
  }

  Future<void> setRegion(String region) async {
    await _db.setValue('region', region);
    await _db.removeValue('content_refreshed_at');
    state = state.copyWith(region: region);
    unawaited(ref.read(apiProvider).updateMe({'region': region}).catchError((_) {}));
  }

  Future<void> setFontScale(double scale) async {
    await _db.setValue('font_scale', '$scale');
    state = state.copyWith(fontScale: scale);
  }

  Future<void> rescheduleReminders() async {
    final s = state.strings;
    final list = await ref.read(repoProvider).reminders();
    await ref.read(notificationsProvider).rescheduleAll(list, (r) => reminders.reminderTitle(s, r));
  }

  /// Records reminders that went past their grace window without being marked done.
  Future<void> logMissedReminders() => reminders.logMissedReminders(ref.read(repoProvider), DateTime.now());

  /// The user chose to sign out: ends the session on the server and removes their
  /// data from this phone. An expired session never comes here (see _onSessionExpired).
  Future<void> signOut() async {
    await BackgroundSync.cancel();
    try {
      await ref.read(apiProvider).logout();
    } on Object {
      // Offline or already ended: the session expires on the server by itself.
    }
    await _secure.clearSession();
    ref.read(apiProvider).clearSession();
    await _wipeKeepingDeviceSettings(); // the phone keeps only the signed-in user's data
    await ref.read(notificationsProvider).rescheduleAll(const [], (_) => '');
    state = AppState(ready: true, language: state.language, online: state.online, fontScale: state.fontScale, catalog: state.catalog);
  }

  @override
  void dispose() {
    _retry.cancel();
    _timer?.cancel();
    _conn?.cancel();
    super.dispose();
  }
}
