import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ignirelay_app/app/controllers/active_field_controller.dart';
import 'package:ignirelay_app/app/controllers/envelope_dispatcher_v2.dart';
import 'package:ignirelay_app/app/controllers/message_publisher_v2.dart';
import 'package:ignirelay_app/app/crypto/field_auth_v2.dart';
import 'package:ignirelay_app/app/db/database_helper.dart';
import 'package:ignirelay_app/app/proto/event_envelope_v2.dart';
import 'package:ignirelay_app/app/services/anon_identity.dart' show SecureKvStore;
import 'package:ignirelay_app/app/services/author_rate_limiter.dart';
import 'package:ignirelay_app/app/services/ble_v2_bridge.dart';
import 'package:ignirelay_app/app/services/envelope_store_v2.dart';
import 'package:ignirelay_app/app/services/event_publisher_v2_facade.dart';
import 'package:ignirelay_app/app/services/field_key_store.dart';
import 'package:ignirelay_app/app/services/field_session_store.dart';
import 'package:ignirelay_app/app/services/mesh_trace_writer.dart';
import 'package:ignirelay_app/app/services/peer_capability_registry.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    DatabaseHelper.testDatabasePathOverride = inMemoryDatabasePath;
  });

  setUp(() async {
    await DatabaseHelper().resetForTest();
  });

  test('queues when bridge is absent, then drains after attach + active peer',
      () async {
    final registry = PeerCapabilityRegistry(
      helloTimeout: const Duration(seconds: 5),
    );
    final facade = EventPublisherV2Facade(registry: registry);
    addTearDown(() async {
      await facade.dispose();
      await registry.dispose();
    });

    // No ActiveFieldController attached → zero-field path; the publish queues.
    final queued = await facade.publishPresence(anonUserId: Uint8List(16));
    expect(queued.queued, isTrue);
    expect(facade.pendingQueueDepth, 1);

    final bridge = await _makeRecordingBridge(registry);
    facade.attachBridge(bridge);
    await _drainMicrotasks();
    expect(bridge.invocations, isEmpty);
    expect(facade.pendingQueueDepth, 1);

    _markPeerActive(registry, 'AA:BB');
    await _drainMicrotasks();
    expect(bridge.invocations.length, 1);
    expect(bridge.invocations.single.peerId, 'AA:BB');
    expect(bridge.invocations.single.eventType, EventTypeV2.presence);
    expect(facade.pendingQueueDepth, 0);
  });

  test('queues when no active peers, then drains on peer-ready transition',
      () async {
    final registry = PeerCapabilityRegistry(
      helloTimeout: const Duration(seconds: 5),
    );
    final bridge = await _makeRecordingBridge(registry);
    final facade = EventPublisherV2Facade(
      registry: registry,
      bridge: bridge,
    );
    addTearDown(() async {
      await facade.dispose();
      await registry.dispose();
    });

    final queued = await facade.publishStatusUpdate(
      safetyState: SafetyState.safe,
    );
    expect(queued.queued, isTrue);
    expect(facade.pendingQueueDepth, 1);
    expect(bridge.invocations, isEmpty);

    _markPeerActive(registry, 'CC:DD');
    await _drainMicrotasks();
    expect(bridge.invocations.length, 1);
    expect(bridge.invocations.single.peerId, 'CC:DD');
    expect(bridge.invocations.single.eventType, EventTypeV2.statusUpdate);
    expect(facade.pendingQueueDepth, 0);
  });

  test('pending queue cap keeps newest entries (drops oldest FIFO)', () async {
    final registry = PeerCapabilityRegistry(
      helloTimeout: const Duration(seconds: 5),
    );
    final facade = EventPublisherV2Facade(registry: registry);
    addTearDown(() async {
      await facade.dispose();
      await registry.dispose();
    });

    const cap = EventPublisherV2Facade.kMaxPendingEntries;
    const total = cap + 3;
    // Distinguish entries by anon_user_id[0] so we can assert FIFO eviction.
    for (var i = 0; i < total; i++) {
      await facade.publishPresence(
        anonUserId: Uint8List.fromList(List<int>.filled(16, i % 256)),
      );
    }
    expect(facade.pendingQueueDepth, cap);

    final bridge = await _makeRecordingBridge(registry);
    _markPeerActive(registry, 'EE:FF');
    facade.attachBridge(bridge);
    await _drainMicrotasks();

    expect(bridge.invocations.length, cap);
    expect(
      PresenceData.decode(bridge.invocations.first.payload).anonUserId.first,
      (total - cap) % 256,
    );
    expect(
      PresenceData.decode(bridge.invocations.last.payload).anonUserId.first,
      (total - 1) % 256,
    );
    expect(facade.pendingQueueDepth, 0);
  });

  test('drain drops stale entries via pending TTL/age guard', () async {
    DateTime fakeNow = DateTime.now();
    final registry = PeerCapabilityRegistry(
      helloTimeout: const Duration(seconds: 5),
    );
    final facade = EventPublisherV2Facade(
      registry: registry,
      now: () => fakeNow,
    );
    addTearDown(() async {
      await facade.dispose();
      await registry.dispose();
    });

    await facade.publishStatusUpdate(
      safetyState: SafetyState.safe,
    );
    expect(facade.pendingQueueDepth, 1);

    fakeNow = fakeNow.add(const Duration(hours: 25));
    final bridge = await _makeRecordingBridge(registry);
    _markPeerActive(registry, 'GG:HH');
    facade.attachBridge(bridge);
    await _drainMicrotasks();

    expect(bridge.invocations, isEmpty,
        reason: 'stale pending entries should be dropped before send');
    expect(facade.pendingQueueDepth, 0);
  });

  test('Outbox_V2 persists queued row with pre-allocated envelope_id',
      () async {
    final db = DatabaseHelper();
    final registry = PeerCapabilityRegistry(
      helloTimeout: const Duration(seconds: 5),
    );
    final expectedEnvelopeId = _filledEnvelopeId(0x2A);
    final facade = EventPublisherV2Facade(
      registry: registry,
      db: db,
      envelopeIdFactory: () => Uint8List.fromList(expectedEnvelopeId),
    );
    addTearDown(() async {
      await facade.dispose();
      await registry.dispose();
    });

    final queued = await facade.publishPresence(anonUserId: Uint8List(16));
    expect(queued.queued, isTrue);

    final rows = await _waitForOutboxRowCount(db, 1);
    expect(rows.single['event_type'], EventTypeV2.presence);
    expect(
      Uint8List.fromList(rows.single['envelope_id'] as List<int>),
      orderedEquals(expectedEnvelopeId),
    );
  });

  test(
      'restart hydrate re-drain reuses persisted envelope_id and clears Outbox_V2 row',
      () async {
    final db = DatabaseHelper();
    final firstRegistry = PeerCapabilityRegistry(
      helloTimeout: const Duration(seconds: 5),
    );
    final persistedEnvelopeId = _filledEnvelopeId(0x33);
    final firstFacade = EventPublisherV2Facade(
      registry: firstRegistry,
      db: db,
      envelopeIdFactory: () => Uint8List.fromList(persistedEnvelopeId),
    );

    final queued = await firstFacade.publishStatusUpdate(
      safetyState: SafetyState.safe,
    );
    expect(queued.queued, isTrue);

    final queuedRows = await _waitForOutboxRowCount(db, 1);
    expect(
      Uint8List.fromList(queuedRows.single['envelope_id'] as List<int>),
      orderedEquals(persistedEnvelopeId),
    );

    await firstFacade.dispose();
    await firstRegistry.dispose();

    final secondRegistry = PeerCapabilityRegistry(
      helloTimeout: const Duration(seconds: 5),
    );
    final bridge = await _makeRecordingBridge(secondRegistry);
    final secondFacade = EventPublisherV2Facade(
      registry: secondRegistry,
      db: db,
      envelopeIdFactory: () => _filledEnvelopeId(0x99),
    );
    addTearDown(() async {
      await secondFacade.dispose();
      await secondRegistry.dispose();
    });

    await secondFacade.hydrationDone;
    expect(secondFacade.pendingQueueDepth, 1);

    secondFacade.attachBridge(bridge);
    _markPeerActive(secondRegistry, 'RM:01');
    await _drainMicrotasks();

    expect(bridge.invocations.length, 1);
    expect(
      bridge.invocations.single.envelopeId,
      isNotNull,
      reason: 'drain must pass persisted envelope_id to bridge sendEnvelope',
    );
    expect(
      bridge.invocations.single.envelopeId!,
      orderedEquals(persistedEnvelopeId),
    );

    await _waitForOutboxRowCount(db, 0);
    expect(secondFacade.pendingQueueDepth, 0);
  });

  test('hydrate prunes stale/expired Outbox_V2 rows and does not send them',
      () async {
    final db = DatabaseHelper();
    final fakeNow = DateTime.fromMillisecondsSinceEpoch(1900000000000);
    await _insertOutboxRow(
      db: db,
      envelopeId: _filledEnvelopeId(0x41),
      eventType: EventTypeV2.chatMessage,
      priority: PriorityV2.normal,
      payload: Uint8List.fromList([1]),
      createdAtHlcMs:
          fakeNow.subtract(const Duration(hours: 26)).millisecondsSinceEpoch,
      expiresAtHlcMs:
          fakeNow.add(const Duration(hours: 1)).millisecondsSinceEpoch,
      enqueuedAtMs:
          fakeNow.subtract(const Duration(hours: 25)).millisecondsSinceEpoch,
      maxHops: 6,
    );
    await _insertOutboxRow(
      db: db,
      envelopeId: _filledEnvelopeId(0x42),
      eventType: EventTypeV2.statusUpdate,
      priority: PriorityV2.status,
      payload: Uint8List.fromList([2]),
      createdAtHlcMs:
          fakeNow.subtract(const Duration(minutes: 2)).millisecondsSinceEpoch,
      expiresAtHlcMs:
          fakeNow.subtract(const Duration(seconds: 1)).millisecondsSinceEpoch,
      enqueuedAtMs:
          fakeNow.subtract(const Duration(minutes: 1)).millisecondsSinceEpoch,
      maxHops: 6,
    );

    final registry = PeerCapabilityRegistry(
      helloTimeout: const Duration(seconds: 5),
    );
    final bridge = await _makeRecordingBridge(registry);
    final facade = EventPublisherV2Facade(
      registry: registry,
      db: db,
      now: () => fakeNow,
    );
    addTearDown(() async {
      await facade.dispose();
      await registry.dispose();
    });

    await facade.hydrationDone;
    expect(facade.pendingQueueDepth, 0);
    await _waitForOutboxRowCount(db, 0);

    facade.attachBridge(bridge);
    _markPeerActive(registry, 'RM:02');
    await _drainMicrotasks();
    expect(bridge.invocations, isEmpty);
  });

  test('publishStatusUpdate applies impliedPriorityFloor', () async {
    final registry = PeerCapabilityRegistry(
      helloTimeout: const Duration(seconds: 5),
    );
    final bridge = await _makeRecordingBridge(registry);
    final facade = EventPublisherV2Facade(
      registry: registry,
      bridge: bridge,
    );
    addTearDown(() async {
      await facade.dispose();
      await registry.dispose();
    });
    _markPeerActive(registry, 'II:JJ');

    await facade.publishStatusUpdate(
      safetyState: SafetyState.safe,
      priority: PriorityV2.normal,
    );
    await facade.publishStatusUpdate(
      safetyState: SafetyState.injured,
      priority: PriorityV2.status,
    );
    await facade.publishStatusUpdate(
      safetyState: SafetyState.safe,
      priority: PriorityV2.status,
      needs: const [
        NeedEntry(
          category: NeedCategory.water,
          severity: NeedSeverity.urgent,
          expiresAtHlc: HlcTimestampV2(msSinceEpoch: 1, counter: 0),
        ),
      ],
    );
    await facade.publishStatusUpdate(
      safetyState: SafetyState.trapped,
      priority: PriorityV2.status,
    );

    expect(bridge.invocations.length, 4);
    expect(bridge.invocations[0].priority, PriorityV2.status,
        reason: 'SAFE should floor at STATUS');
    expect(bridge.invocations[1].priority, PriorityV2.sosYellow,
        reason: 'INJURED should floor at SOS_YELLOW');
    expect(bridge.invocations[2].priority, PriorityV2.sosYellow,
        reason: 'urgent need should floor at SOS_YELLOW');
    expect(bridge.invocations[3].priority, PriorityV2.sosRed,
        reason: 'TRAPPED should floor at SOS_RED');
  });

  test('publishPresence rides the ACTIVE field (real field_id + mac key)',
      () async {
    final registry = PeerCapabilityRegistry(
      helloTimeout: const Duration(seconds: 5),
    );
    final bridge = await _makeRecordingBridge(registry);
    final facade = EventPublisherV2Facade(
      registry: registry,
      bridge: bridge,
    );
    final secret = Uint8List.fromList(List<int>.filled(32, 0xA5));
    final fieldCtrl = await _makeFieldController(secret: secret);
    facade.attachActiveField(fieldCtrl);
    addTearDown(() async {
      await facade.dispose();
      await registry.dispose();
      fieldCtrl.dispose();
    });
    _markPeerActive(registry, 'PR:01');

    final anon = Uint8List.fromList(List<int>.generate(16, (i) => i + 1));
    final location = LocationEvidence.fromDegrees(
      source: LocationSource.gps,
      frame: LocationFrame.subject,
      latDegrees: 25.0339805,
      lngDegrees: 121.5654177,
      observedAt: const HlcTimestampV2(msSinceEpoch: 1234, counter: 0),
    );

    final outcome = await facade.publishPresence(
      anonUserId: anon,
      location: location,
      batteryHint: 73,
    );
    expect(outcome.anyAccepted, isTrue);
    expect(bridge.invocations.length, 1);

    final call = bridge.invocations.single;
    // §6 matrix: PRESENCE → NORMAL; §11.2: TTL 4h, max_hops 4.
    expect(call.eventType, EventTypeV2.presence);
    expect(call.priority, PriorityV2.normal);
    expect(call.maxHops, 4);
    expect(
      call.expiresAtHlc.msSinceEpoch - call.createdAtHlc.msSinceEpoch,
      const Duration(hours: 4).inMilliseconds,
    );

    // Payload round-trips back to the same PresenceData (anon + location).
    final decoded = PresenceData.decode(call.payload);
    expect(decoded.anonUserId, orderedEquals(anon));
    expect(decoded.batteryHint, 73);
    expect(decoded.location.source, LocationSource.gps);
    expect(decoded.location.latE7, 250339805); // round-to-nearest trap value
    expect(decoded.location.lngE7, 1215654177);

    // Rides the ACTIVE field's real field_id (non-zero) + 32-byte mac key.
    expect(call.fieldId, isNotNull);
    expect(call.fieldId!.length, FieldAuthV2.fieldIdBytes);
    expect(FieldAuthV2.isZeroFieldId(call.fieldId!), isFalse);
    expect(call.fieldMacKey, isNotNull);
    expect(call.fieldMacKey!.length, 32);

    final expectedFieldId = await FieldAuthV2.deriveFieldId(secret);
    expect(call.fieldId!, orderedEquals(expectedFieldId));
  });

  test('publishCheckpoint encodes a typed CheckpointData payload (A9)',
      () async {
    final registry = PeerCapabilityRegistry(
      helloTimeout: const Duration(seconds: 5),
    );
    final bridge = await _makeRecordingBridge(registry);
    final facade = EventPublisherV2Facade(
      registry: registry,
      bridge: bridge,
    );
    addTearDown(() async {
      await facade.dispose();
      await registry.dispose();
    });
    _markPeerActive(registry, 'CP:01');

    final anon = Uint8List.fromList(List<int>.generate(16, (i) => i + 1));
    final outcome = await facade.publishCheckpoint(
      anonUserId: anon,
      checkpointId: 'gate-7',
      location: LocationEvidence.fromDegrees(
        source: LocationSource.gps,
        frame: LocationFrame.subject,
        latDegrees: 25.04,
        lngDegrees: 121.56,
      ),
    );
    expect(outcome.anyAccepted, isTrue);
    expect(bridge.invocations.length, 1);

    final call = bridge.invocations.single;
    // §6 matrix: CHECKPOINT → STATUS; §11.2: TTL 12h, max_hops 6.
    expect(call.eventType, EventTypeV2.checkpoint);
    expect(call.priority, PriorityV2.status);
    expect(call.maxHops, 6);
    expect(
      call.expiresAtHlc.msSinceEpoch - call.createdAtHlc.msSinceEpoch,
      const Duration(hours: 12).inMilliseconds,
    );

    final decoded = CheckpointData.decode(call.payload);
    expect(decoded.anonUserId, orderedEquals(anon));
    expect(decoded.checkpointId, 'gate-7');
    expect(decoded.location.latE7, 250400000);
    expect(decoded.location.lngE7, 1215600000);
  });

  test('publishAdminBroadcast encodes a typed AdminBroadcastData payload (A9)',
      () async {
    final registry = PeerCapabilityRegistry(
      helloTimeout: const Duration(seconds: 5),
    );
    final bridge = await _makeRecordingBridge(registry);
    final facade = EventPublisherV2Facade(
      registry: registry,
      bridge: bridge,
    );
    addTearDown(() async {
      await facade.dispose();
      await registry.dispose();
    });
    _markPeerActive(registry, 'AD:01');

    final outcome = await facade.publishAdminBroadcast(message: '請保持冷靜');
    expect(outcome.anyAccepted, isTrue);
    expect(bridge.invocations.length, 1);

    final call = bridge.invocations.single;
    // §6 matrix: ADMIN_BROADCAST → ALERT; §11.2: TTL 6h, max_hops 12.
    expect(call.eventType, EventTypeV2.adminBroadcast);
    expect(call.priority, PriorityV2.alert);
    expect(call.maxHops, 12);
    expect(
      call.expiresAtHlc.msSinceEpoch - call.createdAtHlc.msSinceEpoch,
      const Duration(hours: 6).inMilliseconds,
    );

    final decoded = AdminBroadcastData.decode(call.payload);
    expect(decoded.scope, AdminScope.all); // toAllNodes default
    expect(decoded.message, '請保持冷靜');
    // The payload carries an expires_at so receivers can auto-dismiss the banner.
    expect(decoded.expiresAt.msSinceEpoch, greaterThan(0));
  });

  test('publishAdminBroadcast rejects an over-budget message (ArgumentError)',
      () async {
    final registry = PeerCapabilityRegistry(
      helloTimeout: const Duration(seconds: 5),
    );
    final facade = EventPublisherV2Facade(registry: registry);
    addTearDown(() async {
      await facade.dispose();
      await registry.dispose();
    });

    final tooLong = 'x' * (AdminBroadcastData.kMessageMaxLen + 1);
    expect(
      () => facade.publishAdminBroadcast(message: tooLong),
      throwsArgumentError,
    );
  });

  test('multi-field switch → published field_id follows the active field (A7)',
      () async {
    final registry = PeerCapabilityRegistry(
      helloTimeout: const Duration(seconds: 5),
    );
    final bridge = await _makeRecordingBridge(registry);
    final facade = EventPublisherV2Facade(registry: registry, bridge: bridge);
    final secretA = Uint8List.fromList(List<int>.filled(32, 0x11));
    final secretB = Uint8List.fromList(List<int>.filled(32, 0x22));
    final fieldCtrl = await _makeFieldController(secret: secretA); // A active
    facade.attachActiveField(fieldCtrl);
    addTearDown(() async {
      await facade.dispose();
      await registry.dispose();
      fieldCtrl.dispose();
    });
    _markPeerActive(registry, 'SW:01');

    final idA = await FieldAuthV2.deriveFieldId(secretA);
    final idB = await FieldAuthV2.deriveFieldId(secretB);
    expect(idA, isNot(orderedEquals(idB)));

    // 1) active = A → the send rides A's field_id.
    await facade.publishPresence(anonUserId: Uint8List(16));
    expect(bridge.invocations.last.fieldId!, orderedEquals(idA));

    // 2) join B → B becomes active → the next send rides B's field_id.
    await fieldCtrl.joinBySecret(secretB, displayName: 'B');
    await facade.publishPresence(anonUserId: Uint8List(16));
    expect(bridge.invocations.last.fieldId!, orderedEquals(idB));

    // 3) switch back to A (joinedFields is oldest-first ⇒ first = A).
    fieldCtrl.setActive(fieldCtrl.joinedFields.first.fieldIdHex);
    await facade.publishPresence(anonUserId: Uint8List(16));
    expect(bridge.invocations.last.fieldId!, orderedEquals(idA));
  });

  test('non-control publish with no joined field returns noField (not queued)',
      () async {
    final registry = PeerCapabilityRegistry(
      helloTimeout: const Duration(seconds: 5),
    );
    final bridge = await _makeRecordingBridge(registry);
    final facade = EventPublisherV2Facade(
      registry: registry,
      bridge: bridge,
    );
    final fieldCtrl = await _makeFieldController(); // no field joined
    facade.attachActiveField(fieldCtrl);
    addTearDown(() async {
      await facade.dispose();
      await registry.dispose();
      fieldCtrl.dispose();
    });
    _markPeerActive(registry, 'NF:01');

    final outcome = await facade.publishPresence(anonUserId: Uint8List(16));
    expect(outcome.noField, isTrue,
        reason: 'no joined/active field → reject, not queue (A5 §21.6)');
    expect(outcome.queued, isFalse);
    expect(facade.pendingQueueDepth, 0);
    expect(bridge.invocations, isEmpty);
  });

  test('queued envelope persists its active field_id to Outbox_V2 (#4-7)',
      () async {
    final db = DatabaseHelper();
    final registry = PeerCapabilityRegistry(
      helloTimeout: const Duration(seconds: 5),
    );
    final secret = Uint8List.fromList(List<int>.filled(32, 0x5A));
    final facade = EventPublisherV2Facade(registry: registry, db: db);
    final fieldCtrl = await _makeFieldController(secret: secret);
    facade.attachActiveField(fieldCtrl);
    addTearDown(() async {
      await facade.dispose();
      await registry.dispose();
      fieldCtrl.dispose();
    });

    // No active peer → queued; the Outbox row must carry the active field_id so
    // a restart-driven re-drain re-binds to the same field (施工筆記 3).
    final queued = await facade.publishPresence(anonUserId: Uint8List(16));
    expect(queued.queued, isTrue);

    final rows = await _waitForOutboxRowCount(db, 1);
    final expectedFieldId = await FieldAuthV2.deriveFieldId(secret);
    expect(
      Uint8List.fromList(rows.single['field_id'] as List<int>),
      orderedEquals(expectedFieldId),
    );
  });

  test(
      'wire field_mac is real + receiver-verifiable: member accepts, other '
      'field rejects',
      () async {
    final registry = PeerCapabilityRegistry(
      helloTimeout: const Duration(seconds: 5),
    );
    addTearDown(() async => registry.dispose());
    _markPeerActive(registry, 'FM:01');

    // A REAL (non-recording) bridge so sendEnvelope actually signs + MACs the
    // envelope via MessagePublisherV2 (the recording bridge short-circuits).
    final db = DatabaseHelper();
    final trace = MeshTraceWriter(db);
    final keyPair = await Ed25519().newKeyPair();
    final authorPub =
        Uint8List.fromList((await keyPair.extractPublicKey()).bytes);
    final publisher = MessagePublisherV2(
      keyPair: keyPair,
      authorPublicKey: authorPub,
      trace: trace,
    );
    final bridge = BleV2Bridge(
      store: EnvelopeStoreV2(db),
      dispatcher: EnvelopeDispatcherV2(
        store: EnvelopeStoreV2(db),
        trace: trace,
        rateLimiter: AuthorRateLimiter(capacity: 100, perSecond: 1000),
      ),
      publisher: publisher,
      registry: registry,
      selfHelloFactory: () => const ProtocolHelloData(
        peerKind: PeerKind.phoneV1,
        maxRxEnvelopeBytes: 2048,
        supportsChunking: true,
        supportsIblt: true,
        supportsBloomV2: true,
        minNegotiatedMtu: 247,
        bgState: BgState.foreground,
      ),
      nativeEventStream: const Stream<dynamic>.empty(),
      writeEventToPeer: (_, __) async => true,
      notifyEventToPeer: (_, __) async => true,
    );

    // A field context derived from a local secret (no debug-secret constant).
    final secret = Uint8List.fromList(List<int>.filled(32, 0xA5));
    final fieldId = await FieldAuthV2.deriveFieldId(secret);
    final macKey = await FieldAuthV2.deriveFieldMacKey(secret);

    const createdAt = HlcTimestampV2(msSinceEpoch: 1000, counter: 0);
    final tx = await bridge.sendEnvelope(
      peerId: 'FM:01',
      eventType: EventTypeV2.presence,
      priority: PriorityV2.normal,
      payload: PresenceData(
        anonUserId: Uint8List.fromList(List<int>.filled(16, 9)),
      ).encode(),
      createdAtHlc: createdAt,
      expiresAtHlc: HlcTimestampV2(
        msSinceEpoch:
            createdAt.msSinceEpoch + const Duration(hours: 4).inMilliseconds,
        counter: 0,
      ),
      maxHops: 4,
      fieldId: fieldId,
      fieldMacKey: macKey,
    );
    expect(tx.sent, isTrue);
    final published = tx.published!;

    // Decode the FINAL wire bytes (not the in-memory struct) and assert the
    // field proofs are actually on the wire.
    final decoded = EventEnvelopeV2.decode(published.wireBytes);
    expect(FieldAuthV2.isZeroFieldId(decoded.fieldId), isFalse);
    expect(decoded.fieldId, orderedEquals(fieldId));
    expect(decoded.fieldMac.length, FieldAuthV2.fieldMacBytes); // 16

    // A receiver in a DIFFERENT field rejects it — proves field_id is real
    // scoping, not zero/wildcard. (Run first: a dropped envelope is not
    // stored, so it can't shadow the member-accept below via dedup.)
    final otherStore = await FieldKeyStore.fromSecrets([
      Uint8List.fromList(List<int>.filled(32, 0xBB)),
    ]);
    final otherDispatcher = EnvelopeDispatcherV2(
      store: EnvelopeStoreV2(db),
      trace: trace,
      rateLimiter: AuthorRateLimiter(capacity: 100, perSecond: 1000),
      fieldKeys: otherStore,
      enableFieldScopeCheck: true,
    );
    addTearDown(() async => otherDispatcher.dispose());
    final reject = await otherDispatcher
        .onReceiveEnvelopeBytes(published.wireBytes, peerId: 'FM:01');
    expect(reject, isA<DispatchDropped>());
    expect((reject as DispatchDropped).dropReason, 'field-scope-mismatch');

    // The strongest proof: a receiver that JOINED the same field (field-scope
    // check ON) ACCEPTS it — i.e. the field_mac genuinely verifies against the
    // key derived from the debug secret over the canonical sig input.
    final memberStore = await FieldKeyStore.fromSecrets([secret]);
    final memberDispatcher = EnvelopeDispatcherV2(
      store: EnvelopeStoreV2(db),
      trace: trace,
      rateLimiter: AuthorRateLimiter(capacity: 100, perSecond: 1000),
      fieldKeys: memberStore,
      enableFieldScopeCheck: true,
    );
    addTearDown(() async => memberDispatcher.dispose());
    final accept = await memberDispatcher
        .onReceiveEnvelopeBytes(published.wireBytes, peerId: 'FM:01');
    expect(accept, isA<DispatchAccepted>(),
        reason: 'field_mac must verify for a member of the same field');
  });

  test('publishSosStatus routes through status publish and keeps SOS_RED floor',
      () async {
    final registry = PeerCapabilityRegistry(
      helloTimeout: const Duration(seconds: 5),
    );
    final bridge = await _makeRecordingBridge(registry);
    final facade = EventPublisherV2Facade(
      registry: registry,
      bridge: bridge,
    );
    addTearDown(() async {
      await facade.dispose();
      await registry.dispose();
    });
    _markPeerActive(registry, 'KK:LL');

    await facade.publishSosStatus(safetyState: SafetyState.safe);
    await facade.publishSosStatus(safetyState: SafetyState.trapped);

    expect(bridge.invocations.length, 2);
    for (final call in bridge.invocations) {
      expect(call.eventType, EventTypeV2.statusUpdate);
      expect(call.priority, PriorityV2.sosRed);
      final payload = StatusUpdateData.decode(call.payload);
      expect(
        payload.safetyState == SafetyState.safe ||
            payload.safetyState == SafetyState.trapped,
        isTrue,
      );
    }
  });

  test('publishSosStatus carries LocationEvidence into the payload (#4-6)',
      () async {
    final registry = PeerCapabilityRegistry(
      helloTimeout: const Duration(seconds: 5),
    );
    final bridge = await _makeRecordingBridge(registry);
    final facade = EventPublisherV2Facade(
      registry: registry,
      bridge: bridge,
    );
    addTearDown(() async {
      await facade.dispose();
      await registry.dispose();
    });
    _markPeerActive(registry, 'LO:01');

    await facade.publishSosStatus(
      safetyState: SafetyState.trapped,
      location: LocationEvidence.fromDegrees(
        source: LocationSource.gps,
        frame: LocationFrame.subject,
        latDegrees: 25.0339805,
        lngDegrees: 121.5654177,
      ),
    );
    // No-location SOS still publishes (back-compat).
    await facade.publishSosStatus(safetyState: SafetyState.trapped);

    expect(bridge.invocations.length, 2);
    final withLoc = StatusUpdateData.decode(bridge.invocations[0].payload);
    expect(withLoc.location, isNotNull);
    expect(withLoc.location!.latE7, 250339805);
    expect(withLoc.location!.lngE7, 1215654177);

    final withoutLoc = StatusUpdateData.decode(bridge.invocations[1].payload);
    expect(withoutLoc.location, isNull);
  });

  test('publishHazardMarker encodes a typed HazardMarkerData payload (#4-5)',
      () async {
    final registry = PeerCapabilityRegistry(
      helloTimeout: const Duration(seconds: 5),
    );
    final bridge = await _makeRecordingBridge(registry);
    final facade = EventPublisherV2Facade(
      registry: registry,
      bridge: bridge,
    );
    addTearDown(() async {
      await facade.dispose();
      await registry.dispose();
    });
    _markPeerActive(registry, 'HZ:01');

    final outcome = await facade.publishHazardMarker(
      hazardType: HazardType.flood,
      severity: 4,
      location: LocationEvidence.fromDegrees(
        source: LocationSource.gps,
        frame: LocationFrame.observer,
        latDegrees: 25.04,
        lngDegrees: 121.56,
      ),
      description: '河水暴漲',
      isConfirmation: true,
    );
    expect(outcome.anyAccepted, isTrue);
    expect(bridge.invocations.length, 1);

    final call = bridge.invocations.single;
    // §6 matrix: HAZARD → ALERT; §11.2 max_hops 10.
    expect(call.eventType, EventTypeV2.hazardMarker);
    expect(call.priority, PriorityV2.alert);
    expect(call.maxHops, 10);

    // Payload is a typed HazardMarkerData (NOT a JSON shim) and round-trips.
    final hm = HazardMarkerData.decode(call.payload);
    expect(hm.hazardType, HazardType.flood);
    expect(hm.severity, 4);
    expect(hm.isConfirmation, isTrue);
    expect(hm.description, '河水暴漲');
    expect(hm.location.source, LocationSource.gps);
    expect(hm.location.latE7, 250400000);
    expect(hm.location.lngE7, 1215600000);
  });

  test('publishHazardMarker rejects an over-budget description (ArgumentError)',
      () async {
    final registry = PeerCapabilityRegistry(
      helloTimeout: const Duration(seconds: 5),
    );
    final facade = EventPublisherV2Facade(registry: registry);
    addTearDown(() async {
      await facade.dispose();
      await registry.dispose();
    });

    final tooLong = 'x' * (HazardMarkerData.kDescriptionMaxLen + 1);
    expect(
      () => facade.publishHazardMarker(
        hazardType: HazardType.fire,
        description: tooLong,
      ),
      throwsArgumentError,
    );

    // Exactly at the cap is allowed (no throw; no peer → queued).
    final atCap = 'y' * HazardMarkerData.kDescriptionMaxLen;
    final outcome = await facade.publishHazardMarker(
      hazardType: HazardType.fire,
      description: atCap,
    );
    expect(outcome.queued, isTrue);

    // #4-5 follow-up — the budget is UTF-8 BYTES, not Dart code units. A CJK
    // description whose `.length` is UNDER the cap but whose encoded byte
    // length is OVER must still be rejected (a 3-byte/char string at 94 chars
    // = 282 B > 280). The old `description.length` guard wrongly accepted it.
    final cjkOverBudget = '水' * 94; // 94 code units, 282 UTF-8 bytes
    expect(cjkOverBudget.length, lessThan(HazardMarkerData.kDescriptionMaxLen));
    expect(utf8.encode(cjkOverBudget).length,
        greaterThan(HazardMarkerData.kDescriptionMaxLen));
    expect(
      () => facade.publishHazardMarker(
        hazardType: HazardType.fire,
        description: cjkOverBudget,
      ),
      throwsArgumentError,
    );
  });

  // ── A11-latency-fix — emergency-delivery hook ──────────────────────────
  //
  // SOS / SAFE that finds no ready peer must trigger an immediate connect
  // (the hook) instead of waiting for the next gossip cycle. The predicate is
  // keyed on PRIORITY + SAFETY STATE, never on event type — so PRESENCE and
  // CHECKPOINT (both NON-SOS) must NOT fire it even though CHECKPOINT also
  // rides at PriorityV2.status (the same priority SAFE ends up at).
  group('A11-latency-fix emergency delivery', () {
    test('SOS with a ready peer sends immediately, does NOT call the hook',
        () async {
      final registry =
          PeerCapabilityRegistry(helloTimeout: const Duration(seconds: 5));
      final bridge = await _makeRecordingBridge(registry);
      final hook = _CountingEmergencyDelivery();
      final facade = EventPublisherV2Facade(
        registry: registry,
        bridge: bridge,
        emergencyDelivery: hook,
      );
      addTearDown(() async {
        await facade.dispose();
        await registry.dispose();
      });
      _markPeerActive(registry, 'EM:01');

      final outcome =
          await facade.publishStatusUpdate(safetyState: SafetyState.trapped);
      expect(outcome.anyAccepted, isTrue);
      expect(bridge.invocations.length, 1);
      expect(hook.calls, 0,
          reason: 'a ready peer means no emergency connect is needed');
    });

    test(
        'SOS (TRAPPED) with zero ready peers enqueues once, calls hook once, '
        'no duplicate envelope', () async {
      final registry =
          PeerCapabilityRegistry(helloTimeout: const Duration(seconds: 5));
      final bridge = await _makeRecordingBridge(registry);
      final hook = _CountingEmergencyDelivery();
      final facade = EventPublisherV2Facade(
        registry: registry,
        bridge: bridge,
        emergencyDelivery: hook,
      );
      addTearDown(() async {
        await facade.dispose();
        await registry.dispose();
      });

      final outcome =
          await facade.publishStatusUpdate(safetyState: SafetyState.trapped);
      expect(outcome.queued, isTrue);
      expect(facade.pendingQueueDepth, 1);
      expect(hook.calls, 1);
      expect(bridge.invocations, isEmpty);

      // The hook only accelerates connectivity; it must NOT mint a second
      // envelope. When a peer arrives, the SAME single queued envelope drains
      // exactly once.
      _markPeerActive(registry, 'EM:02');
      await _drainMicrotasks();
      expect(bridge.invocations.length, 1,
          reason: 'exactly one envelope — emergency hook does not duplicate');
      expect(facade.pendingQueueDepth, 0);
      expect(hook.calls, 1, reason: 'no further hook call on drain');
    });

    test('SOS_YELLOW (INJURED) with zero ready peers calls the hook', () async {
      final registry =
          PeerCapabilityRegistry(helloTimeout: const Duration(seconds: 5));
      final bridge = await _makeRecordingBridge(registry);
      final hook = _CountingEmergencyDelivery();
      final facade = EventPublisherV2Facade(
        registry: registry,
        bridge: bridge,
        emergencyDelivery: hook,
      );
      addTearDown(() async {
        await facade.dispose();
        await registry.dispose();
      });

      final outcome =
          await facade.publishStatusUpdate(safetyState: SafetyState.injured);
      expect(outcome.queued, isTrue);
      expect(hook.calls, 1);
    });

    test('SAFE with zero ready peers calls the hook even at STATUS priority',
        () async {
      final registry =
          PeerCapabilityRegistry(helloTimeout: const Duration(seconds: 5));
      final bridge = await _makeRecordingBridge(registry);
      final hook = _CountingEmergencyDelivery();
      final facade = EventPublisherV2Facade(
        registry: registry,
        bridge: bridge,
        emergencyDelivery: hook,
      );
      addTearDown(() async {
        await facade.dispose();
        await registry.dispose();
      });

      final outcome =
          await facade.publishStatusUpdate(safetyState: SafetyState.safe);
      expect(outcome.queued, isTrue);
      expect(hook.calls, 1,
          reason: 'the SOS resolution must propagate fast too');

      // Prove the fire was NOT priority-driven: SAFE stays at STATUS, yet it
      // still triggered the hook (so the predicate genuinely also keys on
      // safetyState == SAFE, per the task spec).
      _markPeerActive(registry, 'EM:03');
      await _drainMicrotasks();
      expect(bridge.invocations.single.priority, PriorityV2.status);
    });

    test('PRESENCE with zero ready peers enqueues but does NOT call the hook',
        () async {
      final registry =
          PeerCapabilityRegistry(helloTimeout: const Duration(seconds: 5));
      final bridge = await _makeRecordingBridge(registry);
      final hook = _CountingEmergencyDelivery();
      final facade = EventPublisherV2Facade(
        registry: registry,
        bridge: bridge,
        emergencyDelivery: hook,
      );
      addTearDown(() async {
        await facade.dispose();
        await registry.dispose();
      });

      final outcome = await facade.publishPresence(anonUserId: Uint8List(16));
      expect(outcome.queued, isTrue);
      expect(facade.pendingQueueDepth, 1);
      expect(hook.calls, 0,
          reason: 'PRESENCE keeps its normal cadence; never emergency');
    });

    test(
        'CHECKPOINT (also STATUS priority) with zero peers does NOT call the '
        'hook — proves the predicate is not priority==STATUS', () async {
      final registry =
          PeerCapabilityRegistry(helloTimeout: const Duration(seconds: 5));
      final bridge = await _makeRecordingBridge(registry);
      final hook = _CountingEmergencyDelivery();
      final facade = EventPublisherV2Facade(
        registry: registry,
        bridge: bridge,
        emergencyDelivery: hook,
      );
      addTearDown(() async {
        await facade.dispose();
        await registry.dispose();
      });

      final outcome = await facade.publishCheckpoint(
        anonUserId: Uint8List(16),
        checkpointId: 'gate-1',
      );
      expect(outcome.queued, isTrue);
      expect(hook.calls, 0);
    });

    test('a throwing emergency hook never fails the publish (stays queued)',
        () async {
      final registry =
          PeerCapabilityRegistry(helloTimeout: const Duration(seconds: 5));
      final bridge = await _makeRecordingBridge(registry);
      final hook = _CountingEmergencyDelivery(throwOnCall: true);
      final facade = EventPublisherV2Facade(
        registry: registry,
        bridge: bridge,
        emergencyDelivery: hook,
      );
      addTearDown(() async {
        await facade.dispose();
        await registry.dispose();
      });

      final outcome =
          await facade.publishStatusUpdate(safetyState: SafetyState.trapped);
      expect(hook.calls, 1, reason: 'hook was invoked');
      expect(outcome.queued, isTrue,
          reason: 'a throwing hook must not abort the publish');
      expect(facade.pendingQueueDepth, 1,
          reason: 'the envelope is still safely queued');
    });
  });
}

class _SendInvocation {
  final String peerId;
  final Uint8List? envelopeId;
  final int eventType;
  final int priority;
  final Uint8List payload;
  final HlcTimestampV2 createdAtHlc;
  final HlcTimestampV2 expiresAtHlc;
  final int maxHops;
  final Uint8List? fieldId;
  final Uint8List? fieldMacKey;

  _SendInvocation({
    required this.peerId,
    required this.envelopeId,
    required this.eventType,
    required this.priority,
    required this.payload,
    required this.createdAtHlc,
    required this.expiresAtHlc,
    required this.maxHops,
    required this.fieldId,
    required this.fieldMacKey,
  });
}

class _RecordingBleV2Bridge extends BleV2Bridge {
  final List<_SendInvocation> invocations = <_SendInvocation>[];
  final ListQueue<TxOutcome> scriptedOutcomes = ListQueue<TxOutcome>();
  int _nextId = 1;

  _RecordingBleV2Bridge({
    required super.store,
    required super.dispatcher,
    required super.publisher,
    required super.registry,
    required super.selfHelloFactory,
    required super.nativeEventStream,
    required super.writeEventToPeer,
    required super.notifyEventToPeer,
  });

  @override
  Future<TxOutcome> sendEnvelope({
    required String peerId,
    required int eventType,
    required int priority,
    required Uint8List payload,
    required HlcTimestampV2 createdAtHlc,
    required HlcTimestampV2 expiresAtHlc,
    required int maxHops,
    Uint8List? envelopeId,
    Uint8List? fieldId,
    Uint8List? fieldMacKey,
    bool isExperimental = false,
  }) async {
    invocations.add(_SendInvocation(
      peerId: peerId,
      envelopeId:
          envelopeId == null ? null : Uint8List.fromList(envelopeId),
      eventType: eventType,
      priority: priority,
      payload: Uint8List.fromList(payload),
      createdAtHlc: createdAtHlc,
      expiresAtHlc: expiresAtHlc,
      maxHops: maxHops,
      fieldId: fieldId == null ? null : Uint8List.fromList(fieldId),
      fieldMacKey:
          fieldMacKey == null ? null : Uint8List.fromList(fieldMacKey),
    ));
    if (scriptedOutcomes.isNotEmpty) {
      return scriptedOutcomes.removeFirst();
    }
    final id = (_nextId++ % 255) + 1;
    final envelope = EventEnvelopeV2(
      envelopeId: Uint8List.fromList(List<int>.filled(16, id)),
      eventType: eventType,
      priority: priority,
      createdAtHlc: createdAtHlc,
      expiresAtHlc: expiresAtHlc,
      maxHops: maxHops,
      authorKey: Uint8List(32),
      sigAlgo: SigAlgo.ed25519,
      signature: Uint8List(64),
      payload: Uint8List.fromList(payload),
      isExperimental: isExperimental,
    );
    final wire = envelope.encode();
    return TxOutcome.sent(PublishedEnvelope(
      envelope: envelope,
      wireBytes: wire,
      chunks: const <Uint8List>[],
      negotiatedMtu: 247,
      effectivePriority: priority,
    ));
  }
}

Future<_RecordingBleV2Bridge> _makeRecordingBridge(
  PeerCapabilityRegistry registry,
) async {
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
  final authorPublicKey =
      Uint8List.fromList((await keyPair.extractPublicKey()).bytes);
  final publisher = MessagePublisherV2(
    keyPair: keyPair,
    authorPublicKey: authorPublicKey,
    trace: trace,
  );

  return _RecordingBleV2Bridge(
    store: store,
    dispatcher: dispatcher,
    publisher: publisher,
    registry: registry,
    selfHelloFactory: () => const ProtocolHelloData(
      peerKind: PeerKind.phoneV1,
      maxRxEnvelopeBytes: 2048,
      supportsChunking: true,
      supportsIblt: true,
      supportsBloomV2: true,
      minNegotiatedMtu: 247,
      bgState: BgState.foreground,
    ),
    nativeEventStream: const Stream<dynamic>.empty(),
    writeEventToPeer: (_, __) async => true,
    notifyEventToPeer: (_, __) async => true,
  );
}

Uint8List _filledEnvelopeId(int byte) =>
    Uint8List.fromList(List<int>.filled(16, byte));

/// Build an [ActiveFieldController] backed by an in-memory secure store + the
/// shared in-memory DB. When [secret] is given, joins it as the active field.
Future<ActiveFieldController> _makeFieldController({List<int>? secret}) async {
  final controller = ActiveFieldController(
    store: FieldSessionStore(
      db: DatabaseHelper(),
      secureStore: _InMemorySecureKv(),
    ),
  );
  if (secret != null) {
    await controller.joinBySecret(secret, displayName: 'test-field');
  }
  return controller;
}

class _InMemorySecureKv implements SecureKvStore {
  final Map<String, String> _m = <String, String>{};
  @override
  Future<String?> read(String key) async => _m[key];
  @override
  Future<void> write(String key, String value) async => _m[key] = value;
  @override
  Future<void> delete(String key) async => _m.remove(key);
}

/// A11-latency-fix — test double for the emergency-delivery hook. Counts calls
/// and can throw to prove a misbehaving hook never aborts the publish.
class _CountingEmergencyDelivery implements EmergencyMeshDelivery {
  _CountingEmergencyDelivery({this.throwOnCall = false});
  final bool throwOnCall;
  int calls = 0;
  @override
  void requestEmergencyConnect() {
    calls++;
    if (throwOnCall) throw StateError('emergency hook boom');
  }
}

Future<List<Map<String, Object?>>> _queryOutboxRows(DatabaseHelper db) async {
  final database = await db.database;
  return database.query('Outbox_V2', orderBy: 'id ASC');
}

Future<List<Map<String, Object?>>> _waitForOutboxRowCount(
  DatabaseHelper db,
  int expectedCount,
) async {
  for (var i = 0; i < 20; i++) {
    final rows = await _queryOutboxRows(db);
    if (rows.length == expectedCount) {
      return rows;
    }
    await _drainMicrotasks();
  }
  final rows = await _queryOutboxRows(db);
  expect(rows, hasLength(expectedCount));
  return rows;
}

Future<void> _insertOutboxRow({
  required DatabaseHelper db,
  required Uint8List envelopeId,
  required int eventType,
  required int priority,
  required Uint8List payload,
  required int createdAtHlcMs,
  required int expiresAtHlcMs,
  required int enqueuedAtMs,
  required int maxHops,
}) async {
  final database = await db.database;
  await database.insert('Outbox_V2', {
    'envelope_id': envelopeId,
    'event_type': eventType,
    'priority': priority,
    'payload': payload,
    'created_at_hlc_ms': createdAtHlcMs,
    'created_at_hlc_ctr': 0,
    'expires_at_hlc_ms': expiresAtHlcMs,
    'expires_at_hlc_ctr': 0,
    'max_hops': maxHops,
    'enqueued_at_ms': enqueuedAtMs,
  });
}

void _markPeerActive(PeerCapabilityRegistry registry, String peerId) {
  registry.onPeerReadyForHello(peerId);
  registry.onHelloAccepted(
    peerId,
    const ProtocolHelloData(
      peerKind: PeerKind.phoneV1,
      maxRxEnvelopeBytes: 2048,
      supportsChunking: true,
      supportsIblt: true,
      supportsBloomV2: true,
      minNegotiatedMtu: 247,
      bgState: BgState.foreground,
    ).encode(),
  );
}

Future<void> _drainMicrotasks() async {
  for (var i = 0; i < 8; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}
