import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_sathi/games/session_recorder.dart';
import 'package:neuro_sathi/games/trials.dart';
import 'package:neuro_sathi/services/difficulty.dart';

void main() {
  const content = GameContent(
    people: [
      PersonCard(name: 'Rina', relationship: 'granddaughter'),
      PersonCard(name: 'Bipul', relationship: 'son'),
      PersonCard(name: 'Mala', relationship: 'daughter'),
    ],
  );
  const slugs = ['photo_recall', 'market_list', 'odd_one_out', 'gamosa_patterns', 'name_it', 'my_day'];

  test('every game produces valid trials at every level', () {
    for (final slug in slugs) {
      for (var level = 1; level <= 5; level++) {
        final trials = trialsFor(slug, content, level, Random(level));
        expect(trials, isNotEmpty, reason: slug);
        for (final t in trials) {
          expect(t.answer, inInclusiveRange(0, t.options.length - 1), reason: '$slug L$level');
          expect(t.options.length, greaterThanOrEqualTo(2), reason: '$slug L$level');
        }
      }
    }
  });

  test('odd one out has exactly one odd item', () {
    for (final t in oddOneOut(content, 3, Random(1))) {
      final odd = t.options[t.answer];
      expect(t.options.where((o) => o == odd).length, 1);
    }
  });

  test('market list asks only about items that were shown', () {
    final trials = marketList(content, 2, Random(7));
    final seen = trials.first.memorize!;
    for (final t in trials) {
      expect(seen, contains(t.options[t.answer]));
      expect(t.options.where(seen.contains).length, 1);
    }
  });

  test('photo recall falls back when the memory book is too small', () {
    final trials = photoRecall(const GameContent(people: [PersonCard(name: 'Rina')]), 1, Random(1));
    expect(trials.first.promptKey, 'what_is_this');
  });

  test('picture-only displays are not read aloud', () {
    expect(weavingPatterns(content, 2, Random(1)).every((t) => !t.speakDisplay), isTrue);
    expect(nameIt(content, 2, Random(1)).every((t) => t.speakDisplay), isTrue);
  });

  test('harder levels offer more choices', () {
    final easy = nameIt(content, 1, Random(1)).first.options.length;
    final hard = nameIt(content, 5, Random(1)).first.options.length;
    expect(hard, greaterThan(easy));
  });

  test('recorder counts repeated errors on the same item', () {
    final r = SessionRecorder(slug: 'name_it', level: 1)
      ..record(isCorrect: false, responseMs: 3000, item: 'Japi')
      ..record(isCorrect: true, responseMs: 2000, item: 'Gamosa')
      ..record(isCorrect: false, responseMs: 4000, item: 'Japi');
    expect(r.trials, 3);
    expect(r.errors, 2);
    expect(r.repeatedErrors, 1);
    expect(r.avgResponseMs, 3000);
  });

  group('difficulty', () {
    SessionStats s(int level, int correct, {bool done = true}) =>
        SessionStats(level: level, trials: 10, correct: correct, completed: done);

    test('steps up after strong sessions', () {
      expect(nextLevel([s(2, 10), s(2, 9)], current: 2, minLevel: 1, maxLevel: 5), 3);
    });
    test('steps down when it is too hard', () {
      expect(nextLevel([s(3, 4), s(3, 5)], current: 3, minLevel: 1, maxLevel: 5), 2);
    });
    test('stays within bounds', () {
      expect(nextLevel([s(5, 10), s(5, 10)], current: 5, minLevel: 1, maxLevel: 5), 5);
      expect(nextLevel([s(1, 2), s(1, 1)], current: 1, minLevel: 1, maxLevel: 5), 1);
    });
    test('needs two sessions before changing', () {
      expect(nextLevel([s(2, 10)], current: 2, minLevel: 1, maxLevel: 5), 2);
    });
  });
}
