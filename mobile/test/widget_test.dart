import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_sathi/widgets/common.dart';

void main() {
  testWidgets('BigTile shows its label and responds to taps', (tester) async {
    var taps = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: BigTile(emoji: '🧩', label: 'Play', onTap: () => taps++)),
    ));
    expect(find.text('Play'), findsOneWidget);
    await tester.tap(find.text('Play'));
    expect(taps, 1);
    // Large touch target for elderly users.
    expect(tester.getSize(find.byType(BigTile)).height, greaterThanOrEqualTo(130));
  });
}
