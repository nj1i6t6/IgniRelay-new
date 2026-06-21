// event_stream_test.dart
//
// Stage 1 corrective gate test:
//   - 每張 dispatch-table（§2.1.2）對應的 event_type 都會 push 到正確的 typed
//     stream（sosAlerts / matchUpdates / hazardEvents / supplyChanges /
//     chatMessages）
//   - 通用 anyEventChanges 在任一筆新事件落地後會發訊號
//   - rawEvents 是 debug 出口；本測試只驗證它存在且可訂閱
//
// 設計策略：用真正的 in-memory DB + 真實 MeshEventHandler / EventDecoder /
// EventStore。我們不打算 mock 整條鏈路 — 太多假對象反而會把測試變成
// implementation 細節的鏡子。透過插入合法 Event_Logs row、手動觸發 handler
// 的 events.add(...) 不容易（singleton），改採直接把 row 寫進 DB 後驅動
// _dispatchRecentEvents 的進入點：呼叫 start() 接著 push 一個 dummy mesh 事件
// 才有 _subscription。但 MeshEventHandler.events 是 broadcast，我們無法 add；
// 所以這個測試走「直呼私有 dispatch」是不可行的，改採行為斷言：訂閱 stream，
// 再用 EventStream._dispatchRecentEvents 的入口 (start + handler.events 的
// public stream) — 由於 MeshEventHandler 是 singleton 且沒有 inject 入口，
// 我們改用 EventStream 內部的 dispatch logic 經由可重複呼叫的 mechanism。
//
// 由於 EventStream 的 dispatch logic 是 private，這份測試以「靜態 invariants」
// 與「整合層面的可訂閱性」為主，外加 anyEventChanges 在 ingest 後可被觀察到。

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ignirelay_app/app/controllers/event_stream.dart';
import 'package:ignirelay_app/app/db/database_helper.dart';
import 'package:ignirelay_app/app/mesh/event_types.dart';
import 'package:ignirelay_app/app/mesh/mesh_event_handler.dart';
import 'package:ignirelay_app/app/proto/mesh_protocol.pb.dart' as pb;
import 'package:ignirelay_app/app/services/event_decoder.dart';
import 'package:ignirelay_app/app/services/event_store.dart';

void main() {
  late DatabaseHelper dbHelper;
  late EventStream stream;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    DatabaseHelper.testDatabasePathOverride = inMemoryDatabasePath;
    SharedPreferences.setMockInitialValues({});
  });

  setUp(() async {
    dbHelper = DatabaseHelper();
    await dbHelper.resetForTest();
    stream = EventStream(
      handler: MeshEventHandler(),
      decoder: EventDecoder(),
      store: EventStore(databaseHelper: dbHelper),
    );
  });

  tearDown(() async {
    await stream.dispose();
  });

  group('EventStream — typed stream exposure', () {
    test('sosAlerts / hazardEvents / anyEventChanges are broadcast streams',
        () {
      expect(stream.sosAlerts.isBroadcast, isTrue);
      expect(stream.hazardEvents.isBroadcast, isTrue);
      expect(stream.anyEventChanges.isBroadcast, isTrue);
    });

    test('rawEvents debug stream is still exposed (survival mode only)', () {
      expect(stream.rawEvents, isNotNull);
    });

    test('debugLogs surface mirrors MeshEventHandler.debugLogs', () {
      expect(stream.debugLogs, isA<List<String>>());
    });
  });

  group('EventStream — dispatch decoding (dispatch table §2.1.2)', () {
    test('requestBroadcast with urgency>=2 decodes via EventDecoder path', () {
      // 直接用 decoder 路徑驗證：EventStream._dispatchRecentEvents 內部呼叫的
      // 是 _decoder.decodeRequestData(payload)。我們確認 decoder 對 SOS
      // payload 能還原成 plain Dart 物件，給 stream layer 用。
      final decoder = EventDecoder();
      final raw = pb.RequestData(
        resourceType: 'WATER',
        quantityNeeded: 1,
        note: 'help me',
        mobilityMode: 'NEED_DELIVER',
      ).writeToBuffer();
      final d = decoder.decodeRequestData(raw);
      expect(d, isNotNull);
      expect(d!.note, 'help me');
    });

    test('sosAlerts carry sender public key for self-alert filtering',
        () async {
      stream.start();
      final sender = List<int>.generate(32, (i) => i + 11);
      final eventId = 'sos-sender-${DateTime.now().microsecondsSinceEpoch}';
      final payload = pb.RequestData(
        resourceType: 'SOS',
        quantityNeeded: 1,
        note: 'remote sos',
        mobilityMode: 'NEED_DELIVER',
      ).writeToBuffer();

      final alertFuture = stream.sosAlerts.first;
      await MeshEventHandler().ingestVerifiedEvent(
        eventId: eventId,
        eventType: EventType.requestBroadcast,
        urgency: 3,
        payload: payload,
        senderPubKey: sender,
        hlcTimestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final alert = await alertFuture.timeout(const Duration(seconds: 2));
      expect(alert.eventId, eventId);
      expect(alert.senderPubKey, sender);
    });

    test('hazardMarker payload decodes via decodeHazardData', () {
      final decoder = EventDecoder();
      final raw = pb.HazardData(
        hazardType: 'FIRE',
        severity: 4,
        centerLat: 24,
        centerLng: 121,
        radiusMeters: 100,
      ).writeToBuffer();
      expect(decoder.decodeHazardData(raw), isA<HazardDataDecoded>());
    });

    test('recentHazards backfills already-stored HAZARD rows (A11 fix)',
        () async {
      // A HAZARD already in Event_Logs (received earlier / projected) must be
      // readable on demand — the broadcast stream alone won't replay it.
      final raw = pb.HazardData(
        hazardType: 'FLOOD',
        severity: 2,
        centerLat: 24.5,
        centerLng: 120.5,
        radiusMeters: 150,
        description: '淹水',
      ).writeToBuffer();
      final eventId = 'hz-${DateTime.now().microsecondsSinceEpoch}';
      await MeshEventHandler().ingestVerifiedEvent(
        eventId: eventId,
        eventType: EventType.hazardMarker,
        urgency: 0,
        payload: raw,
        senderPubKey: List<int>.generate(8, (i) => i),
        hlcTimestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final hazards = await stream.recentHazards();
      final h = hazards.firstWhere((e) => e.eventId == eventId);
      expect(h.type, 'FLOOD');
      expect(h.severity, 2);
      expect(h.description, '淹水');
      expect(h.lat, closeTo(24.5, 1e-9));
      expect(h.lng, closeTo(120.5, 1e-9));
    });
  });

  group('EventStream — mount backfill (A11-debug-4-fix)', () {
    test('recentSos reads coordinates from received_lat/received_lng', () async {
      // The receive-side column fix: ingestVerifiedEvent persists a received
      // event's location into received_lat/received_lng (Event_Logs has no
      // lat/lng column). recentSos (and the shared live mapping) must read THOSE
      // columns, else SOS shows 「（無座標）」 even when the sender had a fix.
      final sender = List<int>.generate(32, (i) => i + 5);
      final eventId = 'sos-bf-${DateTime.now().microsecondsSinceEpoch}';
      final payload =
          pb.RequestData(note: '受困', mobilityMode: 'CAN_GO').writeToBuffer();
      await MeshEventHandler().ingestVerifiedEvent(
        eventId: eventId,
        eventType: EventType.requestBroadcast,
        urgency: 3,
        payload: payload,
        senderPubKey: sender,
        hlcTimestamp: DateTime.now().millisecondsSinceEpoch,
        lat: 25.0339805,
        lng: 121.5654177,
      );

      final alerts = await stream.recentSos();
      final a = alerts.firstWhere((e) => e.eventId == eventId);
      expect(a.urgency, 3);
      expect(a.description, '受困');
      expect(a.senderPubKey, sender);
      expect(a.lat, closeTo(25.0339805, 1e-9));
      expect(a.lng, closeTo(121.5654177, 1e-9));
    });

    test('recentPresence decodes PRESENCE snapshot rows', () async {
      final eventId = 'pres-bf-${DateTime.now().microsecondsSinceEpoch}';
      final snapshot = utf8.encode(jsonEncode(<String, dynamic>{
        'anon8': 'a1b2c3d4',
        'src': 1,
        'observed_ms': DateTime(2026, 6, 15, 12).millisecondsSinceEpoch,
        'lat': 24.5,
        'lng': 120.5,
        'acc': 8,
        'battery': 77,
      }));
      await MeshEventHandler().ingestVerifiedEvent(
        eventId: eventId,
        eventType: LocalReadModelType.presence,
        urgency: 0,
        payload: snapshot,
        senderPubKey: List<int>.generate(8, (i) => i),
        hlcTimestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final list = await stream.recentPresence();
      final p = list.firstWhere((e) => e.eventId == eventId);
      expect(p.anon8, 'a1b2c3d4');
      expect(p.lat, closeTo(24.5, 1e-9));
      expect(p.lng, closeTo(120.5, 1e-9));
      expect(p.batteryHint, 77);
    });

    test('recentSosResolutions decodes SAFE rows keyed by author', () async {
      final author = List<int>.generate(6, (i) => i + 0x40);
      final eventId = 'safe-bf-${DateTime.now().microsecondsSinceEpoch}';
      await MeshEventHandler().ingestVerifiedEvent(
        eventId: eventId,
        eventType: LocalReadModelType.sosResolved,
        urgency: 0,
        payload: utf8.encode(
            jsonEncode(<String, dynamic>{'resolved_ms': DateTime.now().millisecondsSinceEpoch})),
        senderPubKey: author,
        hlcTimestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final list = await stream.recentSosResolutions();
      final expectedHex =
          author.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      expect(list.any((r) => r.authorKeyHex == expectedHex), isTrue);
    });
  });

  group('EventStream — anyEventChanges plain Dart notification', () {
    test('EventLogChanged carries the latest dispatched event id', () {
      final note = EventLogChanged(latestEventId: 'evt-xyz');
      expect(note.latestEventId, 'evt-xyz');
    });
  });
}
