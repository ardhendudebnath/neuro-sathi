import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database.dart';
import '../data/repository.dart';
import '../services/sathi_local.dart' show formatTime;
import '../state/app_state.dart';
import '../widgets/common.dart';
import 'games_screen.dart';
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
          text = '${s.t('next_reminder')}: ${formatTime(m ~/ 60, m % 60)} · ${upcoming.first.title}';
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
