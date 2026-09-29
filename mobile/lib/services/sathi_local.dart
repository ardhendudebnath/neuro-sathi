// Sathi's offline answers. Mirrors backend app/services/sathi_engine.py so the
// same questions work with no internet: today's plan, next medicine,
// "who is ...", and the date and time.

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

const _t = {
  'en': {
    'today_none': 'You have nothing scheduled for the rest of today. Enjoy your day!',
    'today': 'Here is the rest of today: {items}.',
    'med_none': "I don't have any medicine reminders for you. Please ask your family if you are unsure.",
    'med_next': 'Your next medicine is {title} at {time}.',
    'who': '{name} is your {relationship}.',
    'who_desc': '{name} is your {relationship}. {description}',
    'who_unknown': "I'm not sure who that is. Let's look at your memory book together, or ask your family.",
    'time': 'It is {time} on {day}.',
    'fallback': "I'm here with you. I can tell you today's plan, your next medicine, or about the people in your memory book.",
    'family': 'family',
  },
  'hi': {
    'today_none': 'आज के लिए और कुछ तय नहीं है। अपना दिन अच्छे से बिताइए!',
    'today': 'आज का बाकी कार्यक्रम: {items}।',
    'med_none': 'आपकी दवा का कोई रिमाइंडर नहीं है। संदेह हो तो परिवार से पूछिए।',
    'med_next': 'आपकी अगली दवा {title} है, {time} बजे।',
    'who': '{name} आपके {relationship} हैं।',
    'who_desc': '{name} आपके {relationship} हैं। {description}',
    'who_unknown': 'मुझे पक्का नहीं पता वह कौन हैं। चलिए मेमोरी बुक देखते हैं, या परिवार से पूछिए।',
    'time': 'अभी {day}, {time} बजे हैं।',
    'fallback': 'मैं आपके साथ हूँ। मैं आज का कार्यक्रम, अगली दवा, या मेमोरी बुक के लोगों के बारे में बता सकता हूँ।',
    'family': 'परिवार',
  },
};

const _days = {
  'en': ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'],
  'hi': ['सोमवार', 'मंगलवार', 'बुधवार', 'गुरुवार', 'शुक्रवार', 'शनिवार', 'रविवार'],
};

final _schedule = RegExp(r'\b(today|schedule|plan|aaj|karyakram)\b|आज|कार्यक्रम', caseSensitive: false);
final _medicine = RegExp(r'\b(medicine|medication|tablet|pill|dawa|dawai)\b|दवा|दवाई|गोली', caseSensitive: false);
final _who = RegExp(r'\bwho\s+is\b|\bkaun\b|कौन', caseSensitive: false);
final _time = RegExp(r'\b(what\s+(time|day)|which\s+day|samay|din)\b|समय|कौन सा दिन|क्या दिन', caseSensitive: false);

String _tr(String lang, String key, [Map<String, String> args = const {}]) {
  var s = (_t[lang] ?? _t['en']!)[key] ?? _t['en']![key]!;
  args.forEach((k, v) => s = s.replaceAll('{$k}', v));
  return s;
}

String fallbackAnswer(String lang) => _tr(lang, 'fallback');

String formatTime(int hour, int minute) {
  final h = (hour + 11) % 12 + 1;
  return '$h:${minute.toString().padLeft(2, '0')} ${hour >= 12 ? 'PM' : 'AM'}';
}

Set<String> _words(String text) =>
    RegExp(r'''[^\s.,!?।"'()\-]+''').allMatches(text.toLowerCase()).map((m) => m.group(0)!).where((w) => w.runes.length > 2).toSet();

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
String? answerLocally(String question, String lang, List<LocalReminder> reminders, List<LocalPerson> people, DateTime now) {
  final nowMin = now.hour * 60 + now.minute;
  final weekday = now.weekday - 1;
  final days = _days[lang] ?? _days['en']!;

  if (_medicine.hasMatch(question)) {
    final meds = reminders.where((r) => r.active && r.kind == 'medication').toList();
    for (var ahead = 0; ahead < 8; ahead++) {
      final day = (weekday + ahead) % 7;
      final todays = meds.where((r) => r.days.contains(day) && (ahead > 0 || r.minutes >= nowMin)).toList()
        ..sort((a, b) => a.minutes.compareTo(b.minutes));
      if (todays.isNotEmpty) {
        final r = todays.first;
        var when = formatTime(r.hour, r.minute);
        if (ahead > 0) when += ', ${days[day]}';
        return _tr(lang, 'med_next', {'title': r.title, 'time': when});
      }
    }
    return _tr(lang, 'med_none');
  }
  if (_who.hasMatch(question)) {
    final p = findPerson(question, people);
    if (p == null) return _tr(lang, 'who_unknown');
    final args = {'name': p.name ?? p.title, 'relationship': p.relationship ?? _tr(lang, 'family'), 'description': p.description ?? ''};
    return _tr(lang, p.description == null || p.description!.isEmpty ? 'who' : 'who_desc', args);
  }
  if (_time.hasMatch(question)) {
    return _tr(lang, 'time', {'time': formatTime(now.hour, now.minute), 'day': days[weekday]});
  }
  if (_schedule.hasMatch(question)) {
    final items = reminders.where((r) => r.active && r.days.contains(weekday) && r.minutes >= nowMin).toList()
      ..sort((a, b) => a.minutes.compareTo(b.minutes));
    if (items.isEmpty) return _tr(lang, 'today_none');
    return _tr(lang, 'today', {'items': items.map((r) => '${formatTime(r.hour, r.minute)} ${r.title}').join('; ')});
  }
  return null;
}
