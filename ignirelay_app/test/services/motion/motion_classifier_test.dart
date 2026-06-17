// UI-F5a — MotionClassifier hysteresis, with a fake clock and fed samples.
//
// Proves: starts `unknown` (never faked stationary); quiet → stationary after
// the confirm duration; ONE active window does NOT flip stationary→moving (two
// consecutive do); ONE quiet window does NOT flip moving→stationary; transitions
// are emitted once each; and the broadcast controller is closed on dispose.

import 'package:flutter_test/flutter_test.dart';
import 'package:ignirelay_app/app/services/motion/motion_classifier.dart';
import 'package:ignirelay_app/app/services/motion/motion_state.dart';

void main() {
  late DateTime t;
  late MotionClassifier c;

  setUp(() {
    t = DateTime(2026, 1, 1, 0, 0, 0);
    c = MotionClassifier(now: () => t);
  });

  // Fill the current window with `mags`, advance one window, then drop one
  // trailing sample so the just-filled window is finalized & classified.
  void window(List<double> mags) {
    for (final m in mags) {
      c.addSample(m);
    }
    t = t.add(const Duration(seconds: 8));
    c.addSample(mags.isNotEmpty ? mags.first : 9.8);
  }

  List<double> quiet() => List<double>.filled(20, 9.8); // RMS ≈ 0
  List<double> active() =>
      List<double>.generate(20, (i) => i.isEven ? 8.0 : 12.0); // RMS ≈ 2.0

  test('starts unknown — never defaults to stationary', () {
    addTearDown(c.dispose);
    expect(c.state, MotionState.unknown);
  });

  test('hysteresis: quiet→stationary; 1 active stays; 2 active→moving; '
      '1 quiet stays moving', () {
    addTearDown(c.dispose);

    // ~45 s+ of continuous quiet → stationary.
    for (var i = 0; i < 9; i++) {
      window(quiet());
    }
    expect(c.state, MotionState.stationary);

    // A single active window is NOT enough (needs movingConfirmWindows = 2).
    window(active());
    expect(c.state, MotionState.stationary,
        reason: 'one active window < 2 confirm → no flip');

    // A second consecutive active window → moving.
    window(active());
    expect(c.state, MotionState.moving);

    // A single quiet window does NOT flip back (needs 45 s continuous quiet).
    window(quiet());
    expect(c.state, MotionState.moving,
        reason: 'one quiet window < 45 s confirm → no flip');
  });

  test('stateChanges emits each transition once', () async {
    final seen = <MotionState>[];
    final sub = c.stateChanges.listen(seen.add);
    addTearDown(() async {
      await sub.cancel();
      c.dispose();
    });

    for (var i = 0; i < 9; i++) {
      window(quiet());
    }
    window(active());
    window(active());
    await Future<void>.delayed(Duration.zero); // drain broadcast microtasks

    expect(seen, <MotionState>[MotionState.stationary, MotionState.moving]);
  });

  test('dispose closes the broadcast stream (no leak)', () async {
    final done = expectLater(c.stateChanges, emitsDone);
    c.dispose();
    await done;
    // Idempotent + safe after dispose.
    expect(() => c.addSample(9.8), returnsNormally);
    c.dispose();
  });
}
