import 'dart:math';

/// One multiple-choice step. [memorize], when set, is shown first ("Remember
/// these") and hidden before the question. [display] is a large emoji or text.
class Trial {
  const Trial({
    required this.promptKey,
    required this.options,
    required this.answer,
    this.display,
    this.imagePath,
    this.memorize,
    this.speakExtra,
  });

  final String promptKey;
  final List<String> options;
  final int answer;
  final String? display;
  final String? imagePath;
  final List<String>? memorize;
  final String? speakExtra;
}

class PersonCard {
  const PersonCard({required this.name, this.relationship, this.photoPath});
  final String name;
  final String? relationship;
  final String? photoPath;
}

class ObjectCard {
  const ObjectCard(this.title, this.note);
  final String title;
  final String note;
}

/// Content a session can draw on: memory book, synced NER cultural items and built-ins.
class GameContent {
  const GameContent({this.people = const [], this.foods = const [], this.objects = const [], this.language = 'en'});
  final List<PersonCard> people;
  final List<String> foods;
  final List<ObjectCard> objects;
  final String language;
}

const trialsPerSession = 8;

// Built-in, culturally familiar defaults used until content is synced.
const _foods = {
  'en': ['Rice', 'Dal', 'Fish', 'Tea', 'Banana', 'Pitha', 'Potato', 'Egg', 'Mustard greens', 'Bamboo shoot', 'Orange', 'Jaggery'],
  'hi': ['चावल', 'दाल', 'मछली', 'चाय', 'केला', 'पीठा', 'आलू', 'अंडा', 'सरसों का साग', 'बाँस की कोंपल', 'संतरा', 'गुड़'],
};

const _objects = [
  ObjectCard('Gamosa', 'White cloth with a red woven border, given as a mark of respect'),
  ObjectCard('Japi', 'Traditional hat made of bamboo and palm leaves'),
  ObjectCard('Xorai', 'Bell-metal tray on a stand, used for offerings'),
  ObjectCard('Umbrella', 'Keeps you dry in the rainy season'),
  ObjectCard('Kettle', 'Used to boil water for tea'),
  ObjectCard('Mekhela chador', 'Two-piece traditional dress worn in Assam'),
  ObjectCard('Phanek', 'Traditional wrap-around skirt from Manipur'),
  ObjectCard('Dao', 'Large knife used for cutting bamboo and wood'),
];

const _routine = {
  'en': ['Wake up', 'Brush teeth', 'Morning tea', 'Prayer', 'Breakfast', 'Morning medicine', 'Short walk', 'Lunch', 'Rest', 'Evening tea', 'Dinner', 'Sleep'],
  'hi': ['उठना', 'दाँत साफ़ करना', 'सुबह की चाय', 'प्रार्थना', 'नाश्ता', 'सुबह की दवा', 'थोड़ी सैर', 'दोपहर का खाना', 'आराम', 'शाम की चाय', 'रात का खाना', 'सोना'],
};

const _oddPairs = [
  ['🐟', '🐠'], ['🌸', '🌼'], ['☕', '🍵'], ['🍚', '🍙'], ['🐘', '🦏'], ['🥭', '🍋'], ['🐓', '🦆'], ['🌳', '🌲'],
];

const _patternSymbols = ['🔴', '⚪', '🟢', '🟡', '🔷'];

int _choices(int level) => const [2, 3, 3, 4, 4, 4, 5, 5, 5, 5][(level - 1).clamp(0, 9)];

List<String> _optionsWith(String correct, List<String> pool, int n, Random rnd) {
  final others = pool.where((x) => x != correct).toSet().toList()..shuffle(rnd);
  return ([correct, ...others.take(n - 1)])..shuffle(rnd);
}

Trial _mcq(String promptKey, String correct, List<String> pool, int level, Random rnd,
    {String? display, String? imagePath, List<String>? memorize, String? speakExtra}) {
  final options = _optionsWith(correct, pool, _choices(level), rnd);
  return Trial(
    promptKey: promptKey,
    options: options,
    answer: options.indexOf(correct),
    display: display,
    imagePath: imagePath,
    memorize: memorize,
    speakExtra: speakExtra,
  );
}

List<Trial> photoRecall(GameContent c, int level, Random rnd) {
  final people = c.people.where((p) => p.name.isNotEmpty).toList();
  if (people.length < 2) return nameIt(c, level, rnd);
  final names = people.map((p) => p.name).toList();
  return List.generate(trialsPerSession, (_) {
    final p = people[rnd.nextInt(people.length)];
    return _mcq('who_is_this', p.name, names, level, rnd,
        imagePath: p.photoPath, display: p.photoPath == null ? (p.relationship ?? '🙂') : null);
  });
}

List<Trial> marketList(GameContent c, int level, Random rnd) {
  final pool = {...c.foods, ...?_foods[c.language]}.toList()..shuffle(rnd);
  final count = const [3, 4, 5, 6, 7][(level - 1).clamp(0, 4)];
  final seen = pool.take(count).toList();
  final unseen = pool.skip(count).toList();
  return List.generate(min(count, trialsPerSession), (i) {
    final correct = seen[i];
    final distractors = (unseen.toList()..shuffle(rnd)).take(_choices(level) - 1);
    final options = [correct, ...distractors]..shuffle(rnd);
    return Trial(promptKey: 'which_seen', options: options, answer: options.indexOf(correct), memorize: i == 0 ? seen : null);
  });
}

List<Trial> oddOneOut(GameContent c, int level, Random rnd) {
  final size = const [3, 4, 4, 5, 6][(level - 1).clamp(0, 4)];
  return List.generate(trialsPerSession, (_) {
    final pair = _oddPairs[rnd.nextInt(_oddPairs.length)];
    final flip = rnd.nextBool();
    final common = flip ? pair[0] : pair[1];
    final odd = flip ? pair[1] : pair[0];
    final oddAt = rnd.nextInt(size);
    final options = List.generate(size, (i) => i == oddAt ? odd : common);
    return Trial(promptKey: 'odd_one_out', options: options, answer: oddAt);
  });
}

List<Trial> weavingPatterns(GameContent c, int level, Random rnd) {
  return List.generate(trialsPerSession, (_) {
    final symbols = (_patternSymbols.toList()..shuffle(rnd)).take(3).toList();
    final unit = switch (level) {
      1 => [symbols[0], symbols[1]],
      2 => [symbols[0], symbols[0], symbols[1]],
      3 => [symbols[0], symbols[1], symbols[2]],
      _ => [symbols[0], symbols[1], symbols[1], symbols[2]],
    };
    final shown = 3 + level;
    final sequence = List.generate(shown + 1, (i) => unit[i % unit.length]);
    final correct = sequence.last;
    return _mcq('what_comes_next', correct, _patternSymbols, level, rnd, display: sequence.take(shown).join(' '));
  });
}

List<Trial> nameIt(GameContent c, int level, Random rnd) {
  final objects = [...c.objects, ..._objects];
  final titles = objects.map((o) => o.title).toList();
  return List.generate(trialsPerSession, (_) {
    final o = objects[rnd.nextInt(objects.length)];
    return _mcq('what_is_this', o.title, titles, level, rnd, display: o.note);
  });
}

List<Trial> myDay(GameContent c, int level, Random rnd) {
  final steps = _routine[c.language] ?? _routine['en']!;
  final shown = const [2, 3, 3, 4, 4][(level - 1).clamp(0, 4)];
  return List.generate(trialsPerSession, (_) {
    final start = rnd.nextInt(steps.length - shown);
    final correct = steps[start + shown];
    return _mcq('what_comes_next', correct, steps, level, rnd, display: steps.sublist(start, start + shown).join('\n↓\n'));
  });
}

List<Trial> trialsFor(String slug, GameContent c, int level, Random rnd) => switch (slug) {
      'photo_recall' => photoRecall(c, level, rnd),
      'market_list' => marketList(c, level, rnd),
      'odd_one_out' => oddOneOut(c, level, rnd),
      'gamosa_patterns' => weavingPatterns(c, level, rnd),
      'name_it' => nameIt(c, level, rnd),
      'my_day' => myDay(c, level, rnd),
      _ => oddOneOut(c, level, rnd),
    };

const gameIcons = {
  'photo_recall': '👪',
  'market_list': '🧺',
  'odd_one_out': '🔍',
  'gamosa_patterns': '🧵',
  'name_it': '🏺',
  'quick_tap': '👆',
  'my_day': '🌅',
};
