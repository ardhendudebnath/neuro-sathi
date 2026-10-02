import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:neuro_sathi/config.dart';
import 'package:neuro_sathi/data/api_client.dart';
import 'package:neuro_sathi/l10n.dart';
import 'package:neuro_sathi/widgets/tester_tools.dart';

import 'packs.dart';

void main() {
  group('server address typed by a tester', () {
    test('accepts what people actually type', () {
      expect(AppConfig.normalizeServerUrl('192.168.1.5:8000'), 'http://192.168.1.5:8000');
      expect(AppConfig.normalizeServerUrl('  http://192.168.1.5:8000/ '), 'http://192.168.1.5:8000');
      expect(AppConfig.normalizeServerUrl('https://staging.example.org/api//'), 'https://staging.example.org/api');
    });

    test('rejects what cannot work', () {
      expect(AppConfig.normalizeServerUrl(''), isNull);
      expect(AppConfig.normalizeServerUrl('http://'), isNull);
      expect(AppConfig.normalizeServerUrl('ftp://192.168.1.5'), isNull);
    });
  });

  test('the API client talks to the server it is given, and can be repointed', () async {
    final urls = <Uri>[];
    final client = MockClient((request) async {
      urls.add(request.url);
      return http.Response('{"id":"u1"}', 200, headers: {'content-type': 'application/json'});
    });
    final api = ApiClient(client: client, baseUrl: 'http://192.168.1.5:8000', token: 't');

    await api.me();
    api.baseUrl = 'http://10.0.0.7:8000';
    await api.me();

    expect(urls.map((u) => '${u.host}:${u.port}${u.path}'), ['192.168.1.5:8000/me', '10.0.0.7:8000/me']);
  });

  group('sign-in when the server cannot be reached', () {
    final en = Strings(loadPack('en'));

    test('users are asked to connect once', () {
      expect(unreachableMessage(en, 'https://api.example.org', tester: false), en.t('error_no_internet'));
    });

    test('testers are told which address failed', () {
      final message = unreachableMessage(en, 'http://192.168.1.5:8000', tester: true);
      expect(message, contains('http://192.168.1.5:8000'));
      expect(message, isNot(contains('emulator')));
    });

    test("the emulator's address, which a fresh install starts with, is called out", () {
      expect(unreachableMessage(en, 'http://10.0.2.2:8000', tester: true), contains('only works in the Android emulator'));
    });
  });

  test('normal builds use the address fixed at build time', () {
    expect(ApiClient().baseUrl, AppConfig.apiBaseUrl);
    expect(AppConfig.testerBuild, isFalse, reason: 'tests run without TESTER_BUILD');
  });
}
