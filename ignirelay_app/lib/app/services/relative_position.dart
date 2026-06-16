// RelativePositionProjector — A10b. "Me-centric" relative position of one
// subject, derived from two A10 [PositionEstimate]s (local origin + subject) via
// a local equidistant projection. Pure functions — no I/O, no singletons, no
// streams; plain Dart so the UI can feed it estimates and render the result
// without crossing the ui-cannot-import-proto layer rule.
//
// Spec / design: MASTER_EXECUTION_PLAN §5 A10b step 1.
//
// PROJECTION (FROZEN constants — the SAME set as the E1 map-calibration spec
// `ignirelay_app/docs/specs/map_calibration_v1.md`, so App and the cloud
// georeferencing agree to the metre):
//   • 1° latitude  = 110574.0 m                       (metresPerDegLat)
//   • 1° longitude = 111320.0 m × cos(lat₀)           (metresPerDegLngEquator)
//   where lat₀ = the LOCAL (origin) latitude. East is +x, North is +y.
// Distance = hypot(eastM, northM); bearing = atan2(eastM, northM) normalised to
// [0,360) with 0 = true North and increasing CLOCKWISE (E = 90, S = 180, W =
// 270). Longitude deltas are wrapped into (−180,180] so the projection stays
// correct across the ±180° antimeridian.
//
// HARD RULES (same as A10): the derived distance / bearing / confidence /
// uncertainty are UI-local — they MUST NEVER be written to any wire payload or
// DB event row. North is FIXED up — v1 does NOT consume a compass / magnetometer
// (the radar does not rotate); that is deliberately deferred to avoid sensor
// permission + calibration burden.

import 'dart:math' as math;

import 'package:ignirelay_app/app/services/position_estimator.dart';

/// One subject's position relative to the local device. UI-local only.
class RelativePosition {
  /// Distance from the local origin, in metres (≥ 0).
  final double distanceM;

  /// Bearing from the local origin: 0 = true North, clockwise, range [0,360).
  final double bearingDeg;

  /// Carried through from the subject's [PositionEstimate] (NEVER persisted).
  final PositionConfidence confidence;
  final double uncertaintyM;
  final int ageSeconds;

  const RelativePosition({
    required this.distanceM,
    required this.bearingDeg,
    required this.confidence,
    required this.uncertaintyM,
    required this.ageSeconds,
  });
}

class RelativePositionProjector {
  const RelativePositionProjector._();

  // ── Frozen projection constants (see file header / map_calibration_v1) ──
  static const double metresPerDegLat = 110574.0;
  static const double metresPerDegLngEquator = 111320.0;

  static double _deg2rad(double d) => d * math.pi / 180.0;

  /// Project [subject] into the local frame centred on [origin].
  ///
  /// Returns `null` when EITHER estimate lacks a lat/lng — a me-centric radar
  /// can only place subjects that have an absolute coordinate (anchor-only fixes
  /// have no bearing-from-me and stay list-only). A `null` [origin] coordinate
  /// is the "no local position" case the UI degrades on (A10b step 1).
  static RelativePosition? relativeTo(
    PositionEstimate origin,
    PositionEstimate subject,
  ) {
    if (!origin.hasLatLng || !subject.hasLatLng) return null;

    final lat0 = origin.lat!;
    final cosLat0 = math.cos(_deg2rad(lat0));

    // Longitude delta wrapped into (−180, 180] so the antimeridian is handled.
    var dLng = subject.lng! - origin.lng!;
    if (dLng > 180.0) {
      dLng -= 360.0;
    } else if (dLng < -180.0) {
      dLng += 360.0;
    }
    final dLat = subject.lat! - origin.lat!;

    final eastM = dLng * metresPerDegLngEquator * cosLat0; // +x = East
    final northM = dLat * metresPerDegLat; //                 +y = North

    final distanceM = math.sqrt(eastM * eastM + northM * northM);

    // atan2(east, north) ⇒ 0 at due North, +90 at due East (clockwise).
    var bearingDeg = math.atan2(eastM, northM) * 180.0 / math.pi;
    if (bearingDeg < 0) bearingDeg += 360.0;
    if (bearingDeg >= 360.0) bearingDeg -= 360.0; // guard 359.9995→0 rounding

    return RelativePosition(
      distanceM: distanceM,
      bearingDeg: bearingDeg,
      confidence: subject.confidence,
      uncertaintyM: subject.uncertaintyM,
      ageSeconds: subject.ageSeconds,
    );
  }

  /// Batch helper: project every entry of [subjects] against [origin], dropping
  /// the ones that cannot be placed (no lat/lng). Key order is preserved.
  static Map<String, RelativePosition> relativeAll(
    PositionEstimate origin,
    Map<String, PositionEstimate> subjects,
  ) {
    final out = <String, RelativePosition>{};
    for (final e in subjects.entries) {
      final rel = relativeTo(origin, e.value);
      if (rel != null) out[e.key] = rel;
    }
    return out;
  }
}
