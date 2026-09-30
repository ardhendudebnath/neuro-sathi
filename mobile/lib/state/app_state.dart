import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config.dart';
import '../data/api_client.dart';
import '../data/database.dart';
import '../data/repository.dart';
import '../data/secure_store.dart';
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
    this.userId,
    this.name,
    this.language = 'en',
    this.region,
    this.fontScale = 1.4,
    this.online = false,
    this.catalog = LanguageCatalog.none,
  });

  final bool ready;
  final bool signedIn;
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
    final token = await _secure.token();
    ref.read(apiProvider).token = token;
    final catalog = await loadCatalog(_db);
    final language = await storedLanguage(_db, catalog);
    state = state.copyWith(
      ready: true,
      signedIn: token != null,
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

  Future<void> syncNow() async {
    if (!state.signedIn) return;
    final outcome = await _sync.syncNow();
    if (outcome == SyncOutcome.signedOut) {
      await signOut();
      return;
    }
    final downloaded = parseDownloadedPack(await _db.getValue('language_pack'));
    if (downloaded != null) state = state.copyWith(catalog: state.catalog.withDownloaded(downloaded));
    refreshScreens();
  }

  /// The background sync worker writes through its own database connection, which
  /// this isolate's live queries do not see. Re-run them.
  void refreshScreens() => _db.markTablesUpdated(_db.allTables);

  /// The app came back to the foreground.
  Future<void> onResumed() async {
    refreshScreens();
    await logMissedReminders();
    await syncNow();
  }

  Future<void> signedIn(Map<String, dynamic> tokenResponse) async {
    final user = tokenResponse['user'] as Map<String, dynamic>;
    await _secure.setToken(tokenResponse['access_token'] as String);
    ref.read(apiProvider).token = tokenResponse['access_token'] as String;
    await _db.setValue('user_id', user['id'] as String);
    if (user['name'] != null) await _db.setValue('name', user['name'] as String);
    if (user['region'] != null) await _db.setValue('region', user['region'] as String);
    state = state.copyWith(
      signedIn: true,
      userId: user['id'] as String,
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

  Future<void> signOut() async {
    await BackgroundSync.cancel();
    await _secure.clearToken();
    ref.read(apiProvider).token = null;
    await _db.wipe(); // the phone keeps only the signed-in user's data
    await ref.read(notificationsProvider).rescheduleAll(const [], (_) => '');
    state = AppState(ready: true, language: state.language, online: state.online, fontScale: state.fontScale, catalog: state.catalog);
    await _db.setValue('language', state.language);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _conn?.cancel();
    super.dispose();
  }
}
