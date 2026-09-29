import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database.dart';
import '../games/trials.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';
import 'game_play_screen.dart';
import 'quick_tap_screen.dart';

// Shown before the first content sync so the games work on day one, offline.
const _builtInGames = [
  ('photo_recall', 'Who Is This?', 1, 5),
  ('market_list', 'Market List', 1, 5),
  ('odd_one_out', 'Odd One Out', 1, 5),
  ('gamosa_patterns', 'Weaving Patterns', 1, 5),
  ('name_it', 'Name It', 1, 5),
  ('quick_tap', 'Quick Tap', 1, 5),
  ('my_day', 'My Day in Order', 1, 5),
];

class GameEntry {
  const GameEntry(this.slug, this.name, this.minLevel, this.maxLevel, {this.suggestedLevel, this.reason});
  final String slug;
  final String name;
  final int minLevel;
  final int maxLevel;
  final int? suggestedLevel;
  final String? reason;
}

final gameListProvider = FutureProvider.autoDispose<List<GameEntry>>((ref) async {
  final repo = ref.watch(repoProvider);
  final List<GameRow> games = await repo.games();
  final recs = {for (final r in await repo.recommendations()) r.gameSlug: r};
  final base = games.isEmpty
      ? _builtInGames.map((g) => GameEntry(g.$1, g.$2, g.$3, g.$4))
      : games.map((g) => GameEntry(g.slug, g.name, g.minLevel, g.maxLevel));
  final list = base
      .map((g) => GameEntry(g.slug, g.name, g.minLevel, g.maxLevel,
          suggestedLevel: recs[g.slug]?.level, reason: recs[g.slug]?.reason))
      .toList()
    ..sort((a, b) => (recs[a.slug]?.rank ?? 99).compareTo(recs[b.slug]?.rank ?? 99));
  return list;
});

class GamesScreen extends ConsumerWidget {
  const GamesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final games = ref.watch(gameListProvider);
    return Scaffold(
      appBar: AppBar(title: Text(s.t('play'))),
      body: Column(
        children: [
          const OfflineBanner(),
          Expanded(
            child: games.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('$e')),
              data: (list) => ListView.separated(
                padding: const EdgeInsets.all(20),
                itemCount: list.length,
                separatorBuilder: (_, _) => const SizedBox(height: 14),
                itemBuilder: (context, i) {
                  final g = list[i];
                  return Card(
                    elevation: 0,
                    color: i < 2 ? Theme.of(context).colorScheme.primaryContainer : Theme.of(context).colorScheme.surfaceContainerHigh,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () async {
                        await Navigator.of(context).push(MaterialPageRoute<void>(
                          builder: (_) => g.slug == 'quick_tap' ? QuickTapScreen(game: g) : GamePlayScreen(game: g),
                        ));
                        ref.invalidate(gameListProvider);
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Row(
                          children: [
                            Text(gameIcons[g.slug] ?? '🎲', style: const TextStyle(fontSize: 44)),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(g.name, style: Theme.of(context).textTheme.titleLarge),
                                  if (i < 2 && g.reason != null)
                                    Text('${s.t('suggested_for_you')} · ${g.reason}', style: Theme.of(context).textTheme.bodyMedium),
                                ],
                              ),
                            ),
                            const Icon(Icons.play_circle_fill_rounded, size: 48),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
