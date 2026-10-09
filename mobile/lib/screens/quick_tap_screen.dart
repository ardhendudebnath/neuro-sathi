import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/celebration.dart';
import '../design/raised_button.dart';
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
    final still = MediaQuery.of(context).disableAnimations;
    return Scaffold(
      backgroundColor: playGround,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(s.gameName(widget.game.slug, widget.game.name)),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
      ),
      body: DecoratedBox(
        decoration: playBackdrop,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: recorder == null
                ? const Center(child: CircularProgressIndicator())
                : finished
                    ? Celebration(
                        title: s.t('finished'),
                        score: s.t('score', {'correct': recorder!.correct, 'total': recorder!.trials}),
                        stars: starsFor(recorder!.correct, recorder!.trials),
                        action: s.t('done'),
                        onAction: () => Navigator.of(context).pop(),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Expanded(child: Text(s.t('tap_when_you_see'), style: Theme.of(context).textTheme.headlineMedium)),
                              const SizedBox(width: 12),
                              _Disc(emoji: target, size: 84, ring: const Color(0xFF18A28D)),
                            ],
                          ),
                          Expanded(
                            child: Center(
                              child: AnimatedSwitcher(
                                duration: still ? Duration.zero : const Duration(milliseconds: 180),
                                transitionBuilder: (child, animation) =>
                                    ScaleTransition(scale: CurvedAnimation(parent: animation, curve: Curves.easeOutBack), child: child),
                                child: _Disc(
                                  key: ValueKey(index),
                                  emoji: index < 0 ? '…' : sequence[index],
                                  size: 230,
                                  ring: tapped ? const Color(0xFF22A45D) : Colors.white,
                                ),
                              ),
                            ),
                          ),
                          RaisedButton3D(
                            label: s.t('tap'),
                            height: 120,
                            fontSize: 38,
                            tone: tapped ? ButtonTone.soft : ButtonTone.go,
                            onPressed: _tap,
                          ),
                        ],
                      ),
          ),
        ),
      ),
    );
  }
}

/// A picture on a raised white disc; the ring turns green once it is tapped.
class _Disc extends StatelessWidget {
  const _Disc({super.key, required this.emoji, required this.size, required this.ring});

  final String emoji;
  final double size;
  final Color ring;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const RadialGradient(center: Alignment(-0.3, -0.4), colors: [Colors.white, Color(0xFFE4EFEB)], stops: [0.4, 1]),
        border: Border.all(color: ring, width: size / 30),
        boxShadow: [BoxShadow(color: const Color(0x660A283C), offset: Offset(0, size / 10), blurRadius: size / 6, spreadRadius: -size / 14)],
      ),
      child: Text(emoji, style: TextStyle(fontSize: size * 0.5, height: 1.1)),
    );
  }
}