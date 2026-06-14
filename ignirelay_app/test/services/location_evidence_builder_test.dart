// LocationEvidenceBuilder — verifies GPS evidence construction, the
// null-when-unavailable contract, and 1e7 ROUND-TO-NEAREST quantization
// (including the 25.0339805 IEEE-754 trap value from PHASE0B4 §3.1).

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:ignirelay_app/app/proto/event_envelope_v2.dart';
import 'package:ignirelay_app/app/services/location_evidence_builder.dart';

void main() {
  const fixedClock = HlcTimestampV2(msSinceEpoch: 99, counter: 0);

  test('build() returns null when GPS is unavailable', () {
    final builder = LocationEvidenceBuilder(
      currentLocation: () => null,
      clock: () => fixedClock,
    );
    expect(builder.build(), isNull);
  });

  test('build() produces SUBJECT-frame GPS evidence from the current fix', () {
    final builder = LocationEvidenceBuilder(
      currentLocation: () => const LatLng(25.0339805, 121.5654177),
      clock: () => fixedClock,
    );
    final ev = builder.build();
    expect(ev, isNotNull);
    expect(ev!.source, LocationSource.gps);
    expect(ev.frame, LocationFrame.subject);
    expect(ev.observedAt.msSinceEpoch, 99);
    expect(ev.latE7, 250339805);
    expect(ev.lngE7, 1215654177);
  });

  group('1e7 round-to-nearest', () {
    final builder = LocationEvidenceBuilder(clock: () => fixedClock);

    test('25.0339805 → 250339805 (known IEEE-754 trap)', () {
      final ev = builder.buildFromDegrees(
        latDegrees: 25.0339805,
        lngDegrees: 0,
      );
      expect(ev.latE7, 250339805);
    });

    test('rounds to nearest, not truncation, both signs', () {
      // 0.00000015° = 1.5 units → rounds to 2 (nearest, ties away from zero).
      expect(
        builder.buildFromDegrees(latDegrees: 0.00000015, lngDegrees: 0).latE7,
        2,
      );
      // Negative mirrors.
      expect(
        builder.buildFromDegrees(latDegrees: -0.00000015, lngDegrees: 0).latE7,
        -2,
      );
      // 121.5654177° → 1215654177 exactly.
      expect(
        builder.buildFromDegrees(latDegrees: 0, lngDegrees: 121.5654177).lngE7,
        1215654177,
      );
    });

    test('round-trips back to within quantization error', () {
      final ev = builder.buildFromDegrees(
        latDegrees: 25.0339805,
        lngDegrees: 121.5654177,
      );
      expect(ev.latDegrees, closeTo(25.0339805, 1e-7));
      expect(ev.lngDegrees, closeTo(121.5654177, 1e-7));
    });
  });
}
