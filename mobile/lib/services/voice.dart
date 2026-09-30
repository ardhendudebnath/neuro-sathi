import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../l10n/language_pack.dart';

/// On-device voice: text-to-speech for every prompt and on-device speech
/// recognition, so voice works without internet and audio stays on the phone.
///
/// Each language pack lists candidate locales in order of preference (Assamese:
/// as-IN, then bn-IN, since the scripts are shared). The first one this phone
/// supports is used; if none is, [canSpeak] is false and the UI says so.
class Voice {
  final _tts = FlutterTts();
  final _stt = SpeechToText();
  bool _sttReady = false;
  String? _ttsLocale;
  List<String> _sttCandidates = const ['en-IN'];

  bool get canSpeak => _ttsLocale != null;

  Future<void> setLanguage(LanguagePack pack) async {
    _ttsLocale = null;
    for (final locale in pack.ttsLocales) {
      try {
        if (await _tts.isLanguageAvailable(locale) == true) {
          _ttsLocale = locale;
          break;
        }
      } on Object {
        continue; // engine not ready or locale unknown: try the next one
      }
    }
    if (_ttsLocale != null) {
      await _tts.setLanguage(_ttsLocale!);
      await _tts.setSpeechRate(0.42); // slower speech for elderly listeners
      await _tts.setPitch(1.0);
    }
    _sttCandidates = pack.sttLocales;
  }

  Future<void> speak(String text) async {
    if (_ttsLocale == null) return;
    await _tts.stop();
    await _tts.speak(text);
  }

  Future<void> stop() => _tts.stop();

  Future<bool> get canListen async {
    _sttReady = _sttReady || await _stt.initialize();
    return _sttReady;
  }

  static String _norm(String id) => id.replaceAll('_', '-').toLowerCase();

  /// The first of the pack's recognition locales this phone offers, or null for its default.
  Future<String?> _sttLocale() async {
    final available = {for (final l in await _stt.locales()) _norm(l.localeId): l.localeId};
    for (final candidate in _sttCandidates) {
      final match = available[_norm(candidate)];
      if (match != null) return match;
    }
    return null;
  }

  /// Listens once; calls [onResult] with the final recognised words.
  Future<void> listen(void Function(String words) onResult, {void Function()? onDone}) async {
    if (!await canListen) {
      onDone?.call();
      return;
    }
    await _tts.stop();
    const listenFor = Duration(seconds: 12);
    const pauseFor = Duration(seconds: 3);
    final locale = await _sttLocale();
    await _stt.listen(
      // With no matching locale, leave it unset so the recogniser uses its default language.
      listenOptions: locale == null
          ? SpeechListenOptions(listenFor: listenFor, pauseFor: pauseFor, onDevice: true, partialResults: false, cancelOnError: true)
          : SpeechListenOptions(
              localeId: locale,
              listenFor: listenFor,
              pauseFor: pauseFor,
              onDevice: true,
              partialResults: false,
              cancelOnError: true,
            ),
      onResult: (r) {
        if (r.finalResult) {
          onResult(r.recognizedWords);
          onDone?.call();
        }
      },
    );
  }

  Future<void> stopListening() => _stt.stop();
}
