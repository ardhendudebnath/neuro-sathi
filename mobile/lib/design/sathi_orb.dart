import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'tilt.dart';

/// Sathi as a glowing ball, drawn live by a GPU shader (shaders/sathi_orb.frag).
/// It swirls slowly, faster while [listening]. Phones that cannot run the
/// shader, and the "Remove animations" setting, get a still ball instead.
class SathiOrb extends StatefulWidget {
  const SathiOrb({super.key, this.size = 220, this.listening = false, this.animate = true});

  final double size;
  final bool listening;
  final bool animate;

  /// Loaded once for the whole app; null if this phone cannot run it.
  static final Future<ui.FragmentProgram?> program = _load();

  static Future<ui.FragmentProgram?> _load() async {
    try {
      return await ui.FragmentProgram.fromAsset('shaders/sathi_orb.frag');
    } on Object {
      return null;
    }
  }

  @override
  State<SathiOrb> createState() => _SathiOrbState();
}

class _SathiOrbState extends State<SathiOrb> with TickerProviderStateMixin {
  final _clock = ValueNotifier<double>(4);
  final _listen = ValueNotifier<double>(0);
  ui.FragmentShader? _shader;
  Ticker? _ticker;
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    SathiOrb.program.then((p) {
      if (!mounted || p == null) return;
      setState(() => _shader = p.fragmentShader());
    });
    _sync();
  }

  @override
  void didUpdateWidget(SathiOrb oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
    if (!widget.animate) _listen.value = widget.listening ? 1 : 0;
  }

  void _sync() {
    if (widget.animate && _ticker == null) {
      _last = Duration.zero;
      _ticker = createTicker(_tick)..start();
    } else if (!widget.animate && _ticker != null) {
      _ticker!.dispose();
      _ticker = null;
    }
  }

  void _tick(Duration elapsed) {
    final dt = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    _clock.value += dt;
    final goal = widget.listening ? 1.0 : 0.0;
    _listen.value += (goal - _listen.value) * (dt * 4).clamp(0.0, 1.0);
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _shader?.dispose();
    _clock.dispose();
    _listen.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tilt = TiltScope.of(context);
    final shader = _shader;
    return RepaintBoundary(
      child: SizedBox.square(
        dimension: widget.size,
        child: CustomPaint(
          painter: shader == null
              ? _StillOrbPainter(listen: _listen)
              : _ShaderOrbPainter(shader: shader, clock: _clock, listen: _listen, tilt: tilt),
        ),
      ),
    );
  }
}

class _ShaderOrbPainter extends CustomPainter {
  _ShaderOrbPainter({required this.shader, required this.clock, required this.listen, required this.tilt})
      : super(repaint: Listenable.merge([clock, listen, tilt]));

  final ui.FragmentShader shader;
  final ValueListenable<double> clock;
  final ValueListenable<double> listen;
  final ValueListenable<Offset> tilt;

  @override
  void paint(Canvas canvas, Size size) {
    shader
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, clock.value)
      ..setFloat(3, listen.value)
      ..setFloat(4, tilt.value.dx)
      ..setFloat(5, tilt.value.dy);
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(_ShaderOrbPainter oldDelegate) => oldDelegate.shader != shader;
}

/// The same ball as plain gradients, for phones without shader support.
class _StillOrbPainter extends CustomPainter {
  _StillOrbPainter({required this.listen}) : super(repaint: listen);

  final ValueListenable<double> listen;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 * 0.74;
    final glow = Rect.fromCircle(center: c, radius: r * 1.35);
    canvas.drawCircle(
      c,
      r * 1.35,
      Paint()
        ..shader = RadialGradient(
          colors: [const Color(0xFF52E0C7).withValues(alpha: 0.35 + listen.value * 0.25), const Color(0x0052E0C7)],
          stops: const [0.55, 1],
        ).createShader(glow),
    );
    final ball = Rect.fromCircle(center: c, radius: r);
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.32, -0.44),
          colors: [Color(0xFFF3FFFC), Color(0xFF7EE3D2), Color(0xFF3E8DF0), Color(0xFF3B2FA8), Color(0xFF24196E)],
          stops: [0, 0.18, 0.55, 0.88, 1],
        ).createShader(ball),
    );
  }

  @override
  bool shouldRepaint(_StillOrbPainter oldDelegate) => false;
}
