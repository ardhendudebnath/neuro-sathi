import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'fit_text.dart';
import 'lit_tile.dart';

/// How an answer choice looks: waiting to be picked, or after an answer.
enum ChoiceState { idle, correct, wrong, faded }

/// A raised answer tile. After an answer the right one turns green with a
/// tick, a wrong pick turns rose and shakes gently, and the rest fade back.
class ChoiceTile extends StatefulWidget {
  const ChoiceTile({super.key, required this.label, required this.onTap, this.state = ChoiceState.idle, this.big = false, this.minHeight = 76});

  final String label;
  final VoidCallback onTap;
  final ChoiceState state;

  /// A single picture (emoji) shown large instead of words.
  final bool big;
  final double minHeight;

  @override
  State<ChoiceTile> createState() => _ChoiceTileState();
}

class _ChoiceTileState extends State<ChoiceTile> with SingleTickerProviderStateMixin {
  late final _shake = AnimationController(vsync: this, duration: const Duration(milliseconds: 450));
  bool _pressed = false;

  @override
  void didUpdateWidget(ChoiceTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.state == ChoiceState.wrong && oldWidget.state != ChoiceState.wrong && !MediaQuery.of(context).disableAnimations) {
      _shake.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _shake.dispose();
    super.dispose();
  }

  void _press(bool down) {
    if (_pressed != down) setState(() => _pressed = down);
  }

  @override
  Widget build(BuildContext context) {
    final tone = switch (widget.state) {
      ChoiceState.correct => TileTone.green,
      ChoiceState.wrong => TileTone.rose,
      _ => TileTone.plain,
    };
    final radius = BorderRadius.circular(24);
    final text = widget.big
        ? Text(widget.label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 54, height: 1.1))
        : FitText(widget.label, textAlign: TextAlign.center, maxLines: 3, style: TextStyle(fontSize: 24, height: 1.15, fontWeight: FontWeight.w700, color: tone.ink));
    final face = AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      constraints: BoxConstraints(minHeight: widget.minHeight),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: radius,
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [tone.face, tone.faceDeep]),
        border: Border.all(color: widget.state == ChoiceState.idle ? const Color(0xFFD3E2DD) : tone.ball.withValues(alpha: 0.6), width: 2),
        boxShadow: [
          BoxShadow(color: tone.shadow, offset: Offset(0, _pressed ? 3 : 12), blurRadius: _pressed ? 6 : 20, spreadRadius: _pressed ? -6 : -12),
        ],
      ),
      child: text,
    );
    final tile = Stack(
      clipBehavior: Clip.none,
      children: [
        face,
        if (widget.state == ChoiceState.correct)
          // Inside the corner, so a scrolling grid never clips it at its edge.
          const Positioned(top: -10, right: 6, child: GlossyBall(icon: Icons.check_rounded, tone: TileTone.green, size: 40)),
      ],
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
        child: AnimatedOpacity(
          opacity: widget.state == ChoiceState.faded ? 0.55 : 1,
          duration: const Duration(milliseconds: 220),
          child: AnimatedBuilder(
            animation: _shake,
            builder: (context, child) {
              final t = _shake.value;
              final dx = t == 0 || t == 1 ? 0.0 : math.sin(t * math.pi * 6) * (1 - t) * 9;
              return Transform.translate(offset: Offset(dx, 0), child: child);
            },
            child: AnimatedScale(scale: _pressed ? 0.97 : 1, duration: const Duration(milliseconds: 110), child: tile),
          ),
        ),
      ),
    );
  }
}
