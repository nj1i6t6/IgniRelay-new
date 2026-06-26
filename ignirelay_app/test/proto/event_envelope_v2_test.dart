// v0.3 Stage 0c — round-trip tests for the hand-written EventEnvelopeV2 wire codec.
//
// Spec: docs/specs/envelope_v2_spec_2026-05-13.md §3, §5.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ignirelay_app/app/proto/event_envelope_v2.dart';
import 'package:ignirelay_app/app/proto/proto_wire.dart';

void main() {
  group('HlcTimestampV2', () {
    test('round-trips encode/decode', () {
      final h = HlcTimestampV2(msSinceEpoch: 1747350000000, counter: 42);
      final out = HlcTimestampV2.decode(h.encode());
      expect(out.msSinceEpoch, h.msSinceEpoch);
      expect(out.counter, h.counter);
    });

    test('zero defaults survive proto3 omission', () {
      final h = HlcTimestampV2.zero;
      final bytes = h.encode();
      expect(bytes.length, 0, reason: 'all defaults → empty wire bytes');
      final out = HlcTimestampV2.decode(bytes);
      expect(out.msSinceEpoch, 0);
      expect(out.counter, 0);
    });

    test('compareTo orders by ms then counter', () {
      final earlier = HlcTimestampV2(msSinceEpoch: 100, counter: 5);
      final later = HlcTimestampV2(msSinceEpoch: 100, counter: 6);
      final muchLater = HlcTimestampV2(msSinceEpoch: 101, counter: 0);
      expect(earlier.compareTo(later), lessThan(0));
      expect(later.compareTo(muchLater), lessThan(0));
      expect(later.compareTo(later), 0);
    });
  });

  group('EventEnvelopeV2', () {
    EventEnvelopeV2 _sample({int eventType = EventTypeV2.statusUpdate}) {
      return EventEnvelopeV2(
        envelopeId: Uint8List.fromList(List.generate(16, (i) => i)),
        eventType: eventType,
        priority: PriorityV2.sosRed,
        createdAtHlc: HlcTimestampV2(msSinceEpoch: 1747350000000, counter: 0),
        expiresAtHlc: HlcTimestampV2(msSinceEpoch: 1747350720000, counter: 0),
        maxHops: 6,
        authorKey: Uint8List.fromList(List.generate(32, (i) => 0x80 | i)),
        signature: Uint8List.fromList(List.generate(64, (i) => i)),
        payload: Uint8List.fromList([1, 2, 3, 4, 5]),
      );
    }

    test('encodes + decodes bit-identically', () {
      final orig = _sample();
      final bytes = orig.encode();
      final out = EventEnvelopeV2.decode(bytes);
      expect(out.protocolVersion, 3);
      expect(out.envelopeId, orig.envelopeId);
      expect(out.eventType, orig.eventType);
      expect(out.priority, orig.priority);
      expect(out.createdAtHlc.msSinceEpoch, orig.createdAtHlc.msSinceEpoch);
      expect(out.expiresAtHlc.msSinceEpoch, orig.expiresAtHlc.msSinceEpoch);
      expect(out.maxHops, orig.maxHops);
      expect(out.authorKey, orig.authorKey);
      expect(out.sigAlgo, orig.sigAlgo);
      expect(out.signature, orig.signature);
      expect(out.payload, orig.payload);
      expect(out.lastRelayId, '');
      expect(out.isExperimental, false);
    });

    test('rejects when envelope_id is missing or wrong size', () {
      // Build a manual proto wire stream that omits envelope_id.
      final w = ProtoWriter();
      w.writeUint32(1, 3);
      w.writeEnum(3, EventTypeV2.statusUpdate);
      w.writeEnum(4, PriorityV2.sosRed);
      // missing envelope_id at tag 2 entirely
      expect(() => EventEnvelopeV2.decode(w.toBytes()),
          throwsA(isA<ProtoDecodeException>()));
    });

    test('rejects when author_key is wrong size', () {
      final orig = _sample();
      final tampered = EventEnvelopeV2(
        envelopeId: orig.envelopeId,
        eventType: orig.eventType,
        priority: orig.priority,
        createdAtHlc: orig.createdAtHlc,
        expiresAtHlc: orig.expiresAtHlc,
        maxHops: orig.maxHops,
        authorKey: Uint8List(31), // wrong
        signature: orig.signature,
        payload: orig.payload,
      );
      expect(() => EventEnvelopeV2.decode(tampered.encode()),
          throwsA(isA<ProtoDecodeException>()));
    });

    test('skips unknown fields (forward compat)', () {
      final w = ProtoWriter();
      w.writeUint32(1, 3);
      w.writeBytes(2, List.generate(16, (i) => i));
      w.writeEnum(3, EventTypeV2.statusUpdate);
      w.writeEnum(4, PriorityV2.sosRed);
      w.writeMessage(5, HlcTimestampV2(msSinceEpoch: 1, counter: 0).encode());
      w.writeMessage(6, HlcTimestampV2(msSinceEpoch: 2, counter: 0).encode());
      w.writeUint32(7, 6);
      w.writeBytes(8, List.generate(32, (i) => i));
      w.writeUint32(9, 1);
      w.writeBytes(10, List.generate(64, (i) => i));
      w.writeBytes(11, [1, 2, 3]);
      w.writeBytes(14, List.filled(16, 0));
      // unknown tag 99 (varint)
      w.writeUint32(99, 12345);
      // unknown tag 100 (length-delimited)
      w.writeBytes(100, [9, 8, 7]);
      final out = EventEnvelopeV2.decode(w.toBytes());
      expect(out.payload, [1, 2, 3]);
    });

    test('isExperimental defaults to false on wire (proto3 omission)', () {
      final orig = _sample();
      // false → not on wire → default decode == false.
      final bytes = orig.encode();
      final out = EventEnvelopeV2.decode(bytes);
      expect(out.isExperimental, false);
    });

    test('isExperimental round-trips when true', () {
      final orig = EventEnvelopeV2(
        envelopeId: Uint8List.fromList(List.generate(16, (i) => i)),
        eventType: 1500,
        priority: PriorityV2.normal,
        createdAtHlc: HlcTimestampV2(msSinceEpoch: 1, counter: 0),
        expiresAtHlc: HlcTimestampV2(msSinceEpoch: 2, counter: 0),
        maxHops: 1,
        authorKey: Uint8List(32),
        signature: Uint8List(64),
        payload: Uint8List(0),
        isExperimental: true,
      );
      final out = EventEnvelopeV2.decode(orig.encode());
      expect(out.isExperimental, true);
      expect(out.eventType, 1500);
    });
  });

  group('StatusUpdateData', () {
    test('snapshot round-trips', () {
      final s = StatusUpdateData(
        safetyState: SafetyState.injured,
        needs: const [
          NeedEntry(
            category: NeedCategory.water,
            severity: NeedSeverity.urgent,
            expiresAtHlc: HlcTimestampV2(msSinceEpoch: 100, counter: 1),
          ),
        ],
      );
      final out = StatusUpdateData.decode(s.encode());
      expect(out.safetyState, SafetyState.injured);
      expect(out.needs.length, 1);
      expect(out.needs.first.category, NeedCategory.water);
      expect(out.needs.first.severity, NeedSeverity.urgent);
      expect(out.needs.first.expiresAtHlc.msSinceEpoch, 100);
    });

    test('#4-6 location field 3 round-trips (bearing absent)', () {
      final s = StatusUpdateData(
        safetyState: SafetyState.trapped,
        needs: const [
          NeedEntry(
            category: NeedCategory.water,
            severity: NeedSeverity.urgent,
            expiresAtHlc: HlcTimestampV2(msSinceEpoch: 100, counter: 0),
          ),
        ],
        location: LocationEvidence.fromDegrees(
          source: LocationSource.gps,
          frame: LocationFrame.subject,
          latDegrees: 25.0339805,
          lngDegrees: 121.5654177,
          accuracyM: 12,
        ),
      );
      final out = StatusUpdateData.decode(s.encode());
      expect(out.location, isNotNull);
      expect(out.location!.source, LocationSource.gps);
      expect(out.location!.latE7, 250339805);
      expect(out.location!.lngE7, 1215654177);
      expect(out.location!.bearingDeg, isNull);
      expect(out.safetyState, SafetyState.trapped);
      expect(out.needs.length, 1);
    });

    test('#4-6 bearing = 0 (due north) survives round-trip (≠ absent)', () {
      final s = StatusUpdateData(
        safetyState: SafetyState.trapped,
        location: LocationEvidence.fromDegrees(
          source: LocationSource.gps,
          frame: LocationFrame.subject,
          latDegrees: 25.0,
          lngDegrees: 121.0,
          bearingDeg: 0,
        ),
      );
      final out = StatusUpdateData.decode(s.encode());
      expect(out.location, isNotNull);
      expect(out.location!.bearingDeg, 0,
          reason: 'due-north 0° must not be conflated with absent');
    });

    test('#4-6 no location → absent (back-compat byte-identical, decodes null)',
        () {
      final withoutLoc =
          StatusUpdateData(safetyState: SafetyState.injured).encode();
      // Byte-identical to the pre-4-6 encoding (field 3 simply not emitted).
      final legacyShape = StatusUpdateData(
        safetyState: SafetyState.injured,
      ).encode();
      expect(withoutLoc, orderedEquals(legacyShape));
      final out = StatusUpdateData.decode(withoutLoc);
      expect(out.location, isNull);
    });

    test('#4-6 location does NOT change impliedPriorityFloor (regression)', () {
      final loc = LocationEvidence.fromDegrees(
        source: LocationSource.gps,
        frame: LocationFrame.subject,
        latDegrees: 25.0,
        lngDegrees: 121.0,
      );
      // SAFE + non-urgent stays STATUS whether or not a location is attached.
      expect(
        StatusUpdateData(
          safetyState: SafetyState.safe,
          needs: const [
            NeedEntry(
              category: NeedCategory.water,
              severity: NeedSeverity.want,
              expiresAtHlc: HlcTimestampV2.zero,
            ),
          ],
          location: loc,
        ).impliedPriorityFloor(),
        PriorityV2.status,
      );
      // TRAPPED stays SOS_RED with a location attached.
      expect(
        StatusUpdateData(safetyState: SafetyState.trapped, location: loc)
            .impliedPriorityFloor(),
        PriorityV2.sosRed,
      );
    });

    test('impliedPriorityFloor: TRAPPED → SOS_RED', () {
      final s = StatusUpdateData(safetyState: SafetyState.trapped);
      expect(s.impliedPriorityFloor(), PriorityV2.sosRed);
    });

    test('impliedPriorityFloor: SAFE + URGENT need → SOS_YELLOW', () {
      final s = StatusUpdateData(
        safetyState: SafetyState.safe,
        needs: const [
          NeedEntry(
            category: NeedCategory.water,
            severity: NeedSeverity.urgent,
            expiresAtHlc: HlcTimestampV2.zero,
          ),
        ],
      );
      expect(s.impliedPriorityFloor(), PriorityV2.sosYellow);
    });

    test('impliedPriorityFloor: SAFE + non-urgent → STATUS', () {
      final s = StatusUpdateData(
        safetyState: SafetyState.safe,
        needs: const [
          NeedEntry(
            category: NeedCategory.water,
            severity: NeedSeverity.want,
            expiresAtHlc: HlcTimestampV2.zero,
          ),
        ],
      );
      expect(s.impliedPriorityFloor(), PriorityV2.status);
    });
  });

  group('ProtocolHelloData', () {
    test('round-trips a PhoneV1 hello', () {
      final h = ProtocolHelloData(
        peerKind: PeerKind.phoneV1,
        maxRxEnvelopeBytes: 2048,
        supportsIblt: true,
        supportsBloomV2: true,
        supportsChunking: true,
        minNegotiatedMtu: 247,
        capabilities: const ['shelter_status', 'battery_share'],
        bgState: BgState.foreground,
      );
      final out = ProtocolHelloData.decode(h.encode());
      expect(out.peerKind, PeerKind.phoneV1);
      expect(out.maxRxEnvelopeBytes, 2048);
      expect(out.supportsIblt, true);
      expect(out.supportsChunking, true);
      expect(out.minNegotiatedMtu, 247);
      expect(out.capabilities, ['shelter_status', 'battery_share']);
      expect(out.bgState, BgState.foreground);
    });

    test('tolerates a node HELLO carrying additive fields 10-13 (A12)', () {
      // A12: a Field Node appends node_id/node_lat_1e7/node_lng_1e7/
      // install_accuracy_m (fields 10-13). An old phone MUST decode the known
      // 1-9 fields and silently skip the unknown trailing ones (decode uses
      // `default: skipValue`), so this round-trips without throwing.
      final base = ProtocolHelloData(
        peerKind: PeerKind.bleNodeV1,
        maxRxEnvelopeBytes: 512,
        supportsChunking: true,
        minNegotiatedMtu: 185,
        capabilities: const ['iblt-keyhash-v2'],
        bgState: BgState.foreground,
      ).encode();
      final nodeFields = (ProtoWriter()
            ..writeString(10, 'node-7')
            ..writeSint64(11, 250339805)
            ..writeSint64(12, 1215654177)
            ..writeUint32(13, 5))
          .toBytes();
      final combined = Uint8List.fromList([...base, ...nodeFields]);
      final out = ProtocolHelloData.decode(combined);
      expect(out.peerKind, PeerKind.bleNodeV1);
      expect(out.maxRxEnvelopeBytes, 512);
      expect(out.minNegotiatedMtu, 185);
      expect(out.capabilities, ['iblt-keyhash-v2']);
      expect(out.bgState, BgState.foreground);
    });
  });

  group('NodeReceiptData (A12)', () {
    test('round-trips ref_envelope_id + status + queue_depth', () {
      final ref = Uint8List.fromList(List<int>.generate(16, (i) => 0xA0 + i));
      final out = NodeReceiptData.decode(NodeReceiptData(
        refEnvelopeId: ref,
        status: NodeReceiptStatus.rejected,
        queueDepth: 42,
      ).encode());
      expect(out.refEnvelopeId, ref);
      expect(out.status, NodeReceiptStatus.rejected);
      expect(out.queueDepth, 42);
    });

    test('ACCEPTED_STORED (0) + queue 0 omit defaults, decode restores them',
        () {
      final ref = Uint8List.fromList(List<int>.filled(16, 7));
      final encoded = NodeReceiptData(refEnvelopeId: ref).encode();
      final out = NodeReceiptData.decode(encoded);
      expect(out.status, NodeReceiptStatus.acceptedStored);
      expect(out.queueDepth, 0);
      expect(out.refEnvelopeId, ref);
    });

    test('skips unknown trailing fields (additive-safe)', () {
      final ref = Uint8List.fromList(List<int>.filled(16, 3));
      final base = NodeReceiptData(
        refEnvelopeId: ref,
        status: NodeReceiptStatus.duplicate,
        queueDepth: 1,
      ).encode();
      final extra = (ProtoWriter()..writeUint32(9, 999)).toBytes();
      final out =
          NodeReceiptData.decode(Uint8List.fromList([...base, ...extra]));
      expect(out.status, NodeReceiptStatus.duplicate);
      expect(out.queueDepth, 1);
      expect(out.refEnvelopeId, ref);
    });
  });

  group('EventTypeV2 NODE_RECEIPT (A12)', () {
    test('constant is 105 in the control range', () {
      expect(EventTypeV2.nodeReceipt, 105);
    });
    test('isKnown(105) is true', () {
      expect(EventTypeV2.isKnown(EventTypeV2.nodeReceipt), true);
    });
    test('maxHopsDefault(105) is 0 — link-local, never relayed', () {
      expect(EventTypeV2.maxHopsDefault(EventTypeV2.nodeReceipt), 0);
    });
  });

  group('LocationEvidence', () {
    test('round-trips all fields', () {
      final loc = LocationEvidence(
        source: LocationSource.fieldNode,
        frame: LocationFrame.observer,
        latE7: 250339805,
        lngE7: 1215645000,
        accuracyM: 12,
        observedAt: HlcTimestampV2(msSinceEpoch: 1747350000000, counter: 3),
        anchorNodeId: 'cp-03',
        distanceFromAnchorM: 47,
        bearingDeg: 215,
      );
      final out = LocationEvidence.decode(loc.encode());
      expect(out.source, LocationSource.fieldNode);
      expect(out.frame, LocationFrame.observer);
      expect(out.latE7, 250339805);
      expect(out.lngE7, 1215645000);
      expect(out.accuracyM, 12);
      expect(out.observedAt.msSinceEpoch, 1747350000000);
      expect(out.observedAt.counter, 3);
      expect(out.anchorNodeId, 'cp-03');
      expect(out.distanceFromAnchorM, 47);
      expect(out.bearingDeg, 215);
    });

    test('all defaults → empty wire bytes (proto3 omission)', () {
      final bytes = const LocationEvidence().encode();
      expect(bytes.length, 0);
      final out = LocationEvidence.decode(bytes);
      expect(out.source, LocationSource.unknown);
      expect(out.latE7, 0);
      expect(out.lngE7, 0);
      expect(out.observedAt.msSinceEpoch, 0);
    });

    test('negative coordinates round-trip (zigzag sint64)', () {
      // Santiago, CL — both hemispheres negative.
      final loc = LocationEvidence.fromDegrees(
        source: LocationSource.gps,
        frame: LocationFrame.subject,
        latDegrees: -33.4489,
        lngDegrees: -70.6693,
      );
      expect(loc.latE7, -334489000);
      expect(loc.lngE7, -706693000);
      final out = LocationEvidence.decode(loc.encode());
      expect(out.latE7, -334489000);
      expect(out.lngE7, -706693000);
      expect(out.latDegrees, closeTo(-33.4489, 1e-7));
      expect(out.lngDegrees, closeTo(-70.6693, 1e-7));
    });

    test('zigzag keeps a negative coordinate compact (not a 10-byte varint)',
        () {
      // Plain int64 would encode any negative as 10 bytes; zigzag of a
      // ~-7e8 magnitude fits in 5 varint bytes. tag(1B)+value ≤ 6B for the field.
      final loc = LocationEvidence(lngE7: -706693000);
      // Only field 4 (lng) is non-default → whole message stays small.
      expect(loc.encode().length, lessThan(7));
    });

    test('fromDegrees rounds to nearest fixed-point unit', () {
      // 25.0339805 * 1e7 == 250339804.9999… in IEEE-754; round-to-nearest
      // recovers the intended 250339805 (truncation would give …804).
      final loc = LocationEvidence.fromDegrees(
        latDegrees: 25.0339805,
        lngDegrees: 121.5645,
      );
      expect(loc.latE7, 250339805);
      expect(loc.lngE7, 1215645000);
    });

    test('bearing absent decodes to null (distinct from due north)', () {
      final noBearing = const LocationEvidence(latE7: 250339805);
      expect(noBearing.bearingDeg, isNull);
      expect(LocationEvidence.decode(noBearing.encode()).bearingDeg, isNull);
    });

    test('bearing 0 (due north) survives and is NOT absent', () {
      final north = const LocationEvidence(latE7: 250339805, bearingDeg: 0);
      final out = LocationEvidence.decode(north.encode());
      expect(out.bearingDeg, 0,
          reason: '0° north must round-trip, not become null');
    });

    test('bearing 215 round-trips', () {
      final b = const LocationEvidence(latE7: 250339805, bearingDeg: 215);
      expect(LocationEvidence.decode(b.encode()).bearingDeg, 215);
    });

    test('skips unknown fields (forward compat)', () {
      final w = ProtoWriter();
      w.writeEnum(1, LocationSource.gps);
      w.writeSint64(3, 250339805);
      w.writeUint32(99, 42); // unknown varint
      w.writeBytes(100, [1, 2, 3]); // unknown length-delimited
      final out = LocationEvidence.decode(w.toBytes());
      expect(out.source, LocationSource.gps);
      expect(out.latE7, 250339805);
    });
  });

  group('PresenceData', () {
    test('round-trips id + nested location + battery', () {
      final p = PresenceData(
        anonUserId: Uint8List.fromList(List.generate(16, (i) => i + 1)),
        location: LocationEvidence.fromDegrees(
          source: LocationSource.gps,
          frame: LocationFrame.subject,
          latDegrees: 25.0339805,
          lngDegrees: 121.5645,
          accuracyM: 8,
        ),
        batteryHint: 73,
      );
      final out = PresenceData.decode(p.encode());
      expect(out.anonUserId, p.anonUserId);
      expect(out.batteryHint, 73);
      expect(out.location.source, LocationSource.gps);
      expect(out.location.latE7, 250339805);
      expect(out.location.accuracyM, 8);
    });

    test('empty presence round-trips with defaults', () {
      final out = PresenceData.decode(PresenceData().encode());
      expect(out.anonUserId, isEmpty);
      expect(out.batteryHint, 0);
      expect(out.location.latE7, 0);
    });
  });

  group('CheckpointData', () {
    test('round-trips with optional location present', () {
      final c = CheckpointData(
        anonUserId: Uint8List.fromList(List.generate(16, (i) => 0xA0 | i)),
        checkpointId: 'cp-04',
        location: const LocationEvidence(
          source: LocationSource.fieldNode,
          anchorNodeId: 'node-04',
        ),
      );
      final out = CheckpointData.decode(c.encode());
      expect(out.anonUserId, c.anonUserId);
      expect(out.checkpointId, 'cp-04');
      expect(out.location.anchorNodeId, 'node-04');
    });

    test('round-trips with location omitted', () {
      final c = CheckpointData(
        anonUserId: Uint8List.fromList(List.generate(16, (i) => i)),
        checkpointId: 'cp-09',
      );
      final out = CheckpointData.decode(c.encode());
      expect(out.checkpointId, 'cp-09');
      expect(out.location.latE7, 0);
      expect(out.location.anchorNodeId, '');
    });
  });

  group('HazardMarkerData', () {
    test('typed payload round-trips', () {
      final h = HazardMarkerData(
        hazardId: 'hz-0001',
        hazardType: HazardType.landslide,
        severity: 4,
        location: LocationEvidence.fromDegrees(
          source: LocationSource.manual,
          latDegrees: 24.1,
          lngDegrees: 121.2,
        ),
        description: 'road blocked at km 12',
        isConfirmation: true,
      );
      final out = HazardMarkerData.decode(h.encode());
      expect(out.hazardId, 'hz-0001');
      expect(out.hazardType, HazardType.landslide);
      expect(out.severity, 4);
      expect(out.location.latE7, 241000000);
      expect(out.description, 'road blocked at km 12');
      expect(out.isConfirmation, true);
    });

    test('defaults round-trip (unspecified type, no confirmation)', () {
      final out = HazardMarkerData.decode(const HazardMarkerData().encode());
      expect(out.hazardType, HazardType.unspecified);
      expect(out.severity, 0);
      expect(out.isConfirmation, false);
      expect(out.description, '');
    });
  });

  group('AdminBroadcastData', () {
    test('round-trips scope + message + expiry', () {
      final a = AdminBroadcastData(
        scope: AdminScope.field,
        message: 'evacuate sector B',
        expiresAt: HlcTimestampV2(msSinceEpoch: 1747350720000, counter: 0),
      );
      final out = AdminBroadcastData.decode(a.encode());
      expect(out.scope, AdminScope.field);
      expect(out.message, 'evacuate sector B');
      expect(out.expiresAt.msSinceEpoch, 1747350720000);
    });

    test('ALL scope without expiry round-trips', () {
      final a = AdminBroadcastData(
        scope: AdminScope.all,
        message: 'all clear',
      );
      final out = AdminBroadcastData.decode(a.encode());
      expect(out.scope, AdminScope.all);
      expect(out.message, 'all clear');
      expect(out.expiresAt.msSinceEpoch, 0);
    });
  });

  group('EventTypeV2 new whitepaper types (4-2)', () {
    test('constants have the locked values', () {
      expect(EventTypeV2.presence, 3);
      expect(EventTypeV2.checkpoint, 4);
      expect(EventTypeV2.adminBroadcast, 82);
    });

    test('isKnown recognizes the new types', () {
      expect(EventTypeV2.isKnown(EventTypeV2.presence), true);
      expect(EventTypeV2.isKnown(EventTypeV2.checkpoint), true);
      expect(EventTypeV2.isKnown(EventTypeV2.adminBroadcast), true);
    });

    test('maxHopsDefault: presence 4 / checkpoint 6 / admin 12', () {
      expect(EventTypeV2.maxHopsDefault(EventTypeV2.presence), 4);
      expect(EventTypeV2.maxHopsDefault(EventTypeV2.checkpoint), 6);
      expect(EventTypeV2.maxHopsDefault(EventTypeV2.adminBroadcast), 12);
    });
  });
}
// ignore_for_file: prefer_const_constructors, prefer_const_declarations, no_leading_underscores_for_local_identifiers
