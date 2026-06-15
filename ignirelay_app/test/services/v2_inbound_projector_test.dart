// V2InboundProjector — verifies accepted EventEnvelope v2 (receive path) is
// projected into the v1 Event_Logs read-model and reaches EventStream.
//
// Pipeline exercised: MessagePublisherV2 signs → EnvelopeDispatcherV2 accepts
// → V2InboundProjector translates → MeshEventHandler.ingestVerifiedEvent
// persists + projects → EventStream emits a typed event.
// ignore_for_file: prefer_const_constructors

import 'dart:async';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ignirelay_app/app/controllers/envelope_dispatcher_v2.dart';
import 'package:ignirelay_app/app/controllers/event_stream.dart';
import 'package:ignirelay_app/app/controllers/message_publisher_v2.dart';
import 'package:ignirelay_app/app/db/database_helper.dart';
import 'package:ignirelay_app/app/mesh/event_types.dart';
import 'package:ignirelay_app/app/mesh/mesh_constants.dart';
import 'package:ignirelay_app/app/mesh/mesh_event_handler.dart';
import 'package:ignirelay_app/app/proto/event_envelope_v2.dart';
import 'package:ignirelay_app/app/services/author_rate_limiter.dart';
import 'package:ignirelay_app/app/services/event_decoder.dart';
import 'package:ignirelay_app/app/services/event_store.dart';
import 'package:ignirelay_app/app/services/envelope_store_v2.dart';
import 'package:ignirelay_app/app/services/mesh_trace_writer.dart';
import 'package:ignirelay_app/app/services/priority_matrix_v2.dart';
import 'package:ignirelay_app/app/services/v2_inbound_projector.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Harness {
  final EnvelopeDispatcherV2 dispatcher;
  final MessagePublisherV2 publisher;
  final V2InboundProjector projector;
  _Harness(this.dispatcher, this.publisher, this.projector);
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    DatabaseHelper.testDatabasePathOverride = inMemoryDatabasePath;
  });

  setUp(() async {
    await DatabaseHelper().resetForTest();
  });

  Future<_Harness> makeHarness() async {
    final db = DatabaseHelper();
    final store = EnvelopeStoreV2(db);
    final trace = MeshTraceWriter(db);
    final rate = AuthorRateLimiter(capacity: 100, perSecond: 1000);
    final dispatcher = EnvelopeDispatcherV2(
      store: store,
      trace: trace,
      rateLimiter: rate,
    );
    final keyPair = await Ed25519().newKeyPair();
    final pub = await keyPair.extractPublicKey();
    final publisher = MessagePublisherV2(
      keyPair: keyPair,
      authorPublicKey: Uint8List.fromList(pub.bytes),
      trace: trace,
    );
    final projector = V2InboundProjector(
      outcomes: dispatcher.outcomes,
      handler: MeshEventHandler(),
    )..start();
    return _Harness(dispatcher, publisher, projector);
  }

  test('hazard envelope projects to Event_Logs + Hazards_State + EventStream',
      () async {
    final h = await makeHarness();
    final eventStream = EventStream(
      handler: MeshEventHandler(),
      decoder: EventDecoder(),
      store: EventStore(databaseHelper: DatabaseHelper()),
    )..start();
    final hazardFuture = eventStream.hazardEvents.first;

    final payload = HazardMarkerData(
      hazardType: HazardType.flood,
      severity: 3,
      location: LocationEvidence.fromDegrees(
        source: LocationSource.gps,
        frame: LocationFrame.observer,
        latDegrees: 25.04,
        lngDegrees: 121.56,
      ),
      description: '洪水警戒',
    ).encode();
    final published = await h.publisher.send(
      eventType: EventTypeV2.hazardMarker,
      priority: PriorityV2.alert,
      payload: payload,
      createdAtHlc: HlcTimestampV2(msSinceEpoch: 1000, counter: 0),
      expiresAtHlc: HlcTimestampV2(msSinceEpoch: 2000, counter: 0),
      maxHops: 10,
      negotiatedMtu: 247,
      fieldId: Uint8List(16),
    );

    final projectedId = h.projector.projectedEventIds.first;
    final outcome = await h.dispatcher
        .onReceiveEnvelopeBytes(published.wireBytes, peerId: 'AA:BB:CC');
    expect(outcome, isA<DispatchAccepted>());

    final eventId = await projectedId.timeout(const Duration(seconds: 2));
    final db = await DatabaseHelper().database;

    final logs = await db
        .query('Event_Logs', where: 'event_id = ?', whereArgs: [eventId]);
    expect(logs.length, 1);
    expect(logs.first['event_type'], EventType.hazardMarker);

    final hazards = await db.query('Hazards_State');
    expect(hazards.length, 1);
    expect(hazards.first['type'], 'FLOOD');
    expect(hazards.first['severity'], 3);

    final hazardEvent = await hazardFuture.timeout(const Duration(seconds: 2));
    expect(hazardEvent.type, 'FLOOD');
    expect(hazardEvent.severity, 3);
    expect(hazardEvent.lat, 25.04);

    await eventStream.dispose();
    await h.projector.dispose();
    await h.dispatcher.dispose();
  });

  test('SOS-class status update projects to a v1 SOS alert', () async {
    final h = await makeHarness();
    final eventStream = EventStream(
      handler: MeshEventHandler(),
      decoder: EventDecoder(),
      store: EventStore(databaseHelper: DatabaseHelper()),
    )..start();
    final sosFuture = eventStream.sosAlerts.first;

    final payload = StatusUpdateData(safetyState: SafetyState.trapped).encode();
    final published = await h.publisher.send(
      eventType: EventTypeV2.statusUpdate,
      priority: PriorityV2.sosRed,
      payload: payload,
      createdAtHlc: HlcTimestampV2(msSinceEpoch: 1000, counter: 0),
      expiresAtHlc: HlcTimestampV2(msSinceEpoch: 2000, counter: 0),
      maxHops: 6,
      negotiatedMtu: 247,
      fieldId: Uint8List(16),
    );

    final projectedId = h.projector.projectedEventIds.first;
    final outcome = await h.dispatcher
        .onReceiveEnvelopeBytes(published.wireBytes, peerId: 'AA:BB:CC');
    expect(outcome, isA<DispatchAccepted>());

    final eventId = await projectedId.timeout(const Duration(seconds: 2));
    final db = await DatabaseHelper().database;
    final logs = await db
        .query('Event_Logs', where: 'event_id = ?', whereArgs: [eventId]);
    expect(logs.length, 1);
    expect(logs.first['event_type'], EventType.requestBroadcast);
    expect(logs.first['urgency'], 3);

    final sos = await sosFuture.timeout(const Duration(seconds: 2));
    expect(sos.urgency, 3);
    expect(sos.description, '受困');

    await eventStream.dispose();
    await h.projector.dispose();
    await h.dispatcher.dispose();
  });

  test('SAFE status update projects an SOS resolution (A8 / 我安全了)',
      () async {
    final h = await makeHarness();
    final eventStream = EventStream(
      handler: MeshEventHandler(),
      decoder: EventDecoder(),
      store: EventStore(databaseHelper: DatabaseHelper()),
    )..start();
    final resolvedFuture = eventStream.sosResolutions.first;

    final published = await h.publisher.send(
      eventType: EventTypeV2.statusUpdate,
      priority: PriorityV2.status,
      payload: StatusUpdateData(safetyState: SafetyState.safe).encode(),
      createdAtHlc: HlcTimestampV2(msSinceEpoch: 3000, counter: 0),
      expiresAtHlc: HlcTimestampV2(msSinceEpoch: 4000, counter: 0),
      maxHops: 6,
      negotiatedMtu: 247,
      fieldId: Uint8List(16),
    );

    final projectedId = h.projector.projectedEventIds.first;
    final outcome = await h.dispatcher
        .onReceiveEnvelopeBytes(published.wireBytes, peerId: 'AA:BB:CC');
    expect(outcome, isA<DispatchAccepted>());

    final eventId = await projectedId.timeout(const Duration(seconds: 2));
    final db = await DatabaseHelper().database;
    final logs = await db
        .query('Event_Logs', where: 'event_id = ?', whereArgs: [eventId]);
    expect(logs.length, 1);
    expect(logs.first['event_type'], LocalReadModelType.sosResolved);

    final resolved =
        await resolvedFuture.timeout(const Duration(seconds: 2));
    expect(resolved.authorKeyHex.isNotEmpty, isTrue,
        reason: 'resolution is keyed by the author pubkey');

    await eventStream.dispose();
    await h.projector.dispose();
    await h.dispatcher.dispose();
  });

  test('#4-6 SOS with location projects lat/lng into the read-model', () async {
    final h = await makeHarness();
    final payload = StatusUpdateData(
      safetyState: SafetyState.trapped,
      location: LocationEvidence.fromDegrees(
        source: LocationSource.gps,
        frame: LocationFrame.subject,
        latDegrees: 25.0339805,
        lngDegrees: 121.5654177,
      ),
    ).encode();
    final published = await h.publisher.send(
      eventType: EventTypeV2.statusUpdate,
      priority: PriorityV2.sosRed,
      payload: payload,
      createdAtHlc: HlcTimestampV2(msSinceEpoch: 1000, counter: 0),
      expiresAtHlc: HlcTimestampV2(msSinceEpoch: 2000, counter: 0),
      maxHops: 6,
      negotiatedMtu: 247,
      fieldId: Uint8List(16),
    );

    final projectedId = h.projector.projectedEventIds.first;
    final outcome = await h.dispatcher
        .onReceiveEnvelopeBytes(published.wireBytes, peerId: 'AA:BB:CC');
    expect(outcome, isA<DispatchAccepted>());

    final eventId = await projectedId.timeout(const Duration(seconds: 2));
    final db = await DatabaseHelper().database;
    final logs = await db
        .query('Event_Logs', where: 'event_id = ?', whereArgs: [eventId]);
    expect(logs.length, 1);
    expect((logs.first['received_lat'] as num?)?.toDouble(),
        closeTo(25.0339805, 1e-7));
    expect((logs.first['received_lng'] as num?)?.toDouble(),
        closeTo(121.5654177, 1e-7));

    await h.projector.dispose();
    await h.dispatcher.dispose();
  });

  test('#4-6 SOS without location projects with null coords (back-compat)',
      () async {
    final h = await makeHarness();
    final published = await h.publisher.send(
      eventType: EventTypeV2.statusUpdate,
      priority: PriorityV2.sosRed,
      payload: StatusUpdateData(safetyState: SafetyState.trapped).encode(),
      createdAtHlc: HlcTimestampV2(msSinceEpoch: 1000, counter: 0),
      expiresAtHlc: HlcTimestampV2(msSinceEpoch: 2000, counter: 0),
      maxHops: 6,
      negotiatedMtu: 247,
      fieldId: Uint8List(16),
    );
    final projectedId = h.projector.projectedEventIds.first;
    await h.dispatcher
        .onReceiveEnvelopeBytes(published.wireBytes, peerId: 'AA:BB:CC');
    final eventId = await projectedId.timeout(const Duration(seconds: 2));
    final db = await DatabaseHelper().database;
    final logs = await db
        .query('Event_Logs', where: 'event_id = ?', whereArgs: [eventId]);
    expect(logs.length, 1);
    expect(logs.first['received_lat'], isNull);
    expect(logs.first['received_lng'], isNull);

    await h.projector.dispose();
    await h.dispatcher.dispose();
  });

  test('#4-6 budget: TRAPPED + 2 needs + full location envelope <= 240B',
      () async {
    final h = await makeHarness();
    final payload = StatusUpdateData(
      safetyState: SafetyState.trapped,
      needs: [
        NeedEntry(
          category: NeedCategory.water,
          severity: NeedSeverity.urgent,
          expiresAtHlc: HlcTimestampV2(msSinceEpoch: 1000, counter: 0),
        ),
        NeedEntry(
          category: NeedCategory.medicine,
          severity: NeedSeverity.need,
          expiresAtHlc: HlcTimestampV2(msSinceEpoch: 2000, counter: 0),
        ),
      ],
      location: LocationEvidence.fromDegrees(
        source: LocationSource.gps,
        frame: LocationFrame.subject,
        latDegrees: 25.0339805,
        lngDegrees: 121.5654177,
        accuracyM: 12,
        bearingDeg: 270,
      ),
    ).encode();
    // SOS_RED publish must SUCCEED (no over-budget-sos-rejected) and the wire
    // envelope must fit the locked 240B SOS budget. If this ever fails the fix
    // is to cut payload fields, NOT to raise the budget (spec §9.2).
    final published = await h.publisher.send(
      eventType: EventTypeV2.statusUpdate,
      priority: PriorityV2.sosRed,
      payload: payload,
      createdAtHlc: HlcTimestampV2(msSinceEpoch: 1000, counter: 0),
      expiresAtHlc: HlcTimestampV2(msSinceEpoch: 87400000, counter: 0),
      maxHops: 6,
      negotiatedMtu: 247,
      fieldId: Uint8List(16),
    );
    expect(published.wireBytes.length, lessThanOrEqualTo(kSosEnvelopeBudgetBytes));

    await h.projector.dispose();
    await h.dispatcher.dispose();
  });

  test('PRESENCE envelope projects to Event_Logs + presenceUpdates stream',
      () async {
    final h = await makeHarness();
    final eventStream = EventStream(
      handler: MeshEventHandler(),
      decoder: EventDecoder(),
      store: EventStore(databaseHelper: DatabaseHelper()),
    )..start();
    final presenceFuture = eventStream.presenceUpdates.first;

    final anon = Uint8List.fromList(List<int>.generate(16, (i) => 0xA0 + i));
    final payload = PresenceData(
      anonUserId: anon,
      location: LocationEvidence.fromDegrees(
        source: LocationSource.gps,
        frame: LocationFrame.subject,
        latDegrees: 25.0339805,
        lngDegrees: 121.5654177,
        observedAt: const HlcTimestampV2(msSinceEpoch: 4242, counter: 0),
      ),
      batteryHint: 88,
    ).encode();

    final published = await h.publisher.send(
      eventType: EventTypeV2.presence,
      priority: PriorityV2.normal,
      payload: payload,
      createdAtHlc: HlcTimestampV2(msSinceEpoch: 1000, counter: 0),
      expiresAtHlc: HlcTimestampV2(msSinceEpoch: 2000, counter: 0),
      maxHops: 4,
      negotiatedMtu: 247,
      fieldId: Uint8List(16),
    );

    final projectedId = h.projector.projectedEventIds.first;
    final outcome = await h.dispatcher
        .onReceiveEnvelopeBytes(published.wireBytes, peerId: 'AA:BB:CC');
    expect(outcome, isA<DispatchAccepted>());

    final eventId = await projectedId.timeout(const Duration(seconds: 2));
    final db = await DatabaseHelper().database;
    final logs = await db
        .query('Event_Logs', where: 'event_id = ?', whereArgs: [eventId]);
    expect(logs.length, 1);
    expect(logs.first['event_type'], LocalReadModelType.presence);

    final presence = await presenceFuture.timeout(const Duration(seconds: 2));
    expect(presence.anon8, 'a0a1a2a3'); // first 4 bytes of anon_user_id
    expect(presence.source, LocationSource.gps);
    expect(presence.lat, closeTo(25.0339805, 1e-7));
    expect(presence.lng, closeTo(121.5654177, 1e-7));
    expect(presence.batteryHint, 88);

    await eventStream.dispose();
    await h.projector.dispose();
    await h.dispatcher.dispose();
  });

  test('re-projecting the same PRESENCE envelope yields exactly one row',
      () async {
    // Drive the projector directly with a controllable outcomes stream so we
    // can feed the SAME accepted envelope twice (the dispatcher would dedup a
    // second wire delivery before the projector sees it). Asserts the
    // projector's own ingest is idempotent on event_id.
    final outcomes = StreamController<DispatchOutcome>.broadcast();
    final projector = V2InboundProjector(
      outcomes: outcomes.stream,
      handler: MeshEventHandler(),
    )..start();

    final keyPair = await Ed25519().newKeyPair();
    final pub = await keyPair.extractPublicKey();
    final publisher = MessagePublisherV2(
      keyPair: keyPair,
      authorPublicKey: Uint8List.fromList(pub.bytes),
      trace: MeshTraceWriter(DatabaseHelper()),
    );
    final published = await publisher.send(
      eventType: EventTypeV2.presence,
      priority: PriorityV2.normal,
      payload: PresenceData(
        anonUserId: Uint8List.fromList(List<int>.filled(16, 7)),
      ).encode(),
      createdAtHlc: HlcTimestampV2(msSinceEpoch: 1000, counter: 0),
      expiresAtHlc: HlcTimestampV2(msSinceEpoch: 2000, counter: 0),
      maxHops: 4,
      negotiatedMtu: 247,
      fieldId: Uint8List(16),
    );
    final accepted = DispatchAccepted(
      envelope: published.envelope,
      sourceTrust: SourceTrust.unverified,
      peerId: 'AA:BB:CC',
    );

    final ids = <String>[];
    final sub = projector.projectedEventIds.listen(ids.add);

    outcomes.add(accepted);
    outcomes.add(accepted); // same envelope_id → second ingest is a no-op
    await Future<void>.delayed(const Duration(milliseconds: 100));

    final db = await DatabaseHelper().database;
    final eventId = V2InboundProjector.eventIdOf(published.envelope.envelopeId);
    final logs = await db
        .query('Event_Logs', where: 'event_id = ?', whereArgs: [eventId]);
    expect(logs.length, 1, reason: 'duplicate projection must not double-insert');

    await sub.cancel();
    await projector.dispose();
    await outcomes.close();
  });

  test('v2 projection rows are read-model only — excluded from v1 outbound',
      () async {
    final handler = MeshEventHandler();
    // A normal v1 event (no v2- prefix) and a v2 projection row.
    await handler.ingestVerifiedEvent(
      eventId: 'v1only-abc',
      eventType: EventType.hazardMarker,
      urgency: 0,
      payload: const [1],
    );
    await handler.ingestVerifiedEvent(
      eventId: '${MeshEventHandler.v2ProjectionIdPrefix}deadbeefcafe',
      eventType: EventType.hazardMarker,
      urgency: 0,
      payload: const [1],
    );

    // v1 outbound / IBLT set must NOT contain the v2 projection row.
    final outboundIds = await handler.getLocalEventIds();
    expect(outboundIds, contains('v1only-abc'));
    expect(
      outboundIds,
      isNot(contains('${MeshEventHandler.v2ProjectionIdPrefix}deadbeefcafe')),
    );

    // ...but the UI read-model (EventStore) MUST still see it.
    final store = EventStore(databaseHelper: DatabaseHelper());
    final recent = await store.queryRecent(limit: 50);
    final recentIds = recent.map((r) => r['event_id'] as String).toSet();
    expect(
      recentIds,
      contains('${MeshEventHandler.v2ProjectionIdPrefix}deadbeefcafe'),
    );
  });

  test('non-SOS, non-SAFE status (UNSAFE) is not projected into the read-model',
      () async {
    // A8: SAFE now projects an SOS-resolution row (see the test above). Other
    // non-SOS states (UNSAFE) still have no v1 read-model surface yet.
    final h = await makeHarness();
    final payload = StatusUpdateData(safetyState: SafetyState.unsafe).encode();
    // UNSAFE implies PriorityV2.status; matrix accepts STATUS_UPDATE at status.
    final published = await h.publisher.send(
      eventType: EventTypeV2.statusUpdate,
      priority: PriorityV2.status,
      payload: payload,
      createdAtHlc: HlcTimestampV2(msSinceEpoch: 1000, counter: 0),
      expiresAtHlc: HlcTimestampV2(msSinceEpoch: 2000, counter: 0),
      maxHops: 6,
      negotiatedMtu: 247,
      fieldId: Uint8List(16),
    );
    final outcome = await h.dispatcher
        .onReceiveEnvelopeBytes(published.wireBytes, peerId: 'AA:BB:CC');
    expect(outcome, isA<DispatchAccepted>());

    // Give the async projector a chance to run, then assert nothing landed.
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final db = await DatabaseHelper().database;
    final logs = await db.query('Event_Logs');
    expect(logs, isEmpty);

    await h.projector.dispose();
    await h.dispatcher.dispose();
  });
}
