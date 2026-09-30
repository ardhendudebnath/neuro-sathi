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

/// Stands in for the backend: checks access tokens, renews sessions, records
/// /sync requests, and can fail or go offline.
class FakeServer {
  final calls = <String>[]; // every request path, in order
  final syncBodies = <Map<String, dynamic>>[];
  List<Map<String, Object?>> reminders = [];
  int failNextSyncs = 0;
  bool offline = false;

  /// Access tokens the server accepts. Each renewal adds 'access-1', 'access-2', ...
  final validAccess = <String>{'test-token'};
  bool refreshTokenValid = true;
  int? refreshFailsWith; // e.g. 500 for a temporary server error
  int renewals = 0;

  http.Response _ok(Object body) =>
      http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json; charset=utf-8'});

  http.Client get client => MockClient((request) async {
        if (offline) throw http.ClientException('no network');
        final path = request.url.path;
        calls.add(path);

        if (path == '/auth/refresh') {
          if (refreshFailsWith != null) return http.Response('{"detail":"try later"}', refreshFailsWith!);
          if (!refreshTokenValid) return http.Response('{"detail":"Session expired. Please sign in again."}', 401);
          renewals++;
          final token = 'access-$renewals';
          validAccess.add(token);
          return _ok({'access_token': token, 'token_type': 'bearer', 'expires_in': 3600, 'refresh_token': null, 'user': {'id': 'u1'}});
        }
        if (path == '/auth/logout') return http.Response('', 204);
        if (path.startsWith('/auth/')) return http.Response('{"detail":"Not found"}', 404); // sign-in routes take no token

        final bearer = (request.headers['authorization'] ?? '').replaceFirst('Bearer ', '');
        if (!validAccess.contains(bearer)) return http.Response('{"detail":"Invalid token"}', 401);

        if (path == '/me') return _ok({'id': 'u1'});
        if (path == '/sync') {
          if (failNextSyncs > 0) {
            failNextSyncs--;
            return http.Response('{"detail":"temporarily broken"}', 500);
          }
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          syncBodies.add(body);
          return _ok({
            'batch_id': body['batch_id'],
            'applied': 1,
            'rejected': <Object>[],
            'server_time': '2026-09-30T06:30:00Z',
            'memory_book': <Object>[],
            'reminders': reminders,
            'recommendations': <Object>[],
          });
        }
        if (path == '/content/games' || path == '/content/cultural') return http.Response('[]', 200);
        return http.Response('{"detail":"Not found"}', 404);
      });
}
