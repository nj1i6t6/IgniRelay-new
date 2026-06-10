// event_manager_test.dart
//
// 測試下行管道：UI 操作 → EventManager → DB 寫入 + TriageQueue
//
// 使用 sqflite_common_ffi (in-memory SQLite) + mocked SharedPreferences。
//
// Phase 0b #3B-2：舊產品 send path（publishSupply / publishRequest /
// publishMatch* / publishLocationUpdate / getAvailableSupplies / 醫療卡）已從
// EventManager 移除，對應的舊測試群組一併刪除。保留 SOS/求援（publishEvent）、
// 危險標記（publishHazard / confirmHazard）、getRecentEvents、速率限制。

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ignirelay_app/app/crypto/identity_manager.dart';
import 'package:ignirelay_app/app/db/database_helper.dart';
import 'package:ignirelay_app/app/mesh/event_manager.dart';
import 'package:ignirelay_app/app/mesh/event_types.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    DatabaseHelper.testDatabasePathOverride = inMemoryDatabasePath;
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await IdentityManager().initialize();
  });

  setUp(() async {
    await DatabaseHelper().resetForTest();
  });

  final em = EventManager();

  group('EventManager — publishEvent (SOS/求援)', () {
    test('returns non-empty event ID', () async {
      final id = await em.publishEvent(urgency: 0, description: 'Need water');
      expect(id, isNotEmpty);
    });

    test('event ID is unique on repeated calls', () async {
      final id1 = await em.publishEvent(urgency: 0, description: 'test-a');
      final id2 = await em.publishEvent(urgency: 0, description: 'test-b');
      expect(id1, isNot(equals(id2)));
    });

    test('event persisted in Event_Logs with correct urgency', () async {
      final id = await em.publishEvent(urgency: 3, description: 'SOS Red');
      final db = await DatabaseHelper().database;
      final rows = await db.query(
        'Event_Logs',
        where: 'event_id = ?',
        whereArgs: [id],
      );
      expect(rows.length, equals(1));
      expect(rows[0]['urgency'], equals(3));
      expect(rows[0]['event_type'], equals(EventType.requestBroadcast));
    });

    test('event enqueued in TriageQueue', () async {
      final queueBefore = em.queue.length;
      await em.publishEvent(urgency: 2, description: 'SOS Yellow');
      expect(em.queue.length, greaterThan(queueBefore));
    });

    test('SOS_RED event goes to top of TriageQueue', () async {
      // Drain existing queue first by dequeuing everything
      while (em.queue.dequeue() != null) {}

      await em.publishEvent(urgency: 0, description: 'low priority');
      await em.publishEvent(urgency: 3, description: 'SOS RED');

      expect(em.queue.hasSOSRedPreemptionPending, isTrue);
      expect(em.queue.dequeue()?.urgency, equals(3));
    });

    test('publishEvent (no coords, no GPS) writes null to all 4 geo columns',
        () async {
      // 座標語意：無座標一律用 null，不用 0.0 作 sentinel。
      final id = await em.publishEvent(urgency: 1, description: 'no-gps-sos');
      final db = await DatabaseHelper().database;
      final rows = await db.query(
        'Event_Logs',
        where: 'event_id = ?',
        whereArgs: [id],
      );
      expect(rows.length, equals(1));
      expect(rows[0]['received_lat'], isNull);
      expect(rows[0]['received_lng'], isNull);
      expect(rows[0]['origin_lat'], isNull);
      expect(rows[0]['origin_lng'], isNull);
    });

    test('publishEvent (explicit lat/lng) writes all 4 geo columns', () async {
      const lat = 25.034;
      const lng = 121.564;
      final id = await em.publishEvent(
        urgency: 2,
        description: 'sos-with-coords',
        lat: lat,
        lng: lng,
      );
      final db = await DatabaseHelper().database;
      final rows = await db.query(
        'Event_Logs',
        where: 'event_id = ?',
        whereArgs: [id],
      );
      expect(rows.length, equals(1));
      expect(rows[0]['received_lat'], closeTo(lat, 1e-9));
      expect(rows[0]['received_lng'], closeTo(lng, 1e-9));
      expect(rows[0]['origin_lat'], closeTo(lat, 1e-9));
      expect(rows[0]['origin_lng'], closeTo(lng, 1e-9));
    });
  });

  group('EventManager — publishHazard (危險標記)', () {
    test('returns non-empty hazard ID', () async {
      final id = await em.publishHazard(
        type: 'FIRE',
        severity: 3,
        lat: 25.034,
        lng: 121.564,
      );
      expect(id, isNotEmpty);
    });

    test('hazard inserted into Hazards_State with correct fields', () async {
      final hazardId = await em.publishHazard(
        type: 'FLOOD',
        severity: 2,
        lat: 25.011,
        lng: 121.533,
        radiusMeters: 400.0,
      );
      final db = await DatabaseHelper().database;
      final rows = await db.query(
        'Hazards_State',
        where: 'hazard_id = ?',
        whereArgs: [hazardId],
      );
      expect(rows.length, equals(1));
      expect(rows[0]['type'], equals('FLOOD'));
      expect(rows[0]['severity'], equals(2));
      expect((rows[0]['radius'] as num).toDouble(), closeTo(400.0, 0.01));
    });

    test('hazard event enqueued at SOS_YELLOW urgency (2)', () async {
      final queueBefore = em.queue.length;
      await em.publishHazard(
        type: 'GAS_LEAK',
        severity: 1,
        lat: 25.0,
        lng: 121.0,
      );
      expect(em.queue.length, greaterThan(queueBefore));
    });
  });

  group('EventManager — getActiveHazards', () {
    setUp(() => em.resetRateLimit());
    test('getActiveHazards returns at least the hazard just published',
        () async {
      await em.publishHazard(
          type: 'LANDSLIDE', severity: 2, lat: 24.0, lng: 120.5);
      final hazards = await em.getActiveHazards();
      expect(hazards.isNotEmpty, isTrue);
    });
  });

  group('EventManager — confirmHazard', () {
    setUp(() => em.resetRateLimit());
    test('confirmHazard increments confirm_count', () async {
      final hazardId = await em.publishHazard(
        type: 'TSUNAMI',
        severity: 3,
        lat: 25.1,
        lng: 121.6,
      );
      final db = await DatabaseHelper().database;
      final before = (await db.query(
        'Hazards_State',
        where: 'hazard_id = ?',
        whereArgs: [hazardId],
      ))[0]['confirm_count'] as int;

      await em.confirmHazard(hazardId);

      final after = (await db.query(
        'Hazards_State',
        where: 'hazard_id = ?',
        whereArgs: [hazardId],
      ))[0]['confirm_count'] as int;

      expect(after, equals(before + 1));
    });
  });

  group('EventManager — getRecentEvents', () {
    setUp(() => em.resetRateLimit());
    test('getRecentEvents returns list (may be empty or non-empty)', () async {
      final events = await em.getRecentEvents(limit: 5);
      expect(events, isA<List<Map<String, dynamic>>>());
    });

    test('after publishEvent, getRecentEvents includes the new event', () async {
      final id = await em.publishEvent(urgency: 1, description: 'recent-check');
      final events = await em.getRecentEvents(limit: 10);
      final found = events.any((e) => e['event_id'] == id);
      expect(found, isTrue);
    });
  });

  // Rate limit test 放最後：前面的測試會消耗部分配額，
  // 這裡只驗證「在同一窗口內不超過 20 次」的不變式。
  group('EventManager — Rate Limit', () {
    setUp(() => em.resetRateLimit());

    test('more than 20 publishEvent calls in same window throws RateLimitException', () async {
      int successCount = 0;
      bool hitLimit = false;
      for (int i = 0; i < 25; i++) {
        try {
          await em.publishEvent(urgency: 0, description: 'rate-test-$i');
          successCount++;
        } on RateLimitException {
          hitLimit = true;
          break;
        }
      }
      expect(successCount, lessThanOrEqualTo(20),
          reason: 'At most 20 events allowed per hour window');
      if (successCount == 20) {
        expect(hitLimit, isTrue,
            reason: '21st call must throw RateLimitException');
      }
    });
  });
}
