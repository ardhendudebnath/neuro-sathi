import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_sathi/design/fit_text.dart';
import 'package:neuro_sathi/design/lit_tile.dart';
import 'package:neuro_sathi/design/living_hills.dart';
import 'package:neuro_sathi/design/sathi_orb.dart';
import 'package:neuro_sathi/design/sky.dart';
import 'package:neuro_sathi/design/tilt.dart';

void main() {
  test('the sky follows the hour, with evening from 5 PM like the greeting', () {
    expect(DayPart.of(4), DayPart.morning);
    expect(DayPart.of(11), DayPart.morning);
    expect(DayPart.of(12), DayPart.afternoon);
    expect(DayPart.of(16), DayPart.afternoon);
    expect(DayPart.of(17), DayPart.evening);
    expect(DayPart.of(20), DayPart.night);
    expect(DayPart.of(2), DayPart.night);
  });

  test('the greeting stays readable on every sky', () {
    for (final part in DayPart.values) {
      final sky = SkyPalette.of(part);
      // The greeting is large text: WCAG AA asks for 3:1 behind it, and 4.5:1 at the top.
      expect(contrastRatio(sky.ink, sky.behindGreeting), greaterThanOrEqualTo(3), reason: part.name);
      expect(contrastRatio(sky.ink, sky.skyTop), greaterThanOrEqualTo(4.5), reason: part.name);
      expect(sky.darkSky, part == DayPart.evening || part == DayPart.night, reason: part.name);
    }
  });

  test('tilt is zero while the phone rests and never leaves -1 to 1', () {
    expect(tiltFromGravity(const Offset(0.3, 9.6), const Offset(0.3, 9.6)), Offset.zero);
    final far = tiltFromGravity(const Offset(-9, 0), const Offset(9, 9.8));
    expect(far.dx, 1);
    expect(far.dy, -1);
    for (var s = 0.0; s < 60; s += 0.7) {
      final sway = idleSway(s);
      expect(sway.dx.abs(), lessThanOrEqualTo(0.45));
      expect(sway.dy.abs(), lessThanOrEqualTo(0.3));
    }
  });

  testWidgets('labels keep their size when they fit and shrink only as far as needed', (tester) async {
    const style = TextStyle(fontSize: 20);
    expect(fitFontSize('Play', style, maxWidth: 120), 20);
    // One long word cannot wrap, so it shrinks until it fits on its own.
    final shrunk = fitFontSize('Rememberings', style, maxWidth: 200);
    expect(shrunk, lessThan(20));
    expect(shrunk, greaterThanOrEqualTo(13));
    final word = TextPainter(text: TextSpan(text: 'Rememberings', style: style.copyWith(fontSize: shrunk)), textDirection: TextDirection.ltr)..layout();
    expect(word.width, lessThanOrEqualTo(200));
    word.dispose();
    expect(fitFontSize('Rememberingsandmore', style, maxWidth: 60), 13, reason: 'never smaller than the minimum');
  });

  testWidgets('a lit tile shows its label, answers taps and stays a big target', (tester) async {
    var taps = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 170,
            child: LitTile(label: 'Play', icon: Icons.extension_rounded, tone: TileTone.teal, onTap: () => taps++),
          ),
        ),
      ),
    ));
    expect(find.text('Play'), findsOneWidget);
    await tester.tap(find.text('Play'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(taps, 1);
    // Large touch target for elderly users, as before the redesign.
    expect(tester.getSize(find.byType(LitTile)).height, greaterThanOrEqualTo(130));
  });

  testWidgets('the hills and Sathi draw a still picture when animations are off', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: Column(
          children: [
            SizedBox(height: 300, child: LivingHills(palette: SkyPalette.night, animate: false)),
            SathiOrb(size: 120, animate: false),
          ],
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(LivingHills), findsOneWidget);
    expect(find.byType(SathiOrb), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a tile with Sathi inside stays still without a tilt', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 170,
          child: LitTile(label: 'Talk to Sathi', leading: const SathiOrb(size: 68, animate: false), tone: TileTone.violet, onTap: () {}),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(SathiOrb), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
