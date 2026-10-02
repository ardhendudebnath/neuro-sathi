import 'dart:convert';

import 'package:drift/drift.dart' show Value; // drift also exports isNull/isNotNull, which clash with the test matchers
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_sathi/config.dart';
import 'package:neuro_sathi/data/api_client.dart';
import 'package:neuro_sathi/data/database.dart';
import 'package:neuro_sathi/data/repository.dart';
import 'package:neuro_sathi/data/sync_service.dart';
import 'package:neuro_sathi/services/reminders.dart';

import 'support.dart';

void main() {
  late AppDb db;
  late Repository repo;
  late FakeServer server;

  setUp(() {
    db = newTestDb();
    repo = Repository(db);
    server = FakeServer();
  });
  tearDown(() => db.close());

  SyncService service({Future<void> Function()? onRemindersChanged}) =>
      SyncService(db, repo, ApiClient(client: server.client, token: 'test-token'), onRemindersChanged: onRemindersChanged);

  Future<void> playOneGame() => repo.recordSession(
        gameSlug: 'odd_one_out',
        level: 1,
        startedAt: DateTime(2026, 9, 30, 9, 0),
        endedAt: DateTime(2026, 9, 30, 9, 5),
        trials: 8,
        correct: 7,
        errors: 1,
        repeatedErrors: 0,
        avgResponseMs: 2000,
        completed: true,
      );

  Future<int> queued() async => (await db.select(db.syncQueue).get()).length;

  group('shared lock', () {
    test('one holder at a time; released or abandoned locks can be taken', () async {
      const ttl = Duration(minutes: 10);
      expect(await db.tryLock('sync', ttl), isTrue);
      expect(await db.tryLock('sync', ttl), isFalse);
      await db.unlock('sync');
      expect(await db.tryLock('sync', ttl), isTrue);
      expect(await db.tryLock('sync', Duration.zero), isTrue, reason: 'a lock older than the ttl is abandoned');
    });
  });

  group('sync', () {
    test('uploads the queue, stores the server time and clears the queue', () async {
      await playOneGame();
      expect(await queued(), 1);

      expect(await service().syncNow(), SyncOutcome.synced);

      final changes = server.syncBodies.single['changes'] as Map<String, dynamic>;
      expect(changes['game_sessions'], hasLength(1));
      expect(await queued(), 0);
      expect(await db.getValue('last_server_time'), '2026-09-30T06:30:00Z');
      expect(await db.getValue('pending_batch_id'), isNull);
      expect(await db.getValue('lock_sync'), isNull, reason: 'the lock is released');
    });

    test('a failed batch is retried with the same batch id', () async {
      await playOneGame();
      server.failNextSyncs = 1;

      expect(await service().syncNow(), SyncOutcome.failed);
      final batchId = await db.getValue('pending_batch_id');
      expect(batchId, isNotNull);
      expect(await queued(), 1, reason: 'nothing is dropped until the server confirms');

      expect(await service().syncNow(), SyncOutcome.synced);
      expect(server.syncBodies.single['batch_id'], batchId);
      expect(await queued(), 0);
    });

    test('offline keeps the queue and releases the lock', () async {
      await playOneGame();
      server.offline = true;
      final sync = service();

      expect(await sync.syncNow(), SyncOutcome.offline);
      expect(await queued(), 1);
      expect(await db.tryLock('sync', AppConfig.syncLockTtl), isTrue);
      expect(sync.lastProblem, contains('no network'), reason: 'tester builds log why');
    });

    test('says why a sync did not finish, and forgets it once one does', () async {
      server.failNextSyncs = 1;
      final sync = service();

      expect(await sync.syncNow(), SyncOutcome.failed);
      expect(sync.describe(SyncOutcome.failed), allOf(contains('failed'), contains('500'), contains(sync.api.baseUrl)));

      expect(await sync.syncNow(), SyncOutcome.synced);
      expect(sync.lastProblem, isNull);
      expect(sync.describe(SyncOutcome.synced), endsWith(': synced'));
    });

    test('does not run while the other isolate holds the lock', () async {
      await playOneGame();
      expect(await db.tryLock('sync', AppConfig.syncLockTtl), isTrue); // e.g. the background worker

      expect(await service().syncNow(), SyncOutcome.busy);
      expect(server.syncBodies, isEmpty);
      expect(await queued(), 1);
    });

    test('reminders from the server are stored and the alarms rescheduled', () async {
      server.reminders = [
        {
          'id': 'r1',
          'user_id': 'u1',
          'kind': 'medication',
          'title': 'Metformin',
          'time_of_day': '08:00:00',
          'days_of_week': [0, 1, 2, 3, 4, 5, 6],
          'note': null,
          'active': true,
          'updated_at': '2026-09-30T06:00:00Z',
          'deleted': false,
        },
      ];
      var rescheduled = 0;

      expect(await service(onRemindersChanged: () async => rescheduled++).syncNow(), SyncOutcome.synced);

      expect(rescheduled, 1);
      expect((await repo.reminders()).single.title, 'Metformin');
    });

    test('no session: nothing is sent', () async {
      final sync = SyncService(db, repo, ApiClient(client: server.client));
      expect(await sync.syncNow(), SyncOutcome.sessionExpired);
      expect(server.calls, isEmpty);
    });

    test('an expired access token is renewed and the sync goes through', () async {
      await playOneGame();
      final api = ApiClient(
        client: server.client,
        token: 'old',
        accessExpiresAt: DateTime.now().subtract(const Duration(hours: 1)),
        refreshToken: 'refresh',
      );

      expect(await SyncService(db, repo, api).syncNow(), SyncOutcome.synced);

      expect(server.calls.first, '/auth/refresh');
      expect(await queued(), 0);
    });

    test('an ended session loses nothing: the queue waits for the next sign-in', () async {
      await playOneGame();
      server.refreshTokenValid = false;
      var ended = 0;
      final api = ApiClient(
        client: server.client,
        token: 'old',
        accessExpiresAt: DateTime.now().subtract(const Duration(hours: 1)),
        refreshToken: 'ended-on-the-server',
        onSessionExpired: () async => ended++,
      );

      expect(await SyncService(db, repo, api).syncNow(), SyncOutcome.sessionExpired);

      expect(ended, 1);
      expect(await queued(), 1, reason: 'the activity is still on the phone');
      expect(server.syncBodies, isEmpty);
      expect(await db.tryLock('sync', AppConfig.syncLockTtl), isTrue, reason: 'the lock is released');

      // After signing in again the same queue is uploaded.
      final again = ApiClient(client: server.client, token: 'test-token', refreshToken: 'new-session');
      expect(await db.unlock('sync').then((_) => SyncService(db, repo, again).syncNow()), SyncOutcome.synced);
      expect(await queued(), 0);
    });
  });

  group('missed reminders', () {
    final wednesdayNoon = DateTime(2026, 9, 30, 12, 0);

    Future<void> addReminder(
      String id,
      String time, {
      List<int> days = const [0, 1, 2, 3, 4, 5, 6],
      bool active = true,
      DateTime? updatedAt,
    }) =>
        db.into(db.reminders).insert(RemindersCompanion.insert(
              id: id,
              kind: 'medication',
              title: 'Metformin',
              timeOfDay: time,
              daysOfWeek: Value(jsonEncode(days)),
              active: Value(active),
              updatedAt: updatedAt ?? DateTime(2026, 9, 1),
            ));

    Future<List<ActivityRow>> missed() =>
        (db.select(db.activityLogs)..where((t) => t.kind.equals('reminder_missed'))).get();

    test('logs each missed occurrence once, dated when it was due', () async {
      await addReminder('r1', '08:00:00');

      expect(await logMissedReminders(repo, wednesdayNoon), 2, reason: "yesterday's and today's 8:00");
      expect(await logMissedReminders(repo, wednesdayNoon), 0, reason: 'never logged twice');

      final rows = await missed();
      expect(rows.map((r) => r.occurredAt).toSet(), {DateTime(2026, 9, 29, 8, 0), DateTime(2026, 9, 30, 8, 0)});
      expect(rows.map((r) => (jsonDecode(r.payload) as Map<String, dynamic>)['date']).toSet(), {'2026-09-29', '2026-09-30'});
      expect(await queued(), 2, reason: 'they are queued for the caregiver dashboard');
    });

    test('waits for the grace window', () async {
      await addReminder('r1', '11:00:00');
      expect(await logMissedReminders(repo, wednesdayNoon), 1, reason: "only yesterday's; today's 11:00 is still within 2 hours");
      expect((await missed()).single.occurredAt, DateTime(2026, 9, 29, 11, 0));
    });

    test('a reminder marked done is not missed', () async {
      await addReminder('r1', '08:00:00');
      await repo.logActivity(
        'reminder_done',
        {'reminder_id': 'r1', 'kind': 'medication', 'date': '2026-09-30'},
        DateTime(2026, 9, 30, 8, 5),
      );

      expect(await logMissedReminders(repo, wednesdayNoon), 1);
      expect((await missed()).single.occurredAt, DateTime(2026, 9, 29, 8, 0));
    });

    test('a late-evening reminder is counted after midnight', () async {
      await addReminder('r1', '23:00:00');
      final thursdayHalfPastOne = DateTime(2026, 10, 1, 1, 30);

      expect(await logMissedReminders(repo, thursdayHalfPastOne), 1);
      final row = (await missed()).single;
      expect(row.occurredAt, DateTime(2026, 9, 30, 23, 0));
      expect((jsonDecode(row.payload) as Map<String, dynamic>)['date'], '2026-09-30');
    });

    test('ignores times before the reminder existed, paused reminders and other weekdays', () async {
      await addReminder('new', '08:00:00', updatedAt: DateTime(2026, 9, 30, 9, 0)); // added at 9:00 today
      await addReminder('paused', '08:00:00', active: false);
      await addReminder('weekend', '08:00:00', days: [5, 6]);

      expect(await logMissedReminders(repo, wednesdayNoon), 0);
    });
  });
}
