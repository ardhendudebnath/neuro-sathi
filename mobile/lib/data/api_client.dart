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

/// No connection. Callers keep working offline and retry later.
class OfflineException implements Exception {}

class ApiClient {
  ApiClient({http.Client? client, this.token}) : _http = client ?? http.Client();

  final http.Client _http;
  String? token;

  Uri _uri(String path, [Map<String, String>? query]) => Uri.parse('${AppConfig.apiBaseUrl}$path').replace(queryParameters: query);

  Map<String, String> get _headers => {
        'content-type': 'application/json',
        if (token != null) 'authorization': 'Bearer $token',
      };

  Future<dynamic> _send(Future<http.Response> Function() call) async {
    final http.Response res;
    try {
      res = await call().timeout(const Duration(seconds: 20));
    } on SocketException {
      throw OfflineException();
    } on TimeoutException {
      throw OfflineException();
    } on http.ClientException {
      throw OfflineException();
    }
    if (res.statusCode == 204) return null;
    final body = res.body.isEmpty ? null : jsonDecode(utf8.decode(res.bodyBytes));
    if (res.statusCode >= 400) {
      final retry = int.tryParse(res.headers['retry-after'] ?? '');
      final detail = body is Map && body['detail'] is String ? body['detail'] as String : 'Error ${res.statusCode}';
      throw ApiException(res.statusCode, detail, retryAfter: retry == null ? null : Duration(seconds: retry));
    }
    return body;
  }

  Future<dynamic> get(String path, [Map<String, String>? query]) => _send(() => _http.get(_uri(path, query), headers: _headers));

  Future<dynamic> post(String path, [Object? body]) =>
      _send(() => _http.post(_uri(path), headers: _headers, body: jsonEncode(body ?? {})));

  Future<dynamic> patch(String path, Object body) => _send(() => _http.patch(_uri(path), headers: _headers, body: jsonEncode(body)));

  // --- auth ---
  Future<Map<String, dynamic>> requestOtp(String phone) async => (await post('/auth/otp', {'phone': phone})) as Map<String, dynamic>;

  Future<Map<String, dynamic>> verifyOtp(String phone, String code, {String? name}) async =>
      (await post('/auth/verify', {'phone': phone, 'code': code, if (name != null) 'name': name, 'role': 'user'})) as Map<String, dynamic>;

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
    } on SocketException {
      throw OfflineException();
    } on TimeoutException {
      throw OfflineException();
    }
  }

  // --- Sathi ---
  Future<Map<String, dynamic>> sathiAsk(String question, String language) async =>
      (await post('/sathi/ask', {'question': question, 'language': language})) as Map<String, dynamic>;
}
