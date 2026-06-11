import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:ignirelay_app/app/proto/event_envelope_v2.dart';
import 'package:ignirelay_app/app/services/location_evidence_builder.dart';

void main() {
  test('round-to-nearest 1e7 — standard value', () {
    final builder = LocationEvidenceBuilder.forTest(
      () => const LatLng(25.04, 121.56),
    );
    final evidence = builder.build();
    expect(evidence, isNotNull);
    expect(evidence!.latE7, 250400000);
    expect(evidence.lngE7, 1215600000);
    expect(evidence.source, LocationSource.gps);
    expect(evidence.frame, LocationFrame.subject);
  });

  test('round-to-nearest 1e7 — IEEE-754 trap value 25.0339805', () {
    final builder = LocationEvidenceBuilder.forTest(
      () => const LatLng(25.0339805, 121.5647629),
    );
    final evidence = builder.build();
    expect(evidence, isNotNull);
    // 25.0339805 * 1e7 = 250339805 exactly
    expect(evidence!.latE7, 250339805);
    // 121.5647629 * 1e7 = 1215647629
    expect(evidence.lngE7, 1215647629);
  });

  test('round-to-nearest 1e7 — half-up rounding', () {
    // 1.00000005 * 1e7 = 10000000.5 → rounds to 10000001
    final builder = LocationEvidenceBuilder.forTest(
      () => const LatLng(1.00000005, 0.0),
    );
    final evidence = builder.build();
    expect(evidence, isNotNull);
    expect(evidence!.latE7, 10000001);
  });

  test('returns null when GPS unavailable', () {
    final builder = LocationEvidenceBuilder.forTest(() => null);
    expect(builder.build(), isNull);
  });

  test('fromDegrees roundtrip preserves 1e7 precision', () {
    const lat = 25.0339805;
    const lng = 121.5647629;
    final builder = LocationEvidenceBuilder.forTest(
      () => const LatLng(lat, lng),
    );
    final evidence = builder.build()!;
    // latDegrees / lngDegrees getters must round-trip within 1e-7
    expect(
      (evidence.latDegrees - lat).abs() < 1e-7,
      isTrue,
      reason: 'latDegrees roundtrip',
    );
    expect(
      (evidence.lngDegrees - lng).abs() < 1e-7,
      isTrue,
      reason: 'lngDegrees roundtrip',
    );
  });
}
