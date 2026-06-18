// UI-F5b — the pure §4.2 GPS-fix-age policy: refresh decision + honest reason.

import 'package:flutter_test/flutter_test.dart';
import 'package:ignirelay_app/app/services/motion/gps_refresh_policy.dart';
import 'package:ignirelay_app/app/services/motion/motion_state.dart';

void main() {
  group('shouldRefreshBeforePresence', () {
    test('moving + stale fix → refresh', () {
      expect(
        shouldRefreshBeforePresence(
            motion: MotionState.moving,
            fixAge: const Duration(seconds: 31)),
        isTrue,
      );
    });

    test('moving + no fix yet (null age) → refresh', () {
      expect(
        shouldRefreshBeforePresence(motion: MotionState.moving, fixAge: null),
        isTrue,
      );
    });

    test('moving + fresh fix (<30s) → no refresh', () {
      expect(
        shouldRefreshBeforePresence(
            motion: MotionState.moving,
            fixAge: const Duration(seconds: 29)),
        isFalse,
      );
    });

    test('moving + exactly 30s → refresh (>= boundary)', () {
      expect(
        shouldRefreshBeforePresence(
            motion: MotionState.moving,
            fixAge: const Duration(seconds: 30)),
        isTrue,
      );
    });

    test('stationary → never refresh (even with a very old fix)', () {
      expect(
        shouldRefreshBeforePresence(
            motion: MotionState.stationary,
            fixAge: const Duration(hours: 5)),
        isFalse,
      );
      expect(
        shouldRefreshBeforePresence(
            motion: MotionState.stationary, fixAge: null),
        isFalse,
      );
    });

    test('unknown → never refresh (reuse last fix)', () {
      expect(
        shouldRefreshBeforePresence(
            motion: MotionState.unknown, fixAge: null),
        isFalse,
      );
    });
  });

  group('gpsReasonForBeacon (honest reasons)', () {
    test('no fix → unavailable, regardless of motion', () {
      for (final m in MotionState.values) {
        expect(gpsReasonForBeacon(motion: m, hasAnyFix: false),
            GpsPolicyReason.unavailable);
      }
    });

    test('with a fix + moving: refreshed→movingRefresh, not-refreshed→'
        'movingReuseFreshFix; stationary→stationaryReuse, unknown→unknownReuse',
        () {
      expect(
          gpsReasonForBeacon(
              motion: MotionState.moving, hasAnyFix: true, refreshed: true),
          GpsPolicyReason.movingRefresh);
      expect(
          gpsReasonForBeacon(
              motion: MotionState.moving, hasAnyFix: true, refreshed: false),
          GpsPolicyReason.movingReuseFreshFix);
      // Default refreshed:false → never claims a refresh that did not happen.
      expect(gpsReasonForBeacon(motion: MotionState.moving, hasAnyFix: true),
          GpsPolicyReason.movingReuseFreshFix);
      expect(
          gpsReasonForBeacon(motion: MotionState.stationary, hasAnyFix: true),
          GpsPolicyReason.stationaryReuse);
      expect(gpsReasonForBeacon(motion: MotionState.unknown, hasAnyFix: true),
          GpsPolicyReason.unknownReuse);
    });

    test('lowBattery is NOT a GPS policy reason (Owner boundary 8)', () {
      // Honesty guard: the enum must not disguise a cadence reason as a GPS one.
      final names = GpsPolicyReason.values.map((e) => e.name).toList();
      expect(names, isNot(contains('lowBattery')));
      expect(names, isNot(contains('low_battery')));
      expect(
        GpsPolicyReason.values.toSet(),
        {
          GpsPolicyReason.movingRefresh,
          GpsPolicyReason.movingReuseFreshFix,
          GpsPolicyReason.stationaryReuse,
          GpsPolicyReason.unknownReuse,
          GpsPolicyReason.manualEvent,
          GpsPolicyReason.unavailable,
        },
      );
    });
  });
}
