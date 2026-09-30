import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../config.dart';
import 'api_client.dart';
import 'database.dart';
import 'repository.dart';

/// sessionExpired: the server will not renew the session; the queue is kept for
/// when the user signs in again. busy: a sync is already running, here or in the
/// other isolate.
enum SyncOutcome { synced, offline, sessionExpired, failed, busy }

/// Offline-first sync:
/// 1. every local action is already in SyncQueue;
/// 2. when online, queued changes are sent in batches with a batch_id;
/// 3. the server's memory book, reminders and recommendations are applied;
/// 4. only then is the batch cleared from the queue. The batch_id is kept
///    until acknowledged, so a batch interrupted mid-sync is retried with the
///    same id and the server does not apply it twice.
///
/// The same service runs in the app and in the background worker
/// (services/background_sync.dart). A lock in the shared database keeps the
/// two from syncing at the same time.
class SyncService {
  SyncService(this.db, this.repo, this.api, {this.onRemindersChanged});

  final AppDb db;
  final Repository repo;
  final ApiClient api;
  final Future<void> Function()? onRemindersChanged;
  bool _running = false;

  static const _batchSize = 200;
  static const _lock = 'sync';

  Future<SyncOutcome> syncNow() async {
    if (!api.hasSession) return SyncOutcome.sessionExpired;
    if (_running) return SyncOutcome.busy;
    _running = true;
    var locked = false;
    try {
      locked = await db.tryLock(_lock, AppConfig.syncLockTtl);
      if (!locked) return SyncOutcome.busy;
      var more = true;
      while (more) {
        more = await _syncOneBatch();
      }
      await _cachePhotos();
      await _refreshContentIfStale();
      return SyncOutcome.synced;
    } on OfflineException {
      return SyncOutcome.offline;
    } on SessionExpiredException {
      return SyncOutcome.sessionExpired; // nothing is deleted: the queue waits for the next sign-in
    } on ApiException {
      return SyncOutcome.failed;
    } finally {
      if (locked) await db.unlock(_lock);
      _running = false;
    }
  }

  /// Returns true if more queued changes remain.
  Future<bool> _syncOneBatch() async {
    var batchId = await db.getValue('pending_batch_id');
    var maxSeq = int.tryParse(await db.getValue('pending_batch_max_seq') ?? '');
    if (batchId == null || maxSeq == null) {
      final head = await (db.select(db.syncQueue)
            ..orderBy([(t) => OrderingTerm.asc(t.seq)])
            ..limit(_batchSize))
          .get();
      batchId = repo.newId();
      maxSeq = head.isEmpty ? 0 : head.last.seq;
      await db.setValue('pending_batch_id', batchId);
      await db.setValue('pending_batch_max_seq', '$maxSeq');
    }
    final seqLimit = maxSeq;
    final items = await (db.select(db.syncQueue)
          ..where((t) => t.seq.isSmallerOrEqualValue(seqLimit))
          ..orderBy([(t) => OrderingTerm.asc(t.seq)]))
        .get();

    final changes = <String, List<Object?>>{'game_sessions': [], 'activity_log': [], 'memory_book': [], 'reminders': []};
    for (final item in items) {
      changes[item.entity]?.add(jsonDecode(item.payload));
    }
    final since = await db.getValue('last_server_time');
    final res = await api.sync({
      'batch_id': batchId,
      'device_id': await _deviceId(),
      'since': since,
      'changes': changes,
    });

    final reminders = res['reminders'] as List<dynamic>;
    await db.transaction(() async {
      await (db.delete(db.syncQueue)..where((t) => t.seq.isSmallerOrEqualValue(seqLimit))).go();
      await repo.applyServerMemories(res['memory_book'] as List<dynamic>);
      await repo.applyServerReminders(reminders);
      await repo.replaceRecommendations(res['recommendations'] as List<dynamic>);
      await db.setValue('last_server_time', res['server_time'] as String);
      await db.setValue('last_sync_at', DateTime.now().toUtc().toIso8601String());
      await db.removeValue('pending_batch_id');
      await db.removeValue('pending_batch_max_seq');
    });
    if (reminders.isNotEmpty) await onRemindersChanged?.call();

    final count = db.syncQueue.seq.count();
    final remaining = await (db.selectOnly(db.syncQueue)..addColumns([count])).getSingle();
    return (remaining.read(count) ?? 0) > 0;
  }

  Future<String> _deviceId() async {
    var id = await db.getValue('device_id');
    if (id == null) {
      id = repo.newId();
      await db.setValue('device_id', id);
    }
    return id;
  }

  /// Keeps memory-book photos on the phone so photo games work offline.
  Future<void> _cachePhotos() async {
    final userId = await db.getValue('user_id');
    if (userId == null) return;
    final dir = Directory(p.join((await getApplicationDocumentsDirectory()).path, 'photos'));
    await dir.create(recursive: true);
    final missing = (await repo.memories()).where((m) => m.photoKey != null && m.localPhotoPath == null);
    for (final m in missing.take(20)) {
      try {
        final url = await api.photoUrl(userId, m.id);
        final bytes = await api.download(url);
        final file = File(p.join(dir.path, '${m.id}${p.extension(m.photoKey!)}'));
        await file.writeAsBytes(bytes, flush: true);
        await repo.setLocalPhoto(m.id, file.path);
      } on SessionExpiredException {
        rethrow;
      } on ApiException {
        continue; // try again next sync
      }
    }
  }

  /// Games, NER cultural content and the published language pack, refreshed at most daily.
  Future<void> _refreshContentIfStale() async {
    final last = DateTime.tryParse(await db.getValue('content_refreshed_at') ?? '');
    if (last != null && DateTime.now().difference(last) < const Duration(days: 1)) return;
    final region = await db.getValue('region') ?? 'all';
    final language = await db.getValue('language') ?? 'en';
    await repo.replaceGames(await api.games());
    await repo.replaceCultural(await api.cultural(region, 'en'));
    try {
      final pack = await api.languagePack(language);
      await db.setValue('language_pack', jsonEncode(pack['document']));
    } on ApiException catch (e) {
      if (e.status != 404) rethrow;
      await db.removeValue('language_pack'); // not published (e.g. a preview pack): use the bundled one
    }
    await db.setValue('content_refreshed_at', DateTime.now().toIso8601String());
  }
}
