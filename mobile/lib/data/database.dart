import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlcipher_flutter_libs/sqlcipher_flutter_libs.dart';
import 'package:sqlite3/open.dart';

import 'secure_store.dart';

part 'database.g.dart';

// Local, encrypted (SQLCipher) store. Every action is written here first so
// the app never waits for the network; SyncQueue holds changes to upload.

@DataClassName('MemoryEntry')
class MemoryEntries extends Table {
  TextColumn get id => text()();
  TextColumn get kind => text().withDefault(const Constant('person'))();
  TextColumn get title => text()();
  TextColumn get personName => text().nullable()();
  TextColumn get relationship => text().nullable()();
  TextColumn get eventDate => text().nullable()();
  TextColumn get place => text().nullable()();
  TextColumn get description => text().nullable()();
  TextColumn get photoKey => text().nullable()();
  TextColumn get localPhotoPath => text().nullable()();
  DateTimeColumn get updatedAt => dateTime()();
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('ReminderRow')
class Reminders extends Table {
  TextColumn get id => text()();
  TextColumn get kind => text()();
  TextColumn get title => text()();
  TextColumn get timeOfDay => text()(); // HH:MM:SS, local (IST)
  TextColumn get daysOfWeek => text().withDefault(const Constant('[0,1,2,3,4,5,6]'))(); // JSON, Mon = 0
  TextColumn get note => text().nullable()();
  BoolColumn get active => boolean().withDefault(const Constant(true))();
  DateTimeColumn get updatedAt => dateTime()();
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('GameSessionRow')
class GameSessions extends Table {
  TextColumn get id => text()();
  TextColumn get gameSlug => text()();
  IntColumn get level => integer()();
  DateTimeColumn get startedAt => dateTime()();
  DateTimeColumn get endedAt => dateTime().nullable()();
  IntColumn get trials => integer()();
  IntColumn get correct => integer()();
  IntColumn get errors => integer()();
  IntColumn get repeatedErrors => integer().withDefault(const Constant(0))();
  RealColumn get avgResponseMs => real().nullable()();
  BoolColumn get completed => boolean()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('ActivityRow')
class ActivityLogs extends Table {
  TextColumn get id => text()();
  TextColumn get kind => text()();
  TextColumn get payload => text().withDefault(const Constant('{}'))();
  DateTimeColumn get occurredAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('RecommendationRow')
class Recommendations extends Table {
  TextColumn get gameSlug => text()();
  IntColumn get level => integer()();
  IntColumn get rank => integer()();
  TextColumn get reason => text()();

  @override
  Set<Column> get primaryKey => {gameSlug};
}

@DataClassName('GameRow')
class Games extends Table {
  TextColumn get slug => text()();
  TextColumn get name => text()();
  TextColumn get domain => text()();
  IntColumn get minLevel => integer()();
  IntColumn get maxLevel => integer()();
  TextColumn get config => text().withDefault(const Constant('{}'))();

  @override
  Set<Column> get primaryKey => {slug};
}

@DataClassName('CulturalItem')
class CulturalItems extends Table {
  TextColumn get id => text()();
  TextColumn get region => text()();
  TextColumn get category => text()();
  TextColumn get title => text()();
  TextColumn get data => text().withDefault(const Constant('{}'))();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('QueuedChange')
class SyncQueue extends Table {
  IntColumn get seq => integer().autoIncrement()();
  TextColumn get entity => text()(); // game_sessions | activity_log | memory_book | reminders
  TextColumn get recordId => text()();
  TextColumn get payload => text()(); // JSON body for /sync
  DateTimeColumn get queuedAt => dateTime()();
}

@DataClassName('KeyValue')
class KeyValues extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

@DriftDatabase(
  tables: [MemoryEntries, Reminders, GameSessions, ActivityLogs, Recommendations, Games, CulturalItems, SyncQueue, KeyValues],
)
class AppDb extends _$AppDb {
  AppDb(super.e);

  /// In-memory, unencrypted database for tests.
  AppDb.forTesting() : super(NativeDatabase.memory());

  @override
  int get schemaVersion => 1;

  Future<String?> getValue(String key) async =>
      (await (select(keyValues)..where((t) => t.key.equals(key))).getSingleOrNull())?.value;

  Future<void> setValue(String key, String value) =>
      into(keyValues).insertOnConflictUpdate(KeyValuesCompanion.insert(key: key, value: value));

  Future<void> removeValue(String key) => (delete(keyValues)..where((t) => t.key.equals(key))).go();

  /// A lock shared by every connection to this database: the app and the
  /// background sync worker run in different isolates. Returns false if it is
  /// already held; a lock older than [ttl] is treated as abandoned (its holder
  /// was killed) and taken over.
  Future<bool> tryLock(String name, Duration ttl) async {
    try {
      return await transaction(() async {
        final key = 'lock_$name';
        final now = DateTime.now().millisecondsSinceEpoch;
        final heldSince = int.tryParse(await getValue(key) ?? '');
        if (heldSince != null && now - heldSince < ttl.inMilliseconds) return false;
        await setValue(key, '$now');
        return true;
      });
    } on Object {
      return false; // the other connection is writing right now: treat the lock as taken
    }
  }

  Future<void> unlock(String name) => removeValue('lock_$name');

  /// Wipes everything (sign-out): the phone keeps only the signed-in user's data.
  Future<void> wipe() => transaction(() async {
        for (final table in allTables) {
          await delete(table).go();
        }
      });
}

void _openCipher() {
  open.overrideFor(OperatingSystem.android, openCipherOnAndroid);
}

/// Opens the SQLCipher-encrypted database. The 256-bit key is generated once
/// and kept in the Android Keystore-backed secure storage.
Future<AppDb> openEncryptedDb() async {
  await applyWorkaroundToOpenSqlCipherOnOldAndroidVersions();
  _openCipher();
  final store = SecureStore();
  var key = await store.dbKey();
  if (key == null) {
    final rnd = Random.secure();
    key = List.generate(32, (_) => rnd.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
    await store.setDbKey(key);
  }
  final dir = await getApplicationDocumentsDirectory();
  final file = File(p.join(dir.path, 'neuro_sathi.db'));
  final hexKey = key;
  return AppDb(
    NativeDatabase.createInBackground(
      file,
      isolateSetup: _openCipher,
      setup: (db) {
        final cipher = db.select('PRAGMA cipher_version');
        if (cipher.isEmpty) {
          throw StateError('SQLCipher is not available; refusing to store data unencrypted.');
        }
        db.execute("PRAGMA key = \"x'$hexKey'\";");
        // The app and the background sync worker each hold a connection:
        // write-ahead logging lets one read while the other writes, and a
        // writer waits briefly for the other instead of failing.
        db.execute('PRAGMA journal_mode = WAL;');
        db.execute('PRAGMA busy_timeout = 5000;');
      },
    ),
  );
}
