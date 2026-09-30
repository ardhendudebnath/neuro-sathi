import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';

import '../config.dart';
import '../data/api_client.dart';
import '../data/database.dart';
import '../data/repository.dart';
import '../data/secure_store.dart';
import '../data/sync_service.dart';
import '../l10n.dart';
import '../l10n/load.dart';
import 'notifications.dart';
import 'reminders.dart';

// Sync while the app is closed. Android's WorkManager runs the job about once
// an hour, only when there is a connection, and keeps the schedule across
// reboots. Each run:
//   1. logs reminders that were missed (so adherence does not depend on the
//      user opening the app),
//   2. uploads queued activity and pulls the caregiver's changes,
//   3. reschedules the on-device reminder alarms if reminders changed, so a
//      medicine reminder added by a caregiver starts ringing by itself.

const _task = 'neuro_sathi.background_sync';

/// Called by WorkManager in its own isolate, with no UI.
@pragma('vm:entry-point')
void backgroundSyncDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      await runBackgroundSync();
    } on Object catch (e) {
      debugPrint('background sync failed: $e');
    }
    // Always report success: the job is periodic and runs again by itself, so
    // WorkManager's own retry and backoff are not needed on top.
    return true;
  });
}

Future<SyncOutcome> runBackgroundSync() async {
  final store = SecureStore();
  final access = await store.token();
  final refresh = await store.refreshToken();
  // Signed out, or the session ended and the app is waiting for the user to sign in again.
  if (access == null && refresh == null) return SyncOutcome.sessionExpired;
  final api = ApiClient(
    token: access,
    accessExpiresAt: await store.accessExpiresAt(),
    refreshToken: refresh,
    onAccessRenewed: store.saveAccess, // so the next run, or the app's next start, begins with a valid token
    onSessionExpired: store.clearSession, // the app then asks the user to sign in again; all data is kept
  );
  final db = await openEncryptedDb();
  try {
    final repo = Repository(db);
    final catalog = await loadCatalog(db);
    final strings = Strings(catalog.pack(await storedLanguage(db, catalog)), catalog.english);
    final notifications = ReminderNotifications();
    await notifications.init((_) {}, requestPermission: false);

    await logMissedReminders(repo, DateTime.now());
    final sync = SyncService(
      db,
      repo,
      api,
      onRemindersChanged: () async =>
          notifications.rescheduleAll(await repo.reminders(), (r) => reminderTitle(strings, r)),
    );
    // If the app is open and syncing right now this returns "busy" and leaves it to the app.
    return await sync.syncNow();
  } finally {
    await db.close();
  }
}

class BackgroundSync {
  /// Call once at app start, before scheduling.
  static Future<void> initialize() => _guard(() => Workmanager().initialize(backgroundSyncDispatcher));

  /// Safe to call on every start: the unique name keeps a single schedule.
  static Future<void> schedule() => _guard(
        () => Workmanager().registerPeriodicTask(
          _task,
          _task,
          frequency: AppConfig.backgroundSyncInterval,
          constraints: Constraints(networkType: NetworkType.connected),
        ),
      );

  /// On sign-out.
  static Future<void> cancel() => _guard(() => Workmanager().cancelByUniqueName(_task));

  /// Background sync is an extra: the app must work without it (the platform
  /// may not support it, or the plugin may be unavailable in tests).
  static Future<void> _guard(Future<void> Function() action) async {
    try {
      await action();
    } on Object catch (e) {
      debugPrint('background sync unavailable: $e');
    }
  }
}
