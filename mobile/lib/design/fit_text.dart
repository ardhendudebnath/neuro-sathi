import 'package:flutter/widgets.dart';

/// The largest font size, from [style]'s size down to [minSize], at which
/// [text] fits [maxWidth] in at most [maxLines] lines without breaking a word.
/// Long single words (Bodo गोसोखांहोनायफोर) shrink instead of being cut.
double fitFontSize(
  String text,
  TextStyle style, {
  required double maxWidth,
  int maxLines = 2,
  double minSize = 13,
  TextScaler textScaler = TextScaler.noScaling,
  TextDirection textDirection = TextDirection.ltr,
}) {
  var size = style.fontSize ?? 14;
  final words = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  bool fits(double s) {
    final sized = style.copyWith(fontSize: s);
    for (final word in words) {
      final p = TextPainter(text: TextSpan(text: word, style: sized), textDirection: textDirection, textScaler: textScaler)..layout();
      final tooWide = p.width > maxWidth;
      p.dispose();
      if (tooWide) return false;
    }
    final all = TextPainter(text: TextSpan(text: text, style: sized), textDirection: textDirection, textScaler: textScaler, maxLines: maxLines)
      ..layout(maxWidth: maxWidth);
    final overflow = all.didExceedMaxLines;
    all.dispose();
    return !overflow;
  }

  while (size > minSize && !fits(size)) {
    size -= 1;
  }
  return size < minSize ? minSize : size;
}

/// Text that keeps its size when it fits and shrinks just enough when it doesn't.
class FitText extends StatelessWidget {
  const FitText(this.text, {super.key, required this.style, this.maxLines = 2, this.minSize = 13, this.textAlign = TextAlign.start});

  final String text;
  final TextStyle style;
  final int maxLines;
  final double minSize;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = fitFontSize(
          text,
          style,
          maxWidth: constraints.maxWidth,
          maxLines: maxLines,
          minSize: minSize,
          textScaler: MediaQuery.textScalerOf(context),
          textDirection: Directionality.of(context),
        );
        return Text(text, style: style.copyWith(fontSize: size), maxLines: maxLines, textAlign: textAlign, overflow: TextOverflow.ellipsis);
      },
    );
  }
}
