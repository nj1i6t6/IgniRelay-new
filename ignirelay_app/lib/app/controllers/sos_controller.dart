// SosController — app-layer state machine for the SOS UX (A8 / 白皮書 §13.4).
//
// Spec / design: MASTER_EXECUTION_PLAN A8.
//
// Drives the misfire-guarded SOS flow so the UI never touches app/proto and
// never sends without the mandatory countdown:
//
//   idle ──arm(safetyState)──▶ countdown ──(5s elapsed)──▶ sending ──▶ sent
//     ▲                            │
//     └────── cancelCountdown ─────┘   (誤觸防護: aborts before any publish)
//
// The wire SOS is a STATUS_UPDATE carrying the chosen `safetyState`
// (TRAPPED=RED / INJURED=YELLOW) plus the device's best current location
// (A4 / OD-1; null when no GPS). The §5.3 priority floor (TRAPPED→SOS_RED,
// INJURED→SOS_YELLOW) is applied by the facade, not here.
//
// "我安全了" (markSafe) re-publishes a STATUS_UPDATE with safetyState=SAFE. Per
// OD-8 there is NO `SOS_CANCELLED` wire type: LWW (spec §10.2, STATUS_UPDATE by
// author) converges the whole mesh to the latest state, and the read-model
// marks the prior SOS resolved.

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:ignirelay_app/app/proto/event_envelope_v2.dart' show SafetyState;
import 'package:ignirelay_app/app/services/event_publisher_v2_facade.dart';
import 'package:ignirelay_app/app/services/location_evidence_builder.dart';

/// SOS flow phase. The countdown is the misfire guard; `sending`/`sent`/`failed`
/// reflect the publish call's lifecycle.
enum SosPhase { idle, countdown, sending, sent, failed }

/// UI-facing SOS severity. Maps to the wire [SafetyState] inside the controller
/// so the UI layer never imports `app/proto` (layer rule ui-cannot-import-proto).
enum SosSeverity {
  /// TRAPPED → SOS_RED (§5.3 floor).
  trapped,

  /// INJURED → SOS_YELLOW (§5.3 floor).
  injured;

  int get safetyState =>
      this == SosSeverity.trapped ? SafetyState.trapped : SafetyState.injured;
}

class SosController extends ChangeNotifier {
  SosController({
    required EventPublisherV2Facade facade,
    required LocationEvidenceBuilder locationBuilder,
    Duration countdownDuration = const Duration(seconds: 5),
  })  : _facade = facade,
        _locationBuilder = locationBuilder,
        _countdown = countdownDuration;

  final EventPublisherV2Facade _facade;
  final LocationEvidenceBuilder _locationBuilder;
  final Duration _countdown;

  Timer? _tickTimer;
  Timer? _sendTimer;

  SosPhase _phase = SosPhase.idle;
  int _secondsRemaining = 0;
  SosSeverity? _armedSeverity;
  SosSeverity? _activeSeverity;
  BroadcastOutcome? _lastOutcome;

  SosPhase get phase => _phase;

  /// Seconds left on the cancel countdown (only meaningful while
  /// [phase] == [SosPhase.countdown]).
  int get secondsRemaining => _secondsRemaining;

  /// The severity chosen for the in-flight / counting-down SOS.
  SosSeverity? get armedSeverity => _armedSeverity;

  /// The severity of the SOS currently broadcast for THIS device, or null once
  /// "我安全了" has cleared it. Drives the persistent "you are in SOS" banner +
  /// the markSafe affordance.
  SosSeverity? get activeSeverity => _activeSeverity;

  bool get isCountingDown => _phase == SosPhase.countdown;

  /// Whether this device has a live (un-cleared) SOS out on the mesh.
  bool get hasActiveSos => _activeSeverity != null;

  /// The outcome of the last publish (send or markSafe), for the status row.
  BroadcastOutcome? get lastOutcome => _lastOutcome;

  /// Begin the 5-second cancelable countdown for an SOS of [severity]. Re-arming
  /// while already counting down restarts with the new severity. No publish
  /// happens until the countdown elapses.
  void arm(SosSeverity severity) {
    _cancelTimers();
    _armedSeverity = severity;
    _phase = SosPhase.countdown;
    _secondsRemaining = _countdown.inSeconds;
    notifyListeners();
    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_secondsRemaining > 0) {
        _secondsRemaining -= 1;
        notifyListeners();
      }
    });
    _sendTimer = Timer(_countdown, () {
      _tickTimer?.cancel();
      _send();
    });
  }

  /// Abort the countdown before any publish (misfire guard). No-op unless
  /// currently counting down.
  void cancelCountdown() {
    if (_phase != SosPhase.countdown) return;
    _cancelTimers();
    _armedSeverity = null;
    _secondsRemaining = 0;
    _phase = SosPhase.idle;
    notifyListeners();
  }

  Future<void> _send() async {
    final severity = _armedSeverity;
    if (severity == null) return;
    _phase = SosPhase.sending;
    notifyListeners();
    try {
      final outcome = await _facade.publishStatusUpdate(
        safetyState: severity.safetyState,
        location: _locationBuilder.build(), // null when no GPS — still sent
      );
      _activeSeverity = severity;
      _lastOutcome = outcome;
      _phase = SosPhase.sent;
    } catch (_) {
      _phase = SosPhase.failed;
    }
    notifyListeners();
  }

  /// "我安全了" — clear this device's SOS by broadcasting a SAFE STATUS_UPDATE
  /// (OD-8: no new wire type; LWW converges + read-model marks resolved).
  /// Returns the publish outcome (null if a send was somehow in flight with no
  /// armed state).
  Future<BroadcastOutcome?> markSafe() async {
    _cancelTimers();
    final outcome = await _facade.publishStatusUpdate(
      safetyState: SafetyState.safe,
      location: _locationBuilder.build(),
    );
    _activeSeverity = null;
    _armedSeverity = null;
    _lastOutcome = outcome;
    _phase = SosPhase.idle;
    notifyListeners();
    return outcome;
  }

  void _cancelTimers() {
    _tickTimer?.cancel();
    _tickTimer = null;
    _sendTimer?.cancel();
    _sendTimer = null;
  }

  @override
  void dispose() {
    _cancelTimers();
    super.dispose();
  }
}
