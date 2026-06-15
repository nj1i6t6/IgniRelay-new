// A8 — SosController state machine (DoD D1: 觸發 / 倒數 / 取消 / 送出 four states)
// + the §5.3 priority-floor integration assertion (TRAPPED→SOS_RED,
// INJURED→SOS_YELLOW) and the "我安全了" SAFE resolution (D2 sender side).
//
// Harness: the REAL EventPublisherV2Facade with a joined field but no active
// peer, so each publish QUEUES to Outbox_V2 — we then read that row's stored
// `priority` + `payload` to assert the floored wire priority and safetyState
// without standing up a recording BLE bridge.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:ignirelay_app/app/controllers/active_field_controller.dart';
import 'package:ignirelay_app/app/controllers/sos_controller.dart';
import 'package:ignirelay_app/app/db/database_helper.dart';
import 'package:ignirelay_app/app/proto/event_envelope_v2.dart';
import 'package:ignirelay_app/app/services/anon_identity.dart';
import 'package:ignirelay_app/app/services/event_publisher_v2_facade.dart';
import 'package:ignirelay_app/app/services/field_session_store.dart';
import 'package:ignirelay_app/app/services/location_evidence_builder.dart';
import 'package:ignirelay_app/app/services/peer_capability_registry.dart';

class _Kv implements SecureKvStore {
  final Map<String, String> _m = {};
  @override
  Future<String?> read(String k) async => _m[k];
  @override
  Future<void> write(String k, String v) async => _m[k] = v;
  @override
  Future<void> delete(String k) async => _m.remove(k);
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

  Future<ActiveFieldController> joinedField() async {
    final c = ActiveFieldController(
      store: FieldSessionStore(db: DatabaseHelper(), secureStore: _Kv()),
    );
    await c.joinBySecret(
      Uint8List.fromList(List<int>.filled(32, 0x3C)),
      displayName: 'f',
    );
    return c;
  }

  // No-GPS location builder (PRESENCE/SOS still send with null evidence).
  LocationEvidenceBuilder noGps() =>
      LocationEvidenceBuilder(currentLocation: () => null);

  Future<List<Map<String, Object?>>> outbox() async {
    final db = await DatabaseHelper().database;
    return db.query('Outbox_V2', orderBy: 'id ASC');
  }

  Future<({SosController sos, EventPublisherV2Facade facade})> makeSos({
    Duration countdown = const Duration(milliseconds: 40),
  }) async {
    final registry = PeerCapabilityRegistry(
      helloTimeout: const Duration(seconds: 5),
    );
    final facade =
        EventPublisherV2Facade(registry: registry, db: DatabaseHelper());
    final field = await joinedField();
    facade.attachActiveField(field);
    final sos = SosController(
      facade: facade,
      locationBuilder: noGps(),
      countdownDuration: countdown,
    );
    addTearDown(() async {
      sos.dispose();
      await facade.dispose();
      await registry.dispose();
      field.dispose();
    });
    return (sos: sos, facade: facade);
  }

  test('arm starts the cancelable countdown (no publish yet)', () async {
    final h = await makeSos(countdown: const Duration(seconds: 5));
    h.sos.arm(SosSeverity.injured);
    expect(h.sos.phase, SosPhase.countdown);
    expect(h.sos.isCountingDown, isTrue);
    expect(h.sos.armedSeverity, SosSeverity.injured);
    expect(h.sos.secondsRemaining, 5);
    // Nothing published during the countdown window.
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(await outbox(), isEmpty);
  });

  test('cancelCountdown aborts before any publish (misfire guard)', () async {
    final h = await makeSos(countdown: const Duration(seconds: 5));
    h.sos.arm(SosSeverity.trapped);
    h.sos.cancelCountdown();
    expect(h.sos.phase, SosPhase.idle);
    expect(h.sos.armedSeverity, isNull);
    expect(h.sos.hasActiveSos, isFalse);
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(await outbox(), isEmpty);
  });

  test('countdown elapses → sends; TRAPPED floors at SOS_RED (§5.3)', () async {
    final h = await makeSos();
    h.sos.arm(SosSeverity.trapped);
    await Future<void>.delayed(const Duration(milliseconds: 220));
    expect(h.sos.phase, SosPhase.sent);
    expect(h.sos.hasActiveSos, isTrue);
    expect(h.sos.activeSeverity, SosSeverity.trapped);

    final rows = await outbox();
    expect(rows.length, 1, reason: 'queued (no active peer)');
    expect(rows.single['priority'], PriorityV2.sosRed);
    final data = StatusUpdateData.decode(rows.single['payload'] as Uint8List);
    expect(data.safetyState, SafetyState.trapped);
  });

  test('INJURED floors at SOS_YELLOW (§5.3)', () async {
    final h = await makeSos();
    h.sos.arm(SosSeverity.injured);
    await Future<void>.delayed(const Duration(milliseconds: 220));
    expect(h.sos.phase, SosPhase.sent);
    final rows = await outbox();
    expect(rows.single['priority'], PriorityV2.sosYellow);
    expect(
      StatusUpdateData.decode(rows.single['payload'] as Uint8List).safetyState,
      SafetyState.injured,
    );
  });

  test('markSafe publishes a SAFE STATUS_UPDATE and clears active SOS (OD-8)',
      () async {
    final h = await makeSos();
    h.sos.arm(SosSeverity.trapped);
    await Future<void>.delayed(const Duration(milliseconds: 220));
    expect(h.sos.hasActiveSos, isTrue);

    await h.sos.markSafe();
    expect(h.sos.hasActiveSos, isFalse);
    expect(h.sos.activeSeverity, isNull);
    expect(h.sos.phase, SosPhase.idle);

    final rows = await outbox();
    expect(rows.length, 2, reason: 'original SOS + SAFE resolution');
    final safe = StatusUpdateData.decode(rows.last['payload'] as Uint8List);
    expect(safe.safetyState, SafetyState.safe);
    // SAFE has no SOS floor → STATUS priority (no SOS_CANCELLED wire type).
    expect(rows.last['priority'], PriorityV2.status);
  });
}
