// MotionService — UI-F5b. Wires a [MotionSource] to a [MotionClassifier] and
// exposes the classified [MotionState] transitions for the presence beacon.
//
// Owns the lifecycle so `main.dart` can start it with the beacon and stop
// sampling when the app is backgrounded (power). [start]/[stop] double as
// resume/pause and are idempotent: a second [start] never double-subscribes,
// [stop] before [start] is safe, and [dispose] tears everything down without a
// leak (cancels the subscription, stops the source, closes the classifier).

import 'dart:async';

import 'package:ignirelay_app/app/services/motion/motion_classifier.dart';
import 'package:ignirelay_app/app/services/motion/motion_source.dart';
import 'package:ignirelay_app/app/services/motion/motion_state.dart';

class MotionService {
  MotionService({
    required MotionSource source,
    MotionClassifier? classifier,
    DateTime Function()? now,
  })  : _source = source,
        _classifier = classifier ?? MotionClassifier(now: now ?? DateTime.now);

  final MotionSource _source;
  final MotionClassifier _classifier;

  StreamSubscription<double>? _sub;
  bool _running = false;
  bool _disposed = false;

  /// Distinct motion-state transitions (broadcast). Survives pause/resume; closed
  /// by [dispose].
  Stream<MotionState> get stateChanges => _classifier.stateChanges;

  /// The current coarse motion (`unknown` until enough samples arrive).
  MotionState get state => _classifier.state;

  /// Start (or resume) sampling. Idempotent — a second call while running is a
  /// no-op (no double subscription / double native start).
  Future<void> start() async {
    if (_disposed || _running) return;
    _running = true;
    _sub = _source.magnitudes.listen(_classifier.addSample);
    await _source.start();
  }

  /// Stop (or pause) sampling. Safe to call before [start] and idempotent. Keeps
  /// the classifier alive so its state + subscribers survive a later [start].
  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    await _sub?.cancel();
    _sub = null;
    await _source.stop();
  }

  /// Tear down for good: stop sampling and close the classifier stream (no leak).
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await stop();
    _classifier.dispose();
  }
}
