import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../games/session_recorder.dart';
import '../games/trials.dart';
import '../state/app_state.dart';
import 'games_screen.dart';

enum _Phase { loading, memorize, question, feedback, done }

/// Plays any multiple-choice game: one question per screen, large choices,
/// every prompt read aloud, gentle feedback, results saved locally.
class GamePlayScreen extends ConsumerStatefulWidget {
  const GamePlayScreen({super.key, required this.game});
  final GameEntry game;

  @override
  ConsumerState<GamePlayScreen> createState() => _GamePlayScreenState();
}

class _GamePlayScreenState extends ConsumerState<GamePlayScreen> {
  _Phase phase = _Phase.loading;
  late List<Trial> trials;
  late SessionRecorder recorder;
  int index = 0;
  int? picked;
  final _watch = Stopwatch();
  bool _saved = false;
  // Captured up front: ref must not be used once the widget is being disposed.
  late final _repo = ref.read(repoProvider);
  late final _voice = ref.read(voiceProvider);

  @override
  void initState() {
    super.initState();
    _repo;
    _voice;
    _start();
  }

  Future<void> _start() async {
    final repo = _repo;
    final pack = ref.read(appProvider).currentPack;
    final g = widget.game;
    final level = await chooseLevel(repo, g.slug, suggested: g.suggestedLevel, minLevel: g.minLevel, maxLevel: g.maxLevel);
    final content = await loadContent(repo, pack);
    trials = trialsFor(g.slug, content, level, Random());
    recorder = SessionRecorder(slug: g.slug, level: level);
    if (!mounted) return;
    _showTrial();
  }

  void _showTrial() {
    final t = trials[index];
    setState(() {
      picked = null;
      phase = t.memorize != null ? _Phase.memorize : _Phase.question;
    });
    final s = ref.read(stringsProvider);
    if (t.memorize != null) {
      _say('${s.t('remember_these')}. ${t.memorize!.join(', ')}');
    } else {
      _askQuestion();
    }
  }

  void _askQuestion() {
    final t = trials[index];
    setState(() => phase = _Phase.question);
    _watch
      ..reset()
      ..start();
    final s = ref.read(stringsProvider);
    final display = t.display != null && t.speakDisplay ? '. ${t.display}' : '';
    _say('${s.t(t.promptKey)}$display');
  }

  void _say(String text) => _voice.speak(text);

  void _answer(int i) {
    if (phase != _Phase.question) return;
    _watch.stop();
    final t = trials[index];
    final ok = i == t.answer;
    recorder.record(isCorrect: ok, responseMs: _watch.elapsedMilliseconds, item: t.options[t.answer]);
    setState(() {
      picked = i;
      phase = _Phase.feedback;
    });
    final s = ref.read(stringsProvider);
    _say(ok ? s.t('well_done') : '${s.t('not_quite')} ${t.options[t.answer]}');
  }

  Future<void> _next() async {
    if (index + 1 < trials.length) {
      index++;
      _showTrial();
      return;
    }
    await _save(completed: true);
    setState(() => phase = _Phase.done);
    final s = ref.read(stringsProvider);
    _say('${s.t('finished')} ${s.t('score', {'correct': recorder.correct, 'total': recorder.trials})}');
  }

  Future<void> _save({required bool completed}) async {
    if (_saved) return;
    _saved = true;
    await recorder.save(_repo, completed: completed);
  }

  @override
  void dispose() {
    // Leaving early still records the attempt (completed = false).
    if (phase != _Phase.loading && !_saved) {
      recorder.save(_repo, completed: false);
    }
    _voice.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(s.gameName(widget.game.slug, widget.game.name)),
        bottom: phase == _Phase.loading || phase == _Phase.done
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(8),
                child: LinearProgressIndicator(value: (index + 1) / trials.length, minHeight: 8),
              ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: switch (phase) {
            _Phase.loading => const Center(child: CircularProgressIndicator()),
            _Phase.memorize => _memorize(s.t('remember_these'), s.t('ready')),
            _Phase.question || _Phase.feedback => _question(s.t(trials[index].promptKey), s.t('next')),
            _Phase.done => _done(s.t('finished'), s.t('score', {'correct': recorder.correct, 'total': recorder.trials}), s.t('done')),
          },
        ),
      ),
    );
  }

  Widget _memorize(String title, String ready) {
    final items = trials[index].memorize!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 20),
        Expanded(
          child: ListView(
            children: [
              for (final item in items)
                Card(
                  elevation: 0,
                  color: Theme.of(context).colorScheme.secondaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Text(item, style: Theme.of(context).textTheme.headlineMedium),
                  ),
                ),
            ],
          ),
        ),
        FilledButton(onPressed: _askQuestion, child: Text(ready)),
      ],
    );
  }

  Widget _question(String prompt, String next) {
    final t = trials[index];
    final scheme = Theme.of(context).colorScheme;
    final emojiOptions = t.options.every((o) => o.runes.length <= 2);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(prompt, style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 16),
        if (t.imagePath != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.file(File(t.imagePath!), height: 220, fit: BoxFit.cover),
          ),
        if (t.display != null)
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(color: scheme.surfaceContainerHigh, borderRadius: BorderRadius.circular(16)),
            child: Text(t.display!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 30, height: 1.3)),
          ),
        const SizedBox(height: 20),
        Expanded(
          child: emojiOptions
              ? GridView.count(
                  crossAxisCount: t.options.length <= 4 ? 2 : 3,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  children: [for (var i = 0; i < t.options.length; i++) _option(i, emoji: true)],
                )
              : ListView.separated(
                  itemCount: t.options.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (_, i) => _option(i),
                ),
        ),
        if (phase == _Phase.feedback) FilledButton(onPressed: _next, child: Text(next)),
      ],
    );
  }

  Widget _option(int i, {bool emoji = false}) {
    final t = trials[index];
    final scheme = Theme.of(context).colorScheme;
    Color? bg;
    if (phase == _Phase.feedback) {
      if (i == t.answer) bg = const Color(0xFFCDEFD6);
      if (i == picked && i != t.answer) bg = const Color(0xFFFDE2DD);
    }
    return Material(
      color: bg ?? scheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: scheme.outline, width: 2)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _answer(i),
        child: Container(
          constraints: const BoxConstraints(minHeight: 72),
          alignment: Alignment.center,
          padding: const EdgeInsets.all(14),
          child: Text(t.options[i], textAlign: TextAlign.center, style: TextStyle(fontSize: emoji ? 54 : 24, fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }

  Widget _done(String title, String score, String done) => Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('🌟', textAlign: TextAlign.center, style: TextStyle(fontSize: 90)),
          Text(title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.displaySmall),
          const SizedBox(height: 12),
          Text(score, textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 32),
          FilledButton(onPressed: () => Navigator.of(context).pop(), child: Text(done)),
        ],
      );
}
