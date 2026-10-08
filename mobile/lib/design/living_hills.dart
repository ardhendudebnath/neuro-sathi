import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'sky.dart';
import 'tilt.dart';

/// The home screen's header: the hills of the North-East at the time of day,
/// with mist, tea-garden rows, birds by day and fireflies and stars at night.
/// The layers shift with the phone's tilt. Still when animations are off.
class LivingHills extends StatefulWidget {
  const LivingHills({super.key, required this.palette, this.animate = true});

  final SkyPalette palette;
  final bool animate;

  @override
  State<LivingHills> createState() => _LivingHillsState();
}

class _LivingHillsState extends State<LivingHills> with TickerProviderStateMixin {
  final _clock = ValueNotifier<double>(4);
  Ticker? _ticker;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(LivingHills oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    if (widget.animate && _ticker == null) {
      _ticker = createTicker((elapsed) => _clock.value = 4 + elapsed.inMilliseconds / 1000)..start();
    } else if (!widget.animate && _ticker != null) {
      _ticker!.dispose();
      _ticker = null;
    }
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tilt = TiltScope.of(context);
    return RepaintBoundary(
      child: CustomPaint(
        painter: HillsPainter(palette: widget.palette, clock: _clock, tilt: tilt),
        size: Size.infinite,
      ),
    );
  }
}

class _Layer {
  const _Layer(this.base, this.amp, this.depth, this.f, this.p);
  final double base, amp, depth;
  final List<double> f, p;
}

/// Seeded so the hills keep the same shape every day.
final _layers = () {
  var s = 7;
  double rand() => (s = (s * 16807) % 2147483647) / 2147483647;
  return [
    for (var i = 0; i < 4; i++)
      _Layer(0.56 + i * 0.11, [30.0, 24.0, 18.0, 14.0][i], [0.18, 0.4, 0.7, 1.05][i],
          [0.006 + rand() * 0.004, 0.017 + rand() * 0.006, 0.041 + rand() * 0.01], [rand() * 6, rand() * 6, rand() * 6]),
  ];
}();

final _stars = () {
  final r = math.Random(11);
  return [for (var i = 0; i < 46; i++) (x: r.nextDouble(), y: r.nextDouble() * 0.55, size: 0.6 + r.nextDouble() * 1.2, phase: r.nextDouble() * 6)];
}();

final _flies = () {
  final r = math.Random(5);
  return [for (var i = 0; i < 16; i++) (x: r.nextDouble(), y: 0.62 + r.nextDouble() * 0.32, phase: r.nextDouble() * 6, speed: 0.4 + r.nextDouble() * 0.6)];
}();

class HillsPainter extends CustomPainter {
  HillsPainter({required this.palette, required this.clock, required this.tilt}) : super(repaint: Listenable.merge([clock, tilt]));

  final SkyPalette palette;
  final ValueListenable<double> clock;
  final ValueListenable<Offset> tilt;

  double _hillY(_Layer l, double x, Size size, double shift) {
    final u = x + shift;
    return size.height * l.base -
        l.amp * (0.62 * math.sin(u * l.f[0] * (380 / size.width) * 2 + l.p[0]) + 0.28 * math.sin(u * l.f[1] + l.p[1]) + 0.1 * math.sin(u * l.f[2] + l.p[2]));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final t = clock.value, tl = tilt.value, w = size.width, h = size.height, p = palette;
    canvas.drawRect(
      Offset.zero & size,
      Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [p.skyTop, p.skyBottom], stops: const [0, 0.75]).createShader(Offset.zero & size),
    );

    if (p.stars) {
      final star = Paint();
      for (final s in _stars) {
        star.color = Colors.white.withValues(alpha: 0.45 + 0.55 * (math.sin(t * 1.2 + s.phase)).abs());
        canvas.drawCircle(Offset(s.x * w - tl.dx * 2, s.y * h - tl.dy), s.size, star);
      }
    }

    // Sun or moon, with its glow.
    final sun = Offset(p.sun.dx * w - tl.dx * 5, p.sun.dy * h - tl.dy * 3);
    final r = p.sunRadius;
    canvas.drawCircle(
      sun,
      r * 5,
      Paint()..shader = RadialGradient(colors: [p.sunGlow.withValues(alpha: 0.55), p.sunGlow.withValues(alpha: 0)], stops: const [0.12, 1]).createShader(Rect.fromCircle(center: sun, radius: r * 5)),
    );
    canvas.drawCircle(
      sun,
      r,
      Paint()
        ..shader = RadialGradient(center: const Alignment(-0.35, -0.35), colors: p.sunCore, stops: const [0, 0.45, 1]).createShader(Rect.fromCircle(center: sun, radius: r)),
    );
    if (p.moon) {
      final crater = Paint()..color = const Color(0x5996A0C8);
      canvas.drawCircle(sun + const Offset(4, -3), 3.5, crater);
      canvas.drawCircle(sun + const Offset(-5, 5), 2.5, crater);
    }

    if (p.birds) {
      final bird = Paint()
        ..color = const Color(0x8C1E323C)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round;
      for (var b = 0; b < 3; b++) {
        final bx = ((t * 12 + b * 46) % (w + 60)) - 30;
        final by = h * 0.24 + b * 9 + math.sin(t * 2 + b) * 3;
        final flap = math.sin(t * 12 + b * 2) * 3;
        canvas.drawPath(
          Path()
            ..moveTo(bx - 6, by - flap)
            ..quadraticBezierTo(bx - 3, by - 3, bx, by)
            ..quadraticBezierTo(bx + 3, by - 3, bx + 6, by - flap),
          bird,
        );
      }
    }

    for (var i = 0; i < _layers.length; i++) {
      final l = _layers[i];
      final shift = -tl.dx * l.depth * 48;
      final dy = -tl.dy * l.depth * 6;
      final hill = Path()..moveTo(-20, h);
      for (var x = -20.0; x <= w + 20; x += 6) {
        hill.lineTo(x, _hillY(l, x, size, shift) + dy);
      }
      hill
        ..lineTo(w + 20, h)
        ..close();
      canvas.drawPath(hill, Paint()..color = p.hills[i]);

      if (i == 1 || i == 2) {
        // A band of mist drifting between the hills.
        final mx = ((t * 6 * (i + 1)) % (w * 1.6)) - w * 0.3;
        final my = h * (l.base + 0.03);
        final mist = Rect.fromCenter(center: Offset(mx, my), width: w * 1.1, height: 36);
        canvas.drawOval(mist, Paint()..shader = RadialGradient(colors: [p.mist.withValues(alpha: 0.42), p.mist.withValues(alpha: 0)]).createShader(mist));
      }

      if (i == _layers.length - 1) {
        // Rows of tea bushes on the nearest hill.
        final row = Paint()
          ..color = Colors.white.withValues(alpha: 0.1)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round;
        for (var k = 1; k <= 6; k++) {
          for (var x = -20.0; x <= w + 20; x += 13) {
            final y0 = _hillY(l, x, size, shift) + dy + k * 9;
            final y1 = _hillY(l, x + 7, size, shift) + dy + k * 9;
            canvas.drawLine(Offset(x, y0), Offset(x + 7, y1), row);
          }
        }
      }
    }

    if (p.fireflies) {
      for (final f in _flies) {
        final fx = f.x * w + math.sin(t * 0.6 * f.speed + f.phase) * 18 - tl.dx * 10;
        final fy = f.y * h + math.cos(t * 0.8 * f.speed + f.phase) * 8;
        final a = 0.35 + 0.65 * (math.sin(t * 2 * f.speed + f.phase)).abs();
        final c = Offset(fx, fy);
        canvas.drawCircle(
          c,
          7,
          Paint()..shader = RadialGradient(colors: [Color.fromRGBO(230, 255, 150, a), const Color.fromRGBO(230, 255, 150, 0)]).createShader(Rect.fromCircle(center: c, radius: 7)),
        );
      }
    }
  }

  @override
  bool shouldRepaint(HillsPainter oldDelegate) => oldDelegate.palette != palette || oldDelegate.clock != clock || oldDelegate.tilt != tilt;
}
