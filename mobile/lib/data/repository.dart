import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'database.dart';

const _uuid = Uuid();

String iso(DateTime d) => d.toUtc().toIso8601String();

/// All local reads and writes. Every write that the server must know about is
/// stored and queued for /sync in the same transaction.
class Repository {
  Repository(this.db);
  final AppDb db;

  String newId() => _uuid.v4();

  Future<void> _enqueue(String entity, String id, Map<String, Object?> payload) => db.into(db.syncQueue).insert(
        SyncQueueCompanion.insert(entity: entity, recordId: id, payload: jsonEncode(payload), queuedAt: DateTime.now()),
      );

  // --- memory book ---

  Stream<List<MemoryEntry>> watchMemories() => (db.select(db.memoryEntries)
        ..where((t) => t.deleted.equals(false))
        ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)]))
      .watch();

  Future<List<MemoryEntry>> memories() => (db.select(db.memoryEntries)..where((t) => t.deleted.equals(false))).get();

  Future<void> setLocalPhoto(String id, String path) =>
      (db.update(db.memoryEntries)..where((t) => t.id.equals(id))).write(MemoryEntriesCompanion(localPhotoPath: Value(path)));

  // --- reminders ---

  Stream<List<ReminderRow>> watchReminders() => (db.select(db.reminders)
        ..where((t) => t.deleted.equals(false))
        ..orderBy([(t) => OrderingTerm.asc(t.timeOfDay)]))
      .watch();

  Future<List<ReminderRow>> reminders() => (db.select(db.reminders)..where((t) => t.deleted.equals(false))).get();

  // --- activity ---

  Future<void> logActivity(String kind, [Map<String, Object?> payload = const {}]) async {
    final id = newId();
    final now = DateTime.now();
    await db.transaction(() async {
      await db.into(db.activityLogs).insert(
            ActivityLogsCompanion.insert(id: id, kind: kind, payload: Value(jsonEncode(payload)), occurredAt: now),
          );
      await _enqueue('activity_log', id, {
        'id': id,
        'kind': kind,
        'payload': payload,
        'occurred_at': iso(now),
        'updated_at': iso(now),
      });
    });
  }

  Future<bool> hasActivity(String kind, bool Function(Map<String, dynamic> payload) match, DateTime since) async {
    final rows = await (db.select(db.activityLogs)
          ..where((t) => t.kind.equals(kind) & t.occurredAt.isBiggerOrEqualValue(since)))
        .get();
    return rows.any((r) => match(jsonDecode(r.payload) as Map<String, dynamic>));
  }

  Future<void> recordSession({
    required String gameSlug,
    required int level,
    required DateTime startedAt,
    required DateTime endedAt,
    required int trials,
    required int correct,
    required int errors,
    required int repeatedErrors,
    required double? avgResponseMs,
    required bool completed,
  }) async {
    final id = newId();
    await db.transaction(() async {
      await db.into(db.gameSessions).insert(GameSessionsCompanion.insert(
            id: id,
            gameSlug: gameSlug,
            level: level,
            startedAt: startedAt,
            endedAt: Value(endedAt),
            trials: trials,
            correct: correct,
            errors: errors,
            repeatedErrors: Value(repeatedErrors),
            avgResponseMs: Value(avgResponseMs),
            completed: completed,
          ));
      await _enqueue('game_sessions', id, {
        'id': id,
        'game_slug': gameSlug,
        'level': level,
        'started_at': iso(startedAt),
        'ended_at': iso(endedAt),
        'trials': trials,
        'correct': correct,
        'errors': errors,
        'repeated_errors': repeatedErrors,
        'avg_response_ms': avgResponseMs,
        'completed': completed,
        'updated_at': iso(endedAt),
      });
    });
  }

  Future<List<GameSessionRow>> sessionsFor(String slug, {int limit = 5}) => (db.select(db.gameSessions)
        ..where((t) => t.gameSlug.equals(slug))
        ..orderBy([(t) => OrderingTerm.desc(t.startedAt)])
        ..limit(limit))
      .get();

  // --- content and recommendations ---

  Future<List<GameRow>> games() => db.select(db.games).get();

  Future<List<RecommendationRow>> recommendations() =>
      (db.select(db.recommendations)..orderBy([(t) => OrderingTerm.asc(t.rank)])).get();

  Future<List<CulturalItem>> cultural({String? category}) {
    final q = db.select(db.culturalItems);
    if (category != null) q.where((t) => t.category.equals(category));
    return q.get();
  }

  Future<void> replaceGames(List<dynamic> rows) => db.transaction(() async {
        await db.delete(db.games).go();
        for (final r in rows.cast<Map<String, dynamic>>()) {
          await db.into(db.games).insert(GamesCompanion.insert(
                slug: r['slug'] as String,
                name: r['name'] as String,
                domain: r['domain'] as String,
                minLevel: r['min_level'] as int,
                maxLevel: r['max_level'] as int,
                config: Value(jsonEncode(r['config'])),
              ));
        }
      });

  Future<void> replaceCultural(List<dynamic> rows) => db.transaction(() async {
        await db.delete(db.culturalItems).go();
        for (final r in rows.cast<Map<String, dynamic>>()) {
          await db.into(db.culturalItems).insert(CulturalItemsCompanion.insert(
                id: r['id'] as String,
                region: r['region'] as String,
                category: r['category'] as String,
                title: r['title'] as String,
                data: Value(jsonEncode(r['data'])),
              ));
        }
      });

  // --- applying server data from /sync ---

  Future<void> applyServerMemories(List<dynamic> rows) async {
    for (final r in rows.cast<Map<String, dynamic>>()) {
      await db.into(db.memoryEntries).insertOnConflictUpdate(MemoryEntriesCompanion.insert(
            id: r['id'] as String,
            kind: Value(r['kind'] as String),
            title: r['title'] as String,
            personName: Value(r['person_name'] as String?),
            relationship: Value(r['relationship'] as String?),
            eventDate: Value(r['event_date'] as String?),
            place: Value(r['place'] as String?),
            description: Value(r['description'] as String?),
            photoKey: Value(r['photo_key'] as String?),
            updatedAt: DateTime.parse(r['updated_at'] as String),
            deleted: Value(r['deleted'] as bool),
          ));
    }
  }

  Future<void> applyServerReminders(List<dynamic> rows) async {
    for (final r in rows.cast<Map<String, dynamic>>()) {
      await db.into(db.reminders).insertOnConflictUpdate(RemindersCompanion.insert(
            id: r['id'] as String,
            kind: r['kind'] as String,
            title: r['title'] as String,
            timeOfDay: r['time_of_day'] as String,
            daysOfWeek: Value(jsonEncode(r['days_of_week'])),
            note: Value(r['note'] as String?),
            active: Value(r['active'] as bool),
            updatedAt: DateTime.parse(r['updated_at'] as String),
            deleted: Value(r['deleted'] as bool),
          ));
    }
  }

  Future<void> replaceRecommendations(List<dynamic> rows) async {
    await db.delete(db.recommendations).go();
    for (final r in rows.cast<Map<String, dynamic>>()) {
      await db.into(db.recommendations).insert(RecommendationsCompanion.insert(
            gameSlug: r['game_slug'] as String,
            level: r['level'] as int,
            rank: r['rank'] as int,
            reason: r['reason'] as String,
          ));
    }
  }
}

List<int> daysOf(ReminderRow r) => (jsonDecode(r.daysOfWeek) as List<dynamic>).cast<int>();
