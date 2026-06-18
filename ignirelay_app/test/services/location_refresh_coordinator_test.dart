// UI-F5b — LocationRefreshCoordinator: §4.2 refresh decisions + honest reason,
// driven by fake refreshOnce / lastFixAt / clock (no plugin, no singleton).

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:ignirelay_app/app/services/location_refresh_coordinator.dart';
import 'package:ignirelay_app/app/services/motion/gps_refresh_policy.dart';
import 'package:ignirelay_app/app/services/motion/motion_state.dart';

void main() {
  late DateTime now;
  DateTime? fixAt;
  int refreshCalls = 0;
  bool refreshSucceeds = true;

  LocationRefreshCoordinator build() => LocationRefreshCoordinator(
        lastFixAt: () => fixAt,
        refreshOnce: (timeout) async {
          refreshCalls++;
          if (refreshSucceeds) {
            fixAt = now; // a fresh fix was obtained
            return const LatLng(25.0, 121.0);
          }
          // failure → last-known (null if never had one)
          return fixAt == null ? null : const LatLng(25.0, 121.0);
        },
        now: () => now,
      );

  setUp(() {
    now = DateTime(2026, 1, 1, 12, 0, 0);
    fixAt = null;
    refreshCalls = 0;
    refreshSucceeds = true;
  });

  test('beacon moving + stale → one refresh, reason movingRefresh', () async {
    fixAt = now.subtract(const Duration(seconds: 40));
    final c = build();
    await c.ensureFreshForBeacon(MotionState.moving);
    expect(refreshCalls, 1);
    expect(c.lastReason, GpsPolicyReason.movingRefresh);
  });

  test('beacon moving + fresh → NO refresh, reason movingReuseFreshFix '
      '(never claims a refresh that did not happen)', () async {
    fixAt = now.subtract(const Duration(seconds: 10));
    final c = build();
    await c.ensureFreshForBeacon(MotionState.moving);
    expect(refreshCalls, 0);
    expect(c.lastReason, GpsPolicyReason.movingReuseFreshFix);
  });

  test('beacon stationary → NO refresh, reason stationaryReuse', () async {
    fixAt = now.subtract(const Duration(hours: 2));
    final c = build();
    await c.ensureFreshForBeacon(MotionState.stationary);
    expect(refreshCalls, 0);
    expect(c.lastReason, GpsPolicyReason.stationaryReuse);
  });

  test('beacon unknown → NO refresh, reason unknownReuse', () async {
    fixAt = now.subtract(const Duration(minutes: 5));
    final c = build();
    await c.ensureFreshForBeacon(MotionState.unknown);
    expect(refreshCalls, 0);
    expect(c.lastReason, GpsPolicyReason.unknownReuse);
  });

  test('beacon moving, no fix, refresh fails → reason unavailable', () async {
    refreshSucceeds = false; // fixAt stays null
    final c = build();
    await c.ensureFreshForBeacon(MotionState.moving);
    expect(refreshCalls, 1);
    expect(c.lastReason, GpsPolicyReason.unavailable);
  });

  test('manual event: always one bounded refresh, reason manualEvent',
      () async {
    fixAt = now.subtract(const Duration(minutes: 30));
    final c = build();
    final fix = await c.ensureFreshForManualEvent(
        timeout: const Duration(milliseconds: 1500));
    expect(refreshCalls, 1);
    expect(fix, isNotNull);
    expect(c.lastReason, GpsPolicyReason.manualEvent);
  });

  test('manual event: no fix + refresh fails → unavailable, returns null',
      () async {
    refreshSucceeds = false;
    final c = build();
    final fix = await c.ensureFreshForManualEvent(
        timeout: const Duration(seconds: 2));
    expect(refreshCalls, 1);
    expect(fix, isNull);
    expect(c.lastReason, GpsPolicyReason.unavailable);
  });

  test('lastFixAge = now - lastFixAt; null when no fix', () {
    final c = build();
    expect(c.lastFixAge, isNull);
    fixAt = now.subtract(const Duration(seconds: 90));
    expect(c.lastFixAge, const Duration(seconds: 90));
  });
}
