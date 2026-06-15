// A10 — PositionEstimator pure-function tests. Covers the age→confidence
// boundaries on BOTH sides of 2min and 10min (DoD D1), the linear uncertainty
// growth, and the freshest-fix fusion (incl. anchor-only + future-dated clamp).

import 'package:flutter_test/flutter_test.dart';

import 'package:ignirelay_app/app/services/position_estimator.dart';

void main() {
  group('confidenceForAge boundaries', () {
    test('≤2min → HIGH (incl. the 120s boundary)', () {
      expect(PositionEstimator.confidenceForAge(0), PositionConfidence.high);
      expect(PositionEstimator.confidenceForAge(119), PositionConfidence.high);
      expect(PositionEstimator.confidenceForAge(120), PositionConfidence.high);
    });

    test('2min < age ≤ 10min → MEDIUM (both boundaries)', () {
      expect(PositionEstimator.confidenceForAge(121), PositionConfidence.medium);
      expect(PositionEstimator.confidenceForAge(599), PositionConfidence.medium);
      expect(PositionEstimator.confidenceForAge(600), PositionConfidence.medium);
    });

    test('> 10min → LOW', () {
      expect(PositionEstimator.confidenceForAge(601), PositionConfidence.low);
      expect(PositionEstimator.confidenceForAge(99999), PositionConfidence.low);
    });

    test('negative age clamps to 0 → HIGH', () {
      expect(PositionEstimator.confidenceForAge(-50), PositionConfidence.high);
    });
  });

  test('uncertainty grows linearly with age; accuracy seeds the base', () {
    // No accuracy → GPS-class base 15m; +0.5 m/s.
    expect(PositionEstimator.uncertaintyForAge(0, 0), 15.0);
    expect(PositionEstimator.uncertaintyForAge(0, 100), closeTo(65.0, 1e-9));
    // Known accuracy seeds the base.
    expect(PositionEstimator.uncertaintyForAge(30, 0), 30.0);
    expect(PositionEstimator.uncertaintyForAge(30, 60), closeTo(60.0, 1e-9));
  });

  group('estimate (freshest-fix fusion)', () {
    final t0 = DateTime(2026, 6, 15, 12, 0, 0);

    test('empty evidence → null', () {
      expect(PositionEstimator.estimate(const [], now: t0), isNull);
    });

    test('picks the freshest fix and derives age/confidence/uncertainty', () {
      final est = PositionEstimator.estimate([
        PositionObservation(
            lat: 1, lng: 2, accuracyM: 10,
            observedAt: t0.subtract(const Duration(minutes: 8))),
        PositionObservation(
            lat: 25.0339805, lng: 121.5654177, accuracyM: 12,
            observedAt: t0.subtract(const Duration(seconds: 30))),
      ], now: t0);
      expect(est, isNotNull);
      expect(est!.lat, 25.0339805);
      expect(est.lng, 121.5654177);
      expect(est.ageSeconds, 30);
      expect(est.confidence, PositionConfidence.high);
      expect(est.uncertaintyM, closeTo(12 + 0.5 * 30, 1e-9));
    });

    test('anchor-only fix → no latLng, anchor + distance reported', () {
      final est = PositionEstimator.estimate([
        PositionObservation(
            anchorNodeId: 'CP-7', distanceM: 180,
            observedAt: t0.subtract(const Duration(minutes: 5))),
      ], now: t0);
      expect(est!.hasLatLng, isFalse);
      expect(est.anchorNodeId, 'CP-7');
      expect(est.distanceM, 180);
      expect(est.confidence, PositionConfidence.medium); // 5min
    });

    test('future-dated observation clamps age to 0 (HIGH)', () {
      final est = PositionEstimator.estimate([
        PositionObservation(
            lat: 1, lng: 1, observedAt: t0.add(const Duration(seconds: 10))),
      ], now: t0);
      expect(est!.ageSeconds, 0);
      expect(est.confidence, PositionConfidence.high);
    });
  });
}
