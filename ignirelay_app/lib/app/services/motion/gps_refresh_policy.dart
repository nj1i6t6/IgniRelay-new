// GPS-fix-age policy — the pure half of UI-F5b's §4.2 location behaviour.
//
// Spec: docs/APP_UI_IA_REWORK_PLAN.md §4.2. Like [motionPresenceInterval], these
// are pure functions of (motion, fix-age) so they are unit-testable with a fake
// clock and free of any platform/Geolocator dependency. The side-effecting part
// (actually calling `LocationService.refreshOnce`) lives in
// `LocationRefreshCoordinator`; this file only decides WHETHER and reports WHY.
//
// §4.2 behaviour encoded here:
//   • moving    → refresh GPS before PRESENCE when the last fix is older than
//                 `moving_min_fix_age` (30 s); publish at the moving cadence.
//   • stationary→ reuse the last known fix; never trigger a refresh (and the
//                 always-on high-accuracy stream is removed elsewhere, so GPS is
//                 never hot while stationary).
//   • unknown   → reuse the last known fix (no source wired / not enough samples).

import 'package:ignirelay_app/app/services/motion/motion_state.dart';

/// The honest set of reasons the GPS policy can report for the A11 diagnostic
/// (§4.2 "GPS policy reason"). Deliberately has NO `lowBattery` member: low
/// battery changes the *presence cadence*, not the GPS-refresh decision, so it
/// is surfaced on the beacon-cadence line instead — never disguised as a GPS
/// reason (Owner boundary 8).
enum GpsPolicyReason {
  /// Moving + stale fix → a one-shot high-accuracy refresh was actually taken.
  movingRefresh,

  /// Moving but the last fix was still fresh (< moving_min_fix_age) → it is
  /// reused; NO refresh was taken. Distinct from [movingRefresh] so the A11
  /// diagnostic never claims a refresh that did not happen.
  movingReuseFreshFix,

  /// Stationary → the last known fix is reused; no refresh.
  stationaryReuse,

  /// Motion unknown (no source / too few samples) → the last fix is reused.
  unknownReuse,

  /// A manual safety event requested one bounded fresh fix.
  manualEvent,

  /// No fix is available at all (never acquired, or a refresh failed/timed out).
  unavailable,
}

/// Whether a PRESENCE beacon should take a one-shot GPS refresh BEFORE publishing
/// (§4.2). True only when [motion] is `moving` AND the last fix is missing or at
/// least [movingMinFixAge] old. Stationary / unknown always reuse the last fix.
bool shouldRefreshBeforePresence({
  required MotionState motion,
  required Duration? fixAge,
  Duration movingMinFixAge = const Duration(seconds: 30),
}) {
  if (motion != MotionState.moving) return false;
  return fixAge == null || fixAge >= movingMinFixAge;
}

/// The honest GPS policy reason for a beacon publish, given the motion state,
/// whether ANY fix (fresh or last-known) is available afterwards, and whether a
/// refresh was actually taken ([refreshed]). Moving splits into [movingRefresh]
/// (a refresh ran) vs [movingReuseFreshFix] (the fix was still fresh, so no
/// refresh) — the diagnostic never claims a refresh that did not happen.
/// `manualEvent` is set by the coordinator's manual path, not derived here.
GpsPolicyReason gpsReasonForBeacon({
  required MotionState motion,
  required bool hasAnyFix,
  bool refreshed = false,
}) {
  if (!hasAnyFix) return GpsPolicyReason.unavailable;
  switch (motion) {
    case MotionState.moving:
      return refreshed
          ? GpsPolicyReason.movingRefresh
          : GpsPolicyReason.movingReuseFreshFix;
    case MotionState.stationary:
      return GpsPolicyReason.stationaryReuse;
    case MotionState.unknown:
      return GpsPolicyReason.unknownReuse;
  }
}
