import '../config.dart';
import '../data/database.dart';
import '../data/repository.dart';
import '../l10n.dart';

// Reminder bookkeeping shared by the app and the background sync worker.

/// Notification title for a reminder.
String reminderTitle(Strings s, ReminderRow r) => r.kind == 'medication' ? s.t('medicine_time') : s.t('reminder');

/// The calendar day a reminder occurrence belongs to, as YYYY-MM-DD.
String occurrenceDate(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';

/// Logs `reminder_missed` for every occurrence that is past the grace window
/// and was not marked done. Feeds routine adherence on the caregiver dashboard.
///
/// Yesterday is checked as well as today, so a late-evening reminder whose
/// grace window ends after midnight is still counted. Each entry is dated at
/// the time the reminder was due, and an occurrence from before the reminder
/// was created or last changed is never counted. Returns how many were logged.
Future<int> logMissedReminders(Repository repo, DateTime now, {Duration grace = AppConfig.reminderGrace}) async {
  var logged = 0;
  final today = DateTime(now.year, now.month, now.day);
  final yesterday = DateTime(now.year, now.month, now.day - 1);
  for (final r in await repo.reminders()) {
    if (!r.active) continue;
    final parts = r.timeOfDay.split(':').map(int.parse).toList();
    for (final day in [yesterday, today]) {
      if (!daysOf(r).contains(day.weekday - 1)) continue;
      final due = DateTime(day.year, day.month, day.day, parts[0], parts[1]);
      if (now.isBefore(due.add(grace)) || due.isBefore(r.updatedAt)) continue;
      final date = occurrenceDate(day);
      bool sameOccurrence(Map<String, dynamic> p) => p['reminder_id'] == r.id && p['date'] == date;
      if (await repo.hasActivity('reminder_done', sameOccurrence, day) ||
          await repo.hasActivity('reminder_missed', sameOccurrence, day)) {
        continue;
      }
      await repo.logActivity('reminder_missed', {'reminder_id': r.id, 'kind': r.kind, 'date': date}, due);
      logged++;
    }
  }
  return logged;
}
