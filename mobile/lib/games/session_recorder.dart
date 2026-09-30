import 'dart:convert';
import 'dart:math';

import '../data/repository.dart';
import '../l10n/language_pack.dart';
import '../services/difficulty.dart';
import 'trials.dart';

/// Collects per-trial performance (accuracy, response time, repeated errors)
/// and saves one game session locally; it reaches the server at the next sync.
class SessionRecorder {
  SessionRecorder({required this.slug, required this.level});

  final String slug;
  final int level;
  final DateTime startedAt = DateTime.now();
  final List<int> _responseMs = [];
  final Map<String, int> _missedItems = {};
  int trials = 0;
  int correct = 0;
  int errors = 0;
  int repeatedErrors = 0;

  void record({required bool isCorrect, required int responseMs, required String item}) {
    trials++;
    _responseMs.add(responseMs);
    if (isCorrect) {
      correct++;
      return;
    }
    errors++;
    final before = _missedItems[item] ?? 0;
    if (before > 0) repeatedErrors++; // the same item was already missed this session
    _missedItems[item] = before + 1;
  }

  double? get avgResponseMs => _responseMs.isEmpty ? null : _responseMs.reduce((a, b) => a + b) / _responseMs.length;

  Future<void> save(Repository repo, {required bool completed}) async {
    if (trials == 0) return;
    await repo.recordSession(
      gameSlug: slug,
      level: level,
      startedAt: startedAt,
      endedAt: DateTime.now(),
      trials: trials,
      correct: correct,
      errors: errors,
      repeatedErrors: repeatedErrors,
      avgResponseMs: avgResponseMs,
      completed: completed,
    );
  }
}

/// Level for this session: the server's recommendation if there is one,
/// otherwise the on-device rules applied to recent local sessions.
Future<int> chooseLevel(Repository repo, String slug, {int? suggested, required int minLevel, required int maxLevel}) async {
  final recent = await repo.sessionsFor(slug);
  if (recent.isEmpty) return (suggested ?? minLevel).clamp(minLevel, maxLevel);
  final local = nextLevel(
    recent
        .map((r) => SessionStats(level: r.level, trials: r.trials, correct: r.correct, completed: r.completed, repeatedErrors: r.repeatedErrors))
        .toList(),
    current: recent.first.level,
    minLevel: minLevel,
    maxLevel: maxLevel,
  );
  return suggested == null ? local : min(max(local, suggested - 1), suggested + 1);
}

/// Builds the content games draw on: the memory book plus word lists, routines
/// and objects from the user's language pack. Server cultural items are in
/// English, so they are added only for English.
Future<GameContent> loadContent(Repository repo, LanguagePack pack) async {
  final memories = await repo.memories();
  final english = pack.code == 'en';
  final serverFoods = english ? (await repo.cultural(category: 'food')).map((f) => f.title) : const <String>[];
  final serverObjects = english
      ? (await repo.cultural(category: 'object'))
          .map((o) => ObjectCard(o.title, ((jsonDecode(o.data) as Map<String, dynamic>)['note'] as String?) ?? o.title))
      : const <ObjectCard>[];
  return GameContent(
    people: memories
        .where((m) => m.kind == 'person')
        .map((m) => PersonCard(name: m.personName ?? m.title, relationship: m.relationship, photoPath: m.localPhotoPath))
        .toList(),
    foods: {...(pack.foods.isEmpty ? defaultFoods : pack.foods), ...serverFoods}.toList(),
    routine: pack.routine.isEmpty ? defaultRoutine : pack.routine,
    objects: [
      ...(pack.objects.isEmpty ? defaultObjects : pack.objects.map((o) => ObjectCard(o.title, o.note))),
      ...serverObjects,
    ],
  );
}