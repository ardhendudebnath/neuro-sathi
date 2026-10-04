import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database.dart';
import '../data/repository.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';
import 'games_screen.dart';
import 'login_screen.dart';
import 'memories_screen.dart';
import 'reminders_screen.dart';
import 'sathi_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  void _open(BuildContext context, Widget screen) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final name = ref.watch(appProvider.select((a) => a.name));
    final greeting = '${s.greeting(DateTime.now())}${name == null ? '' : ', $name'}';
    return Scaffold(
      appBar: AppBar(
        title: Text(s.t('app_name')),
        actions: [
          IconButton(
            iconSize: 32,
            tooltip: s.t('settings'),
            icon: const Icon(Icons.settings_rounded),
            onPressed: () => _open(context, const SettingsScreen()),
          ),
        ],
      ),
      body: Column(
        children: [
          const OfflineBanner(),
          const _SignInAgainBanner(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Row(
                  children: [
                    Expanded(child: Text(greeting, style: Theme.of(context).textTheme.headlineMedium)),
                    SpeakButton(greeting),
                  ],
                ),
                const SizedBox(height: 16),
                const _NextReminderCard(),
                const _OnTimeRemindersCard(),
                const SizedBox(height: 20),
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                  childAspectRatio: 0.95,
                  children: [
                    BigTile(emoji: '🧩', label: s.t('play'), onTap: () => _open(context, const GamesScreen())),
                    BigTile(
                      emoji: '📖',
                      label: s.t('memories'),
                      color: const Color(0xFFFFE8CC),
                      onTap: () => _open(context, const MemoriesScreen()),
                    ),
                    BigTile(
                      emoji: '⏰',
                      label: s.t('reminders'),
                      color: const Color(0xFFE3F0FF),
                      onTap: () => _open(context, const RemindersScreen()),
                    ),
                    BigTile(
                      emoji: '💬',
                      label: s.t('talk_to_sathi'),
                      color: const Color(0xFFEDE3FF),
                      onTap: () => _open(context, const SathiScreen()),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NextReminderCard extends ConsumerWidget {
  const _NextReminderCard();

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
            .where((r) => r.active && daysOf(r).contains(now.weekday - 1) && minutesOf(r) >= nowMin)
            .toList()
          ..sort((a, b) => minutesOf(a).compareTo(minutesOf(b)));
        final String text;
        if (upcoming.isEmpty) {
          text = s.t('no_more_today');
        } else {
          final m = minutesOf(upcoming.first);
          text = '${s.t('next_reminder')}: ${s.formatTime(m ~/ 60, m % 60)} · ${upcoming.first.title}';
        }
        return Card(
          elevation: 0,
          color: Theme.of(context).colorScheme.secondaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                const Text('⏰', style: TextStyle(fontSize: 32)),
                const SizedBox(width: 14),
                Expanded(child: Text(text, style: Theme.of(context).textTheme.titleLarge)),
                SpeakButton(text),
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
        return Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Card(
            elevation: 0,
            color: const Color(0xFFFFEFD6),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(s.t('reminders_may_be_late'), style: Theme.of(context).textTheme.bodyLarge)),
                      SpeakButton(s.t('reminders_may_be_late')),
                    ],
                  ),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: () => ref.read(appProvider.notifier).allowExactAlarms(),
                    child: Text(s.t('ring_on_time')),
                  ),
                ],
              ),
            ),
          ),
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
    return Container(
      width: double.infinity,
      color: const Color(0xFFE3F0FF),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(s.t('session_expired'), style: Theme.of(context).textTheme.bodyLarge)),
              SpeakButton(s.t('session_expired')),
            ],
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const LoginScreen(reauth: true)),
            ),
            child: Text(s.t('sign_in_again')),
          ),
        ],
      ),
    );
  }
}
