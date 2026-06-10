import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ignirelay_app/app/crypto/identity_manager.dart';
import 'package:ignirelay_app/app/controllers/event_publisher.dart';
import 'package:ignirelay_app/app/db/database_helper.dart';
import 'package:ignirelay_app/app/mesh/event_manager.dart';
import 'package:ignirelay_app/app/mesh/event_types.dart';
import 'package:ignirelay_app/app/proto/event_envelope_v2.dart';
import 'package:ignirelay_app/app/services/event_publisher_v2_facade.dart';
import 'package:ignirelay_app/app/services/peer_capability_registry.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    DatabaseHelper.testDatabasePathOverride = inMemoryDatabasePath;
    SharedPreferences.setMockInitialValues(<String, Object>{});
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    await IdentityManager().initialize();
  });

  setUp(() async {
    await DatabaseHelper().resetForTest();
    _drainEventManagerQueue(EventManager());
  });

  test('publishEvent keeps legacy write and dual-writes status to v2 facade',
      () async {
    final spy = _SpyEventPublisherV2Facade();
    addTearDown(spy.dispose);
    final publisher = EventPublisher(
      eventManager: EventManager(),
      v2Facade: spy,
    );

    final eventId = await publisher.publishEvent(
      urgency: 2,
      description: 'need water',
    );

    final db = await DatabaseHelper().database;
    final rows = await db.query(
      'Event_Logs',
      where: 'event_id = ?',
      whereArgs: [eventId],
    );
    expect(rows.length, 1);
    expect(rows.first['event_type'], EventType.requestBroadcast);
    expect(rows.first['urgency'], 2);

    expect(spy.statusCalls.length, 1);
    expect(spy.statusCalls.single.safetyState, SafetyState.injured);
  });

  test('publishHazard keeps legacy write and dual-writes hazard payload',
      () async {
    final spy = _SpyEventPublisherV2Facade();
    addTearDown(spy.dispose);
    final publisher = EventPublisher(
      eventManager: EventManager(),
      v2Facade: spy,
    );

    final hazardId = await publisher.publishHazard(
      type: 'FIRE',
      severity: 3,
      lat: 25.03,
      lng: 121.56,
      radiusMeters: 180,
      description: 'smoke seen',
    );

    final db = await DatabaseHelper().database;
    final hazardRows = await db.query(
      'Hazards_State',
      where: 'hazard_id = ?',
      whereArgs: [hazardId],
    );
    expect(hazardRows.length, 1);
    expect(hazardRows.first['type'], 'FIRE');

    expect(spy.hazardPayloads.length, 1);
    final map = jsonDecode(
      utf8.decode(spy.hazardPayloads.single),
    ) as Map<String, dynamic>;
    expect(map['type'], 'FIRE');
    expect(map['severity'], 3);
    expect(map['schema'], 'hazard_marker_v0_3_json_shim');
  });
}

class _StatusCall {
  final int safetyState;
  final List<NeedEntry> needs;
  final int priority;

  _StatusCall({
    required this.safetyState,
    required this.needs,
    required this.priority,
  });
}

class _SpyEventPublisherV2Facade extends EventPublisherV2Facade {
  final List<_StatusCall> statusCalls = <_StatusCall>[];
  final List<Uint8List> hazardPayloads = <Uint8List>[];

  _SpyEventPublisherV2Facade()
      : super(
          registry: PeerCapabilityRegistry(
            helloTimeout: const Duration(seconds: 5),
          ),
        );

  @override
  Future<BroadcastOutcome> publishStatusUpdate({
    required int safetyState,
    List<NeedEntry> needs = const <NeedEntry>[],
    int priority = PriorityV2.status,
  }) {
    statusCalls.add(_StatusCall(
      safetyState: safetyState,
      needs: List<NeedEntry>.from(needs),
      priority: priority,
    ));
    return Future<BroadcastOutcome>.value(BroadcastOutcome.noActivePeers());
  }

  @override
  Future<BroadcastOutcome> publishHazardMarker({
    required Uint8List payload,
    int priority = PriorityV2.alert,
  }) {
    hazardPayloads.add(Uint8List.fromList(payload));
    return Future<BroadcastOutcome>.value(BroadcastOutcome.noActivePeers());
  }
}

void _drainEventManagerQueue(EventManager em) {
  while (em.queue.dequeue() != null) {}
}
