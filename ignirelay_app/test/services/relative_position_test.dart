// A10b — RelativePositionProjector pure-function tests (DoD D1). Covers the four
// quadrants (N/E/S/W), the ±180° antimeridian wrap, distance 0 (same point),
// bearing wrap (359.x°→0°), and the cos(lat₀) high-latitude longitude scaling.
// Numerical assertions use a ≤0.5% relative tolerance against the documented
// local-equidistant projection (110574 m/° lat, 111320·cos(lat₀) m/° lng) — a
// constant swap or a dropped cos(lat₀) exceeds that tolerance and fails.

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:ignirelay_app/app/services/position_estimator.dart';
import 'package:ignirelay_app/app/services/relative_position.dart';

const double _degLat = 110574.0;
const double _degLngEq = 111320.0;

PositionEstimate _at(double lat, double lng,
        {PositionConfidence c = PositionConfidence.high}) =>
    PositionEstimate(
      lat: lat,
      lng: lng,
      confidence: c,
      uncertaintyM: 15,
      ageSeconds: 10,
    );

double _eastM(double lat0, double dLng) =>
    dLng * _degLngEq * cos(lat0 * pi / 180.0);
double _northM(double dLat) => dLat * _degLat;
double _dist(double lat0, double dLat, double dLng) =>
    sqrt(_northM(dLat) * _northM(dLat) + _eastM(lat0, dLng) * _eastM(lat0, dLng));

/// ≤0.5% relative tolerance (with a tiny absolute floor for near-zero values).
Matcher _within(double expected) =>
    closeTo(expected, expected.abs() * 0.005 + 1e-6);

void main() {
  group('four quadrants (lat₀ = 25°)', () {
    const lat0 = 25.0, lng0 = 121.0;
    final origin = _at(lat0, lng0);

    test('North → bearing 0, distance = Δlat × 110574', () {
      final r = RelativePositionProjector.relativeTo(origin, _at(25.01, 121.0))!;
      expect(r.bearingDeg, closeTo(0.0, 0.02));
      expect(r.distanceM, _within(_dist(lat0, 0.01, 0)));
    });

    test('East → bearing 90, distance scaled by cos(lat₀)', () {
      final r = RelativePositionProjector.relativeTo(origin, _at(25.0, 121.01))!;
      expect(r.bearingDeg, closeTo(90.0, 0.02));
      expect(r.distanceM, _within(_dist(lat0, 0, 0.01)));
    });

    test('South → bearing 180', () {
      final r = RelativePositionProjector.relativeTo(origin, _at(24.99, 121.0))!;
      expect(r.bearingDeg, closeTo(180.0, 0.02));
      expect(r.distanceM, _within(_dist(lat0, -0.01, 0)));
    });

    test('West → bearing 270', () {
      final r = RelativePositionProjector.relativeTo(origin, _at(25.0, 120.99))!;
      expect(r.bearingDeg, closeTo(270.0, 0.02));
      expect(r.distanceM, _within(_dist(lat0, 0, -0.01)));
    });
  });

  test('±180° antimeridian: Δlng wraps so a 0.002° gap stays small', () {
    final origin = _at(25.0, 179.999);
    final r = RelativePositionProjector.relativeTo(origin, _at(25.0, -179.999))!;
    // 0.002° east across the seam, NOT ~360°.
    expect(r.distanceM, lessThan(500));
    expect(r.distanceM, _within(_dist(25.0, 0, 0.002)));
    expect(r.bearingDeg, closeTo(90.0, 0.1)); // due east
  });

  test('same point → distance 0, bearing 0', () {
    final origin = _at(25.0, 121.0);
    final r = RelativePositionProjector.relativeTo(origin, _at(25.0, 121.0))!;
    expect(r.distanceM, closeTo(0.0, 1e-6));
    expect(r.bearingDeg, closeTo(0.0, 1e-9));
  });

  test('bearing wraps to 359.x° (not −0.x°) just west of due north', () {
    final origin = _at(25.0, 121.0);
    final r =
        RelativePositionProjector.relativeTo(origin, _at(25.1, 120.9999))!;
    expect(r.bearingDeg, greaterThan(359.0));
    expect(r.bearingDeg, lessThan(360.0)); // never exactly 360
  });

  test('cos(lat₀): the same Δlng east shrinks ~×0.5 at lat₀ = 60°', () {
    final eq = RelativePositionProjector.relativeTo(
        _at(0.0, 0.0), _at(0.0, 0.01))!;
    final hi = RelativePositionProjector.relativeTo(
        _at(60.0, 0.0), _at(60.0, 0.01))!;
    expect(eq.distanceM, _within(_dist(0.0, 0, 0.01)));
    expect(hi.distanceM, _within(_dist(60.0, 0, 0.01)));
    // cos(60°) = 0.5 → high-latitude east distance is half the equatorial one.
    expect(hi.distanceM / eq.distanceM, closeTo(0.5, 0.005));
  });

  group('placement guards + batch', () {
    final origin = _at(25.0, 121.0);

    test('subject without lat/lng → null (anchor-only stays list-only)', () {
      const anchorOnly = PositionEstimate(
        anchorNodeId: 'CP-1',
        distanceM: 50,
        confidence: PositionConfidence.medium,
        uncertaintyM: 30,
        ageSeconds: 120,
      );
      expect(RelativePositionProjector.relativeTo(origin, anchorOnly), isNull);
    });

    test('origin without lat/lng → null (no local position)', () {
      const noOrigin = PositionEstimate(
        confidence: PositionConfidence.low,
        uncertaintyM: 99,
        ageSeconds: 999,
      );
      expect(
          RelativePositionProjector.relativeTo(noOrigin, _at(25.01, 121.0)),
          isNull);
    });

    test('relativeAll drops unplaceable subjects, keeps the rest', () {
      final out = RelativePositionProjector.relativeAll(origin, {
        'north': _at(25.01, 121.0),
        'anchor': const PositionEstimate(
          anchorNodeId: 'CP-2',
          confidence: PositionConfidence.low,
          uncertaintyM: 50,
          ageSeconds: 600,
        ),
        'east': _at(25.0, 121.01),
      });
      expect(out.keys, containsAll(<String>['north', 'east']));
      expect(out.containsKey('anchor'), isFalse);
    });

    test('confidence / uncertainty / age pass through from the subject', () {
      final subj = _at(25.01, 121.0, c: PositionConfidence.medium);
      final r = RelativePositionProjector.relativeTo(origin, subj)!;
      expect(r.confidence, PositionConfidence.medium);
      expect(r.uncertaintyM, 15);
      expect(r.ageSeconds, 10);
    });
  });
}
