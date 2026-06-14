// HazardTypeCodec — maps between the typed v3 `HazardType` enum (carried on the
// wire by `HazardMarkerData.hazard_type`) and the legacy v1 hazard-type STRING
// used by the `Hazards_State` read-model / `EventStream.hazardEvents`.
//
// A3 (#4-5) swaps the HAZARD wire payload from a raw-JSON shim to typed
// `HazardMarkerData`. The wire now carries an INT enum, but the v1 read-model
// path still keys hazards by a free string. This codec keeps that int↔string
// mapping in ONE place so the SENDER (`EventPublisher._dualWriteHazardMarker`)
// and the RECEIVER (`V2InboundProjector._projectHazard`) cannot drift.
//
// The string values are the canonical UPPERCASE forms; `fromV1String` is
// lenient (case-insensitive, a few aliases) and falls back to `other` for any
// unrecognised string so a sender's free-text type never hard-fails encoding.

import 'package:ignirelay_app/app/proto/event_envelope_v2.dart';

class HazardTypeCodec {
  /// Typed `HazardType` enum value → canonical v1 read-model string.
  static String toV1String(int hazardType) {
    switch (hazardType) {
      case HazardType.fire:
        return 'FIRE';
      case HazardType.flood:
        return 'FLOOD';
      case HazardType.landslide:
        return 'LANDSLIDE';
      case HazardType.collapse:
        return 'COLLAPSE';
      case HazardType.chemical:
        return 'CHEMICAL';
      case HazardType.blockedRoute:
        return 'ROADBLOCK';
      case HazardType.other:
        return 'OTHER';
      case HazardType.unspecified:
      default:
        return 'UNKNOWN';
    }
  }

  /// v1 read-model string → typed `HazardType` enum value. Case-insensitive;
  /// unrecognised strings map to `HazardType.other` (never throws).
  static int fromV1String(String type) {
    switch (type.trim().toUpperCase()) {
      case 'FIRE':
        return HazardType.fire;
      case 'FLOOD':
        return HazardType.flood;
      case 'LANDSLIDE':
        return HazardType.landslide;
      case 'COLLAPSE':
        return HazardType.collapse;
      case 'CHEMICAL':
        return HazardType.chemical;
      case 'ROADBLOCK':
      case 'BLOCKED_ROUTE':
      case 'BLOCKED':
        return HazardType.blockedRoute;
      case 'UNKNOWN':
      case '':
        return HazardType.unspecified;
      case 'OTHER':
        return HazardType.other;
      default:
        return HazardType.other;
    }
  }
}
