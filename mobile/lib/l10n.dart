import 'l10n/language_pack.dart';

export 'l10n/catalog.dart';
export 'l10n/language_pack.dart';

/// UI text for one language, falling back to English for anything missing.
/// All wording lives in the language packs (content/language-packs).
class Strings {
  Strings(this.pack, [LanguagePack? english]) : english = english ?? pack;

  final LanguagePack pack;
  final LanguagePack english;

  String get language => pack.code;

  String t(String key, [Map<String, Object> args = const {}]) => _fill(pack.strings[key] ?? english.strings[key] ?? key, args);

  /// Text meant to be spoken, e.g. reminder announcements.
  String voice(String key, [Map<String, Object> args = const {}]) =>
      _fill(pack.voicePrompts[key] ?? english.voicePrompts[key] ?? '', args);

  String _fill(String template, Map<String, Object> args) {
    var s = template;
    args.forEach((k, v) => s = s.replaceAll('{$k}', v is num ? pack.localizeDigits('$v') : '$v'));
    return s;
  }

  String greeting(DateTime now) {
    if (now.hour < 12) return t('greeting_morning');
    if (now.hour < 17) return t('greeting_afternoon');
    return t('greeting_evening');
  }

  /// [weekday] is 0 = Monday, matching the backend.
  String dayName(int weekday) => (pack.days.length == 7 ? pack.days : english.days)[weekday];

  String formatTime(int hour, int minute) => pack.formatTime(hour, minute);

  String region(String code) => pack.regions[code] ?? english.regions[code] ?? code;

  /// English uses the name from the server (admins can rename games); other
  /// languages use the translated name from their pack.
  String gameName(String slug, String serverName) => pack.code == 'en' ? serverName : pack.gameNames[slug] ?? serverName;
}
