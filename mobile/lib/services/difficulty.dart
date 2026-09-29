// On-device difficulty, so levels adapt during offline play. Same explainable
// rules as the backend's personalisation engine; the server's recommendation
// (applied at each sync) takes over when it is newer.

class SessionStats {
  const SessionStats({required this.level, required this.trials, required this.correct, required this.completed, this.repeatedErrors = 0});
  final int level;
  final int trials;
  final int correct;
  final bool completed;
  final int repeatedErrors;
}

/// [recent] is newest first.
int nextLevel(List<SessionStats> recent, {required int current, required int minLevel, required int maxLevel}) {
  final window = recent.take(5).toList();
  if (window.length < 2) return current.clamp(minLevel, maxLevel);
  final trials = window.fold<int>(0, (s, x) => s + x.trials);
  if (trials == 0) return current.clamp(minLevel, maxLevel);
  final accuracy = window.fold<int>(0, (s, x) => s + x.correct) / trials;
  final completion = window.where((x) => x.completed).length / window.length;
  final repeated = window.fold<int>(0, (s, x) => s + x.repeatedErrors) / trials;
  final level = window.first.level;
  if (accuracy >= 0.85 && completion >= 0.9) return (level + 1).clamp(minLevel, maxLevel);
  if (accuracy < 0.6 || completion < 0.5 || repeated > 0.3) return (level - 1).clamp(minLevel, maxLevel);
  return level.clamp(minLevel, maxLevel);
}
