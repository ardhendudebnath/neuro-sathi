// Sathi's offline answers. Mirrors backend app/services/sathi_engine.py so the
// same questions work with no internet: next medicine, the date and time,
// "who is ...", and today's plan. Wording and the words Sathi listens for come
// from the user's language pack.

import '../l10n/language_pack.dart';

class LocalReminder {
  const LocalReminder(this.title, this.kind, this.hour, this.minute, this.days, {this.active = true});
  final String title;
  final String kind;
  final int hour;
  final int minute;
  final List<int> days; // 0 = Monday
  final bool active;

  int get minutes => hour * 60 + minute;
}

class LocalPerson {
  const LocalPerson({required this.title, this.name, this.relationship, this.description});
  final String title;
  final String? name;
  final String? relationship;
  final String? description;
}

String _answer(LanguagePack pack, LanguagePack english, String key, [Map<String, String> args = const {}]) {
  var s = pack.sathiAnswers[key] ?? english.sathiAnswers[key] ?? '';
  args.forEach((k, v) => s = s.replaceAll('{$k}', v));
  return s;
}

String fallbackAnswer(LanguagePack pack, LanguagePack english) => _answer(pack, english, 'fallback');

/// English 12-hour time ("8:00 PM"); use LanguagePack.formatTime for other languages.
String formatTime(int hour, int minute) {
  final h = (hour + 11) % 12 + 1;
  return '$h:${minute.toString().padLeft(2, '0')} ${hour >= 12 ? 'PM' : 'AM'}';
}

Set<String> _words(String text) => tokenize(text).where((w) => w.runes.length > 2).toSet();

LocalPerson? findPerson(String question, List<LocalPerson> people) {
  final q = _words(question);
  LocalPerson? best;
  var bestScore = 0;
  for (final p in people) {
    final fields = _words([p.name, p.relationship, p.title].whereType<String>().join(' '));
    final score = q.intersection(fields).length;
    if (score > bestScore) {
      best = p;
      bestScore = score;
    }
  }
  return best;
}

/// Returns an answer, or null if the question needs the online companion.
String? answerLocally(
  String question,
  LanguagePack pack,
  LanguagePack english,
  List<LocalReminder> reminders,
  List<LocalPerson> people,
  DateTime now,
) {
  final nowMin = now.hour * 60 + now.minute;
  final weekday = now.weekday - 1;
  String day(int d) => (pack.days.length == 7 ? pack.days : english.days)[d];

  if (hasIntent(question, pack, english, 'medicine')) {
    final meds = reminders.where((r) => r.active && r.kind == 'medication').toList();
    for (var ahead = 0; ahead < 8; ahead++) {
      final d = (weekday + ahead) % 7;
      final todays = meds.where((r) => r.days.contains(d) && (ahead > 0 || r.minutes >= nowMin)).toList()
        ..sort((a, b) => a.minutes.compareTo(b.minutes));
      if (todays.isNotEmpty) {
        final r = todays.first;
        var when = pack.formatTime(r.hour, r.minute);
        if (ahead > 0) when += ', ${day(d)}';
        return _answer(pack, english, 'med_next', {'title': r.title, 'time': when});
      }
    }
    return _answer(pack, english, 'med_none');
  }
  // Time before "who": "कौन सा दिन" (which day) contains "कौन" (who).
  if (hasIntent(question, pack, english, 'time')) {
    return _answer(pack, english, 'time', {'time': pack.formatTime(now.hour, now.minute), 'day': day(weekday)});
  }
  if (hasIntent(question, pack, english, 'who')) {
    final p = findPerson(question, people);
    if (p == null) return _answer(pack, english, 'who_unknown');
    final args = {
      'name': p.name ?? p.title,
      'relationship': p.relationship ?? _answer(pack, english, 'family'),
      'description': p.description ?? '',
    };
    return _answer(pack, english, p.description == null || p.description!.isEmpty ? 'who' : 'who_desc', args);
  }
  if (hasIntent(question, pack, english, 'schedule')) {
    final items = reminders.where((r) => r.active && r.days.contains(weekday) && r.minutes >= nowMin).toList()
      ..sort((a, b) => a.minutes.compareTo(b.minutes));
    if (items.isEmpty) return _answer(pack, english, 'today_none');
    return _answer(pack, english, 'today', {'items': items.map((r) => '${pack.formatTime(r.hour, r.minute)} ${r.title}').join('; ')});
  }
  return null;
}
