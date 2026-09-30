import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_sathi/data/api_client.dart';

import 'support.dart';

void main() {
  late FakeServer server;
  setUp(() => server = FakeServer());

  final anHourAgo = DateTime.now().subtract(const Duration(hours: 1));
  final inAnHour = DateTime.now().add(const Duration(hours: 1));

  test('renews first when the access token has expired', () async {
    String? stored;
    final api = ApiClient(
      client: server.client,
      token: 'old',
      accessExpiresAt: anHourAgo,
      refreshToken: 'refresh',
      onAccessRenewed: (token, _) async => stored = token,
    );

    expect(await api.me(), {'id': 'u1'});

    expect(server.calls, ['/auth/refresh', '/me']);
    expect(api.token, 'access-1');
    expect(stored, 'access-1', reason: 'the renewed token is handed over to be stored');
    expect(api.accessExpiresAt!.isAfter(DateTime.now().add(const Duration(minutes: 55))), isTrue);
  });

  test('renews and retries when the server refuses a token that looked valid', () async {
    final api = ApiClient(client: server.client, token: 'revoked-early', accessExpiresAt: inAnHour, refreshToken: 'refresh');

    expect(await api.me(), {'id': 'u1'});

    expect(server.calls, ['/me', '/auth/refresh', '/me']);
  });

  test('does not renew while the access token is still good', () async {
    final api = ApiClient(client: server.client, token: 'test-token', accessExpiresAt: inAnHour, refreshToken: 'refresh');
    await api.me();
    expect(server.calls, ['/me']);
  });

  test('requests made at the same time share one renewal', () async {
    final api = ApiClient(client: server.client, token: 'old', accessExpiresAt: anHourAgo, refreshToken: 'refresh');
    await Future.wait([api.me(), api.me(), api.me()]);
    expect(server.renewals, 1);
  });

  test('a refused refresh token ends the session, once', () async {
    server.refreshTokenValid = false;
    var ended = 0;
    final api = ApiClient(
      client: server.client,
      token: 'old',
      accessExpiresAt: anHourAgo,
      refreshToken: 'refresh',
      onSessionExpired: () async => ended++,
    );

    await expectLater(api.me(), throwsA(isA<SessionExpiredException>()));
    await expectLater(api.me(), throwsA(isA<SessionExpiredException>()));

    expect(ended, 1);
    expect(api.hasSession, isFalse);
  });

  test('a temporary server error during renewal does not end the session', () async {
    server.refreshFailsWith = 500;
    var ended = 0;
    final api = ApiClient(
      client: server.client,
      token: 'old',
      accessExpiresAt: anHourAgo,
      refreshToken: 'refresh',
      onSessionExpired: () async => ended++,
    );

    await expectLater(
      api.me(),
      throwsA(isA<ApiException>().having((e) => e.status, 'status', 500).having((e) => e is SessionExpiredException, 'expired', isFalse)),
    );
    expect(ended, 0);
    expect(api.refreshToken, 'refresh');

    server.refreshFailsWith = null; // the server recovers: the same session carries on
    expect(await api.me(), {'id': 'u1'});
  });

  test('being offline during renewal does not end the session', () async {
    server.offline = true;
    final api = ApiClient(client: server.client, token: 'old', accessExpiresAt: anHourAgo, refreshToken: 'refresh');

    await expectLater(api.me(), throwsA(isA<OfflineException>()));
    expect(api.refreshToken, 'refresh');
  });

  test('an older session with no refresh token ends when its access token is refused', () async {
    final api = ApiClient(client: server.client, token: 'expired-seven-day-token');
    await expectLater(api.me(), throwsA(isA<SessionExpiredException>()));
    expect(server.calls, ['/me'], reason: 'there is nothing to renew with');
  });

  test('sign-in calls carry no access token and are never retried through renewal', () async {
    final api = ApiClient(client: server.client, token: 'old', accessExpiresAt: anHourAgo, refreshToken: 'refresh');
    // The fake server has no /auth/otp route: a plain 404 comes back, with no renewal attempt.
    await expectLater(api.requestOtp('9876543210'), throwsA(isA<ApiException>().having((e) => e.status, 'status', 404)));
    expect(server.calls, ['/auth/otp']);
  });

  test('logout sends the refresh token', () async {
    final api = ApiClient(client: server.client, token: 'test-token', accessExpiresAt: inAnHour, refreshToken: 'refresh');
    await api.logout();
    expect(server.calls, ['/auth/logout']);
  });
}
