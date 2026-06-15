// PositionEstimator — A10. Mapless "last trusted position" fusion.
//
// Spec / design: MASTER_EXECUTION_PLAN §5 A10; REBUILD_PLAN §3.6 (mapless
// 「位置證據」model). The HARD layering rule (§3.6 / REBUILD §3.6 note 1):
//   • `LocationEvidence` (a single observation) rides the wire — small, signed,
//     mergeable.
//   • `PositionEstimate` (the fused best guess: confidence + uncertainty) is
//     **UI-local, derived on the fly, and MUST NEVER be written to any wire
//     payload or DB event row** (A10 prohibition). Storing a HIGH confidence is
//     a lie 30 minutes later (REBUILD §3.6 note); confidence/uncertainty are
//     therefore recomputed from each observation's AGE every time.
//
// Everything here is plain Dart (no app/proto types) so the UI can both feed it
// observations and render its output without crossing the ui-cannot-import-proto
// layer rule.
//
// This file is a pure function library — no I/O, no singletons, no streams.

/// Confidence band for a fused [PositionEstimate], derived from evidence age.
enum PositionConfidence { high, medium, low }

/// A single position observation — the UI-local, plain-Dart projection of a
/// received `LocationEvidence` (from a PRESENCE / CHECKPOINT read-model row).
/// `lat`/`lng` are absent for anchor-only fixes; `accuracyM == 0` means unknown.
class PositionObservation {
  final double? lat;
  final double? lng;

  /// Anchor (Field Node / checkpoint) id when the fix is anchor-relative.
  final String? anchorNodeId;

  /// Distance from [anchorNodeId] in metres, when known.
  final double? distanceM;

  /// Bearing to the subject, degrees 0..359, when known.
  final double? bearingDeg;

  /// Horizontal accuracy estimate in metres (0 == unknown).
  final int accuracyM;

  /// `LocationSource.*` numeric (1=GPS, 2=FIELD_NODE, 3=BLE_RSSI, …). Kept as a
  /// plain int so the UI need not import app/proto.
  final int source;

  /// When the observation was made (UI clock / HLC ms mapped to DateTime).
  final DateTime observedAt;

  const PositionObservation({
    this.lat,
    this.lng,
    this.anchorNodeId,
    this.distanceM,
    this.bearingDeg,
    this.accuracyM = 0,
    this.source = 0,
    required this.observedAt,
  });

  bool get hasLatLng => lat != null && lng != null;
}

/// The fused best estimate for one subject. UI-local only (see file header).
class PositionEstimate {
  final double? lat;
  final double? lng;
  final String? anchorNodeId;
  final double? distanceM;
  final double? bearingDeg;

  /// Derived from [ageSeconds] at estimation time — NEVER persisted.
  final PositionConfidence confidence;

  /// Derived radius in metres; grows with age (NEVER persisted).
  final double uncertaintyM;

  /// Age of the freshest evidence the estimate is built from, in seconds.
  final int ageSeconds;

  const PositionEstimate({
    this.lat,
    this.lng,
    this.anchorNodeId,
    this.distanceM,
    this.bearingDeg,
    required this.confidence,
    required this.uncertaintyM,
    required this.ageSeconds,
  });

  bool get hasLatLng => lat != null && lng != null;
}

class PositionEstimator {
  const PositionEstimator._();

  // ── Confidence age thresholds (A10 / §3.6 principle 4) ──────────────────
  // ≤2min → HIGH, ≤10min → MEDIUM, otherwise LOW. Inclusive upper bounds.
  static const Duration highMaxAge = Duration(minutes: 2);
  static const Duration mediumMaxAge = Duration(minutes: 10);

  // ── Uncertainty growth (§3.6 principle 4: "uncertainty 隨時間增加") ───────
  // uncertainty = base + growthRate × ageSeconds, linear. The base is the
  // observation's own accuracy when known, else a GPS-class seed. These are the
  // ONLY tuning constants; they are derivation parameters, never wire/DB values.
  static const double baseUncertaintyM = 15.0;
  static const double uncertaintyGrowthMPerSec = 0.5;

  /// Map an evidence age (seconds, clamped to ≥0) to a confidence band.
  /// Boundaries: 120s → HIGH, 121s → MEDIUM, 600s → MEDIUM, 601s → LOW.
  static PositionConfidence confidenceForAge(int ageSeconds) {
    final age = ageSeconds < 0 ? 0 : ageSeconds;
    if (age <= highMaxAge.inSeconds) return PositionConfidence.high;
    if (age <= mediumMaxAge.inSeconds) return PositionConfidence.medium;
    return PositionConfidence.low;
  }

  /// Derived uncertainty radius (metres) for an observation at the given age.
  static double uncertaintyForAge(int accuracyM, int ageSeconds) {
    final age = ageSeconds < 0 ? 0 : ageSeconds;
    final base = accuracyM > 0 ? accuracyM.toDouble() : baseUncertaintyM;
    return base + uncertaintyGrowthMPerSec * age;
  }

  /// Fuse one subject's observation set into a single [PositionEstimate], or
  /// `null` when there is no evidence. v1 fusion = "freshest fix wins" (the most
  /// recent observation by [PositionObservation.observedAt]); richer multi-
  /// evidence fusion (weighting by source/accuracy) is a later phase. Confidence
  /// and uncertainty are derived from that fix's AGE relative to [now]
  /// (defaults to `DateTime.now()`), never read from storage.
  static PositionEstimate? estimate(
    List<PositionObservation> evidence, {
    DateTime? now,
  }) {
    if (evidence.isEmpty) return null;
    final clock = now ?? DateTime.now();
    var latest = evidence.first;
    for (final o in evidence) {
      if (o.observedAt.isAfter(latest.observedAt)) latest = o;
    }
    final ageRaw = clock.difference(latest.observedAt).inSeconds;
    final age = ageRaw < 0 ? 0 : ageRaw;
    return PositionEstimate(
      lat: latest.lat,
      lng: latest.lng,
      anchorNodeId: latest.anchorNodeId,
      distanceM: latest.distanceM,
      bearingDeg: latest.bearingDeg,
      confidence: confidenceForAge(age),
      uncertaintyM: uncertaintyForAge(latest.accuracyM, age),
      ageSeconds: age,
    );
  }
}
