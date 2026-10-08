import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database.dart';
import '../data/repository.dart';
import '../design/fit_text.dart';
import '../design/grow_route.dart';
import '../design/lit_tile.dart';
import '../design/living_hills.dart';
import '../design/sathi_orb.dart';
import '../design/sky.dart';
import '../design/tilt.dart';
import '../services/reminders.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';
import 'games_screen.dart';
import 'login_screen.dart';
import 'memories_screen.dart';
import 'reminders_screen.dart';
import 'sathi_screen.dart';
import 'settings_screen.dart';

const _ground = Color(0xFFEAF2EF);

/// Home: the hills of the North-East at the time of day, the next reminder,
/// and four lit tiles that grow into their screens. Everything that moves stops
/// while another screen is open, and stays still with "Remove animations" on.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> with TickerProviderStateMixin {
  final _tilt = Tilt();
  late DayPart _part = DayPart.of(DateTime.now().hour);
  int _day = DateTime.now().day;
  Timer? _clock;
  bool _away = false;

  /// Reminders marked done today: the next-reminder card skips them and the
  /// progress ring counts them, so the two always agree.
  Set<String> _doneToday = const {};

  @override
  void initState() {
    super.initState();
    _loadDone();
    _clock = Timer.periodic(const Duration(minutes: 1), (_) {
      final now = DateTime.now();
      final part = DayPart.of(now.hour);
      if (part != _part) setState(() => _part = part);
      if (now.day != _day) {
        _day = now.day;
        _loadDone();
      }
    });
  }

  Future<void> _loadDone() async {
    final done = await remindersDoneToday(ref.read(repoProvider), DateTime.now());
    if (mounted) setState(() => _doneToday = done);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncTilt();
  }

  void _syncTilt() {
    if (!_away && !MediaQuery.of(context).disableAnimations) {
      _tilt.start(this);
    } else {
      _tilt.stop();
    }
  }

  @override
  void dispose() {
    _clock?.cancel();
    _tilt.dispose();
    super.dispose();
  }

  /// Opens [screen] growing out of [from]; the hills pause once it covers them.
  Future<void> _open(BuildContext from, Widget screen, {Color color = const Color(0xFFF7F5F0)}) async {
    final route = GrowRoute<void>(origin: GrowRoute.originOf(from), color: color, builder: (_) => screen);
    final closed = Navigator.of(context).push(route);
    void covered(AnimationStatus status) {
      if (status == AnimationStatus.completed && mounted && !_away) {
        setState(() => _away = true);
        _syncTilt();
      }
    }

    route.animation?.addStatusListener(covered);
    await closed;
    route.animation?.removeStatusListener(covered);
    if (!mounted) return;
    setState(() => _away = false);
    _syncTilt();
    _loadDone(); // a reminder may have been marked done meanwhile
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final name = ref.watch(appProvider.select((a) => a.name));
    final online = ref.watch(appProvider.select((a) => a.online));
    final now = DateTime.now();
    final greeting = '${s.greeting(now)}${name == null ? '' : ', $name'}';
    final palette = SkyPalette.of(_part);
    final animate = !MediaQuery.of(context).disableAnimations;
    final padding = MediaQuery.paddingOf(context);
    final grow = (MediaQuery.textScalerOf(context).scale(1) - 1).clamp(0.0, 1.0) * 90;
    final headerHeight = padding.top + 232 + grow;
    final overlay = (palette.darkSky ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark).copyWith(statusBarColor: Colors.transparent);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlay,
      child: Scaffold(
        backgroundColor: _ground,
        body: TickerMode(
          enabled: !_away,
          child: TiltScope(
            tilt: _tilt,
            child: Stack(
              children: [
                Positioned(left: 0, right: 0, top: 0, height: headerHeight + 64, child: LivingHills(palette: palette, animate: animate)),
                ListView(
                  padding: EdgeInsets.fromLTRB(18, padding.top + 6, 18, padding.bottom + 24),
                  children: [
                    ConstrainedBox(
                      constraints: BoxConstraints(minHeight: headerHeight - padding.top - 6),
                      child: _Header(
                        greeting: greeting,
                        day: s.dayName(now.weekday - 1),
                        palette: palette,
                        onSettings: (from) => _open(from, const SettingsScreen()),
                      ),
                    ),
                    _NextReminderCard(done: _doneToday, onOpen: (from) => _open(from, const RemindersScreen())),
                    const _OnTimeRemindersCard(),
                    const _SignInAgainBanner(),
                    if (!online) const Padding(padding: EdgeInsets.only(top: 12), child: ClipRRect(borderRadius: BorderRadius.all(Radius.circular(18)), child: OfflineBanner())),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: Builder(
                            builder: (tile) => LitTile(
                              label: s.t('play'),
                              icon: Icons.extension_rounded,
                              tone: TileTone.teal,
                              onTap: () => _open(tile, const GamesScreen()),
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Builder(
                            builder: (tile) => LitTile(
                              label: s.t('memories'),
                              icon: Icons.auto_stories_rounded,
                              tone: TileTone.amber,
                              onTap: () => _open(tile, const MemoriesScreen()),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: Builder(
                            builder: (tile) => LitTile(
                              label: s.t('reminders'),
                              icon: Icons.alarm_rounded,
                              tone: TileTone.blue,
                              onTap: () => _open(tile, const RemindersScreen()),
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Builder(
                            builder: (tile) => LitTile(
                              label: s.t('talk_to_sathi'),
                              leading: SathiOrb(size: 68, animate: animate && !_away),
                              tone: TileTone.violet,
                              onTap: () => _open(tile, const SathiScreen(), color: SathiScreen.background),
                            ),
                          ),
                        ),
                      ],
                    ),
                    _TodayProgress(done: _doneToday),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// App name, settings, the greeting and today's day name, drawn on the sky.
class _Header extends ConsumerWidget {
  const _Header({required this.greeting, required this.day, required this.palette, required this.onSettings});

  final String greeting;
  final String day;
  final SkyPalette palette;
  final void Function(BuildContext from) onSettings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ink = palette.ink;
    final glow = palette.darkSky
        ? const [Shadow(color: Color(0x73000000), offset: Offset(0, 2), blurRadius: 12)]
        : const [Shadow(color: Color(0xB3FFFFFF), blurRadius: 16), Shadow(color: Color(0xA6FFFFFF), offset: Offset(0, 1), blurRadius: 2)];
    final glass = Colors.white.withValues(alpha: palette.darkSky ? 0.16 : 0.32);
    final rim = Colors.white.withValues(alpha: 0.55);
    final s = ref.watch(stringsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(s.t('app_name'), style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, letterSpacing: 0.6, color: ink, shadows: glow)),
            ),
            Builder(
              builder: (button) => IconButton(
                iconSize: 28,
                tooltip: s.t('settings'),
                onPressed: () => onSettings(button),
                style: IconButton.styleFrom(foregroundColor: ink, backgroundColor: glass, side: BorderSide(color: rim), minimumSize: const Size(52, 52)),
                icon: const Icon(Icons.settings_rounded),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        FitText(greeting, maxLines: 3, minSize: 22, style: TextStyle(fontSize: 32, height: 1.06, fontWeight: FontWeight.w800, color: ink, shadows: glow)),
        const SizedBox(height: 6),
        Row(
          children: [
            Flexible(child: Text(day, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: ink, shadows: glow))),
            const SizedBox(width: 10),
            SpeakButton('$greeting. $day', foreground: ink, background: glass, border: rim),
          ],
        ),
      ],
    );
  }
}

/// A pill capsule, drawn rather than shown as an emoji, for medicine reminders.
class _Capsule extends StatelessWidget {
  const _Capsule();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 60,
      height: 60,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(center: Alignment(-0.3, -0.4), colors: [Colors.white, Color(0xFFFFE4E0)], stops: [0, 0.72]),
        boxShadow: [BoxShadow(color: Color(0x80C83C32), offset: Offset(0, 6), blurRadius: 12, spreadRadius: -8)],
      ),
      alignment: Alignment.center,
      child: Transform.rotate(
        angle: 0.66,
        child: Container(
          width: 20,
          height: 44,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(11),
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFFF7B6E), Color(0xFFFF7B6E), Colors.white, Color(0xFFEDEDED)],
              stops: [0, 0.5, 0.5, 1],
            ),
            boxShadow: const [BoxShadow(color: Color(0x73961E14), offset: Offset(0, 7), blurRadius: 9, spreadRadius: -4)],
          ),
          foregroundDecoration: BoxDecoration(
            borderRadius: BorderRadius.circular(11),
            gradient: LinearGradient(colors: [Colors.white.withValues(alpha: 0.55), Colors.white.withValues(alpha: 0), Colors.black.withValues(alpha: 0.14)], stops: const [0, 0.4, 1]),
          ),
        ),
      ),
    );
  }
}

const _kindIcon = {
  'medication': Icons.medication_rounded,
  'hydration': Icons.water_drop_rounded,
  'meal': Icons.rice_bowl_rounded,
  'activity': Icons.directions_walk_rounded,
  'appointment': Icons.local_hospital_rounded,
  'custom': Icons.star_rounded,
};

class _NextReminderCard extends ConsumerWidget {
  const _NextReminderCard({required this.done, required this.onOpen});

  /// Reminders already marked done today, which are not "next" any more.
  final Set<String> done;
  final void Function(BuildContext from) onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    return StreamBuilder<List<ReminderRow>>(
      stream: ref.watch(repoProvider).watchReminders(),
      builder: (context, snap) {
        final now = DateTime.now();
        final nowMin = now.hour * 60 + now.minute;
        int minutesOf(ReminderRow r) {
          final p = r.timeOfDay.split(':').map(int.parse).toList();
          return p[0] * 60 + p[1];
        }

        final upcoming = (snap.data ?? const <ReminderRow>[])
            .where((r) => r.active && !done.contains(r.id) && daysOf(r).contains(now.weekday - 1) && minutesOf(r) >= nowMin)
            .toList()
          ..sort((a, b) => minutesOf(a).compareTo(minutesOf(b)));
        final next = upcoming.isEmpty ? null : upcoming.first;
        final m = next == null ? 0 : minutesOf(next);
        final when = next == null ? '' : '${s.t('next_reminder')} · ${s.formatTime(m ~/ 60, m % 60)}';
        final title = next == null ? s.t('no_more_today') : next.title;
        final leading = next == null
            ? const GlossyBall(icon: Icons.check_rounded, tone: TileTone.teal, size: 56)
            : next.kind == 'medication'
                ? const _Capsule()
                : GlossyBall(icon: _kindIcon[next.kind] ?? Icons.star_rounded, tone: TileTone.blue, size: 56);
        return Semantics(
          button: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onOpen(context),
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 13, 10, 13),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: Colors.white),
                boxShadow: const [BoxShadow(color: Color(0x990A283C), offset: Offset(0, 22), blurRadius: 34, spreadRadius: -20)],
              ),
              child: Row(
                children: [
                  leading,
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (when.isNotEmpty) Text(when, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF46625C))),
                        Text(title, style: const TextStyle(fontSize: 23, height: 1.12, fontWeight: FontWeight.w800, color: Color(0xFF0E2320))),
                      ],
                    ),
                  ),
                  SpeakButton(when.isEmpty ? title : '$when. $title', foreground: const Color(0xFF0B4A42), background: const Color(0xFFD6F0EA)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// A ring showing how many of today's reminders are done.
class _TodayProgress extends ConsumerWidget {
  const _TodayProgress({required this.done});

  /// Reminders marked done today.
  final Set<String> done;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    return StreamBuilder<List<ReminderRow>>(
      stream: ref.watch(repoProvider).watchReminders(),
      builder: (context, snap) {
        final weekday = DateTime.now().weekday - 1;
        final today = (snap.data ?? const <ReminderRow>[]).where((r) => r.active && daysOf(r).contains(weekday)).toList();
        if (today.isEmpty) return const SizedBox.shrink();
        final total = today.length;
        final finished = today.where((r) => done.contains(r.id)).length;
        return Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white),
              boxShadow: const [BoxShadow(color: Color(0x800A283C), offset: Offset(0, 12), blurRadius: 24, spreadRadius: -18)],
            ),
            child: Row(
              children: [
                SizedBox.square(
                  dimension: 46,
                  child: CircularProgressIndicator(
                    value: finished / total,
                    strokeWidth: 7,
                    strokeCap: StrokeCap.round,
                    backgroundColor: const Color(0xFFD6E6E1),
                    color: const Color(0xFF18A28D),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    '${s.t('reminders')}: ${s.pack.localizeDigits('$finished / $total')}',
                    style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: Color(0xFF10221F)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Android may hold a reminder back by up to an hour unless the app is allowed
/// exact alarms ("Alarms & reminders"), which Android 14 and later leave off.
/// Shown only then, and only when there is a reminder to ring.
class _OnTimeRemindersCard extends ConsumerWidget {
  const _OnTimeRemindersCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(appProvider.select((a) => a.exactAlarms))) return const SizedBox.shrink();
    final s = ref.watch(stringsProvider);
    return StreamBuilder<List<ReminderRow>>(
      stream: ref.watch(repoProvider).watchReminders(),
      builder: (context, snap) {
        if (!(snap.data ?? const <ReminderRow>[]).any((r) => r.active)) return const SizedBox.shrink();
        return _Notice(
          color: const Color(0xFFFFEFD6),
          text: s.t('reminders_may_be_late'),
          action: s.t('ring_on_time'),
          onAction: () => ref.read(appProvider.notifier).allowExactAlarms(),
        );
      },
    );
  }
}

/// Shown when the server has ended the session. The app keeps working with the
/// data on the phone; this only asks the user to verify their number again so
/// their activity reaches their family.
class _SignInAgainBanner extends ConsumerWidget {
  const _SignInAgainBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(appProvider.select((a) => a.sessionExpired))) return const SizedBox.shrink();
    final s = ref.watch(stringsProvider);
    return _Notice(
      color: const Color(0xFFE3F0FF),
      text: s.t('session_expired'),
      action: s.t('sign_in_again'),
      onAction: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const LoginScreen(reauth: true))),
    );
  }
}

/// A rounded notice with a read-aloud button and one action.
class _Notice extends StatelessWidget {
  const _Notice({required this.color, required this.text, required this.action, required this.onAction});

  final Color color;
  final String text;
  final String action;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(22),
          boxShadow: const [BoxShadow(color: Color(0x400A283C), offset: Offset(0, 10), blurRadius: 20, spreadRadius: -14)],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyLarge)),
                SpeakButton(text),
              ],
            ),
            const SizedBox(height: 8),
            FilledButton(onPressed: onAction, child: Text(action)),
          ],
        ),
      ),
    );
  }
}
