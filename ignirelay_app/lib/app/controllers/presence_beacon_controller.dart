// PresenceBeaconController — A9 (1). Periodic PRESENCE footprint beacon.
//
// Spec / design: MASTER_EXECUTION_PLAN §5 A9 (1); whitepaper PRESENCE = a node's
// "last footprint" (LWW by anon_user_id). The beacon refreshes that footprint on
// a fixed cadence so the mesh keeps a fresh "last seen here" for this node
// WITHOUT the user pressing anything. It is the automatic counterpart to the
// manual `PresenceController.publishPresence` (A2) — and publishes through that
// same path (the publish callback is wired to it in `main.dart`).
//
// CADENCE (all three are constructor constants — "參數常數化"):
//   • normal:       every [normalInterval]      (120s default)
//   • low battery:  every [lowBatteryInterval]  (300s default) when the battery
//     reading is below [lowBatteryThreshold] (20%) — fewer radio wakeups when
//     the battery is critical. The battery is re-read before every (re)arm, so
//     the cadence adapts as the battery drains/charges, including the FIRST
//     interval.
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
  })  : _publish = publish,
        _isMeshRunning = isMeshRunning,
        _hasJoinedField = hasJoinedField,
        _readBattery = readBattery,
        _normalInterval = normalInterval,
        _lowBatteryInterval = lowBatteryInterval,
        _lowBatteryThreshold = lowBatteryThreshold,
        _now = now ?? DateTime.now,
        _enabled = enabled {
    _currentInterval = _normalInterval;
    if (_enabled) unawaited(_arm());
  }

  final PresenceBeaconPublish _publish;
  final bool Function() _isMeshRunning;
  final bool Function() _hasJoinedField;
  final Future<int?> Function()? _readBattery;
  final Duration _normalInterval;
  final Duration _lowBatteryInterval;
  final int _lowBatteryThreshold;
  final DateTime Function() _now;

  bool _enabled;
  bool _disposed = false;
  Timer? _timer;
  int _beaconCount = 0;
  int? _lastBattery;
  DateTime? _lastBeaconAt;
  late Duration _currentInterval;

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

  /// Re-read the battery, recompute the cadence, and (re)arm the one-shot timer.
  Future<void> _arm() async {
    if (_disposed || !_enabled) return;
    final battery = await _readBatterySafely();
    if (_disposed || !_enabled) return;
    _lastBattery = battery;
    _currentInterval = (battery != null && battery < _lowBatteryThreshold)
        ? _lowBatteryInterval
        : _normalInterval;
    _timer?.cancel();
    _timer = Timer(_currentInterval, _onFire);
    notifyListeners();
  }

  Future<void> _onFire() async {
    if (_disposed) return;
    if (_enabled && _isMeshRunning() && _hasJoinedField()) {
      try {
        await _publish(batteryHint: _lastBattery);
        _beaconCount++;
        _lastBeaconAt = _now();
      } catch (e) {
        // Beacon is best-effort; a failed publish must not kill the loop.
        debugPrint('[PresenceBeacon] publish failed: $e');
      }
    }
    // Re-arm even when gated, so the loop resumes beaconing the moment the mesh
    // starts / a field is joined — without waiting for the user to toggle.
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
    _timer?.cancel();
    _timer = null;
    super.dispose();
  }
}
