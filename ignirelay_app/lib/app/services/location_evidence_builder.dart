import 'package:latlong2/latlong.dart';

import 'package:ignirelay_app/app/crdt/hlc.dart';
import 'package:ignirelay_app/app/proto/event_envelope_v2.dart';
import 'package:ignirelay_app/app/services/location_service.dart';

/// Returns the current device LatLng, or null when GPS is unavailable.
typedef LatLngProvider = LatLng? Function();

/// Builds a [LocationEvidence] from the device's GPS fix.
///
/// Production callers use the default constructor (wraps [LocationService]).
/// Tests inject a [LatLngProvider] via [LocationEvidenceBuilder.forTest].
class LocationEvidenceBuilder {
  final LatLngProvider _latLng;

  LocationEvidenceBuilder({LocationService? locationService})
      : _latLng = _wrapService(locationService ?? LocationService());

  /// Test-only: supply a custom lat/lng provider.
  LocationEvidenceBuilder.forTest(this._latLng);

  LocationEvidence? build() {
    final loc = _latLng();
    if (loc == null) return null;
    final hlc = HLC.now();
    return LocationEvidence.fromDegrees(
      source: LocationSource.gps,
      frame: LocationFrame.subject,
      latDegrees: loc.latitude,
      lngDegrees: loc.longitude,
      observedAt: HlcTimestampV2(
        msSinceEpoch: hlc.timestamp,
        counter: hlc.counter,
      ),
    );
  }

  static LatLngProvider _wrapService(LocationService svc) =>
      () => svc.currentLocation;
}
