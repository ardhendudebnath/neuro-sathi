import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_sathi/services/sathi_local.dart';

void main() {
  final wednesday10am = DateTime(2026, 9, 30, 10, 0);
  const reminders = [
    LocalReminder('Metformin', 'medication', 8, 0, [0, 1, 2, 3, 4, 5, 6]),
    LocalReminder('Amlodipine', 'medication', 20, 0, [0, 1, 2, 3, 4, 5, 6]),
    LocalReminder('Walk', 'activity', 17, 0, [0, 1, 2, 3, 4, 5, 6]),
    LocalReminder('Weekend market', 'activity', 18, 0, [5, 6]),
  ];
  const people = [
    LocalPerson(title: 'Rina', name: 'Rina', relationship: 'granddaughter', description: 'She lives in Guwahati.'),
    LocalPerson(title: 'Bipul', name: 'Bipul', relationship: 'son'),
  ];

  test('next medicine later today', () {
    expect(answerLocally('when is my medicine?', 'en', reminders, people, wednesday10am), 'Your next medicine is Amlodipine at 8:00 PM.');
  });

  test('next medicine rolls over to tomorrow', () {
    final late = DateTime(2026, 9, 30, 21, 0);
    expect(answerLocally('which tablet next', 'en', reminders, people, late), contains('Metformin at 8:00 AM, Thursday'));
  });

  test('who is uses the memory book', () {
    expect(answerLocally('Who is Rina?', 'en', reminders, people, wednesday10am), 'Rina is your granddaughter. She lives in Guwahati.');
    expect(answerLocally('who is my son', 'en', reminders, people, wednesday10am), 'Bipul is your son.');
  });

  test("today's plan lists only remaining items for today", () {
    final a = answerLocally('what is my plan for today', 'en', reminders, people, wednesday10am)!;
    expect(a, contains('Walk'));
    expect(a, isNot(contains('Metformin')));
    expect(a, isNot(contains('Weekend')));
  });

  test('Hindi questions', () {
    expect(answerLocally('मेरी दवा कब है?', 'hi', reminders, people, wednesday10am), contains('Amlodipine'));
    const hiPeople = [LocalPerson(title: 'रीना', name: 'रीना', relationship: 'पोती')];
    expect(answerLocally('रीना कौन है?', 'hi', reminders, hiPeople, wednesday10am), contains('रीना'));
  });

  test('other questions go online', () {
    expect(answerLocally('Tell me about Majuli', 'en', reminders, people, wednesday10am), isNull);
  });

  test('time format', () {
    expect(formatTime(0, 5), '12:05 AM');
    expect(formatTime(12, 0), '12:00 PM');
    expect(formatTime(20, 30), '8:30 PM');
  });
}
