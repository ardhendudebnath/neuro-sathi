import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database.dart';
import '../design/fit_text.dart';
import '../design/grow_route.dart';
import '../design/lit_tile.dart';
import '../design/raised_button.dart';
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

/// The ground under the Play screens, and the soft light falling on it from above.
const playGround = Color(0xFFEAF2EF);
const playBackdrop = BoxDecoration(
  gradient: RadialGradient(
    center: Alignment(0, -1),
    radius: 1.4,
    colors: [Colors.white, Color(0xFFEEF6F3), Color(0xFFE1ECE8)],
    stops: [0, 0.5, 1],
  ),
);

/// The icon and colors of each game's card.
const _looks = <String, (IconData, TileTone)>{
  'photo_recall': (Icons.face_rounded, TileTone.violet),
  'market_list': (Icons.shopping_basket_rounded, TileTone.amber),
  'odd_one_out': (Icons.category_rounded, TileTone.teal),
  'gamosa_patterns': (Icons.texture_rounded, TileTone.blue),
  'name_it': (Icons.record_voice_over_rounded, TileTone.rose),
  'quick_tap': (Icons.touch_app_rounded, TileTone.amber),
  'my_day': (Icons.schedule_rounded, TileTone.teal),
};

(IconData, TileTone) gameLook(String slug) => _looks[slug] ?? (Icons.extension_rounded, TileTone.blue);

/// Play: the games as a row of 3D cards to swipe through, or step through with
/// the large arrows. The chosen card grows into its game.
class GamesScreen extends ConsumerWidget {
  const GamesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final games = ref.watch(gameListProvider);
    return Scaffold(
      backgroundColor: playGround,
      extendBodyBehindAppBar: true,
      appBar: AppBar(title: Text(s.t('play')), backgroundColor: Colors.transparent, surfaceTintColor: Colors.transparent),
      body: DecoratedBox(
        decoration: playBackdrop,
        child: SafeArea(
          child: Column(
            children: [
              const OfflineBanner(),
              Expanded(
                child: games.when(
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(child: Text('$e')),
                  data: (list) => _GameCarousel(games: list),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GameCarousel extends ConsumerStatefulWidget {
  const _GameCarousel({required this.games});

  final List<GameEntry> games;

  @override
  ConsumerState<_GameCarousel> createState() => _GameCarouselState();
}

class _GameCarouselState extends ConsumerState<_GameCarousel> {
  final _pages = PageController(viewportFraction: 0.68);
  final _cards = <int, GlobalKey>{};
  int _current = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _goTo(int i) {
    if (i < 0 || i >= widget.games.length) return;
    if (MediaQuery.of(context).disableAnimations) {
      _pages.jumpToPage(i);
    } else {
      _pages.animateToPage(i, duration: const Duration(milliseconds: 420), curve: Curves.easeOutCubic);
    }
  }

  Future<void> _play(int i) async {
    final g = widget.games[i];
    final card = _cards[i]?.currentContext;
    await Navigator.of(context).push(GrowRoute<void>(
      origin: card == null ? Rect.zero : GrowRoute.originOf(card),
      color: playGround,
      builder: (_) => g.slug == 'quick_tap' ? QuickTapScreen(game: g) : GamePlayScreen(game: g),
    ));
    if (!mounted) return;
    ref.invalidate(gameListProvider); // levels and suggestions may have changed
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final games = widget.games;
    if (games.isEmpty) return const SizedBox.shrink();
    final current = _current.clamp(0, games.length - 1).toInt();
    final name = s.gameName(games[current].slug, games[current].name);
    return Column(
      children: [
        Expanded(
          child: PageView.builder(
            controller: _pages,
            itemCount: games.length,
            onPageChanged: (i) => setState(() => _current = i),
            itemBuilder: (context, i) {
              final g = games[i];
              return AnimatedBuilder(
                animation: _pages,
                builder: (context, child) {
                  final page = _pages.hasClients && _pages.position.haveDimensions ? (_pages.page ?? current.toDouble()) : current.toDouble();
                  final offset = (i - page).clamp(-1.5, 1.5).toDouble();
                  final depth = offset.abs();
                  final card = Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()
                      ..setEntry(3, 2, 0.0014)
                      ..rotateY(-offset * 0.55),
                    child: Transform.scale(scale: 1 - depth * 0.12, child: child),
                  );
                  return depth < 0.01 ? card : Opacity(opacity: (1 - depth * 0.35).clamp(0.0, 1.0).toDouble(), child: card);
                },
                child: _GameCard(
                  key: _cards.putIfAbsent(i, GlobalKey.new),
                  name: s.gameName(g.slug, g.name),
                  look: gameLook(g.slug),
                  badge: i < 2 && g.reason != null ? s.t('suggested_for_you') : null,
                  // Recommendation reasons come from the server in English.
                  reason: i < 2 && s.language == 'en' ? g.reason : null,
                  onTap: () => i == current ? _play(i) : _goTo(i),
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _Arrow(icon: Icons.chevron_left_rounded, tooltip: s.t('back'), onPressed: current > 0 ? () => _goTo(current - 1) : null),
              const SizedBox(width: 14),
              Flexible(
                child: Wrap(
                  alignment: WrapAlignment.center,
                  children: [
                    for (var i = 0; i < games.length; i++)
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        width: i == current ? 22 : 10,
                        height: 10,
                        margin: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(5),
                          color: i == current ? const Color(0xFF18A28D) : const Color(0xFFBFD3CD),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              _Arrow(icon: Icons.chevron_right_rounded, tooltip: s.t('next'), onPressed: current < games.length - 1 ? () => _goTo(current + 1) : null),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: Row(
            children: [
              Expanded(child: RaisedButton3D(label: s.t('play'), icon: Icons.play_arrow_rounded, onPressed: () => _play(current))),
              const SizedBox(width: 12),
              Padding(padding: const EdgeInsets.only(bottom: 6), child: SpeakButton(name)),
            ],
          ),
        ),
      ],
    );
  }
}

/// One game: a lit card with its glossy icon ball and name.
class _GameCard extends StatelessWidget {
  const _GameCard({super.key, required this.name, required this.look, required this.onTap, this.badge, this.reason});

  final String name;
  final (IconData, TileTone) look;
  final VoidCallback onTap;
  final String? badge;
  final String? reason;

  @override
  Widget build(BuildContext context) {
    final (icon, tone) = look;
    final radius = BorderRadius.circular(34);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 18),
      child: Semantics(
        button: true,
        label: name,
        excludeSemantics: true,
        onTap: onTap,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 22),
            decoration: BoxDecoration(
              borderRadius: radius,
              gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [tone.face, tone.faceDeep]),
              boxShadow: [BoxShadow(color: tone.shadow, offset: const Offset(0, 24), blurRadius: 34, spreadRadius: -20)],
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
            child: Column(
              children: [
                if (badge != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.85), borderRadius: BorderRadius.circular(999)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.star_rounded, size: 18, color: Color(0xFFF0A21E)),
                        const SizedBox(width: 4),
                        Flexible(child: Text(badge!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: tone.ink))),
                      ],
                    ),
                  ),
                const Spacer(),
                GlossyBall(icon: icon, tone: tone, size: 112),
                const SizedBox(height: 22),
                FitText(name, textAlign: TextAlign.center, minSize: 18, style: TextStyle(fontSize: 28, height: 1.1, fontWeight: FontWeight.w800, color: tone.ink)),
                if (reason != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    reason!,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: tone.ink.withValues(alpha: 0.75)),
                  ),
                ],
                const Spacer(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A large round arrow for stepping through the games without swiping.
class _Arrow extends StatelessWidget {
  const _Arrow({required this.icon, required this.tooltip, required this.onPressed});

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon),
      iconSize: 34,
      tooltip: tooltip,
      onPressed: onPressed,
      style: IconButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF0B4A42),
        disabledBackgroundColor: Colors.white.withValues(alpha: 0.5),
        minimumSize: const Size(58, 58),
        elevation: 3,
        shadowColor: const Color(0x660A283C),
      ),
    );
  }
}
