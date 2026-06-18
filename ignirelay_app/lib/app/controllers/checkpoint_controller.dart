// CheckpointController — app-layer orchestrator for publishing CHECKPOINT (#4-2).
//
// Spec / design: MASTER_EXECUTION_PLAN §5 A9 (2); envelope_v2_spec §10.2 (NOT
// LWW — each crossing is a distinct event) + §11.2 (STATUS / 12h / max_hops 6).
//
// Mirrors [PresenceController]: the UI (debug shell) must NOT build the wire
// `LocationEvidence` or assemble the anon id itself (layer rule #4:
// ui-cannot-import-proto). This controller assembles the CHECKPOINT inputs in
// the app layer — the anon_user_id from [AnonIdentityService] and the current
// GPS evidence from [LocationEvidenceBuilder] — and calls
// `EventPublisherV2Facade.publishCheckpoint`. The UI just supplies a
// `checkpointId` and gets a plain [BroadcastOutcome] back.
//
// In v0.3 the trigger is a manual debug button; the real crossing flow (Field
// Node QR / physical contact) lands in Stage D.

import 'dart:typed_data';

import 'package:ignirelay_app/app/services/anon_identity.dart';
import 'package:ignirelay_app/app/services/event_publisher_v2_facade.dart';
import 'package:ignirelay_app/app/services/location_evidence_builder.dart';

class CheckpointController {
  CheckpointController({
    required EventPublisherV2Facade facade,
    required AnonIdentityService anonIdentity,
    required LocationEvidenceBuilder locationBuilder,
    // UI-F5b — optional bounded fresh-GPS hook (§4.2 manual event). Wired in
    // main.dart to a ≤2000ms one-shot refresh that falls back to last-known; its
    // failure never aborts the send (a null location is acceptable).
    Future<void> Function()? ensureFreshLocation,
  })  : _facade = facade,
        _anonIdentity = anonIdentity,
        _locationBuilder = locationBuilder,
        _ensureFreshLocation = ensureFreshLocation;

  final EventPublisherV2Facade _facade;
  final AnonIdentityService _anonIdentity;
  final LocationEvidenceBuilder _locationBuilder;
  final Future<void> Function()? _ensureFreshLocation;

  /// Publish a CHECKPOINT crossing at [checkpointId]: resolve the anon_user_id,
  /// attach the best current GPS evidence (or none), and broadcast via the v2
  /// facade. With no field joined the facade rejects with
  /// [BroadcastOutcome.noField] (A5 §21.6).
  Future<BroadcastOutcome> publishCheckpoint({
    required String checkpointId,
  }) async {
    final anonUserId = await _anonIdentity.getOrCreate();
    final f = _ensureFreshLocation;
    if (f != null) {
      try {
        await f(); // §4.2: one bounded fresh fix, fall back to last-known
      } catch (_) {
        // Best-effort — a refresh failure must not abort the checkpoint send.
      }
    }
    final location = _locationBuilder.build(); // null when GPS unavailable
    return _facade.publishCheckpoint(
      anonUserId: Uint8List.fromList(anonUserId),
      checkpointId: checkpointId,
      location: location,
    );
  }
}
