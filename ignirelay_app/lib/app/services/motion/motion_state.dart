// MotionState + the pure motion-aware presence cadence matrix (UI-F5a).
//
// Spec: docs/APP_UI_IA_REWORK_PLAN.md §4.2. The cadence is a pure function of
// (motion, low-battery) — easy to unit-test and free of any platform/native
// dependency. The native accelerometer source that drives [MotionState] is
// UI-F5b; until then production motion stays [MotionState.unknown], which maps
// to the SAME fixed 120 s / 300 s cadence the beacon used before UI-F5 (so F5a
// is a zero-behaviour-change cut on real devices).

/// Coarse motion of THIS device, derived locally from low-rate accelerometer
/// magnitude (UI-F5b). `unknown` = no motion source yet / not enough samples —
/// it is NEVER faked as `stationary` (the cadence falls back to the fixed
/// default instead). `staff`-style fabrication has no analogue here.
enum MotionState { unknown, stationary, moving }

/// The presence-beacon interval for a given motion + battery state (§4.2).
///
/// moving 30 s · stationary 180 s · low-battery moving 60 s · low-battery
/// stationary 300 s. `unknown` falls back to [unknownInterval] /
/// [unknownLowBatteryInterval] (120 s / 300 s = the pre-UI-F5 fixed cadence),
/// so a build with no motion source behaves exactly as before.
Duration motionPresenceInterval({
  required MotionState motion,
  required bool lowBattery,
  Duration movingInterval = const Duration(seconds: 30),
  Duration stationaryInterval = const Duration(seconds: 180),
  Duration lowBatteryMovingInterval = const Duration(seconds: 60),
  Duration lowBatteryStationaryInterval = const Duration(seconds: 300),
  Duration unknownInterval = const Duration(seconds: 120),
  Duration unknownLowBatteryInterval = const Duration(seconds: 300),
}) {
  switch (motion) {
    case MotionState.moving:
      return lowBattery ? lowBatteryMovingInterval : movingInterval;
    case MotionState.stationary:
      return lowBattery ? lowBatteryStationaryInterval : stationaryInterval;
    case MotionState.unknown:
      return lowBattery ? unknownLowBatteryInterval : unknownInterval;
  }
}
