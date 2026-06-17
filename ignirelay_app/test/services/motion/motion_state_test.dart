// UI-F5a — the pure motion-aware cadence matrix (§4.2).

import 'package:flutter_test/flutter_test.dart';
import 'package:ignirelay_app/app/services/motion/motion_state.dart';

void main() {
  group('motionPresenceInterval — normal battery', () {
    test('moving → 30s', () {
      expect(
        motionPresenceInterval(motion: MotionState.moving, lowBattery: false),
        const Duration(seconds: 30),
      );
    });
    test('stationary → 180s', () {
      expect(
        motionPresenceInterval(
            motion: MotionState.stationary, lowBattery: false),
        const Duration(seconds: 180),
      );
    });
  });

  group('motionPresenceInterval — low battery', () {
    test('moving → 60s', () {
      expect(
        motionPresenceInterval(motion: MotionState.moving, lowBattery: true),
        const Duration(seconds: 60),
      );
    });
    test('stationary → 300s', () {
      expect(
        motionPresenceInterval(
            motion: MotionState.stationary, lowBattery: true),
        const Duration(seconds: 300),
      );
    });
  });

  group('unknown → fixed fallback (pre-UI-F5 behaviour)', () {
    test('normal battery → 120s', () {
      expect(
        motionPresenceInterval(motion: MotionState.unknown, lowBattery: false),
        const Duration(seconds: 120),
      );
    });
    test('low battery → 300s', () {
      expect(
        motionPresenceInterval(motion: MotionState.unknown, lowBattery: true),
        const Duration(seconds: 300),
      );
    });
  });
}
