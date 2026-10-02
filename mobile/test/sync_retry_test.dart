import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_sathi/data/sync_retry.dart';
import 'package:neuro_sathi/data/sync_service.dart';

// testWidgets runs on a fake clock that pump() moves forward.
void main() {
  testWidgets('a sync that did not finish is tried again after 30 seconds and 2 minutes, then left to the regular sync',
      (tester) async {
    final retry = SyncRetry();
    var attempts = 0;
    void attempt() {
      attempts++;
      retry.after(SyncOutcome.offline, attempt);
    }

    attempt(); // e.g. the sync when the app opens, while the phone's connection is still coming back
    await tester.pump(const Duration(seconds: 29));
    expect(attempts, 1);
    await tester.pump(const Duration(seconds: 1));
    expect(attempts, 2);
    await tester.pump(const Duration(minutes: 2));
    expect(attempts, 3);
    await tester.pump(const Duration(hours: 1));
    expect(attempts, 3, reason: 'after the series the 15-minute sync takes over');
    expect(retry.pending, isFalse);
  });

  testWidgets('a server error or another sync in progress is retried too; a finished sync or ended session is not',
      (tester) async {
    final retry = SyncRetry();
    for (final outcome in [SyncOutcome.failed, SyncOutcome.busy]) {
      retry.restart();
      retry.after(outcome, () {});
      expect(retry.pending, isTrue, reason: outcome.name);
    }
    for (final outcome in [SyncOutcome.synced, SyncOutcome.sessionExpired]) {
      retry.restart();
      retry.after(outcome, () => fail('retried after ${outcome.name}'));
      expect(retry.pending, isFalse, reason: outcome.name);
    }
  });

  testWidgets('a new reason to sync drops the waiting retry and starts the series again', (tester) async {
    final retry = SyncRetry();
    var retried = 0;
    retry.after(SyncOutcome.offline, () => retried++);
    await tester.pump(const Duration(seconds: 30));
    expect(retried, 1);
    retry.after(SyncOutcome.offline, () => retried++); // the retry failed too: the next one waits 2 minutes

    retry.restart(); // the app is opened again, and its own sync replaces the waiting retry
    await tester.pump(const Duration(minutes: 5));
    expect(retried, 1, reason: 'the waiting retry was dropped');

    retry.after(SyncOutcome.offline, () => retried++);
    await tester.pump(const Duration(seconds: 30));
    expect(retried, 2, reason: 'a fresh series starts with the short delay');
  });
}
