import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/celebration.dart';
import '../design/choice_tile.dart';
import '../design/lit_tile.dart';
import '../design/raised_button.dart';
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
    final playing = phase != _Phase.loading && phase != _Phase.done;
    return Scaffold(
      backgroundColor: playGround,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(s.gameName(widget.game.slug, widget.game.name)),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        bottom: playing
            ? PreferredSize(
                preferredSize: const Size.fromHeight(22),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                  child: LinearProgressIndicator(
                    value: (index + 1) / trials.length,
                    minHeight: 12,
                    borderRadius: BorderRadius.circular(6),
                    backgroundColor: const Color(0xFFD6E6E1),
                    color: const Color(0xFF18A28D),
                  ),
                ),
              )
            : null,
      ),
      body: DecoratedBox(
        decoration: playBackdrop,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: switch (phase) {
              _Phase.loading => const Center(child: CircularProgressIndicator()),
              _Phase.memorize => _memorize(s.t('remember_these'), s.t('ready')),
              _Phase.question || _Phase.feedback => _question(s.t(trials[index].promptKey), s.t('next')),
              _Phase.done => Celebration(
                  title: s.t('finished'),
                  score: s.t('score', {'correct': recorder.correct, 'total': recorder.trials}),
                  stars: starsFor(recorder.correct, recorder.trials),
                  action: s.t('done'),
                  onAction: () => Navigator.of(context).pop(),
                ),
            },
          ),
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
          child: ListView.separated(
            padding: const EdgeInsets.only(bottom: 12),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (_, i) => _MemoryCard(items[i]),
          ),
        ),
        RaisedButton3D(label: ready, onPressed: _askQuestion),
      ],
    );
  }

  ChoiceState _stateOf(int i) {
    if (phase != _Phase.feedback) return ChoiceState.idle;
    if (i == trials[index].answer) return ChoiceState.correct;
    if (i == picked) return ChoiceState.wrong;
    return ChoiceState.faded;
  }

  Widget _question(String prompt, String next) {
    final t = trials[index];
    final emojiOptions = t.options.every((o) => o.runes.length <= 2);
    Widget choice(int i) => ChoiceTile(label: t.options[i], big: emojiOptions, state: _stateOf(i), onTap: () => _answer(i));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(prompt, style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 16),
        if (t.imagePath != null)
          DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              boxShadow: const [BoxShadow(color: Color(0x590A283C), offset: Offset(0, 14), blurRadius: 24, spreadRadius: -12)],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Image.file(File(t.imagePath!), height: 220, fit: BoxFit.cover),
            ),
          ),
        if (t.display != null)
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white),
              boxShadow: const [BoxShadow(color: Color(0x4D0A283C), offset: Offset(0, 12), blurRadius: 22, spreadRadius: -14)],
            ),
            child: Text(t.display!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 30, height: 1.3)),
          ),
        const SizedBox(height: 12),
        Expanded(
          child: emojiOptions
              ? GridView.count(
                  padding: const EdgeInsets.only(top: 12, bottom: 8),
                  crossAxisCount: t.options.length <= 4 ? 2 : 3,
                  mainAxisSpacing: 14,
                  crossAxisSpacing: 14,
                  children: [for (var i = 0; i < t.options.length; i++) choice(i)],
                )
              : ListView.separated(
                  padding: const EdgeInsets.only(top: 12, bottom: 8),
                  itemCount: t.options.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 14),
                  itemBuilder: (_, i) => choice(i),
                ),
        ),
        if (phase == _Phase.feedback) Padding(padding: const EdgeInsets.only(top: 8), child: RaisedButton3D(label: next, onPressed: _next)),
      ],
    );
  }
}

/// One thing to remember, on a warm raised card.
class _MemoryCard extends StatelessWidget {
  const _MemoryCard(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    const tone = TileTone.amber;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFFFF4E5), Color(0xFFFFE2BF)]),
        boxShadow: const [BoxShadow(color: Color(0x59B05C14), offset: Offset(0, 12), blurRadius: 20, spreadRadius: -12)],
      ),
      child: Text(text, style: TextStyle(fontSize: 26, height: 1.2, fontWeight: FontWeight.w700, color: tone.ink)),
    );
  }
}