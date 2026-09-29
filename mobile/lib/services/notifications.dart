import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../data/database.dart';
import '../data/repository.dart';

/// Reminders are scheduled on the phone, so they fire with no signal at all.
class ReminderNotifications {
  final _plugin = FlutterLocalNotificationsPlugin();

  static const _channel = AndroidNotificationDetails(
    'reminders',
    'Reminders',
    channelDescription: 'Medicine, meals, water and daily routine reminders',
    importance: Importance.max,
    priority: Priority.high,
    category: AndroidNotificationCategory.reminder,
    fullScreenIntent: false,
  );

  Future<void> init(void Function(String? payload) onTap) async {
    tzdata.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Kolkata')); // all of NER is on IST
    await _plugin.initialize(
      const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
      onDidReceiveNotificationResponse: (r) => onTap(r.payload),
    );
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  /// Stable int id per (reminder, weekday) for the plugin.
  static int _notificationId(String reminderId, int weekday) => (reminderId.hashCode & 0x0fffffff) * 8 + weekday;

  Future<void> rescheduleAll(List<ReminderRow> reminders, String Function(ReminderRow) titleFor) async {
    await _plugin.cancelAll();
    for (final r in reminders.where((r) => r.active && !r.deleted)) {
      final parts = r.timeOfDay.split(':').map(int.parse).toList();
      for (final weekday in daysOf(r)) {
        try {
          await _plugin.zonedSchedule(
            _notificationId(r.id, weekday),
            titleFor(r),
            r.note == null ? r.title : '${r.title} - ${r.note}',
            nextInstance(weekday, parts[0], parts[1], tz.TZDateTime.now(tz.local)),
            const NotificationDetails(android: _channel),
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
            matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
            payload: r.id,
          );
        } catch (e) {
          debugPrint('could not schedule reminder ${r.id}: $e');
        }
      }
    }
  }

  /// Next occurrence of weekday (0 = Monday) at hh:mm, strictly after [now].
  static tz.TZDateTime nextInstance(int weekday, int hour, int minute, tz.TZDateTime now) {
    var at = tz.TZDateTime(now.location, now.year, now.month, now.day, hour, minute);
    while (at.weekday - 1 != weekday || !at.isAfter(now)) {
      at = at.add(const Duration(days: 1));
    }
    return at;
  }
}
