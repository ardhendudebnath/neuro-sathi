import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_sathi/services/notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

void main() {
  setUpAll(tzdata.initializeTimeZones);

  test('next instance of a weekly reminder', () {
    final ist = tz.getLocation('Asia/Kolkata');
    final wedNoon = tz.TZDateTime(ist, 2026, 9, 30, 12); // Wednesday
    // Wednesday (2) 8:00 has passed -> next week.
    expect(ReminderNotifications.nextInstance(2, 8, 0, wedNoon), tz.TZDateTime(ist, 2026, 10, 7, 8));
    // Wednesday 20:00 is later today.
    expect(ReminderNotifications.nextInstance(2, 20, 0, wedNoon), tz.TZDateTime(ist, 2026, 9, 30, 20));
    // Friday (4) 9:30.
    expect(ReminderNotifications.nextInstance(4, 9, 30, wedNoon), tz.TZDateTime(ist, 2026, 10, 2, 9, 30));
  });
}
