import 'dart:convert';
import 'dart:ffi';

import 'package:drift/drift.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:neuro_sathi/data/database.dart';
import 'package:sqlite3/open.dart';

/// An in-memory database for tests, using the machine's SQLite library.
AppDb newTestDb() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  open.overrideFor(OperatingSystem.linux, () {
    try {
      return DynamicLibrary.open('libsqlite3.so');
    } on ArgumentError {
      return DynamicLibrary.open('libsqlite3.so.0'); // runtime package only, no -dev symlink
    }
  });
  return AppDb.forTesting();
}

/// Stands in for the backend: records /sync requests and can fail or go offline.
class FakeServer {
  final syncBodies = <Map<String, dynamic>>[];
  List<Map<String, Object?>> reminders = [];
  int failNextSyncs = 0;
  bool offline = false;

  http.Client get client => MockClient((request) async {
        if (offline) throw http.ClientException('no network');
        final path = request.url.path;
        if (path == '/sync') {
          if (failNextSyncs > 0) {
            failNextSyncs--;
            return http.Response('{"detail":"temporarily broken"}', 500);
          }
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          syncBodies.add(body);
          return http.Response(
            jsonEncode({
              'batch_id': body['batch_id'],
              'applied': 1,
              'rejected': <Object>[],
              'server_time': '2026-09-30T06:30:00Z',
              'memory_book': <Object>[],
              'reminders': reminders,
              'recommendations': <Object>[],
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        if (path == '/content/games' || path == '/content/cultural') return http.Response('[]', 200);
        return http.Response('{"detail":"Not found"}', 404);
      });
}
