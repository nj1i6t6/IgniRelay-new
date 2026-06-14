// PresenceController — app-layer orchestrator for publishing PRESENCE (#4-4).
//
// Spec / design: MASTER_EXECUTION_PLAN §5 A2.
//
// The UI (debug shell) must NOT build the wire `LocationEvidence` itself
// (layer rule #4: ui-cannot-import-proto). This controller assembles the
// PRESENCE inputs in the app layer — the anon_user_id from
// [AnonIdentityService] and the current GPS evidence from
// [LocationEvidenceBuilder] — and calls
// `EventPublisherV2Facade.publishPresence`. The UI just calls
// [publishPresence] and gets a plain [BroadcastOutcome] back.

import 'dart:typed_data';

import 'package:ignirelay_app/app/services/anon_identity.dart';
import 'package:ignirelay_app/app/services/event_publisher_v2_facade.dart';
import 'package:ignirelay_app/app/services/location_evidence_builder.dart';

class PresenceController {
  PresenceController({
    required EventPublisherV2Facade facade,
    required AnonIdentityService anonIdentity,
    required LocationEvidenceBuilder locationBuilder,
  })  : _facade = facade,
        _anonIdentity = anonIdentity,
        _locationBuilder = locationBuilder;

  final EventPublisherV2Facade _facade;
  final AnonIdentityService _anonIdentity;
  final LocationEvidenceBuilder _locationBuilder;

  /// Publish a PRESENCE footprint: resolve the anon_user_id, attach the best
  /// current GPS evidence (or none), and broadcast via the v2 facade.
  Future<BroadcastOutcome> publishPresence({int? batteryHint}) async {
    final anonUserId = await _anonIdentity.getOrCreate();
    final location = _locationBuilder.build(); // null when GPS unavailable
    return _facade.publishPresence(
      anonUserId: Uint8List.fromList(anonUserId),
      location: location,
      batteryHint: batteryHint,
    );
  }
}
