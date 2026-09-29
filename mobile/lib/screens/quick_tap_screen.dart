import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../games/session_recorder.dart';
import '../state/app_state.dart';
import 'games_screen.dart';

/// Processing-speed game: pictures appear one at a time; tap only for the target.
class QuickTapScreen extends ConsumerStatefulWidget {
  const QuickTapScreen({super.key, required this.game});
  final GameEntry game;

  @override
  ConsumerState<QuickTapScreen> createState() => _QuickTapScreenState();
}

class _QuickTapScreenState extends ConsumerState<QuickTapScreen> {
  static const _pool = ['🐟', '🌸', '☕', '🐘', '🥭', '🐓', '🌳', '🍚'];
  static const _stimuliByLevel = [8, 10, 12, 14, 16];
  static const _windowMsByLevel = [2500, 2000, 1700, 1400, 1200];

  late final _repo = ref.read(repoProvider);
  late final _voice = ref.read(voiceProvider);
  final _rnd = Random();
  SessionRecorder? recorder;
  late String target;
  late List<String> sequence;
  int index = -1;
  bool tapped = false;
  bool finished = false;
  int windowMs = 2500;
  Timer? _timer;
  final _watch = Stopwatch();

  @override
  void initState() {
    super.initState();
    // Resolve now: ref must not be used once the widget is being disposed.
    _repo;
    _voice;
    _start();
  }

  Future<void> _start() async {
    final g = widget.game;
    final level = await chooseLevel(_repo, g.slug, suggested: g.suggestedLevel, minLevel: g.minLevel, maxLevel: g.maxLevel);
    final i = (level - 1).clamp(0, 4);
    target = _pool[_rnd.nextInt(_pool.length)];
    // About 40% targets, never two identical sequences.
    sequence = List.generate(_stimuliByLevel[i], (_) => _rnd.nextDouble() < 0.4 ? target : _pool[_rnd.nextInt(_pool.length)]);
    windowMs = _windowMsByLevel[i];
    if (!mounted) return;
    setState(() => recorder = SessionRecorder(slug: g.slug, level: level));
    _voice.speak(ref.read(stringsProvider).t('tap_when_you_see'));
    _timer = Timer(const Duration(seconds: 3), _nextStimulus);
  }

  void _nextStimulus() {
    if (index >= 0) _score();
    if (index + 1 >= sequence.length) {
      _finish();
      return;
    }
    setState(() {
      index++;
      tapped = false;
    });
    _watch
      ..reset()
      ..start();
    _timer = Timer(Duration(milliseconds: windowMs), _nextStimulus);
  }

  void _score() {
    final isTarget = sequence[index] == target;
    final correct = isTarget == tapped;
    recorder!.record(isCorrect: correct, responseMs: tapped ? _watch.elapsedMilliseconds : windowMs, item: sequence[index]);
  }

  void _tap() {
    if (index < 0 || tapped || finished) return;
    _watch.stop();
    setState(() => tapped = true);
  }

  Future<void> _finish() async {
    setState(() => finished = true);
    await recorder!.save(_repo, completed: true);
    final s = ref.read(stringsProvider);
    _voice.speak('${s.t('finished')} ${s.t('score', {'correct': recorder!.correct, 'total': recorder!.trials})}');
  }

  @override
  void dispose() {
    _timer?.cancel();
    if (!finished && recorder != null && recorder!.trials > 0) recorder!.save(_repo, completed: false);
    _voice.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text(widget.game.name)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: recorder == null
              ? const Center(child: CircularProgressIndicator())
              : finished
                  ? Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text('🌟', textAlign: TextAlign.center, style: TextStyle(fontSize: 90)),
                        Text(s.t('finished'), textAlign: TextAlign.center, style: text.displaySmall),
                        Text(s.t('score', {'correct': recorder!.correct, 'total': recorder!.trials}),
                            textAlign: TextAlign.center, style: text.headlineMedium),
                        const SizedBox(height: 32),
                        FilledButton(onPressed: () => Navigator.of(context).pop(), child: Text(s.t('done'))),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('${s.t('tap_when_you_see')}  $target', style: text.headlineMedium),
                        Expanded(
                          child: Center(
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 150),
                              child: Text(
                                index < 0 ? '…' : sequence[index],
                                key: ValueKey(index),
                                style: const TextStyle(fontSize: 140),
                              ),
                            ),
                          ),
                        ),
                        SizedBox(
                          height: 120,
                          child: FilledButton(
                            onPressed: _tap,
                            style: FilledButton.styleFrom(backgroundColor: tapped ? Colors.grey : null),
                            child: Text(s.t('tap'), style: const TextStyle(fontSize: 36)),
                          ),
                        ),
                      ],
                    ),
        ),
      ),
    );
  }
}
