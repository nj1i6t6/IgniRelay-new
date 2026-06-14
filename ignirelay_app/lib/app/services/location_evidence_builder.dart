// LocationEvidenceBuilder — turns the device's current GPS fix into a wire
// `LocationEvidence` (or `null` when GPS is unavailable).
//
// Spec / design: MASTER_EXECUTION_PLAN §5 A2 step 2, PHASE0B4_WIRE_DESIGN §3.1.
//
// Wraps `LocationService` (the legacy GPS singleton). When a fix is available
// it produces a SUBJECT-frame, GPS-source `LocationEvidence` with lat/lng
// quantized to 1e7 fixed-point ROUND-TO-NEAREST (the only rounding mode all
// platforms agree on — see `LocationEvidence.fromDegrees`). When GPS is
// unavailable it returns `null`; anchor / PDR fixes are A10 / Phase 1.
//
// The GPS source and the clock are injected as plain callbacks so the builder
// is unit-testable (esp. the 1e7 rounding, incl. the 25.0339805 IEEE-754 trap)
// without standing up the platform location plugin.

import 'package:latlong2/latlong.dart';

import 'package:ignirelay_app/app/crdt/hlc.dart';
import 'package:ignirelay_app/app/proto/event_envelope_v2.dart';
import 'package:ignirelay_app/app/services/location_service.dart';

class LocationEvidenceBuilder {
  /// [currentLocation] supplies the latest known fix (null == no GPS); defaults
  /// to the `LocationService` singleton. [clock] supplies `observed_at`;
  /// defaults to `HLC.now()`.
  LocationEvidenceBuilder({
    LatLng? Function()? currentLocation,
    HlcTimestampV2 Function()? clock,
  })  : _currentLocation =
            currentLocation ?? (() => LocationService().currentLocation),
        _clock = clock ?? _hlcNow;

  final LatLng? Function() _currentLocation;
  final HlcTimestampV2 Function() _clock;

  /// Build SUBJECT-frame GPS evidence from the current fix, or `null` when no
  /// GPS fix is available.
  LocationEvidence? build() {
    final loc = _currentLocation();
    if (loc == null) return null;
    return buildFromDegrees(
      latDegrees: loc.latitude,
      lngDegrees: loc.longitude,
    );
  }

  /// Build SUBJECT-frame GPS evidence from explicit degrees. lat/lng are
  /// quantized to the nearest 1e7 fixed-point unit (round-to-nearest); the
  /// `observed_at` HLC comes from the injected clock.
  LocationEvidence buildFromDegrees({
    required double latDegrees,
    required double lngDegrees,
    int accuracyM = 0,
  }) {
    return LocationEvidence.fromDegrees(
      source: LocationSource.gps,
      frame: LocationFrame.subject,
      latDegrees: latDegrees,
      lngDegrees: lngDegrees,
      accuracyM: accuracyM,
      observedAt: _clock(),
    );
  }

  static HlcTimestampV2 _hlcNow() {
    final h = HLC.now();
    return HlcTimestampV2(msSinceEpoch: h.timestamp, counter: h.counter);
  }
}
