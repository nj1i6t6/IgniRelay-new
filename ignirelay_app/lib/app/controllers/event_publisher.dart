import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:ignirelay_app/app/mesh/event_manager.dart';
import 'package:ignirelay_app/app/proto/event_envelope_v2.dart';
import 'package:ignirelay_app/app/services/event_publisher_v2_facade.dart';
import 'package:ignirelay_app/app/services/hazard_type_codec.dart';

/// EventPublisher — UI/app-layer facade over [EventManager] (legacy v0.2
/// publish path) with optional dual-write to [EventPublisherV2Facade]
/// (v0.3 wire path).
///
/// Phase 0b #3B-2: the old-product send surface (supply / request / chat /
/// match-negotiation / location / cancel / expireStaleMatches) was removed
/// from both [EventManager] and this facade. What remains are the two
/// whitepaper-aligned publish paths: SOS/求援 (`publishEvent`, still dual-written
/// as a v2 STATUS_UPDATE) and HAZARD_MARKER (`publishHazard`, **v2-only since
/// A11-debug-2-fix** — the v1 legacy dual-write was removed because the receiver
/// landed both copies as two `Event_Logs` rows, i.e. the duplicate HAZARD bug),
/// plus the read-only hazard query/CRUD forwarders. Chat is no longer
/// dual-written here — `ChatService` talks to the v2 facade directly.
///
/// IMPORTANT for tests: `v2Facade` is optional. Harnesses that construct
/// `EventPublisher(eventManager: EventManager())` keep working (they simply
/// skip the dual-write step). main.dart wires both.
class EventPublisher {
  EventPublisher({
    required EventManager eventManager,
    EventPublisherV2Facade? v2Facade,
  })  : _em = eventManager,
        _v2 = v2Facade;

  final EventManager _em;
  final EventPublisherV2Facade? _v2;

  /// Depth of the v0.3 facade's local pending outbox (envelopes queued but not
  /// yet sent to a peer). `0` when no v2 facade is wired (legacy / test
  /// harness). Read by the 安全 tab CommunicationState summary (UI-F4); a plain
  /// read-through so UI keeps talking to this facade, not the lower-level v2
  /// facade. Never throws.
  int get pendingQueueDepth => _v2?.pendingQueueDepth ?? 0;

  /// Map legacy "urgency" (0..3+) to spec §5.3 SafetyState enum.
  ///
  /// Legacy `publishEvent` overloads multiple semantics into one
  /// integer ("triage urgency" 0=info, 1=watch, 2=help, 3=critical),
  /// while the v2 STATUS_UPDATE payload exposes the structured safety
  /// state directly. This mapping is the smallest faithful translation;
  /// callers that want richer needs[] semantics should use the facade
  /// directly.
  ///
  /// Wave 3E-r3 — priority is NOT derived here. The facade applies the
  /// spec §5.3 implied-priority floor (`StatusUpdateData.
  /// impliedPriorityFloor()`) based on the safety state we set, so:
  /// `urgency >= 3` (TRAPPED) → facade emits at SOS_RED; `urgency == 2`
  /// (INJURED) → facade emits at SOS_YELLOW.
  static int _legacyUrgencyToSafetyState(int urgency) {
    if (urgency >= 3) return SafetyState.trapped;
    if (urgency == 2) return SafetyState.injured;
    if (urgency == 1) return SafetyState.unsafe;
    return SafetyState.safe; // 0 / cancel
  }

  Future<String> publishEvent({
    required int urgency,
    required String description,
    double? lat,
    double? lng,
    double maxRangeMeters = 1000.0,
    bool attachMedicalCard = false,
  }) async {
    final id = await _em.publishEvent(
      urgency: urgency,
      description: description,
      lat: lat,
      lng: lng,
      maxRangeMeters: maxRangeMeters,
      attachMedicalCard: attachMedicalCard,
    );
    _dualWriteStatusUpdate(urgency: urgency);
    return id;
  }

  /// Publish a HAZARD_MARKER. **v2-only** (A11-debug-2-fix): the legacy v1
  /// dual-write (`EventManager.publishHazard`) is removed — it made the receiver
  /// land BOTH a v1 and a v2 copy as two `Event_Logs` rows with different
  /// event_ids, i.e. the "duplicate HAZARD after restart" the A11 device test
  /// hit. HAZARD now rides the v0.3 envelope only; the `V2InboundProjector`
  /// covers receiver display. NO wire/proto/canonical change — this only stops
  /// EMITTING the legacy copy.
  ///
  /// Intentional consequences (recorded in STATUS — A11-debug-2-fix):
  ///   • HAZARD is no longer delivered to v1-only peers (part of the v2 migration).
  ///   • The sender no longer writes a LOCAL read-model row for its own hazard
  ///     (the v1 path did that); a self-sent event is not self-listed — same as
  ///     SOS, which has never round-tripped through the local read-model.
  ///   • No `EventManager` rate-limit, and [radiusMeters] is no longer persisted
  ///     (both lived on the v1 path; the v2 payload carries no radius — reserved
  ///     tag). [radiusMeters] is kept for API compatibility but ignored.
  /// The returned String is a UI-only correlation handle (debug snackbar); the
  /// real envelope id is owned by the v2 facade.
  Future<String> publishHazard({
    required String type,
    required int severity,
    required double lat,
    required double lng,
    double radiusMeters = 200.0,
    String description = '',
  }) async {
    _publishHazardMarkerV2(
      type: type,
      severity: severity,
      lat: lat,
      lng: lng,
      description: description,
    );
    // UI-only correlation handle: HAZARD is v2-only, so there is no v1 event id
    // to return; the real envelope id is owned by the v2 facade.
    return 'hz-${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}';
  }

  Future<List<Map<String, dynamic>>> getActiveHazards() =>
      _em.getActiveHazards();
  Future<String> getReporterHex() => _em.getReporterHex();
  Future<void> confirmHazard(String hazardId) => _em.confirmHazard(hazardId);
  Future<void> updateHazard(
    String hazardId, {
    String? type,
    int? severity,
    double? lat,
    double? lng,
    double? radiusMeters,
    String? description,
  }) =>
      _em.updateHazard(
        hazardId,
        type: type,
        severity: severity,
        lat: lat,
        lng: lng,
        radiusMeters: radiusMeters,
        description: description,
      );
  Future<void> deleteHazard(String hazardId) => _em.deleteHazard(hazardId);
  Future<Map<String, dynamic>?> findNearbyHazard(
    double lat,
    double lng,
    String type, {
    double searchRadius = 500.0,
  }) =>
      _em.findNearbyHazard(lat, lng, type, searchRadius: searchRadius);

  // ── v0.3 dual-write helpers (Stage 0c wave 3E-r2) ─────────────────────
  //
  // These never throw to the caller: the v2 facade is fire-and-forget so
  // a wire-side failure never blocks the legacy v0.2 publish (which is
  // still the authoritative local-write path). Errors are debug-logged.

  void _dualWriteStatusUpdate({required int urgency}) {
    final v2 = _v2;
    if (v2 == null) return;
    final safetyState = _legacyUrgencyToSafetyState(urgency);
    // Always go through publishStatusUpdate; the facade applies the
    // §5.3 implied-priority floor based on safetyState/needs, so we
    // never need to pre-decide SOS_RED vs SOS_YELLOW vs STATUS here.
    final fut = v2.publishStatusUpdate(safetyState: safetyState);
    unawaited(fut.catchError((Object e, StackTrace s) {
      debugPrint('[EventPublisher] v2 publishStatusUpdate failed: $e');
      // Synthetic outcome — never observed by callers because we ignore
      // the future, but keeps the type signature honest.
      return BroadcastOutcome.noActivePeers();
    }));
  }

  void _publishHazardMarkerV2({
    required String type,
    required int severity,
    required double lat,
    required double lng,
    required String description,
  }) {
    final v2 = _v2;
    if (v2 == null) return;
    // #4-5: typed HazardMarkerData payload. The legacy `type` STRING maps to the
    // wire `HazardType` enum via HazardTypeCodec; lat/lng become a
    // LocationEvidence. The typed payload carries no radius (reserved tag); since
    // A11-debug-2-fix removed the v1 read-model path, radius is no longer
    // persisted anywhere (acceptable — the mapless HAZARD UI never shows radius).
    final fut = v2.publishHazardMarker(
      hazardType: HazardTypeCodec.fromV1String(type),
      severity: severity,
      location: LocationEvidence.fromDegrees(
        source: LocationSource.gps,
        frame: LocationFrame.observer,
        latDegrees: lat,
        lngDegrees: lng,
      ),
      description: description,
    );
    unawaited(fut.catchError((Object e, StackTrace s) {
      debugPrint('[EventPublisher] v2 publishHazardMarker failed: $e');
      return BroadcastOutcome.noActivePeers();
    }));
  }
}
