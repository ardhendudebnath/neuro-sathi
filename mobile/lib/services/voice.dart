import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// On-device voice: text-to-speech for every prompt and on-device speech
/// recognition, so voice works without internet and audio stays on the phone.
class Voice {
  final _tts = FlutterTts();
  final _stt = SpeechToText();
  bool _sttReady = false;
  String _language = 'en';

  static const _locales = {'en': 'en-IN', 'hi': 'hi-IN', 'bn': 'bn-IN', 'as': 'as-IN'};

  Future<void> setLanguage(String language) async {
    _language = language;
    await _tts.setLanguage(_locales[language] ?? 'en-IN');
    await _tts.setSpeechRate(0.42); // slower speech for elderly listeners
    await _tts.setPitch(1.0);
  }

  Future<void> speak(String text) async {
    await _tts.stop();
    await _tts.speak(text);
  }

  Future<void> stop() => _tts.stop();

  Future<bool> get canListen async {
    _sttReady = _sttReady || await _stt.initialize();
    return _sttReady;
  }

  /// Listens once; calls [onResult] with the final recognised words.
  Future<void> listen(void Function(String words) onResult, {void Function()? onDone}) async {
    if (!await canListen) {
      onDone?.call();
      return;
    }
    await _tts.stop();
    await _stt.listen(
      listenOptions: SpeechListenOptions(
        localeId: _locales[_language] ?? 'en-IN',
        listenFor: const Duration(seconds: 12),
        pauseFor: const Duration(seconds: 3),
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
