// LocationRefreshCoordinator — UI-F5b. The side-effecting half of §4.2's GPS
// policy: it decides (via the pure `gps_refresh_policy`) when to take a one-shot
// `LocationService.refreshOnce`, and records the honest reason + fix age for the
// A11 diagnostic.
//
// It wraps [LocationService] through injected callbacks (lastFixAt / refreshOnce
// / now) so it is unit-testable with fakes — no platform plugin, no singleton.
//
// Two entry points:
//   • ensureFreshForBeacon(motion) — used by the PRESENCE beacon's pre-publish
//     hook: refreshes ONLY when moving & the last fix is stale (§4.2); stationary
//     / unknown reuse the last fix. Reason → movingRefresh / stationaryReuse /
//     unknownReuse / unavailable.
//   • ensureFreshForManualEvent(timeout) — used by SOS / markSafe / HAZARD /
//     CHECKPOINT: ONE bounded fresh fix, falling back to last-known; never throws
//     and never blocks past the timeout (Owner boundary 3). Reason → manualEvent
//     (or unavailable when no fix exists at all).

import 'package:latlong2/latlong.dart';

import 'package:ignirelay_app/app/services/motion/gps_refresh_policy.dart';
import 'package:ignirelay_app/app/services/motion/motion_state.dart';

class LocationRefreshCoordinator {
  LocationRefreshCoordinator({
    required DateTime? Function() lastFixAt,
    required Future<LatLng?> Function(Duration timeout) refreshOnce,
    DateTime Function()? now,
    Duration beaconRefreshTimeout = const Duration(seconds: 8),
    Duration movingMinFixAge = const Duration(seconds: 30),
  })  : _lastFixAt = lastFixAt,
        _refreshOnce = refreshOnce,
        _now = now ?? DateTime.now,
        _beaconRefreshTimeout = beaconRefreshTimeout,
        _movingMinFixAge = movingMinFixAge;

  final DateTime? Function() _lastFixAt;
  final Future<LatLng?> Function(Duration timeout) _refreshOnce;
  final DateTime Function() _now;
  final Duration _beaconRefreshTimeout;
  final Duration _movingMinFixAge;

  GpsPolicyReason _lastReason = GpsPolicyReason.unknownReuse;

  /// The age of the current fix, or null when no fix has ever been obtained.
  Duration? get lastFixAge {
    final at = _lastFixAt();
    if (at == null) return null;
    return _now().difference(at);
  }

  /// The honest reason the GPS policy last acted (A11 diagnostic, §4.2).
  GpsPolicyReason get lastReason => _lastReason;

  /// PRESENCE beacon pre-publish hook: refresh GPS only when moving & the last
  /// fix is stale; otherwise reuse. Updates [lastReason]. Never throws.
  Future<void> ensureFreshForBeacon(MotionState motion) async {
    final refresh = shouldRefreshBeforePresence(
      motion: motion,
      fixAge: lastFixAge,
      movingMinFixAge: _movingMinFixAge,
    );
    if (refresh) {
      await _refreshOnce(_beaconRefreshTimeout);
    }
    _lastReason = gpsReasonForBeacon(
      motion: motion,
      hasAnyFix: _lastFixAt() != null,
      refreshed: refresh,
    );
  }

  /// Manual safety event hook: ONE bounded fresh fix, falling back to last-known.
  /// Returns the fresh-or-last-known fix (may be null). Updates [lastReason] to
  /// `manualEvent`, or `unavailable` when no fix exists at all. Never throws.
  Future<LatLng?> ensureFreshForManualEvent({
    required Duration timeout,
  }) async {
    final fix = await _refreshOnce(timeout);
    _lastReason = (fix == null && _lastFixAt() == null)
        ? GpsPolicyReason.unavailable
        : GpsPolicyReason.manualEvent;
    return fix;
  }
}
