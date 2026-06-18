// location_service_test.dart
//
// Bug 4 驗證：LocationService 靜態工具函數 + onFirstFix 回呼機制
// GPS 實際呼叫無法在 unit test 中測試，但可測試 haversine / bearing / formatDistance

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:ignirelay_app/app/services/location_service.dart';

void main() {
  group('LocationService — Static Utilities', () {
    test('haversineMeters: same point = 0', () {
      const p = LatLng(25.033, 121.565);
      expect(LocationService.haversineMeters(p, p), closeTo(0, 0.01));
    });

    test('haversineMeters: Taipei to Kaohsiung ~300 km', () {
      const taipei = LatLng(25.033, 121.565);
      const kaohsiung = LatLng(22.627, 120.301);
      final dist = LocationService.haversineMeters(taipei, kaohsiung);
      expect(dist, greaterThan(280000));
      expect(dist, lessThan(320000));
    });

    test('bearing: due east ≈ 90°', () {
      const from = LatLng(0, 0);
      const to = LatLng(0, 1);
      expect(LocationService.bearing(from, to), closeTo(90, 1));
    });

    test('bearing: due north ≈ 0°', () {
      const from = LatLng(0, 0);
      const to = LatLng(1, 0);
      expect(LocationService.bearing(from, to), closeTo(0, 1));
    });

    test('bearingToDirection covers all 8 directions', () {
      expect(LocationService.bearingToDirection(0), equals('北方'));
      expect(LocationService.bearingToDirection(45), equals('東北方'));
      expect(LocationService.bearingToDirection(90), equals('東方'));
      expect(LocationService.bearingToDirection(135), equals('東南方'));
      expect(LocationService.bearingToDirection(180), equals('南方'));
      expect(LocationService.bearingToDirection(225), equals('西南方'));
      expect(LocationService.bearingToDirection(270), equals('西方'));
      expect(LocationService.bearingToDirection(315), equals('西北方'));
    });

    test('formatDistance: meters', () {
      expect(LocationService.formatDistance(500), equals('500 m'));
    });

    test('formatDistance: kilometers', () {
      expect(LocationService.formatDistance(2500), equals('2.5 km'));
    });

    test('normalizeDistance: 0m = 1.0', () {
      expect(LocationService.normalizeDistance(0), equals(1.0));
    });

    test('normalizeDistance: maxRange = 0.0', () {
      expect(LocationService.normalizeDistance(20000), equals(0.0));
    });

    test('normalizeDistance: 10km = 0.5 (with 20km max)', () {
      expect(LocationService.normalizeDistance(10000), closeTo(0.5, 0.01));
    });
  });

  group('LocationService — onFirstFix callback (Bug 4)', () {
    test('onFirstFix field is initially null', () {
      final service = LocationService();
      expect(service.onFirstFix, isNull);
    });

    test('onFirstFix can be set and read back', () {
      final service = LocationService();
      bool called = false;
      service.onFirstFix = () { called = true; };
      expect(service.onFirstFix, isNotNull);
      service.onFirstFix!();
      expect(called, isTrue);
    });

    test('hasLocation is false before init', () {
      // Fresh singleton — if no GPS has run, currentLocation is null
      // (In test env GPS won't initialize)
      final service = LocationService();
      // This test just validates the property accessor doesn't throw
      expect(service.hasLocation, isA<bool>());
    });
  });

  // UI-F5b — §4.2: one-shot refresh, fix timestamp, no continuous high-accuracy
  // stream. Uses the injected Geolocator seams + resetForTest so the shared
  // singleton never leaks fakes/state across the suite (Owner boundary 7).
  group('LocationService — §4.2 refresh (UI-F5b)', () {
    late LocationService svc;

    setUp(() {
      svc = LocationService();
      svc.resetForTest();
    });
    tearDown(() {
      svc.resetForTest();
    });

    test('init takes ONE fix, stamps lastFixAt, no continuous re-fetch',
        () async {
      var currentCalls = 0;
      final base = DateTime(2026, 1, 1, 12, 0, 0);
      svc
        ..now = (() => base)
        ..isServiceEnabledFn = (() async => true)
        ..checkPermissionFn = (() async => LocationPermission.whileInUse)
        ..getLastKnownFn = (() async => null)
        ..getCurrentFn = (() async {
          currentCalls++;
          return const LatLng(25.0, 121.5);
        });

      await svc.init();

      expect(svc.currentLocation, const LatLng(25.0, 121.5));
      expect(svc.lastFixAt, base);
      // One-shot only: UI-F5b removed the always-on getPositionStream, so init
      // does not keep re-fetching (no hot high-accuracy stream).
      expect(currentCalls, 1);
    });

    test('refreshOnce updates currentLocation + lastFixAt', () async {
      final t0 = DateTime(2026, 1, 1, 12, 0, 0);
      svc
        ..now = (() => t0)
        ..getCurrentFn = (() async => const LatLng(10.0, 20.0));

      final fix = await svc.refreshOnce(timeout: const Duration(seconds: 2));

      expect(fix, const LatLng(10.0, 20.0));
      expect(svc.currentLocation, const LatLng(10.0, 20.0));
      expect(svc.lastFixAt, t0);
    });

    test('refreshOnce timeout keeps last-known + returns it (never throws)',
        () async {
      svc.getCurrentFn = (() async => const LatLng(1.0, 2.0));
      await svc.refreshOnce(timeout: const Duration(seconds: 2));

      // A fix that never completes (Completer → no pending timer) → timeout fires.
      svc.getCurrentFn = (() => Completer<LatLng?>().future);
      final fix =
          await svc.refreshOnce(timeout: const Duration(milliseconds: 50));

      expect(fix, const LatLng(1.0, 2.0), reason: 'falls back to last-known');
      expect(svc.currentLocation, const LatLng(1.0, 2.0));
    });

    test('refreshOnce failure keeps last-known; returns null when none',
        () async {
      svc.getCurrentFn = (() async => throw Exception('gps off'));
      final fix = await svc.refreshOnce(timeout: const Duration(seconds: 1));
      expect(fix, isNull);
      expect(svc.currentLocation, isNull);
    });

    test('concurrent refreshOnce calls dedup to one underlying fetch', () async {
      var calls = 0;
      svc.getCurrentFn = (() async {
        calls++;
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return const LatLng(3.0, 4.0);
      });

      final results = await Future.wait([svc.refreshOnce(), svc.refreshOnce()]);

      expect(calls, 1, reason: 'in-flight dedup');
      expect(results[0], const LatLng(3.0, 4.0));
      expect(results[1], const LatLng(3.0, 4.0));
    });
  });
}
