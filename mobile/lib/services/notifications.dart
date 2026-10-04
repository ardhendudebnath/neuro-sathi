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

  /// [requestPermission] is false in the background sync worker: asking for the
  /// notification permission needs a screen, and the app has already asked.
  Future<void> init(void Function(String? payload) onTap, {bool requestPermission = true}) async {
    tzdata.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Kolkata')); // all of NER is on IST
    await _plugin.initialize(
      const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
      onDidReceiveNotificationResponse: (r) => onTap(r.payload),
    );
    if (requestPermission) await _android?.requestNotificationsPermission();
  }

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  /// Whether reminders can ring at the exact minute. Without it Android may hold
  /// a reminder back by up to an hour to save battery. Android 14 and later keep
  /// it off until the user allows "Alarms & reminders" for the app.
  Future<bool> exactAlarmsAllowed() async {
    try {
      return await _android?.canScheduleExactNotifications() ?? false;
    } on Object {
      return false;
    }
  }

  /// Opens Android's "Alarms & reminders" setting for this app. The user may
  /// answer there or later: check [exactAlarmsAllowed] when the app is back.
  Future<void> requestExactAlarms() async {
    try {
      await _android?.requestExactAlarmsPermission();
    } on Object catch (e) {
      debugPrint('could not open the alarms setting: $e');
    }
  }

  static AndroidScheduleMode scheduleMode({required bool exact}) =>
      exact ? AndroidScheduleMode.exactAllowWhileIdle : AndroidScheduleMode.inexactAllowWhileIdle;

  /// Stable int id per (reminder, weekday) for the plugin.
  static int _notificationId(String reminderId, int weekday) => (reminderId.hashCode & 0x0fffffff) * 8 + weekday;

  Future<void> rescheduleAll(List<ReminderRow> reminders, String Function(ReminderRow) titleFor) async {
    final mode = scheduleMode(exact: await exactAlarmsAllowed());
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
            androidScheduleMode: mode,
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
