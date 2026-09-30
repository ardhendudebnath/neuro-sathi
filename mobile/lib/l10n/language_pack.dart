import 'dart:convert';

// One language pack, parsed from content/language-packs/<code>.json (bundled
// into assets/lang/ at build time, or downloaded from the server when a newer
// version is published). The text helpers mirror backend/app/language_packs.py.

class TimePeriod {
  const TimePeriod(this.from, this.label);
  final int from; // hour of day (0-23) this day-part starts
  final String label;
}

class LanguagePack {
  LanguagePack({
    required this.code,
    required this.version,
    required this.englishName,
    required this.nativeName,
    required this.release,
    required this.reviewStatus,
    required this.ttsLocales,
    required this.sttLocales,
    required this.strings,
    required this.voicePrompts,
    required this.days,
    required this.timeFormat,
    required this.periods,
    required this.digits,
    required this.regions,
    required this.sathiAnswers,
    required this.sathiKeywords,
    required this.gameNames,
    required this.foods,
    required this.routine,
    required this.objects,
  });

  factory LanguagePack.fromJson(Map<String, dynamic> j) {
    final meta = j['meta'] as Map<String, dynamic>;
    final time = j['time'] as Map<String, dynamic>;
    final sathi = j['sathi'] as Map<String, dynamic>;
    final games = j['games'] as Map<String, dynamic>;
    Map<String, String> strMap(Object? m) => (m as Map<String, dynamic>).map((k, v) => MapEntry(k, v as String));
    List<String> strList(Object? l) => (l as List<dynamic>).cast<String>();
    return LanguagePack(
      code: j['language'] as String,
      version: j['version'] as int,
      englishName: meta['english_name'] as String,
      nativeName: meta['native_name'] as String,
      release: meta['release'] as String,
      reviewStatus: (meta['review'] as Map<String, dynamic>)['status'] as String,
      ttsLocales: strList(meta['tts_locales']),
      sttLocales: strList(meta['stt_locales']),
      strings: strMap(j['strings']),
      voicePrompts: strMap(j['voice_prompts']),
      days: strList(j['days']),
      timeFormat: time['format'] as String,
      periods: [
        for (final p in (time['periods'] as List<dynamic>).cast<Map<String, dynamic>>())
          TimePeriod(p['from'] as int, p['label'] as String),
      ],
      digits: (time['digits'] as String?) ?? 'latin',
      regions: strMap(j['regions']),
      sathiAnswers: strMap(sathi['answers']),
      sathiKeywords: (sathi['keywords'] as Map<String, dynamic>).map((k, v) => MapEntry(k, strList(v))),
      gameNames: strMap(games['names']),
      foods: strList(games['foods']),
      routine: strList(games['routine']),
      objects: [
        for (final o in (games['objects'] as List<dynamic>).cast<Map<String, dynamic>>())
          (title: o['title'] as String, note: o['note'] as String),
      ],
    );
  }

  static LanguagePack parse(String source) => LanguagePack.fromJson(jsonDecode(source) as Map<String, dynamic>);

  /// Used only before the bundled packs have loaded: every lookup falls back to its key.
  factory LanguagePack.empty() => LanguagePack(
        code: 'en',
        version: 0,
        englishName: 'English',
        nativeName: 'English',
        release: 'public',
        reviewStatus: 'source',
        ttsLocales: const ['en-IN'],
        sttLocales: const ['en-IN'],
        strings: const {},
        voicePrompts: const {},
        days: const ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'],
        timeFormat: '{h}:{mm} {period}',
        periods: const [TimePeriod(0, 'AM'), TimePeriod(12, 'PM')],
        digits: 'latin',
        regions: const {},
        sathiAnswers: const {},
        sathiKeywords: const {},
        gameNames: const {},
        foods: const [],
        routine: const [],
        objects: const [],
      );

  final String code;
  final int version;
  final String englishName;
  final String nativeName;
  final String release; // public | preview
  final String reviewStatus; // source | unreviewed | reviewed
  final List<String> ttsLocales;
  final List<String> sttLocales;
  final Map<String, String> strings;
  final Map<String, String> voicePrompts;
  final List<String> days;
  final String timeFormat;
  final List<TimePeriod> periods;
  final String digits; // latin | beng | deva
  final Map<String, String> regions;
  final Map<String, String> sathiAnswers;
  final Map<String, List<String>> sathiKeywords;
  final Map<String, String> gameNames;
  final List<String> foods;
  final List<String> routine;
  final List<({String title, String note})> objects;

  bool get isPublic => release == 'public';

  static const _digitSets = {'latin': '0123456789', 'beng': '০১২৩৪৫৬৭৮৯', 'deva': '०१२३४५६७८९'};

  String localizeDigits(String text) {
    final native = _digitSets[digits] ?? _digitSets['latin']!;
    if (native == _digitSets['latin']) return text;
    final out = StringBuffer();
    for (final unit in text.codeUnits) {
      out.write(unit >= 0x30 && unit <= 0x39 ? native[unit - 0x30] : String.fromCharCode(unit));
    }
    return out.toString();
  }

  /// 12-hour time with this language's day-part words and digits, e.g. "8:00 PM", "ৰাতি ৮:০০".
  String formatTime(int hour, int minute) {
    var label = periods.isEmpty ? '' : periods.last.label; // early hours belong to the night
    for (final p in periods) {
      if (hour >= p.from) label = p.label;
    }
    final h = (hour + 11) % 12 + 1;
    final text = timeFormat
        .replaceAll('{h}', '$h')
        .replaceAll('{mm}', minute.toString().padLeft(2, '0'))
        .replaceAll('{period}', label);
    return localizeDigits(text);
  }
}

// --- keyword matching for Sathi's offline intents --------------------------------------

// Precomposed nukta letters -> base + nukta, so either Unicode form of e.g. য় matches.
const _nukta = {
  'ড়': 'ড়', 'ঢ়': 'ঢ়', 'য়': 'য়',
  'ऩ': 'ऩ', 'ऱ': 'ऱ', 'ऴ': 'ऴ',
  'क़': 'क़', 'ख़': 'ख़', 'ग़': 'ग़', 'ज़': 'ज़',
  'ड़': 'ड़', 'ढ़': 'ढ़', 'फ़': 'फ़', 'य़': 'य़',
};

final _token = RegExp(r'''[^\s.,!?।॥"'()\-:;]+''');

String normalizeText(String text) {
  final out = StringBuffer();
  for (final rune in text.runes) {
    final ch = String.fromCharCode(rune);
    out.write(_nukta[ch] ?? ch);
  }
  return out.toString().toLowerCase();
}

List<String> tokenize(String text) => _token.allMatches(normalizeText(text)).map((m) => m.group(0)!).toList();

/// A keyword is a word or phrase; a trailing * lets the last word take suffixes.
bool keywordMatches(List<String> tokens, String keyword) {
  final prefix = keyword.endsWith('*');
  final parts = tokenize(prefix ? keyword.substring(0, keyword.length - 1) : keyword);
  if (parts.isEmpty) return false;
  for (var i = 0; i + parts.length <= tokens.length; i++) {
    var ok = true;
    for (var k = 0; k < parts.length - 1 && ok; k++) {
      ok = tokens[i + k] == parts[k];
    }
    if (!ok) continue;
    final last = tokens[i + parts.length - 1];
    if (last == parts.last || (prefix && last.startsWith(parts.last))) return true;
  }
  return false;
}

/// The language's own keywords plus English ones (people mix in words like "tablet").
bool hasIntent(String question, LanguagePack pack, LanguagePack english, String intent) {
  final keywords = [
    ...?pack.sathiKeywords[intent],
    if (pack.code != english.code) ...?english.sathiKeywords[intent],
  ];
  final tokens = tokenize(question);
  return keywords.any((k) => keywordMatches(tokens, k));
}
