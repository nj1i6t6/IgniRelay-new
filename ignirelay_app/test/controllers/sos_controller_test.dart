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
import 'package:latlong2/latlong.dart';
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
    Future<LatLng?> Function()? ensureFreshLocation,
    Future<LatLng?> Function()? lastKnownLocation,
    LatLng? Function()? currentLocation,
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
      locationBuilder: currentLocation == null
          ? noGps()
          : LocationEvidenceBuilder(currentLocation: currentLocation),
      countdownDuration: countdown,
      ensureFreshLocation: ensureFreshLocation,
      lastKnownLocation: lastKnownLocation,
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

  // ── UI-F5b — bounded fresh-GPS hook (§4.2 manual event) ─────────────────────

  test('SOS send awaits ensureFreshLocation BEFORE reading the location',
      () async {
    final order = <String>[];
    final h = await makeSos(
      ensureFreshLocation: () async {
        order.add('refresh');
        return null;
      },
      currentLocation: () {
        order.add('build');
        return null;
      },
    );
    h.sos.arm(SosSeverity.trapped);
    await Future<void>.delayed(const Duration(milliseconds: 220));
    expect(h.sos.phase, SosPhase.sent);
    expect(order, containsAllInOrder(<String>['refresh', 'build']),
        reason: 'one fresh fix requested before building the SOS location');
  });

  test('a throwing/failed ensureFreshLocation NEVER aborts the SOS send',
      () async {
    // Owner boundaries 1 & 3 / SOS zero-delay: GPS failure → still sent.
    final h = await makeSos(
      ensureFreshLocation: () async => throw Exception('gps boom'),
    );
    h.sos.arm(SosSeverity.trapped);
    await Future<void>.delayed(const Duration(milliseconds: 220));
    expect(h.sos.phase, SosPhase.sent, reason: 'GPS failure must not abort SOS');
    final rows = await outbox();
    expect(rows.length, 1, reason: 'SOS queued despite refresh failure');
    final data = StatusUpdateData.decode(rows.single['payload'] as Uint8List);
    expect(data.safetyState, SafetyState.trapped);
  });

  test('markSafe also requests one bounded fresh fix before SAFE', () async {
    var refreshCalls = 0;
    final h = await makeSos(ensureFreshLocation: () async {
      refreshCalls++;
      return null;
    });
    h.sos.arm(SosSeverity.trapped);
    await Future<void>.delayed(const Duration(milliseconds: 220));
    final afterSend = refreshCalls; // _send called the hook once
    await h.sos.markSafe();
    expect(refreshCalls, afterSend + 1, reason: 'markSafe refreshes too');
  });

  // ── A11-debug-1-fix — SOS / SAFE attach a REAL coordinate when one exists ──
  // The 無座標-on-receiver bug: the refresh hook's resolved fix was discarded
  // and the bounded refresh never consulted the OS last-known. These lock in
  // the "use whatever real fix exists; never fabricate" contract.

  test('SOS attaches the fresh fix the refresh resolved (lat/lng correct)',
      () async {
    final h = await makeSos(
      // The bounded refresh resolves a real fix; the SOS must build evidence
      // from THAT fix (was discarded → location read from an empty source).
      ensureFreshLocation: () async => const LatLng(22.64131, 120.30958),
    );
    h.sos.arm(SosSeverity.trapped);
    await Future<void>.delayed(const Duration(milliseconds: 220));
    expect(h.sos.phase, SosPhase.sent);
    final loc =
        StatusUpdateData.decode((await outbox()).single['payload'] as Uint8List)
            .location;
    expect(loc, isNotNull, reason: 'a resolved fix must ride the SOS');
    expect(loc!.latDegrees, closeTo(22.64131, 1e-5));
    expect(loc.lngDegrees, closeTo(120.30958, 1e-5));
  });

  test('SOS with no fix anywhere still publishes, location == null (no fake)',
      () async {
    // noGps builder + no refresh hook + no OS last-known → honest null.
    final h = await makeSos();
    h.sos.arm(SosSeverity.trapped);
    await Future<void>.delayed(const Duration(milliseconds: 220));
    expect(h.sos.phase, SosPhase.sent);
    expect(
      StatusUpdateData.decode((await outbox()).single['payload'] as Uint8List)
          .location,
      isNull,
    );
  });

  test('markSafe attaches a real fix when one exists', () async {
    final h = await makeSos(
      ensureFreshLocation: () async => const LatLng(22.0, 120.0),
    );
    h.sos.arm(SosSeverity.trapped);
    await Future<void>.delayed(const Duration(milliseconds: 220));
    await h.sos.markSafe();
    final safe =
        StatusUpdateData.decode((await outbox()).last['payload'] as Uint8List);
    expect(safe.safetyState, SafetyState.safe);
    expect(safe.location, isNotNull);
    expect(safe.location!.latDegrees, closeTo(22.0, 1e-5));
  });

  test('refresh fails but builder last-known exists → uses last-known',
      () async {
    // The bounded refresh throws; the builder still has a (last-known) fix.
    final h = await makeSos(
      ensureFreshLocation: () async => throw Exception('refresh boom'),
      currentLocation: () => const LatLng(25.03, 121.56),
    );
    h.sos.arm(SosSeverity.injured);
    await Future<void>.delayed(const Duration(milliseconds: 220));
    expect(h.sos.phase, SosPhase.sent);
    final loc =
        StatusUpdateData.decode((await outbox()).single['payload'] as Uint8List)
            .location;
    expect(loc, isNotNull, reason: 'last-known used when refresh fails');
    expect(loc!.latDegrees, closeTo(25.03, 1e-5));
  });

  test('refresh + builder empty but OS last-known exists → uses OS last-known',
      () async {
    // Device case: bounded refresh yields nothing, in-app source empty, but the
    // OS still holds an older fix. The SOS must attach THAT real coordinate.
    final h = await makeSos(
      ensureFreshLocation: () async => null,
      lastKnownLocation: () async => const LatLng(24.5, 118.2),
    );
    h.sos.arm(SosSeverity.trapped);
    await Future<void>.delayed(const Duration(milliseconds: 220));
    final loc =
        StatusUpdateData.decode((await outbox()).single['payload'] as Uint8List)
            .location;
    expect(loc, isNotNull, reason: 'OS last-known used as last resort');
    expect(loc!.latDegrees, closeTo(24.5, 1e-5));
    expect(loc.lngDegrees, closeTo(118.2, 1e-5));
  });

  test('refresh + builder + OS last-known all empty → null, never throws',
      () async {
    final h = await makeSos(
      ensureFreshLocation: () async => null,
      lastKnownLocation: () async => null,
    );
    h.sos.arm(SosSeverity.trapped);
    await Future<void>.delayed(const Duration(milliseconds: 220));
    expect(h.sos.phase, SosPhase.sent, reason: 'no fix must not abort the SOS');
    expect(
      StatusUpdateData.decode((await outbox()).single['payload'] as Uint8List)
          .location,
      isNull,
    );
  });

  test('a throwing OS last-known seam is treated as null, never aborts the SOS',
      () async {
    // A11-debug-1-fix-polish — zero-delay red line: even the last-resort seam
    // must not abort the send if it throws (the default impl swallows, but an
    // injected / alternate seam might not).
    final h = await makeSos(
      ensureFreshLocation: () async => null,
      lastKnownLocation: () async => throw Exception('last-known boom'),
    );
    h.sos.arm(SosSeverity.trapped);
    await Future<void>.delayed(const Duration(milliseconds: 220));
    expect(h.sos.phase, SosPhase.sent,
        reason: 'a throwing last-known seam must not abort the SOS');
    expect(
      StatusUpdateData.decode((await outbox()).single['payload'] as Uint8List)
          .location,
      isNull,
    );
  });
}
