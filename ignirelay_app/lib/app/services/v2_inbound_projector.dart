// V2InboundProjector — projects accepted EventEnvelope v2 (receive path) into
// the v1 `Event_Logs` read-model so `EventStream` / UI can see v2-received
// events.
//
// WHY THIS EXISTS
//
// The v2 receive path (BleV2Bridge → EnvelopeDispatcherV2 → EnvelopeStoreV2)
// terminates in `Envelopes_V2` and never writes `Event_Logs`, which is the
// ONLY table `EventStream` reads. Without this adapter, anything received over
// the v0.3 wire is invisible to the UI. This class bridges that gap during the
// v1→v2 migration window. It is the explicit, deletable "v2 → v1 read-model"
// seam: when v1 is finally retired and the UI reads the v2 store directly,
// delete this file.
//
// TRANSLATION (only the UI-surfaced types are projected)
//
//   • (CHAT_MESSAGE removed in A6 / OD-6 — chat retired; v2 number 30 reserved.
//      A received type-30 envelope now falls through to the default no-op.)
//   • HAZARD_MARKER  (v2 50 → v1 4):  the v2 wire carries a typed
//     `HazardMarkerData` payload (#4-5); decoded and rebuilt into a v1
//     `pb.HazardData` proto so the existing Hazards_State projection +
//     EventStream.hazardEvents decode unchanged. The wire `HazardType` enum
//     maps to the v1 read-model string via `HazardTypeCodec`.
//   • STATUS_UPDATE  (v2 1): SOS-class only (safetyState TRAPPED/INJURED) →
//     v1 requestBroadcast SOS, matching how the legacy path models SOS. Non-SOS
//     status (SAFE/UNSAFE) has no v1 UI surface yet (the v0.3 Now/status tab)
//     and is skipped.
//
// IDEMPOTENCY
//
// The v1 `event_id` is derived deterministically from the 16-byte envelope_id
// ("v2-" + hex). Re-projecting the same envelope is a no-op because
// MeshEventHandler dedups on `event_id` (memory LRU + DB).
//
// MIGRATION NOTE — DOUBLE DISPLAY DURING DUAL-WRITE
//
// The four v2-eligible types are still DUAL-WRITTEN on the legacy v1 wire (see
// EventPublisher). While dual-write is on, a received event arrives on BOTH
// wires with DIFFERENT ids, so it will surface twice. Disabling the per-type v1
// dual-write (the migration step) removes the duplicate. This projector is the
// prerequisite that makes such a per-type v2-only migration safe.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:fixnum/fixnum.dart' as fixnum;

import 'package:ignirelay_app/app/controllers/envelope_dispatcher_v2.dart';
import 'package:ignirelay_app/app/mesh/event_types.dart';
import 'package:ignirelay_app/app/mesh/mesh_event_handler.dart';
import 'package:ignirelay_app/app/proto/event_envelope_v2.dart';
import 'package:ignirelay_app/app/proto/mesh_protocol.pb.dart' as pb;
import 'package:ignirelay_app/app/services/hazard_type_codec.dart';

class V2InboundProjector {
  V2InboundProjector({
    required Stream<DispatchOutcome> outcomes,
    required MeshEventHandler handler,
  })  : _outcomes = outcomes,
        _handler = handler;

  final Stream<DispatchOutcome> _outcomes;
  final MeshEventHandler _handler;
  StreamSubscription<DispatchOutcome>? _sub;

  /// Emits the v1 `event_id` after each successful projection. Test-only
  /// signal so unit tests can deterministically await a projection instead of
  /// polling the DB.
  final StreamController<String> _projected =
      StreamController<String>.broadcast();

  @visibleForTesting
  Stream<String> get projectedEventIds => _projected.stream;

  /// Begin consuming dispatcher outcomes. Idempotent.
  void start() {
    _sub ??= _outcomes.listen((o) {
      if (o is DispatchAccepted) {
        unawaited(_project(o));
      }
    });
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
  }

  Future<void> dispose() async {
    await stop();
    await _projected.close();
  }

  static String eventIdOf(Uint8List envelopeId) {
    final hex =
        envelopeId.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    // Prefix marks the row as a read-model-only projection so v1 outbound /
    // sync paths can exclude it (see MeshEventHandler.v2ProjectionIdPrefix).
    return '${MeshEventHandler.v2ProjectionIdPrefix}$hex';
  }

  Future<void> _project(DispatchAccepted accepted) async {
    final env = accepted.envelope;
    final eventId = eventIdOf(env.envelopeId);
    try {
      switch (env.eventType) {
        // CHAT_MESSAGE (v2 30) projection removed in A6 (OD-6) — chat retired;
        // a received type-30 envelope falls through to the default no-op below.
        case EventTypeV2.hazardMarker:
          await _projectHazard(accepted, eventId);
          break;
        case EventTypeV2.statusUpdate:
          await _projectStatus(accepted, eventId);
          break;
        case EventTypeV2.presence:
          await _projectPresence(accepted, eventId);
          break;
        case EventTypeV2.checkpoint:
          await _projectCheckpoint(accepted, eventId);
          break;
        case EventTypeV2.adminBroadcast:
          await _projectAdminBroadcast(accepted, eventId);
          break;
        default:
          // Not a UI-surfaced type (supply / match / official / control);
          // nothing to project into the v1 read-model.
          break;
      }
    } catch (e) {
      debugPrint('[V2Projector] project failed for $eventId: $e');
    }
  }

  Future<void> _ingest({
    required String eventId,
    required int v1EventType,
    required int urgency,
    required List<int> payload,
    required DispatchAccepted accepted,
    double? lat,
    double? lng,
  }) async {
    final env = accepted.envelope;
    await _handler.ingestVerifiedEvent(
      eventId: eventId,
      eventType: v1EventType,
      urgency: urgency,
      payload: payload,
      senderPubKey: env.authorKey,
      hlcTimestamp: env.createdAtHlc.msSinceEpoch,
      hlcCounter: env.createdAtHlc.counter,
      ttl: env.maxHops,
      lat: lat,
      lng: lng,
      sourceNodeId: accepted.peerId ?? 'v2',
    );
    if (!_projected.isClosed) _projected.add(eventId);
  }

  Future<void> _projectHazard(DispatchAccepted a, String eventId) async {
    final hm = HazardMarkerData.decode(a.envelope.payload);
    final lat = hm.location.latDegrees;
    final lng = hm.location.lngDegrees;
    // _handleHazardEvent requires non-zero coordinates to project.
    if (lat == 0 || lng == 0) return;
    final hazard = pb.HazardData()
      ..hazardId = eventId
      ..hazardType = HazardTypeCodec.toV1String(hm.hazardType)
      ..severity = hm.severity
      ..centerLat = lat
      ..centerLng = lng
      // Typed HazardMarkerData carries no radius (reserved tag); the v1
      // read-model keeps a default. radius rides only the legacy v1 path.
      ..radiusMeters = 200.0
      ..observedAt = fixnum.Int64(a.envelope.createdAtHlc.msSinceEpoch)
      ..description = hm.description
      ..isConfirmation = hm.isConfirmation;
    await _ingest(
      eventId: eventId,
      v1EventType: EventType.hazardMarker,
      urgency: 0,
      payload: hazard.writeToBuffer(),
      accepted: a,
      lat: lat,
      lng: lng,
    );
  }

  Future<void> _projectStatus(DispatchAccepted a, String eventId) async {
    final s = StatusUpdateData.decode(a.envelope.payload);
    // Stage 0.5 SCOPE: urgency is derived from safetyState ONLY. The spec
    // §5.3 priority floor also raises an URGENT `need` (while SAFE) to
    // SOS_YELLOW; we deliberately DO NOT project that here, because "safe but
    // urgently needs water" belongs on the v0.3 status/needs surface (Now
    // tab), not shoehorned into the v1 SOS list. TODO(v0.3 Now tab): project
    // needs-based urgency once that read-model exists. Until then such updates
    // are intentionally invisible to the v1 read-model.
    final urgency = _safetyStateToUrgency(s.safetyState);
    if (urgency < 2) {
      // A8 (OD-8): a SAFE STATUS_UPDATE is the "我安全了" resolution — project a
      // local-read-model row so the UI marks this author's prior SOS resolved
      // (LWW by author, spec §10.2; no SOS_CANCELLED wire type). Other non-SOS
      // states (UNSAFE) still have no v1 surface yet (v0.3 Now tab).
      if (s.safetyState == SafetyState.safe) {
        await _projectSosResolved(a, eventId);
      } else {
        debugPrint(
            '[V2Projector] skip non-SOS status safetyState=${s.safetyState}');
      }
      return;
    }
    // Represent as a v1 SOS (requestBroadcast + urgency>=2), matching how the
    // legacy path models SOS. #4-6: StatusUpdateData now self-carries an
    // optional location (field 3); when present, project lat/lng into the
    // read-model row (received_lat/lng) so the SOS list shows the last trusted
    // position. Absent (null) → no coords, back-compat unchanged.
    final loc = s.location;
    final hasLoc = loc != null &&
        (loc.source != LocationSource.unknown ||
            loc.latE7 != 0 ||
            loc.lngE7 != 0);
    final req = pb.RequestData()
      ..requestId = eventId
      ..resourceType = ''
      ..quantityNeeded = 0
      ..note = _noteForSafetyState(s.safetyState)
      ..mobilityMode = 'CAN_GO';
    await _ingest(
      eventId: eventId,
      v1EventType: EventType.requestBroadcast,
      urgency: urgency,
      payload: req.writeToBuffer(),
      accepted: a,
      lat: hasLoc ? loc.latDegrees : null,
      lng: hasLoc ? loc.lngDegrees : null,
    );
  }

  /// Project a SAFE STATUS_UPDATE as an SOS resolution row (A8). The author is
  /// carried by `sender_pub_key` (via [_ingest]); `EventStream` reads that to
  /// emit a resolution keyed by author so the UI clears that author's SOS card.
  Future<void> _projectSosResolved(DispatchAccepted a, String eventId) async {
    final snapshot = <String, dynamic>{
      'resolved_ms': a.envelope.createdAtHlc.msSinceEpoch,
    };
    await _ingest(
      eventId: eventId,
      v1EventType: LocalReadModelType.sosResolved,
      urgency: 0,
      payload: utf8.encode(jsonEncode(snapshot)),
      accepted: a,
    );
  }

  Future<void> _projectPresence(DispatchAccepted a, String eventId) async {
    final p = PresenceData.decode(a.envelope.payload);
    final loc = p.location;
    final hasLoc = loc.source != LocationSource.unknown ||
        loc.latE7 != 0 ||
        loc.lngE7 != 0;
    final observedMs = loc.observedAt.msSinceEpoch != 0
        ? loc.observedAt.msSinceEpoch
        : a.envelope.createdAtHlc.msSinceEpoch;
    // Plain-JSON snapshot for UI rendering. PRESENCE has no v1 enum, so the
    // row is tagged LocalReadModelType.presence (local read-model only, never
    // on wire). `anon8` is the first 4 bytes of anon_user_id as hex (a short,
    // non-reversible display handle — NOT the full id).
    final snapshot = <String, dynamic>{
      'anon8': _hexPrefix(p.anonUserId, 4),
      'src': loc.source,
      'observed_ms': observedMs,
      if (hasLoc) 'lat': loc.latDegrees,
      if (hasLoc) 'lng': loc.lngDegrees,
      if (loc.accuracyM != 0) 'acc': loc.accuracyM,
      if (p.batteryHint != 0) 'battery': p.batteryHint,
    };
    await _ingest(
      eventId: eventId,
      v1EventType: LocalReadModelType.presence,
      urgency: 0,
      payload: utf8.encode(jsonEncode(snapshot)),
      accepted: a,
      lat: hasLoc ? loc.latDegrees : null,
      lng: hasLoc ? loc.lngDegrees : null,
    );
  }

  Future<void> _projectCheckpoint(DispatchAccepted a, String eventId) async {
    final c = CheckpointData.decode(a.envelope.payload);
    final loc = c.location;
    final hasLoc = loc.source != LocationSource.unknown ||
        loc.latE7 != 0 ||
        loc.lngE7 != 0;
    final observedMs = loc.observedAt.msSinceEpoch != 0
        ? loc.observedAt.msSinceEpoch
        : a.envelope.createdAtHlc.msSinceEpoch;
    // Plain-JSON snapshot. CHECKPOINT has no v1 enum, so the row is tagged
    // LocalReadModelType.checkpoint (local read-model only, never on wire) and is
    // NOT collapsed (each crossing is a distinct event, spec §10.2 — not LWW).
    final snapshot = <String, dynamic>{
      'checkpoint_id': c.checkpointId,
      'anon8': _hexPrefix(c.anonUserId, 4),
      'src': loc.source,
      'observed_ms': observedMs,
      if (hasLoc) 'lat': loc.latDegrees,
      if (hasLoc) 'lng': loc.lngDegrees,
    };
    await _ingest(
      eventId: eventId,
      v1EventType: LocalReadModelType.checkpoint,
      urgency: 0,
      payload: utf8.encode(jsonEncode(snapshot)),
      accepted: a,
      lat: hasLoc ? loc.latDegrees : null,
      lng: hasLoc ? loc.lngDegrees : null,
    );
  }

  Future<void> _projectAdminBroadcast(
      DispatchAccepted a, String eventId) async {
    final ab = AdminBroadcastData.decode(a.envelope.payload);
    final expiresMs = ab.expiresAt.msSinceEpoch; // 0 == no expiry
    // Plain-JSON snapshot. ADMIN_BROADCAST has no v1 enum, so the row is tagged
    // LocalReadModelType.adminBroadcast (local read-model only, never on wire).
    // Distinct directives coexist (spec §10.2 — not LWW); the UI auto-dismisses
    // each by `expires_ms`.
    final snapshot = <String, dynamic>{
      'scope': ab.scope,
      'message': ab.message,
      if (expiresMs != 0) 'expires_ms': expiresMs,
    };
    await _ingest(
      eventId: eventId,
      v1EventType: LocalReadModelType.adminBroadcast,
      urgency: 0,
      payload: utf8.encode(jsonEncode(snapshot)),
      accepted: a,
    );
  }

  static String _hexPrefix(Uint8List bytes, int n) {
    final take = bytes.length < n ? bytes.length : n;
    final sb = StringBuffer();
    for (var i = 0; i < take; i++) {
      sb.write(bytes[i].toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }

  static int _safetyStateToUrgency(int safetyState) {
    switch (safetyState) {
      case SafetyState.trapped:
        return 3;
      case SafetyState.injured:
        return 2;
      case SafetyState.unsafe:
        return 1;
      default:
        return 0;
    }
  }

  static String _noteForSafetyState(int safetyState) {
    switch (safetyState) {
      case SafetyState.trapped:
        return '受困';
      case SafetyState.injured:
        return '受傷';
      default:
        return 'SOS';
    }
  }
}
