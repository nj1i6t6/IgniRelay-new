// v0.3 Stage 0c / Phase 0b #4-2 — EnvelopeStoreV2 PRESENCE LWW.
//
// PRESENCE is "last footprint": LWW keyed by anon_user_id (spec §10.2), so the
// newest footprint per person wins and supersedes older ones. This exercises
// the store layer in isolation (tryStore takes signatureStatus directly — no
// dispatcher / signature verification needed).

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ignirelay_app/app/db/database_helper.dart';
import 'package:ignirelay_app/app/proto/event_envelope_v2.dart';
import 'package:ignirelay_app/app/services/envelope_store_v2.dart';
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

  EventEnvelopeV2 presenceEnvelope({
    required int idByte,
    required List<int> anonUserId,
    required int hlcMs,
    int hlcCtr = 0,
  }) {
    return EventEnvelopeV2(
      envelopeId: Uint8List.fromList(List.generate(16, (i) => (idByte + i) & 0xFF)),
      eventType: EventTypeV2.presence,
      priority: PriorityV2.normal,
      createdAtHlc: HlcTimestampV2(msSinceEpoch: hlcMs, counter: hlcCtr),
      expiresAtHlc: HlcTimestampV2(msSinceEpoch: hlcMs + 3600000, counter: 0),
      maxHops: 4,
      authorKey: Uint8List.fromList(List.generate(32, (i) => (idByte * 7 + i) & 0xFF)),
      signature: Uint8List(64),
      payload: PresenceData(
        anonUserId: Uint8List.fromList(anonUserId),
      ).encode(),
    );
  }

  group('EnvelopeStoreV2 PRESENCE LWW (4-2)', () {
    test('newer footprint wins per anon_user_id', () async {
      final store = EnvelopeStoreV2(DatabaseHelper());
      final anon = List.generate(16, (i) => 0xA0 | i);

      final older = presenceEnvelope(idByte: 1, anonUserId: anon, hlcMs: 1000);
      final newer = presenceEnvelope(idByte: 50, anonUserId: anon, hlcMs: 2000);

      final r1 = await store.tryStore(envelope: older, signatureStatus: 0);
      expect(r1.outcome, StoreOutcome.inserted);
      expect(r1.isLwwWinner, true);

      final r2 = await store.tryStore(envelope: newer, signatureStatus: 0);
      expect(r2.isLwwWinner, true, reason: 'newer HLC takes the slot');

      final winner = await store.currentLwwWinner(
        eventType: EventTypeV2.presence,
        lwwKeyComponent: Uint8List.fromList(anon),
      );
      expect(winner, newer.envelopeId);
    });

    test('older footprint arriving after newer does not win', () async {
      final store = EnvelopeStoreV2(DatabaseHelper());
      final anon = List.generate(16, (i) => i + 1);

      final newer = presenceEnvelope(idByte: 50, anonUserId: anon, hlcMs: 2000);
      final older = presenceEnvelope(idByte: 1, anonUserId: anon, hlcMs: 1000);

      await store.tryStore(envelope: newer, signatureStatus: 0);
      final r = await store.tryStore(envelope: older, signatureStatus: 0);
      expect(r.isLwwWinner, false);

      final winner = await store.currentLwwWinner(
        eventType: EventTypeV2.presence,
        lwwKeyComponent: Uint8List.fromList(anon),
      );
      expect(winner, newer.envelopeId);
    });

    test('different anon_user_id keep independent winners', () async {
      final store = EnvelopeStoreV2(DatabaseHelper());
      final anonA = List.generate(16, (i) => 0x10 | i);
      final anonB = List.generate(16, (i) => 0x70 | i);

      final a = presenceEnvelope(idByte: 1, anonUserId: anonA, hlcMs: 1000);
      final b = presenceEnvelope(idByte: 60, anonUserId: anonB, hlcMs: 1000);

      expect((await store.tryStore(envelope: a, signatureStatus: 0)).isLwwWinner, true);
      expect((await store.tryStore(envelope: b, signatureStatus: 0)).isLwwWinner, true);

      expect(
        await store.currentLwwWinner(
            eventType: EventTypeV2.presence,
            lwwKeyComponent: Uint8List.fromList(anonA)),
        a.envelopeId,
      );
      expect(
        await store.currentLwwWinner(
            eventType: EventTypeV2.presence,
            lwwKeyComponent: Uint8List.fromList(anonB)),
        b.envelopeId,
      );
    });
  });
}
// ignore_for_file: prefer_const_constructors, prefer_const_declarations
