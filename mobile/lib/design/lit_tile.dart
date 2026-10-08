import 'package:flutter/material.dart';

import 'fit_text.dart';
import 'tilt.dart';

/// Colors for one tile: a light face ([face], [faceDeep]), the shadow it casts,
/// the three tones of its glossy ball, and the label color.
class TileTone {
  const TileTone({
    required this.face,
    required this.faceDeep,
    required this.shadow,
    required this.ballLight,
    required this.ball,
    required this.ballDeep,
    required this.ink,
  });

  final Color face;
  final Color faceDeep;
  final Color shadow;
  final Color ballLight;
  final Color ball;
  final Color ballDeep;
  final Color ink;

  static const teal = TileTone(
    face: Color(0xFFE7F8F4),
    faceDeep: Color(0xFFBBE8DE),
    shadow: Color(0x800F6E66),
    ballLight: Color(0xFF68D8C5),
    ball: Color(0xFF18A28D),
    ballDeep: Color(0xFF0A6A5E),
    ink: Color(0xFF0A4740),
  );
  static const amber = TileTone(
    face: Color(0xFFFFF4E5),
    faceDeep: Color(0xFFFFD6A6),
    shadow: Color(0x75B05C14),
    ballLight: Color(0xFFFFC680),
    ball: Color(0xFFF08A24),
    ballDeep: Color(0xFFB2550A),
    ink: Color(0xFF6A3204),
  );
  static const blue = TileTone(
    face: Color(0xFFEAF3FF),
    faceDeep: Color(0xFFC1DAFF),
    shadow: Color(0x751D4EA0),
    ballLight: Color(0xFF93C7FF),
    ball: Color(0xFF3D8BF0),
    ballDeep: Color(0xFF1C51AC),
    ink: Color(0xFF113C7D),
  );
  static const violet = TileTone(
    face: Color(0xFFF2EDFF),
    faceDeep: Color(0xFFD6C8FF),
    shadow: Color(0x7A583CB4),
    ballLight: Color(0xFFBDA8FF),
    ball: Color(0xFF7B5CF0),
    ballDeep: Color(0xFF4A31AE),
    ink: Color(0xFF34228A),
  );
  static const rose = TileTone(
    face: Color(0xFFFFF0EE),
    faceDeep: Color(0xFFFFD2CC),
    shadow: Color(0x75A8281C),
    ballLight: Color(0xFFFFB3A8),
    ball: Color(0xFFF0604F),
    ballDeep: Color(0xFFA8281C),
    ink: Color(0xFF7A1F15),
  );
}

/// A glossy ball with a white icon. Its highlight and shadow follow the tilt,
/// as if lit by the same sun as everything else on the screen.
class GlossyBall extends StatelessWidget {
  const GlossyBall({super.key, required this.icon, required this.tone, this.size = 64});

  final IconData icon;
  final TileTone tone;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Offset>(
      valueListenable: TiltScope.of(context),
      builder: (context, t, _) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            center: Alignment(-0.36 + t.dx * 0.28, -0.48 + t.dy * 0.24),
            radius: 0.95,
            colors: [Colors.white.withValues(alpha: 0.95), tone.ballLight, tone.ball, tone.ballDeep],
            stops: const [0, 0.22, 0.62, 1],
          ),
          boxShadow: [BoxShadow(color: tone.shadow, offset: Offset(-t.dx * 4, size * 0.16), blurRadius: size * 0.25, spreadRadius: -size * 0.12)],
        ),
        child: Icon(
          icon,
          color: Colors.white,
          size: size * 0.52,
          shadows: const [Shadow(color: Color(0x40000000), offset: Offset(0, 2), blurRadius: 3)],
        ),
      ),
    );
  }
}

/// A large home-screen tile that looks raised: it leans with the phone, its
/// shine and shadow move with the light, and it sinks when pressed.
class LitTile extends StatefulWidget {
  const LitTile({super.key, required this.label, required this.tone, required this.onTap, this.icon, this.leading, this.height = 146})
      : assert(icon != null || leading != null);

  final String label;
  final TileTone tone;
  final VoidCallback onTap;
  final IconData? icon;

  /// Shown instead of the glossy ball, e.g. Sathi's live orb.
  final Widget? leading;
  final double height;

  @override
  State<LitTile> createState() => _LitTileState();
}

class _LitTileState extends State<LitTile> {
  bool _pressed = false;

  void _press(bool down) {
    if (_pressed != down) setState(() => _pressed = down);
  }

  @override
  Widget build(BuildContext context) {
    final tone = widget.tone;
    final radius = BorderRadius.circular(30);
    // Taller when the user has chosen larger text, so two lines of label still fit.
    final height = widget.height + (MediaQuery.textScalerOf(context).scale(1) - 1).clamp(0.0, 1.0) * 60;
    final label = FitText(
      widget.label,
      style: TextStyle(fontSize: 21, height: 1.1, fontWeight: FontWeight.w800, color: tone.ink),
    );
    return Semantics(
      button: true,
      label: widget.label,
      excludeSemantics: true,
      onTap: widget.onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _press(true),
        onTapUp: (_) => _press(false),
        onTapCancel: () => _press(false),
        onTap: widget.onTap,
        child: ValueListenableBuilder<Offset>(
          valueListenable: TiltScope.of(context),
          builder: (context, t, child) {
            final face = Container(
              height: height,
              decoration: BoxDecoration(
                borderRadius: radius,
                gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [tone.face, tone.faceDeep]),
                boxShadow: [
                  BoxShadow(
                    color: tone.shadow,
                    offset: _pressed ? const Offset(0, 6) : Offset(-t.dx * 10, 16 - t.dy * 7),
                    blurRadius: _pressed ? 10 : 26,
                    spreadRadius: _pressed ? -8 : -14,
                  ),
                  BoxShadow(color: tone.shadow.withValues(alpha: 0.25), offset: const Offset(0, 2), blurRadius: 5, spreadRadius: -2),
                ],
              ),
              foregroundDecoration: BoxDecoration(
                borderRadius: radius,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.white.withValues(alpha: 0.6), Colors.white.withValues(alpha: 0), Colors.black.withValues(alpha: 0), Colors.black.withValues(alpha: 0.05)],
                  stops: const [0, 0.06, 0.8, 1],
                ),
              ),
              child: Stack(
                children: [
                  // The shine, where the light falls on the tile.
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: radius,
                        gradient: RadialGradient(
                          center: Alignment(-0.45 + t.dx * 0.5, -0.7 + t.dy * 0.4),
                          radius: 1.1,
                          colors: [Colors.white.withValues(alpha: 0.85), Colors.white.withValues(alpha: 0)],
                          stops: const [0, 0.55],
                        ),
                      ),
                    ),
                  ),
                  Padding(padding: const EdgeInsets.all(14), child: child),
                ],
              ),
            );
            return Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.0012)
                ..rotateX(-t.dy * 0.12)
                ..rotateY(t.dx * 0.15),
              child: AnimatedScale(
                scale: _pressed ? 0.97 : 1,
                duration: const Duration(milliseconds: 120),
                child: AnimatedSlide(offset: Offset(0, _pressed ? 0.025 : 0), duration: const Duration(milliseconds: 120), child: face),
              ),
            );
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              widget.leading ?? GlossyBall(icon: widget.icon!, tone: tone),
              label,
            ],
          ),
        ),
      ),
    );
  }
}
