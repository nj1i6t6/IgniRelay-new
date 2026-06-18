// NativeMotionSource — UI-F5b. The Android `MotionSource` backed by the existing
// `NativeBridge` accelerometer (no new dependency, no extra channel). Non-Android
// platforms use `NoopMotionSource` instead, so motion stays `unknown` there
// (iOS deferred). The start/stop invokers and the magnitude stream are injectable
// so this is unit-testable without the platform channel.
//
// Layer note: this is `lib/app/services` importing `lib/platform` — allowed
// (only platform→app and ui→platform are forbidden, see CLAUDE.md).

import 'package:ignirelay_app/app/services/motion/motion_source.dart';
import 'package:ignirelay_app/platform/native_bridge.dart';

class NativeMotionSource implements MotionSource {
  NativeMotionSource({
    Future<bool> Function()? start,
    Future<void> Function()? stop,
    Stream<double>? magnitudes,
  })  : _startFn = start ?? NativeBridge.startMotionSensor,
        _stopFn = stop ?? NativeBridge.stopMotionSensor,
        _magnitudes = magnitudes ?? NativeBridge.motionMagnitudes;

  final Future<bool> Function() _startFn;
  final Future<void> Function() _stopFn;
  final Stream<double> _magnitudes;

  bool _started = false;

  @override
  Stream<double> get magnitudes => _magnitudes;

  /// Idempotent: a second `start()` while already running is a no-op (the native
  /// listener is never double-registered).
  @override
  Future<void> start() async {
    if (_started) return;
    _started = true;
    await _startFn();
  }

  /// Safe to call before `start()` (no-op) and idempotent.
  @override
  Future<void> stop() async {
    if (!_started) return;
    _started = false;
    await _stopFn();
  }
}
