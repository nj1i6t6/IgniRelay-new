// LocalPositionSource — A10b. The device's OWN latest position, as a plain-Dart
// observation / estimate for the relative-position radar's origin.
//
// Spec / design: MASTER_EXECUTION_PLAN §5 A10b step 1 ("本機最新 PositionEstimate").
//
// FIRST-RISK RULE (A10b): "me" must be the device's own GPS fix — NEVER guessed
// from a received PRESENCE / SOS / CHECKPOINT (i.e. never "the first peer" or
// "the newest row"). This wraps the legacy [LocationService] singleton in the
// app layer so the UI reads the local fix through DI and never touches the
// singleton directly (CLAUDE.md: legacy singletons may be wrapped, not leaked to
// UI). Returns `null` when no GPS fix is available — the radar then degrades to
// the list view with a "需要本機位置" hint.
//
// The GPS source and the clock are injected as plain callbacks so this is
// unit-/widget-testable without the platform location plugin.

import 'package:latlong2/latlong.dart';

import 'package:ignirelay_app/app/services/location_service.dart';
import 'package:ignirelay_app/app/services/position_estimator.dart';

class LocalPositionSource {
  LocalPositionSource({
    LatLng? Function()? currentLocation,
    DateTime Function()? now,
  })  : _currentLocation =
            currentLocation ?? (() => LocationService().currentLocation),
        _now = now ?? DateTime.now;

  final LatLng? Function() _currentLocation;
  final DateTime Function() _now;

  /// The device's own position as a single observation, or `null` when GPS is
  /// unavailable. `observedAt` = now() because [LocationService] does not retain
  /// the fix time; the origin's own age is irrelevant to the radar — the origin
  /// is the centre, not a plotted/aged dot, so only SUBJECT ages drive
  /// confidence / uncertainty.
  PositionObservation? currentObservation() {
    final loc = _currentLocation();
    if (loc == null) return null;
    return PositionObservation(
      lat: loc.latitude,
      lng: loc.longitude,
      source: 1, // LocationSource.gps
      observedAt: _now(),
    );
  }

  /// The device's own position fused into a [PositionEstimate] (the radar
  /// origin), or `null` when there is no fix.
  PositionEstimate? currentEstimate() {
    final obs = currentObservation();
    if (obs == null) return null;
    return PositionEstimator.estimate([obs], now: _now());
  }
}
