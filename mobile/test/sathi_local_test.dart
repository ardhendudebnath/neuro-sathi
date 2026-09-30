import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_sathi/services/sathi_local.dart';

import 'packs.dart';

void main() {
  final en = loadPack('en');
  final hi = loadPack('hi');
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

  String? ask(String q, [DateTime? now]) => answerLocally(q, en, en, reminders, people, now ?? wednesday10am);

  test('next medicine later today', () {
    expect(ask('when is my medicine?'), 'Your next medicine is Amlodipine at 8:00 PM.');
  });

  test('next medicine rolls over to tomorrow', () {
    expect(ask('which tablet next', DateTime(2026, 9, 30, 21, 0)), contains('Metformin at 8:00 AM, Thursday'));
  });

  test('who is uses the memory book', () {
    expect(ask('Who is Rina?'), 'Rina is your granddaughter. She lives in Guwahati.');
    expect(ask('who is my son'), 'Bipul is your son.');
  });

  test("today's plan lists only remaining items for today", () {
    final a = ask('what is my plan for today')!;
    expect(a, contains('Walk'));
    expect(a, isNot(contains('Metformin')));
    expect(a, isNot(contains('Weekend')));
  });

  test('Hindi questions', () {
    expect(answerLocally('मेरी दवा कब है?', hi, en, reminders, people, wednesday10am), contains('Amlodipine'));
    const hiPeople = [LocalPerson(title: 'रीना', name: 'रीना', relationship: 'पोती')];
    expect(answerLocally('रीना कौन है?', hi, en, reminders, hiPeople, wednesday10am), contains('रीना'));
  });

  test('Hindi "which day" is a time question, not a who question', () {
    expect(answerLocally('आज कौन सा दिन है?', hi, en, reminders, people, wednesday10am), contains('बुधवार'));
  });

  test('Assamese, Bengali and Nepali answers match the server', () {
    const med = [LocalReminder('Metformin', 'medication', 20, 0, [0, 1, 2, 3, 4, 5, 6])];
    expect(answerLocally('মোৰ ঔষধ কেতিয়া?', loadPack('as'), en, med, const [], wednesday10am),
        'আপোনাৰ পৰৱৰ্তী ঔষধ Metformin, ৰাতি ৮:০০ বজাত।');
    const nati = [LocalPerson(title: 'Rina', name: 'Rina', relationship: 'নাতনি')];
    expect(answerLocally('Rina কে?', loadPack('bn'), en, const [], nati, wednesday10am), 'Rina আপনার নাতনি।');
    expect(answerLocally('अहिले कति बज्यो?', loadPack('ne'), en, const [], const [], wednesday10am),
        'अहिले बुधबार, बिहान १०:०० बज्यो।');
  });

  test('other questions go online', () {
    expect(ask('Tell me about Majuli'), isNull);
  });

  test('offline fallback is in the user language', () {
    expect(fallbackAnswer(loadPack('bn'), en), startsWith('আমি আপনার সঙ্গে আছি।'));
  });

  test('English time format', () {
    expect(formatTime(0, 5), '12:05 AM');
    expect(formatTime(12, 0), '12:00 PM');
    expect(formatTime(20, 30), '8:30 PM');
  });
}
