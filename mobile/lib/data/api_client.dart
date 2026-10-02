import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../config.dart';

class ApiException implements Exception {
  ApiException(this.status, this.message, {this.retryAfter});
  final int status;
  final String message;
  final Duration? retryAfter;

  @override
  String toString() => 'ApiException($status): $message';
}

/// The server will not renew this session: the user has to verify their number
/// again. Nothing on the phone is deleted because of it.
class SessionExpiredException extends ApiException {
  SessionExpiredException() : super(401, 'Session expired');
}

/// No connection. Callers keep working offline and retry later.
class OfflineException implements Exception {
  OfflineException([this.cause]);

  /// The underlying error, such as "Connection refused", for tester builds' logs.
  final Object? cause;

  @override
  String toString() => cause == null ? 'Offline' : 'Offline ($cause)';
}

/// Talks to the backend and keeps the session alive.
///
/// The access token lasts about an hour. It is renewed with the refresh token
/// before a request when it is about to expire, and once more if the server
/// still refuses it. The session counts as expired only when the server rejects
/// the refresh token itself; being offline or a temporary server error never
/// ends it.
class ApiClient {
  ApiClient({
    http.Client? client,
    String? baseUrl,
    this.token,
    this.accessExpiresAt,
    this.refreshToken,
    this.onAccessRenewed,
    this.onSessionExpired,
  })  : _http = client ?? http.Client(),
        baseUrl = baseUrl ?? AppConfig.apiBaseUrl;

  final http.Client _http;

  /// The backend's address. Fixed at build time, except in tester builds.
  String baseUrl;

  String? token;
  DateTime? accessExpiresAt;
  String? refreshToken;

  /// Called with each renewed access token so it can be stored.
  Future<void> Function(String token, DateTime expiresAt)? onAccessRenewed;

  /// Called when the server has ended the session.
  Future<void> Function()? onSessionExpired;

  Future<void>? _renewing;

  static const _json = {'content-type': 'application/json'};
  static const _renewEarly = Duration(seconds: 30);

  bool get hasSession => token != null || refreshToken != null;

  void clearSession() {
    token = null;
    accessExpiresAt = null;
    refreshToken = null;
  }

  Uri _uri(String path, [Map<String, String>? query]) => Uri.parse('$baseUrl$path').replace(queryParameters: query);

  Map<String, String> get _headers => {..._json, if (token != null) 'authorization': 'Bearer $token'};

  Future<http.Response> _attempt(Future<http.Response> Function() call) async {
    try {
      return await call().timeout(const Duration(seconds: 20));
    } on SocketException catch (e) {
      throw OfflineException(e);
    } on TimeoutException catch (e) {
      throw OfflineException(e);
    } on http.ClientException catch (e) {
      throw OfflineException(e);
    }
  }

  dynamic _decode(http.Response res) {
    if (res.statusCode == 204) return null;
    final body = res.body.isEmpty ? null : jsonDecode(utf8.decode(res.bodyBytes));
    if (res.statusCode >= 400) {
      final retry = int.tryParse(res.headers['retry-after'] ?? '');
      final detail = body is Map && body['detail'] is String ? body['detail'] as String : 'Error ${res.statusCode}';
      throw ApiException(res.statusCode, detail, retryAfter: retry == null ? null : Duration(seconds: retry));
    }
    return body;
  }

  /// [call] is re-run after a renewal, so it must read [_headers] each time.
  Future<dynamic> _send(Future<http.Response> Function() call, {bool auth = true}) async {
    if (!auth) return _decode(await _attempt(call));
    await _renewIfDue();
    var res = await _attempt(call);
    if (res.statusCode == 401) {
      await _renew(); // throws SessionExpiredException if the session cannot be renewed
      res = await _attempt(call);
      if (res.statusCode == 401) throw await _expire();
    }
    return _decode(res);
  }

  Future<void> _renewIfDue() async {
    if (refreshToken == null) return; // nothing to renew with: the server decides
    final expires = accessExpiresAt;
    final stillValid = token != null && (expires == null || DateTime.now().isBefore(expires.subtract(_renewEarly)));
    if (!stillValid) await _renew();
  }

  /// One renewal at a time: requests made meanwhile wait for the same one.
  Future<void> _renew() => _renewing ??= _doRenew().whenComplete(() => _renewing = null);

  Future<void> _doRenew() async {
    final refresh = refreshToken;
    if (refresh == null) throw await _expire();
    final res = await _attempt(
      () => _http.post(_uri('/auth/refresh'), headers: _json, body: jsonEncode({'refresh_token': refresh})),
    );
    if (res.statusCode == 401) throw await _expire();
    // Anything else that is not a success (rate limit, server error) is temporary:
    // _decode throws an ApiException and the session is kept.
    final body = _decode(res) as Map<String, dynamic>;
    final access = body['access_token'] as String;
    final expiresAt = DateTime.now().add(Duration(seconds: body['expires_in'] as int));
    token = access;
    accessExpiresAt = expiresAt;
    await onAccessRenewed?.call(access, expiresAt);
  }

  Future<SessionExpiredException> _expire() async {
    final hadSession = hasSession;
    clearSession();
    if (hadSession) await onSessionExpired?.call();
    return SessionExpiredException();
  }

  Future<dynamic> get(String path, [Map<String, String>? query]) => _send(() => _http.get(_uri(path, query), headers: _headers));

  Future<dynamic> post(String path, [Object? body]) =>
      _send(() => _http.post(_uri(path), headers: _headers, body: jsonEncode(body ?? {})));

  Future<dynamic> patch(String path, Object body) => _send(() => _http.patch(_uri(path), headers: _headers, body: jsonEncode(body)));

  /// For the sign-in routes, which take no access token.
  Future<dynamic> _postOpen(String path, Object body) =>
      _send(() => _http.post(_uri(path), headers: _json, body: jsonEncode(body)), auth: false);

  // --- auth ---
  Future<Map<String, dynamic>> requestOtp(String phone) async =>
      (await _postOpen('/auth/otp', {'phone': phone})) as Map<String, dynamic>;

  /// Returns access_token, expires_in, refresh_token and user.
  Future<Map<String, dynamic>> verifyOtp(String phone, String code, {String? name}) async => (await _postOpen(
        '/auth/verify',
        {'phone': phone, 'code': code, if (name != null) 'name': name, 'role': 'user', 'device': 'phone'},
      )) as Map<String, dynamic>;

  /// Ends this session on the server (explicit sign-out).
  Future<void> logout() async {
    final refresh = refreshToken;
    if (refresh != null) await _postOpen('/auth/logout', {'refresh_token': refresh});
  }

  // --- account ---
  Future<Map<String, dynamic>> me() async => (await get('/me')) as Map<String, dynamic>;
  Future<void> updateMe(Map<String, Object?> fields) async => patch('/me', fields);
  Future<Map<String, dynamic>> profile() async => (await get('/me/profile')) as Map<String, dynamic>;
  Future<void> updateProfile(Map<String, Object?> fields) async => patch('/me/profile', fields);
  Future<Map<String, dynamic>> linkCode() async => (await post('/links/code')) as Map<String, dynamic>;

  // --- sync and content ---
  Future<Map<String, dynamic>> sync(Map<String, Object?> body) async => (await post('/sync', body)) as Map<String, dynamic>;
  Future<List<dynamic>> games() async => (await get('/content/games')) as List<dynamic>;
  Future<List<dynamic>> cultural(String region, String language) async =>
      (await get('/content/cultural', {'region': region, 'language': language})) as List<dynamic>;
  Future<Map<String, dynamic>> languagePack(String language) async =>
      (await get('/content/language-packs/$language')) as Map<String, dynamic>;

  Future<String> photoUrl(String userId, String entryId) async =>
      ((await get('/users/$userId/memory-book/$entryId/photo')) as Map<String, dynamic>)['url'] as String;

  Future<List<int>> download(String url) async {
    try {
      final res = await _http.get(Uri.parse(url)).timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) throw ApiException(res.statusCode, 'download failed');
      return res.bodyBytes;
    } on SocketException catch (e) {
      throw OfflineException(e);
    } on TimeoutException catch (e) {
      throw OfflineException(e);
    }
  }

  // --- Sathi ---
  Future<Map<String, dynamic>> sathiAsk(String question, String language) async =>
      (await post('/sathi/ask', {'question': question, 'language': language})) as Map<String, dynamic>;
}
