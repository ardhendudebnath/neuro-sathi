import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database.dart';
import '../data/repository.dart';
import '../services/reminders.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';

const _kindEmoji = {'medication': '💊', 'hydration': '💧', 'meal': '🍚', 'activity': '🚶', 'appointment': '🏥', 'custom': '⭐'};

/// Today's reminders, set by the user's caregiver. "Done" is logged for
/// routine-adherence trends; the phone schedules the alarms itself.
class RemindersScreen extends ConsumerStatefulWidget {
  const RemindersScreen({super.key});

  @override
  ConsumerState<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends ConsumerState<RemindersScreen> {
  final Set<String> _doneToday = {};

  @override
  void initState() {
    super.initState();
    _loadDone();
  }

  Future<void> _loadDone() async {
    final repo = ref.read(repoProvider);
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final date = occurrenceDate(start);
    final done = <String>{};
    for (final r in await repo.reminders()) {
      if (await repo.hasActivity('reminder_done', (p) => p['reminder_id'] == r.id && p['date'] == date, start)) done.add(r.id);
    }
    if (mounted) setState(() => _doneToday.addAll(done));
  }

  Future<void> _markDone(ReminderRow r) async {
    // The date ties this to today's occurrence, so it is not also logged as missed.
    final date = occurrenceDate(DateTime.now());
    await ref.read(repoProvider).logActivity('reminder_done', {'reminder_id': r.id, 'kind': r.kind, 'date': date});
    setState(() => _doneToday.add(r.id));
    ref.read(voiceProvider).speak(ref.read(stringsProvider).t('well_done'));
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final today = DateTime.now().weekday - 1;
    return Scaffold(
      appBar: AppBar(title: Text(s.t('reminders'))),
      body: Column(
        children: [
          const OfflineBanner(),
          Expanded(
            child: StreamBuilder<List<ReminderRow>>(
              stream: ref.watch(repoProvider).watchReminders(),
              builder: (context, snap) {
                final items = (snap.data ?? const <ReminderRow>[]).where((r) => r.active && daysOf(r).contains(today)).toList();
                if (items.isEmpty) {
                  return Center(child: Text(s.t('no_more_today'), style: Theme.of(context).textTheme.titleLarge));
                }
                return ListView.separated(
                  padding: const EdgeInsets.all(20),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 14),
                  itemBuilder: (context, i) {
                    final r = items[i];
                    final p = r.timeOfDay.split(':').map(int.parse).toList();
                    final when = s.formatTime(p[0], p[1]);
                    final done = _doneToday.contains(r.id);
                    final prompt = s.voice(r.kind == 'medication' ? 'reminder_medication' : 'reminder_generic', {'title': r.title});
                    final spoken = '$when. $prompt${r.note == null ? '' : ' ${r.note}'}';
                    return Card(
                      elevation: 0,
                      color: done ? const Color(0xFFE3F4E8) : Theme.of(context).colorScheme.surfaceContainerHigh,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Text(_kindEmoji[r.kind] ?? '⭐', style: const TextStyle(fontSize: 40)),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(when, style: Theme.of(context).textTheme.titleLarge),
                                      Text(r.title, style: Theme.of(context).textTheme.headlineMedium),
                                      if (r.note != null) Text(r.note!, style: Theme.of(context).textTheme.bodyLarge),
                                    ],
                                  ),
                                ),
                                SpeakButton(spoken),
                              ],
                            ),
                            const SizedBox(height: 12),
                            done
                                ? Text('✅ ${s.t('done')}', style: Theme.of(context).textTheme.titleLarge)
                                : FilledButton(onPressed: () => _markDone(r), child: Text(s.t('mark_done'))),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
