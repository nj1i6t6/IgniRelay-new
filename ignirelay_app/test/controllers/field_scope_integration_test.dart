// A5 (4-7) DoD D3 — cross-field isolation integration test.
//
// Publisher signs a v3 envelope under field A; the production-config dispatcher
// (field-scope check ON + real FieldKeyStore) is exercised for the four §21.6
// outcomes, each asserting the spec drop_reason:
//   • member of field A          → DispatchAccepted (field_mac verifies)
//   • member of a DIFFERENT field → field-scope-mismatch
//   • forged field_mac (valid A field_id, wrong key) → field-mac-invalid
//   • tampered field_id on wire   → signature-invalid (field_id is signed)
//
// Reuses the publisher→dispatcher harness pattern from envelope_pipeline_v2.

import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ignirelay_app/app/controllers/envelope_dispatcher_v2.dart';
import 'package:ignirelay_app/app/controllers/message_publisher_v2.dart';
import 'package:ignirelay_app/app/crypto/field_auth_v2.dart';
import 'package:ignirelay_app/app/db/database_helper.dart';
import 'package:ignirelay_app/app/proto/event_envelope_v2.dart';
import 'package:ignirelay_app/app/services/author_rate_limiter.dart';
import 'package:ignirelay_app/app/services/envelope_store_v2.dart';
import 'package:ignirelay_app/app/services/field_key_store.dart';
import 'package:ignirelay_app/app/services/mesh_trace_writer.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final Uint8List _secretA = Uint8List.fromList(List<int>.filled(32, 0xA1));
final Uint8List _secretB = Uint8List.fromList(List<int>.filled(32, 0xB2));

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
    final trace = MeshTraceWriter(db);
    final keyPair = await Ed25519().newKeyPair();
    final pub = Uint8List.fromList((await keyPair.extractPublicKey()).bytes);
    final publisher =
        MessagePublisherV2(keyPair: keyPair, authorPublicKey: pub, trace: trace);
    return _Harness(db, trace, publisher);
  }

  EnvelopeDispatcherV2 dispatcherWith(FieldKeyStore store, _Harness h) {
    final d = EnvelopeDispatcherV2(
      store: EnvelopeStoreV2(h.db),
      trace: h.trace,
      rateLimiter: AuthorRateLimiter(capacity: 100, perSecond: 1000),
      fieldKeys: store,
      enableFieldScopeCheck: true,
    );
    addTearDown(d.dispose);
    return d;
  }

  Future<PublishedEnvelope> signUnderFieldA(
    _Harness h, {
    Uint8List? fieldMacKeyOverride,
  }) async {
    final fieldId = await FieldAuthV2.deriveFieldId(_secretA);
    final macKey =
        fieldMacKeyOverride ?? await FieldAuthV2.deriveFieldMacKey(_secretA);
    return h.publisher.send(
      eventType: EventTypeV2.statusUpdate,
      priority: PriorityV2.sosRed,
      payload: const StatusUpdateData(safetyState: SafetyState.trapped).encode(),
      createdAtHlc: const HlcTimestampV2(msSinceEpoch: 1000, counter: 0),
      expiresAtHlc: const HlcTimestampV2(msSinceEpoch: 9000, counter: 0),
      maxHops: 6,
      negotiatedMtu: 247,
      fieldId: fieldId,
      fieldMacKey: macKey,
    );
  }

  test('member of the same field ACCEPTS (field_mac verifies)', () async {
    final h = await makeHarness();
    final published = await signUnderFieldA(h);
    final storeA = await FieldKeyStore.fromSecrets([_secretA]);
    final outcome = await dispatcherWith(storeA, h)
        .onReceiveEnvelopeBytes(published.wireBytes, peerId: 'AA');
    expect(outcome, isA<DispatchAccepted>());
  });

  test('member of a DIFFERENT field → field-scope-mismatch', () async {
    final h = await makeHarness();
    final published = await signUnderFieldA(h);
    final storeB = await FieldKeyStore.fromSecrets([_secretB]);
    final outcome = await dispatcherWith(storeB, h)
        .onReceiveEnvelopeBytes(published.wireBytes, peerId: 'BB');
    expect(outcome, isA<DispatchDropped>());
    expect((outcome as DispatchDropped).dropReason, 'field-scope-mismatch');
  });

  test('forged field_mac (valid field_id, wrong key) → field-mac-invalid',
      () async {
    final h = await makeHarness();
    // Sign with field A's field_id but a NON-member mac key (field B's).
    final wrongKey = await FieldAuthV2.deriveFieldMacKey(_secretB);
    final published = await signUnderFieldA(h, fieldMacKeyOverride: wrongKey);
    final storeA = await FieldKeyStore.fromSecrets([_secretA]);
    final outcome = await dispatcherWith(storeA, h)
        .onReceiveEnvelopeBytes(published.wireBytes, peerId: 'CC');
    expect(outcome, isA<DispatchDropped>());
    expect((outcome as DispatchDropped).dropReason, 'field-mac-invalid');
  });

  test('tampered field_id on the wire → signature-invalid', () async {
    final h = await makeHarness();
    final published = await signUnderFieldA(h);
    final env = published.envelope;
    // Flip a byte of the field_id but keep the original signature. The dispatcher
    // recomputes the sig input over the tampered field_id (it is signed, §21.4),
    // so the signature no longer verifies — caught BEFORE the field-scope check.
    final tamperedFieldId = Uint8List.fromList(env.fieldId);
    tamperedFieldId[0] ^= 0xFF;
    final tampered = EventEnvelopeV2(
      protocolVersion: env.protocolVersion,
      envelopeId: env.envelopeId,
      eventType: env.eventType,
      priority: env.priority,
      createdAtHlc: env.createdAtHlc,
      expiresAtHlc: env.expiresAtHlc,
      maxHops: env.maxHops,
      authorKey: env.authorKey,
      sigAlgo: env.sigAlgo,
      signature: env.signature,
      payload: env.payload,
      lastRelayId: env.lastRelayId,
      isExperimental: env.isExperimental,
      fieldId: tamperedFieldId,
      fieldMac: env.fieldMac,
    );
    final storeA = await FieldKeyStore.fromSecrets([_secretA]);
    final outcome = await dispatcherWith(storeA, h)
        .onReceiveEnvelopeBytes(tampered.encode(), peerId: 'DD');
    expect(outcome, isA<DispatchDropped>());
    expect((outcome as DispatchDropped).dropReason, 'signature-invalid');
  });
}

class _Harness {
  final DatabaseHelper db;
  final MeshTraceWriter trace;
  final MessagePublisherV2 publisher;
  _Harness(this.db, this.trace, this.publisher);
}
