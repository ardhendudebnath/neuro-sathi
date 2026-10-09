import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_sathi/design/celebration.dart';
import 'package:neuro_sathi/design/choice_tile.dart';
import 'package:neuro_sathi/design/raised_button.dart';
import 'package:neuro_sathi/l10n.dart';
import 'package:neuro_sathi/screens/games_screen.dart';
import 'package:neuro_sathi/state/app_state.dart';

import 'packs.dart';

void main() {
  test('every finished game earns at least one star', () {
    expect(starsFor(0, 8), 1);
    expect(starsFor(4, 8), 2);
    expect(starsFor(7, 8), 3);
    expect(starsFor(0, 0), 1);
  });

  testWidgets('a raised button answers taps, stays big, and ignores taps when disabled', (tester) async {
    var taps = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            RaisedButton3D(label: 'Play', onPressed: () => taps++),
            const RaisedButton3D(label: 'Later', onPressed: null),
          ],
        ),
      ),
    ));
    await tester.tap(find.text('Play'));
    await tester.tap(find.text('Later'), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 200));
    expect(taps, 1);
    expect(tester.getSize(find.byType(RaisedButton3D).first).height, greaterThanOrEqualTo(64));
  });

  testWidgets('after an answer the right choice gets a tick', (tester) async {
    Widget tiles(ChoiceState rice, ChoiceState phone) => MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                ChoiceTile(label: 'Rice', state: rice, onTap: () {}),
                ChoiceTile(label: 'Phone', state: phone, onTap: () {}),
              ],
            ),
          ),
        );
    await tester.pumpWidget(tiles(ChoiceState.idle, ChoiceState.idle));
    expect(find.byIcon(Icons.check_rounded), findsNothing);
    await tester.pumpWidget(tiles(ChoiceState.correct, ChoiceState.wrong));
    await tester.pumpAndSettle(); // the wrong pick's shake finishes
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    expect(find.text('Phone'), findsOneWidget);
  });

  testWidgets('the celebration shows the score and finishes the game', (tester) async {
    var finished = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Celebration(title: 'All done!', score: 'You got 7 of 8', stars: 3, action: 'Done', onAction: () => finished = true),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('You got 7 of 8'), findsOneWidget);
    await tester.tap(find.text('Done'));
    expect(finished, isTrue);
  });

  testWidgets('Play shows the games as cards, and the arrows step through them', (tester) async {
    final en = Strings(loadPack('en'));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        stringsProvider.overrideWithValue(en),
        gameListProvider.overrideWith((ref) async => const [
              GameEntry('odd_one_out', 'Odd One Out', 1, 5, suggestedLevel: 2, reason: 'You enjoy this one'),
              GameEntry('name_it', 'Name It', 1, 5),
              GameEntry('my_day', 'My Day in Order', 1, 5),
            ]),
      ],
      child: const MaterialApp(home: GamesScreen()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Odd One Out'), findsOneWidget);
    expect(find.text(en.t('suggested_for_you')), findsOneWidget);

    final pages = tester.widget<PageView>(find.byType(PageView)).controller!;
    expect(pages.page, 0);
    await tester.tap(find.byTooltip(en.t('next')));
    await tester.pumpAndSettle();
    expect(pages.page, 1);
  });
}
