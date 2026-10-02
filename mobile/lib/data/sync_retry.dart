import 'dart:async';

import '../config.dart';
import 'sync_service.dart';

/// Tries a sync again soon when it did not finish, instead of leaving it to the
/// next periodic sync: the first attempt after the phone wakes up or the app
/// opens often fails while the connection comes back. Each new reason to sync
/// (the app opened, the connection came back, the periodic timer) starts a
/// fresh series of [delays].
class SyncRetry {
  SyncRetry({this.delays = AppConfig.syncRetryDelays});

  final List<Duration> delays;
  Timer? _timer;
  int _attempt = 0;

  static const _unfinished = {SyncOutcome.offline, SyncOutcome.failed, SyncOutcome.busy};

  /// A retry is waiting to run.
  bool get pending => _timer?.isActive ?? false;

  /// A new reason to sync: drop the waiting retry and start the series again.
  void restart() {
    _timer?.cancel();
    _attempt = 0;
  }

  /// Call with the outcome of every sync. Schedules [retry] if the sync did not
  /// finish and the series has delays left.
  void after(SyncOutcome outcome, void Function() retry) {
    _timer?.cancel();
    if (!_unfinished.contains(outcome) || _attempt >= delays.length) return;
    _timer = Timer(delays[_attempt++], retry);
  }

  void cancel() => _timer?.cancel();
}
