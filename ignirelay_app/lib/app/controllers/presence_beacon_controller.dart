// PresenceBeaconController — A9 (1). Periodic PRESENCE footprint beacon.
//
// Spec / design: MASTER_EXECUTION_PLAN §5 A9 (1); whitepaper PRESENCE = a node's
// "last footprint" (LWW by anon_user_id). The beacon refreshes that footprint on
// a fixed cadence so the mesh keeps a fresh "last seen here" for this node
// WITHOUT the user pressing anything. It is the automatic counterpart to the
// manual `PresenceController.publishPresence` (A2) — and publishes through that
// same path (the publish callback is wired to it in `main.dart`).
//
// CADENCE (all constructor constants — "參數常數化"). UI-F5a makes it
// motion-aware (§4.2): the interval is chosen by (motion × battery) via
// `motionPresenceInterval`:
//   • moving 30s / stationary 180s; low-battery moving 60s / stationary 300s;
//   • `unknown` motion (no source wired — the F5a default, until F5b's native
//     accelerometer) falls back to the prior fixed [normalInterval] (120s) /
//     [lowBatteryInterval] (300s) — so F5a is a zero-behaviour-change cut.
//   The battery is re-read before every (re)arm (low when < [lowBatteryThreshold],
//   20%), so the cadence adapts as the battery drains/charges, incl. the FIRST
//   interval. A `stationary → moving` transition publishes immediately (gated)
//   when the last beacon is older than [transitionMinGap] (15s).
//
// GATES — the tick is a strict NO-OP unless BOTH hold (it never beacons
// otherwise; this is the A9 prohibition "beacon 在未加入場域時發送"):
//   1. the mesh transport is running          ([isMeshRunning])
//   2. a field is joined / active             ([hasJoinedField])
// A zero-field PRESENCE would be rejected by the publish facade (A5 §21.6) and
// dropped by every peer anyway, so we do not even attempt it.
//
// UI: a single on/off [enabled] toggle (default ON). Turning it off cancels the
// loop; turning it on re-arms it. Exposed as a [ChangeNotifier] so the debug
// shell switch reflects state.
//
// TESTABILITY: the periodic beacon is a plain one-shot [Timer] re-armed each
// cycle (NOT Timer.periodic — so the cadence can change between cycles), the
// clock is injected ([now]), and battery / gates / publish are plain callbacks.
// The whole cadence (incl. the low-battery downshift and the no-field gate) is
// asserted under `package:fake_async` with zero real time and no platform
// plugins.

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:ignirelay_app/app/services/motion/motion_state.dart';

/// Publish one PRESENCE footprint, optionally tagging the coarse battery hint.
/// Wired in production to `PresenceController.publishPresence`.
typedef PresenceBeaconPublish = Future<void> Function({int? batteryHint});

class PresenceBeaconController extends ChangeNotifier {
  PresenceBeaconController({
    required PresenceBeaconPublish publish,
    required bool Function() isMeshRunning,
    required bool Function() hasJoinedField,
    Future<int?> Function()? readBattery,
    Duration normalInterval = const Duration(seconds: 120),
    Duration lowBatteryInterval = const Duration(seconds: 300),
    int lowBatteryThreshold = 20,
    DateTime Function()? now,
    bool enabled = true,
    // UI-F5a — motion-aware cadence. When [motionStates] is null the controller
    // behaves exactly as before (motion stays `unknown` → normal/low-battery
    // fallback). The four motion intervals are §4.2 constants.
    Stream<MotionState>? motionStates,
    Duration movingInterval = const Duration(seconds: 30),
    Duration stationaryInterval = const Duration(seconds: 180),
    Duration lowBatteryMovingInterval = const Duration(seconds: 60),
    Duration lowBatteryStationaryInterval = const Duration(seconds: 300),
    Duration transitionMinGap = const Duration(seconds: 15),
    // UI-F5b — optional pre-publish hook (§4.2 GPS refresh). Runs INSIDE the
    // gate, just before [publish], with the current motion; its failure never
    // aborts the publish. When null the beacon behaves exactly as before.
    Future<void> Function(MotionState motion)? onBeforePublish,
  })  : _publish = publish,
        _onBeforePublish = onBeforePublish,
        _isMeshRunning = isMeshRunning,
        _hasJoinedField = hasJoinedField,
        _readBattery = readBattery,
        _normalInterval = normalInterval,
        _lowBatteryInterval = lowBatteryInterval,
        _lowBatteryThreshold = lowBatteryThreshold,
        _movingInterval = movingInterval,
        _stationaryInterval = stationaryInterval,
        _lowBatteryMovingInterval = lowBatteryMovingInterval,
        _lowBatteryStationaryInterval = lowBatteryStationaryInterval,
        _transitionMinGap = transitionMinGap,
        _now = now ?? DateTime.now,
        _enabled = enabled {
    _currentInterval = _normalInterval;
    if (motionStates != null) {
      _motionSub = motionStates.listen(_onMotion);
    }
    if (_enabled) unawaited(_arm());
  }

  final PresenceBeaconPublish _publish;
  final Future<void> Function(MotionState motion)? _onBeforePublish;
  final bool Function() _isMeshRunning;
  final bool Function() _hasJoinedField;
  final Future<int?> Function()? _readBattery;
  final Duration _normalInterval;
  final Duration _lowBatteryInterval;
  final int _lowBatteryThreshold;
  final Duration _movingInterval;
  final Duration _stationaryInterval;
  final Duration _lowBatteryMovingInterval;
  final Duration _lowBatteryStationaryInterval;
  final Duration _transitionMinGap;
  final DateTime Function() _now;

  bool _enabled;
  bool _disposed = false;
  Timer? _timer;
  int _beaconCount = 0;
  int? _lastBattery;
  DateTime? _lastBeaconAt;
  late Duration _currentInterval;

  // UI-F5a — current coarse motion. `unknown` until a motion source (F5b) feeds
  // the classifier; never faked as `stationary`.
  MotionState _motion = MotionState.unknown;
  StreamSubscription<MotionState>? _motionSub;

  /// The UI toggle state. Default ON; persists only in memory (the loop is a
  /// foreground affordance — it is re-created with the provider each launch).
  bool get enabled => _enabled;

  /// True while a beacon timer is armed.
  bool get isRunning => _timer != null;

  /// How many footprints this controller has actually published (gates passed).
  int get beaconCount => _beaconCount;

  /// The cadence the NEXT beacon is scheduled at (120s normal / 300s low batt).
  Duration get currentInterval => _currentInterval;

  /// Last battery reading used for the cadence decision (null = unknown).
  int? get lastBattery => _lastBattery;

  /// True when the last reading put us on the low-battery (slower) cadence.
  bool get isLowBattery =>
      _lastBattery != null && _lastBattery! < _lowBatteryThreshold;

  /// When the last footprint was actually published (null = none yet).
  DateTime? get lastBeaconAt => _lastBeaconAt;

  /// (UI-F5a) Current coarse motion driving the cadence. `unknown` until a
  /// motion source is wired (UI-F5b) — surfaced as a diagnostic; never faked.
  MotionState get motionState => _motion;

  /// Turn the automatic beacon on/off (the debug-shell switch).
  void setEnabled(bool value) {
    if (_enabled == value) return;
    _enabled = value;
    if (_enabled) {
      unawaited(_arm());
    } else {
      _timer?.cancel();
      _timer = null;
      notifyListeners();
    }
  }

  /// Re-read the battery, recompute the cadence (motion × battery — §4.2), and
  /// (re)arm the one-shot timer.
  Future<void> _arm() async {
    if (_disposed || !_enabled) return;
    final battery = await _readBatterySafely();
    if (_disposed || !_enabled) return;
    _lastBattery = battery;
    final lowBattery = battery != null && battery < _lowBatteryThreshold;
    _currentInterval = motionPresenceInterval(
      motion: _motion,
      lowBattery: lowBattery,
      movingInterval: _movingInterval,
      stationaryInterval: _stationaryInterval,
      lowBatteryMovingInterval: _lowBatteryMovingInterval,
      lowBatteryStationaryInterval: _lowBatteryStationaryInterval,
      unknownInterval: _normalInterval,
      unknownLowBatteryInterval: _lowBatteryInterval,
    );
    _timer?.cancel();
    _timer = Timer(_currentInterval, _onFire);
    notifyListeners();
  }

  /// Publish one footprint IFF the gates pass (enabled ∧ mesh ∧ field). Shared
  /// by the periodic tick and the motion transition trigger so BOTH obey the
  /// A5 §21.6 gate (UI-F5a / Owner boundary 3).
  Future<void> _publishIfGated() async {
    if (_enabled && _isMeshRunning() && _hasJoinedField()) {
      // UI-F5b: GPS refresh hook runs INSIDE the gate, before publish. Its
      // failure must NEVER abort the publish (§4.2 / Owner boundaries 3 & 11),
      // so it is awaited in its own guarded block.
      try {
        await _onBeforePublish?.call(_motion);
      } catch (e) {
        debugPrint('[PresenceBeacon] onBeforePublish failed: $e');
      }
      try {
        await _publish(batteryHint: _lastBattery);
        _beaconCount++;
        _lastBeaconAt = _now();
      } catch (e) {
        // Beacon is best-effort; a failed publish must not kill the loop.
        debugPrint('[PresenceBeacon] publish failed: $e');
      }
    }
  }

  Future<void> _onFire() async {
    if (_disposed) return;
    await _publishIfGated();
    // Re-arm even when gated, so the loop resumes beaconing the moment the mesh
    // starts / a field is joined — without waiting for the user to toggle.
    await _arm();
  }

  /// UI-F5a — react to a motion-state change. A `stationary → moving`
  /// transition publishes immediately (gates permitting) when the last beacon
  /// is stale (older than [transitionMinGap], or none yet), then re-arms at the
  /// moving cadence. Other changes just re-arm so the new cadence applies.
  void _onMotion(MotionState next) {
    if (_disposed) return;
    final prev = _motion;
    if (prev == next) return;
    _motion = next;
    // Paused (disabled): never publish or arm, but the motion diagnostic still
    // changed — notify so the UI refreshes. This must come BEFORE the
    // transition branch: a `stationary → moving` change while disabled would
    // otherwise fall into [_publishNowAndRearm] → [_arm], both of which early-
    // return without notifying, leaving the diagnostic stale (UI-F5a-polish).
    if (!_enabled) {
      notifyListeners();
      return;
    }
    final last = _lastBeaconAt;
    final stale = last == null || _now().difference(last) >= _transitionMinGap;
    if (prev == MotionState.stationary &&
        next == MotionState.moving &&
        stale) {
      // Immediate (gated) publish, then re-arm at the new cadence.
      _timer?.cancel();
      _timer = null;
      unawaited(_publishNowAndRearm());
    } else {
      unawaited(_arm());
    }
  }

  Future<void> _publishNowAndRearm() async {
    if (_disposed) return;
    await _publishIfGated();
    await _arm();
  }

  Future<int?> _readBatterySafely() async {
    final reader = _readBattery;
    if (reader == null) return null;
    try {
      return await reader();
    } catch (_) {
      // No battery plugin / platform channel (tests, headless) → unknown.
      return null;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _motionSub?.cancel();
    _motionSub = null;
    _timer?.cancel();
    _timer = null;
    super.dispose();
  }
}
