// MotionSource — the seam between a raw accelerometer-magnitude stream and the
// [MotionClassifier] (UI-F5a).
//
// UI-F5a ships ONLY this interface plus a no-op implementation; there is NO
// native code in this cut (no SensorManager / MethodChannel / EventChannel).
// UI-F5b adds the narrow Android `NativeMotionSource` over the existing
// `NativeBridge` channels. With [NoopMotionSource] wired (or nothing wired at
// all), no samples flow → the classifier stays `MotionState.unknown` → the
// beacon uses its fixed fallback cadence.

import 'dart:async';

/// Emits accelerometer magnitude samples (m/s², ≈9.8 at rest). Pure Dart seam:
/// implementations may be native (F5b) or fake (tests).
abstract class MotionSource {
  /// Low-rate stream of accelerometer magnitude readings while started.
  Stream<double> get magnitudes;

  /// Begin sampling (registers the platform listener in the native impl).
  Future<void> start();

  /// Stop sampling (unregisters the listener — power).
  Future<void> stop();
}

/// A source that never emits — motion stays `unknown`. Used until UI-F5b wires
/// the native accelerometer, and as a safe default on platforms without one.
class NoopMotionSource implements MotionSource {
  const NoopMotionSource();

  @override
  Stream<double> get magnitudes => const Stream<double>.empty();

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}
}
