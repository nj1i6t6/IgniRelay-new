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

    // #4-5: the v2 dual-write now hands the facade STRUCTURED args (typed
    // HazardMarkerData), not a JSON shim. The legacy 'FIRE' string maps to the
    // wire HazardType enum; lat/lng become a LocationEvidence.
    expect(spy.hazardCalls.length, 1);
    final call = spy.hazardCalls.single;
    expect(call.hazardType, HazardType.fire);
    expect(call.severity, 3);
    expect(call.description, 'smoke seen');
    expect(call.location, isNotNull);
    expect(call.location!.source, LocationSource.gps);
    expect(call.location!.latDegrees, closeTo(25.03, 1e-6));
    expect(call.location!.lngDegrees, closeTo(121.56, 1e-6));
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

class _HazardCall {
  final int hazardType;
  final int severity;
  final LocationEvidence? location;
  final String description;
  final bool isConfirmation;

  _HazardCall({
    required this.hazardType,
    required this.severity,
    required this.location,
    required this.description,
    required this.isConfirmation,
  });
}

class _SpyEventPublisherV2Facade extends EventPublisherV2Facade {
  final List<_StatusCall> statusCalls = <_StatusCall>[];
  final List<_HazardCall> hazardCalls = <_HazardCall>[];

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
    LocationEvidence? location,
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
    required int hazardType,
    int severity = 0,
    LocationEvidence? location,
    String description = '',
    bool isConfirmation = false,
    int priority = PriorityV2.alert,
  }) {
    hazardCalls.add(_HazardCall(
      hazardType: hazardType,
      severity: severity,
      location: location,
      description: description,
      isConfirmation: isConfirmation,
    ));
    return Future<BroadcastOutcome>.value(BroadcastOutcome.noActivePeers());
  }
}

void _drainEventManagerQueue(EventManager em) {
  while (em.queue.dequeue() != null) {}
}
