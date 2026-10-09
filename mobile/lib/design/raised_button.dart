import 'package:flutter/material.dart';

import 'fit_text.dart';

/// Colors for a [RaisedButton3D]: its face from [top] to [bottom], the [lip]
/// it stands on, and the [ink] of its label.
class ButtonTone {
  const ButtonTone({required this.top, required this.bottom, required this.lip, required this.ink});

  final Color top;
  final Color bottom;
  final Color lip;
  final Color ink;

  /// The main action on a screen.
  static const go = ButtonTone(top: Color(0xFF25B5A0), bottom: Color(0xFF0F6E66), lip: Color(0xFF0A4F49), ink: Colors.white);

  /// A quieter action beside the main one.
  static const soft = ButtonTone(top: Colors.white, bottom: Color(0xFFECF2F0), lip: Color(0xFFC7D7D2), ink: Color(0xFF0B4A42));
}

/// A big button that stands on a lip and sinks onto it when pressed, like a
/// real one. At least 64 dp tall, so it is easy to hit.
class RaisedButton3D extends StatefulWidget {
  const RaisedButton3D({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.tone = ButtonTone.go,
    this.height = 64,
    this.fontSize = 22,
  });

  final String label;

  /// Null shows the button faded and ignores taps.
  final VoidCallback? onPressed;
  final IconData? icon;
  final ButtonTone tone;
  final double height;
  final double fontSize;

  @override
  State<RaisedButton3D> createState() => _RaisedButton3DState();
}

class _RaisedButton3DState extends State<RaisedButton3D> {
  static const _lip = 6.0;
  bool _down = false;

  void _press(bool down) {
    if (_down != down) setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) {
    final tone = widget.tone;
    final enabled = widget.onPressed != null;
    final sink = _down ? _lip - 1 : 0.0;
    final radius = BorderRadius.circular(widget.height / 3);
    final label = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.icon != null) ...[Icon(widget.icon, color: tone.ink, size: widget.fontSize * 1.3), const SizedBox(width: 10)],
        Flexible(
          child: FitText(
            widget.label,
            maxLines: 2,
            minSize: 16,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: widget.fontSize, height: 1.1, fontWeight: FontWeight.w800, color: tone.ink),
          ),
        ),
      ],
    );
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      excludeSemantics: true,
      onTap: widget.onPressed,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => _press(true) : null,
        onTapUp: enabled ? (_) => _press(false) : null,
        onTapCancel: () => _press(false),
        onTap: widget.onPressed,
        child: Opacity(
          opacity: enabled ? 1 : 0.5,
          child: Padding(
            padding: const EdgeInsets.only(bottom: _lip),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 110),
              constraints: BoxConstraints(minHeight: widget.height),
              transform: Matrix4.translationValues(0, sink, 0),
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: radius,
                gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [tone.top, tone.bottom]),
                boxShadow: [
                  BoxShadow(color: tone.lip, offset: Offset(0, _lip - sink)),
                  BoxShadow(color: tone.lip.withValues(alpha: 0.45), offset: Offset(0, _lip - sink + 10), blurRadius: 22, spreadRadius: -10),
                ],
              ),
              foregroundDecoration: BoxDecoration(
                borderRadius: radius,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.white.withValues(alpha: 0.35), Colors.white.withValues(alpha: 0)],
                  stops: const [0, 0.35],
                ),
              ),
              child: label,
            ),
          ),
        ),
      ),
    );
  }
}
