// MotionClassifier — turns a low-rate accelerometer magnitude stream into a
// hysteretic [MotionState] (UI-F5a).
//
// Spec: docs/APP_UI_IA_REWORK_PLAN.md §4.2. Pure Dart + an injected clock — no
// platform/native dependency, so the hysteresis is unit-testable with fed
// samples and a fake clock.
//
// Algorithm: bucket magnitude samples into [motionWindow] (8 s) windows; per
// window compute the RMS of each sample's deviation from the window mean (this
// cancels gravity regardless of orientation). Two thresholds give hysteresis:
//   • → moving after [movingConfirmWindows] (2) CONSECUTIVE windows whose RMS
//     is ≥ [movingRmsThreshold];
//   • → stationary after the RMS stays ≤ [stationaryRmsThreshold] CONTINUOUSLY
//     for [stationaryConfirmDuration] (45 s).
// Because moving needs ≥2 windows and stationary needs ≥45 s of quiet, a single
// noisy sample can't flip stationary→moving and a single quiet sample can't
// flip moving→stationary. Starts in [MotionState.unknown] and only leaves it
// once a confirm threshold is met — it is NEVER defaulted to `stationary`.

import 'dart:async';
import 'dart:math' as math;

import 'package:ignirelay_app/app/services/motion/motion_state.dart';

class MotionClassifier {
  MotionClassifier({
    DateTime Function()? now,
    this.motionWindow = const Duration(seconds: 8),
    this.movingConfirmWindows = 2,
    this.stationaryConfirmDuration = const Duration(seconds: 45),
    this.movingRmsThreshold = 0.6,
    this.stationaryRmsThreshold = 0.25,
  }) : _now = now ?? DateTime.now;

  final DateTime Function() _now;
  final Duration motionWindow;
  final int movingConfirmWindows;
  final Duration stationaryConfirmDuration;

  /// RMS deviation (m/s²) at/above which a window counts as "active". Strictly
  /// greater than [stationaryRmsThreshold] — the gap is the hysteresis band.
  final double movingRmsThreshold;

  /// RMS deviation (m/s²) at/below which a window counts as "quiet".
  final double stationaryRmsThreshold;

  final StreamController<MotionState> _controller =
      StreamController<MotionState>.broadcast();

  /// Emits on each REAL state transition (deduplicated). Broadcast.
  Stream<MotionState> get stateChanges => _controller.stream;

  MotionState _state = MotionState.unknown;
  MotionState get state => _state;

  DateTime? _windowStart;
  final List<double> _samples = <double>[];
  int _consecutiveActive = 0;
  DateTime? _quietSince;
  bool _disposed = false;

  /// Feed one accelerometer magnitude sample (m/s²). Finalizes the current
  /// window first when [motionWindow] has elapsed.
  void addSample(double magnitude) {
    if (_disposed) return;
    final now = _now();
    _windowStart ??= now;
    if (now.difference(_windowStart!) >= motionWindow) {
      _finalizeWindow(now);
    }
    _samples.add(magnitude);
  }

  void _finalizeWindow(DateTime now) {
    if (_samples.isNotEmpty) {
      final mean = _samples.reduce((a, b) => a + b) / _samples.length;
      var sumSq = 0.0;
      for (final s in _samples) {
        final d = s - mean;
        sumSq += d * d;
      }
      final rms = math.sqrt(sumSq / _samples.length);
      _classifyWindow(rms, now);
    }
    _samples.clear();
    _windowStart = now;
  }

  void _classifyWindow(double rms, DateTime now) {
    if (rms >= movingRmsThreshold) {
      _consecutiveActive++;
      _quietSince = null;
    } else {
      _consecutiveActive = 0;
      if (rms <= stationaryRmsThreshold) {
        _quietSince ??= now; // start (or continue) a quiet run
      } else {
        _quietSince = null; // hysteresis dead-zone breaks the quiet run
      }
    }

    if (_consecutiveActive >= movingConfirmWindows) {
      _setState(MotionState.moving);
    } else if (_quietSince != null &&
        now.difference(_quietSince!) >= stationaryConfirmDuration) {
      _setState(MotionState.stationary);
    }
  }

  void _setState(MotionState next) {
    if (_state == next) return;
    _state = next;
    if (!_controller.isClosed) _controller.add(next);
  }

  /// Release the broadcast controller. Safe to call once; idempotent.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _samples.clear();
    _controller.close();
  }
}
