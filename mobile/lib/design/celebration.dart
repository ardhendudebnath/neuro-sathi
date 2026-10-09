import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'lit_tile.dart';
import 'raised_button.dart';

/// Stars for a finished game, out of 3: at least one for finishing, so every
/// session ends on encouragement.
int starsFor(int correct, int total) {
  if (total <= 0) return 1;
  final ratio = correct / total;
  if (ratio >= 0.8) return 3;
  if (ratio >= 0.5) return 2;
  return 1;
}

/// The end of a game: a gold star pops in with a burst of confetti, then the
/// stars earned, the score and a button to finish. Still with animations off.
class Celebration extends StatefulWidget {
  const Celebration({super.key, required this.title, required this.score, required this.stars, required this.action, required this.onAction});

  final String title;
  final String score;
  final int stars;
  final String action;
  final VoidCallback onAction;

  @override
  State<Celebration> createState() => _CelebrationState();
}

class _CelebrationState extends State<Celebration> with TickerProviderStateMixin {
  late final _pop = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
  late final _burst = AnimationController(vsync: this, duration: const Duration(milliseconds: 2200));
  late final _popCurve = CurvedAnimation(parent: _pop, curve: Curves.elasticOut);
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.of(context).disableAnimations) {
      _pop.value = 1;
      _burst.value = 1;
    } else {
      _pop.forward();
      _burst.forward();
    }
  }

  @override
  void dispose() {
    _popCurve.dispose();
    _pop.dispose();
    _burst.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: _ConfettiPainter(_burst)))),
        Center(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: ScaleTransition(
                    scale: _popCurve,
                    child: const GlossyBall(icon: Icons.star_rounded, tone: TileTone.gold, size: 128),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < 3; i++)
                      Icon(Icons.star_rounded, size: 44, color: i < widget.stars ? const Color(0xFFF0A21E) : const Color(0x26000000)),
                  ],
                ),
                const SizedBox(height: 10),
                Text(widget.title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 34, height: 1.1, fontWeight: FontWeight.w800, color: Color(0xFF10221F))),
                const SizedBox(height: 8),
                Text(widget.score, textAlign: TextAlign.center, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600, color: Color(0xFF3C504B))),
                const SizedBox(height: 28),
                RaisedButton3D(label: widget.action, onPressed: widget.onAction),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.progress) : super(repaint: progress);

  final Animation<double> progress;

  static const _colors = [Color(0xFF18A28D), Color(0xFFFFB21E), Color(0xFF3D8BF0), Color(0xFF7B5CF0), Color(0xFFF0604F), Color(0xFF68D8C5)];

  /// Fixed pieces, so every burst looks the same: (angle, speed, size, spin, color).
  static final _pieces = () {
    final r = math.Random(3);
    return [
      for (var i = 0; i < 90; i++)
        (angle: -math.pi / 2 + (r.nextDouble() - 0.5) * 2.2, speed: 0.55 + r.nextDouble() * 0.6, size: 6 + r.nextDouble() * 6, spin: (r.nextDouble() - 0.5) * 14, color: _colors[i % _colors.length]),
    ];
  }();

  @override
  void paint(Canvas canvas, Size size) {
    final t = progress.value;
    if (t <= 0 || t >= 1) return;
    final origin = Offset(size.width / 2, size.height * 0.3);
    final reach = size.shortestSide * 0.9;
    final paint = Paint();
    for (final p in _pieces) {
      final d = p.speed * reach * t;
      final pos = origin + Offset(math.cos(p.angle) * d, math.sin(p.angle) * d + 0.9 * reach * t * t);
      paint.color = p.color.withValues(alpha: (1 - t).clamp(0.0, 1.0).toDouble());
      canvas
        ..save()
        ..translate(pos.dx, pos.dy)
        ..rotate(p.spin * t)
        ..drawRect(Rect.fromCenter(center: Offset.zero, width: p.size, height: p.size / 2), paint)
        ..restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter oldDelegate) => oldDelegate.progress != progress;
}
