// HazardTypeCodec — verifies the typed HazardType enum ↔ v1 read-model string
// mapping is round-trip stable and lenient on unknown input.

import 'package:flutter_test/flutter_test.dart';
import 'package:ignirelay_app/app/proto/event_envelope_v2.dart';
import 'package:ignirelay_app/app/services/hazard_type_codec.dart';

void main() {
  const all = <int>[
    HazardType.unspecified,
    HazardType.fire,
    HazardType.flood,
    HazardType.landslide,
    HazardType.collapse,
    HazardType.chemical,
    HazardType.blockedRoute,
    HazardType.other,
  ];

  test('toV1String → fromV1String round-trips every known enum value', () {
    for (final t in all) {
      expect(HazardTypeCodec.fromV1String(HazardTypeCodec.toV1String(t)), t,
          reason: 'round-trip failed for hazardType=$t');
    }
  });

  test('canonical strings are the expected uppercase forms', () {
    expect(HazardTypeCodec.toV1String(HazardType.fire), 'FIRE');
    expect(HazardTypeCodec.toV1String(HazardType.flood), 'FLOOD');
    expect(HazardTypeCodec.toV1String(HazardType.blockedRoute), 'ROADBLOCK');
    expect(HazardTypeCodec.toV1String(HazardType.unspecified), 'UNKNOWN');
  });

  test('fromV1String is case-insensitive and accepts aliases', () {
    expect(HazardTypeCodec.fromV1String('fire'), HazardType.fire);
    expect(HazardTypeCodec.fromV1String('  FLOOD '), HazardType.flood);
    expect(HazardTypeCodec.fromV1String('BLOCKED_ROUTE'), HazardType.blockedRoute);
    expect(HazardTypeCodec.fromV1String('blocked'), HazardType.blockedRoute);
  });

  test('unknown / empty strings fall back without throwing', () {
    expect(HazardTypeCodec.fromV1String('definitely-not-a-hazard'),
        HazardType.other);
    expect(HazardTypeCodec.fromV1String(''), HazardType.unspecified);
  });
}
