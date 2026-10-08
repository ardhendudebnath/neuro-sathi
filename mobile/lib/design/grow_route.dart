import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

/// Opens a screen by growing it out of the tile that was tapped, and shrinks it
/// back into the tile on the way out. The growing shape is filled with [color]
/// (the new screen's background) while its content fades in. With animations
/// off it simply fades.
class GrowRoute<T> extends PageRouteBuilder<T> {
  GrowRoute({required WidgetBuilder builder, required Rect origin, Color color = const Color(0xFFF7F5F0)})
      : super(
          transitionDuration: const Duration(milliseconds: 520),
          reverseTransitionDuration: const Duration(milliseconds: 420),
          pageBuilder: (context, animation, secondaryAnimation) => builder(context),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            if (MediaQuery.of(context).disableAnimations) return FadeTransition(opacity: animation, child: child);
            final grow = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
            final fade = CurvedAnimation(parent: animation, curve: const Interval(0.25, 1, curve: Curves.easeOut));
            return AnimatedBuilder(
              animation: grow,
              builder: (context, child) {
                final full = Offset.zero & MediaQuery.sizeOf(context);
                return ClipPath(
                  clipper: _RoundedRectClipper(Rect.lerp(origin, full, grow.value)!, lerpDouble(30, 0, grow.value)!),
                  child: child,
                );
              },
              child: Stack(fit: StackFit.expand, children: [ColoredBox(color: color), FadeTransition(opacity: fade, child: child)]),
            );
          },
        );

  /// Where [context]'s widget is on screen, to grow a route out of it.
  static Rect originOf(BuildContext context) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return Rect.zero;
    return box.localToGlobal(Offset.zero) & box.size;
  }
}

class _RoundedRectClipper extends CustomClipper<Path> {
  _RoundedRectClipper(this.rect, this.radius);

  final Rect rect;
  final double radius;

  @override
  Path getClip(Size size) => Path()..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)));

  @override
  bool shouldReclip(_RoundedRectClipper oldClipper) => oldClipper.rect != rect || oldClipper.radius != radius;
}
