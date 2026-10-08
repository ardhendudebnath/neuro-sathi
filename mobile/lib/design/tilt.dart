import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:sensors_plus/sensors_plus.dart';

/// How far the phone is tilted from where it has been resting, from -1 to 1 on
/// each axis. The resting position follows the phone slowly, so the screen
/// settles when the phone is held still and only moves when the phone does.
Offset tiltFromGravity(Offset gravity, Offset resting) => Offset(
      ((resting.dx - gravity.dx) / 2.5).clamp(-1.0, 1.0).toDouble(),
      ((gravity.dy - resting.dy) / 2.5).clamp(-1.0, 1.0).toDouble(),
    );

/// A slow sway for phones without a motion sensor, so the screen still feels alive.
Offset idleSway(double seconds) => Offset(math.sin(seconds * 0.35) * 0.45, math.cos(seconds * 0.28) * 0.3);

/// The tilt that the hills, tiles and Sathi react to. Reads the accelerometer
/// while started; tests and the "Remove animations" setting leave it at zero.
class Tilt extends ChangeNotifier implements ValueListenable<Offset> {
  Offset _value = Offset.zero;
  Offset _target = Offset.zero;
  Offset? _resting;
  bool _hasSensor = false;
  Ticker? _ticker;
  StreamSubscription<AccelerometerEvent>? _sensor;

  @override
  Offset get value => _value;

  void start(TickerProvider vsync) {
    if (_ticker != null) return;
    _ticker = vsync.createTicker(_tick)..start();
    try {
      _sensor = accelerometerEventStream(samplingPeriod: SensorInterval.uiInterval).listen(
        _onSample,
        onError: (Object _) => _hasSensor = false,
        cancelOnError: true,
      );
    } on Object {
      _hasSensor = false; // no sensor plugin (tests) or no sensor: sway instead
    }
  }

  void stop() {
    _ticker?.dispose();
    _ticker = null;
    _sensor?.cancel();
    _sensor = null;
    _resting = null;
    _hasSensor = false;
    if (_value != Offset.zero) {
      _value = Offset.zero;
      notifyListeners();
    }
  }

  void _onSample(AccelerometerEvent e) {
    _hasSensor = true;
    final gravity = Offset(e.x, e.y);
    final resting = _resting = _resting == null ? gravity : Offset.lerp(_resting, gravity, 0.02)!;
    _target = tiltFromGravity(gravity, resting);
  }

  void _tick(Duration elapsed) {
    final goal = _hasSensor ? _target : idleSway(elapsed.inMicroseconds / 1e6);
    final next = Offset.lerp(_value, goal, 0.08)!;
    if ((next - _value).distanceSquared < 1e-7) return;
    _value = next;
    notifyListeners();
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}

/// Makes a [Tilt] available below it. Widgets without one see no tilt.
class TiltScope extends InheritedWidget {
  const TiltScope({super.key, required this.tilt, required super.child});

  final ValueListenable<Offset> tilt;

  static final ValueListenable<Offset> _still = ValueNotifier(Offset.zero);

  static ValueListenable<Offset> of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<TiltScope>()?.tilt ?? _still;

  @override
  bool updateShouldNotify(TiltScope oldWidget) => tilt != oldWidget.tilt;
}
