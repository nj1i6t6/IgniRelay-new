// debug_shell_smoke_test.dart
//
// Phase 0b #2 / #4-4 (A2): smoke test for the mapless DebugShell. Verifies the
// shell renders, the core sections exist, AND that the PRESENCE button is a
// REAL publish action (not the `_todoWire` placeholder) — it routes through
// PresenceController → EventPublisherV2Facade and surfaces a BroadcastOutcome
// (queued, since the smoke harness has no BLE bridge / peer).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'dart:typed_data';

import 'package:ignirelay_app/app/controllers/active_field_controller.dart';
import 'package:ignirelay_app/app/controllers/event_stream.dart';
import 'package:ignirelay_app/app/controllers/checkpoint_controller.dart';
import 'package:ignirelay_app/app/controllers/mesh_runtime_controller.dart';
import 'package:ignirelay_app/app/controllers/presence_beacon_controller.dart';
import 'package:ignirelay_app/app/controllers/presence_controller.dart';
import 'package:ignirelay_app/app/db/database_helper.dart';
import 'package:ignirelay_app/app/mesh/mesh_event_handler.dart';
import 'package:ignirelay_app/app/services/anon_identity.dart';
import 'package:ignirelay_app/app/services/event_decoder.dart';
import 'package:ignirelay_app/app/services/event_publisher_v2_facade.dart';
import 'package:ignirelay_app/app/services/event_store.dart';
import 'package:ignirelay_app/app/services/field_session_store.dart';
import 'package:ignirelay_app/app/services/location_evidence_builder.dart';
import 'package:ignirelay_app/app/services/peer_capability_registry.dart';
import 'package:ignirelay_app/ui/shell/debug_shell.dart';

/// In-memory secure store so AnonIdentityService never touches the platform
/// plugin during a widget test.
class _FakeKvStore implements SecureKvStore {
  final Map<String, String> _m = {};
  @override
  Future<String?> read(String key) async => _m[key];
  @override
  Future<void> write(String key, String value) async => _m[key] = value;
  @override
  Future<void> delete(String key) async => _m.remove(key);
}

Widget _wrap(
  Widget child,
  PresenceController presence,
  ActiveFieldController field,
  PresenceBeaconController beacon,
  CheckpointController checkpoint,
) {
  return MultiProvider(
    providers: [
      Provider<MeshRuntimeController>(
        // 不 attachTransport：DebugShell 對未注入 transport 是 null-safe 的。
        create: (_) => MeshRuntimeController.instance,
      ),
      Provider<EventStore>(
        create: (_) => EventStore(databaseHelper: DatabaseHelper()),
      ),
      Provider<EventStream>(
        create: (ctx) => EventStream(
          handler: MeshEventHandler(),
          decoder: EventDecoder(),
          store: ctx.read<EventStore>(),
        ),
        dispose: (_, s) => s.dispose(),
      ),
      Provider<PresenceController>.value(value: presence),
      Provider<CheckpointController>.value(value: checkpoint),
      ListenableProvider<ActiveFieldController>.value(value: field),
      ChangeNotifierProvider<PresenceBeaconController>.value(value: beacon),
    ],
    child: MaterialApp(home: child),
  );
}

/// A beacon whose loop is disabled (enabled:false) so the widget test carries
/// no pending fake timer; its gates are wired to the harness anyway.
PresenceBeaconController _makeBeacon(
    PresenceController presence, ActiveFieldController field) {
  return PresenceBeaconController(
    publish: ({int? batteryHint}) =>
        presence.publishPresence(batteryHint: batteryHint),
    isMeshRunning: () => false,
    hasJoinedField: () => field.active != null,
    enabled: false,
  );
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    DatabaseHelper.testDatabasePathOverride = inMemoryDatabasePath;
  });

  setUp(() async {
    await DatabaseHelper().resetForTest();
  });

  PresenceController makePresence(PeerCapabilityRegistry registry,
      EventPublisherV2Facade facade) {
    return PresenceController(
      facade: facade,
      anonIdentity: AnonIdentityService(store: _FakeKvStore()),
      // No GPS in the smoke harness → null evidence (PRESENCE still sends).
      locationBuilder: LocationEvidenceBuilder(currentLocation: () => null),
    );
  }

  CheckpointController makeCheckpoint(EventPublisherV2Facade facade) {
    return CheckpointController(
      facade: facade,
      anonIdentity: AnonIdentityService(store: _FakeKvStore()),
      locationBuilder: LocationEvidenceBuilder(currentLocation: () => null),
    );
  }

  Future<ActiveFieldController> makeField({bool joined = false}) async {
    final c = ActiveFieldController(
      store: FieldSessionStore(db: DatabaseHelper(), secureStore: _FakeKvStore()),
    );
    if (joined) {
      await c.joinBySecret(
        Uint8List.fromList(List<int>.filled(32, 0x7A)),
        displayName: '測試場域',
      );
    }
    return c;
  }

  testWidgets('DebugShell renders mesh control, field card, actions, log',
      (tester) async {
    // Tall surface so all the lazily-built ListView cards lay out (incl. the
    // A9 checkpoint card) — otherwise the events-log card stays below the fold.
    tester.view.physicalSize = const Size(1080, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final registry = PeerCapabilityRegistry();
    final facade = EventPublisherV2Facade(registry: registry);
    final field = await makeField(); // no field joined
    final presence = makePresence(registry, facade);
    final beacon = _makeBeacon(presence, field);
    final checkpoint = makeCheckpoint(facade);
    addTearDown(() async {
      beacon.dispose();
      await facade.dispose();
      await registry.dispose();
      field.dispose();
    });

    await tester.pumpWidget(
      _wrap(const DebugShell(), presence, field, beacon, checkpoint),
    );
    await tester.pump();

    // shell renders
    expect(find.byType(DebugShell), findsOneWidget);
    expect(find.text('IgniRelay · Phase 0b'), findsOneWidget);

    // BLE mesh toggle button（未注入 transport → 顯示「啟動」）
    expect(find.widgetWithText(FilledButton, '啟動'), findsOneWidget);
    expect(find.text('啟動'), findsOneWidget);

    // #4-7 field card renders; no field joined → prompt + 場域管理 launcher
    // (A7 moved join/create/QR/scan into FieldScreen).
    expect(find.text('場域（field-scope）'), findsOneWidget);
    expect(find.textContaining('尚未加入場域'), findsWidgets);
    expect(find.text('場域管理'), findsOneWidget);

    // PRESENCE (real) + SOS (still placeholder) buttons
    expect(find.text('發 PRESENCE'), findsOneWidget);
    expect(find.text('發 SOS'), findsOneWidget);

    // A9 (1) — automatic PRESENCE beacon toggle renders.
    expect(find.text('自動 PRESENCE 信標'), findsOneWidget);
    expect(find.byType(SwitchListTile), findsOneWidget);

    // presence section
    expect(find.text('最近 PRESENCE 足跡'), findsOneWidget);

    // event log section
    expect(find.text('事件 log（最新 50）'), findsOneWidget);
  });

  testWidgets('PRESENCE button publishes to the active field (queued, no peer)',
      (tester) async {
    final registry = PeerCapabilityRegistry();
    final facade = EventPublisherV2Facade(registry: registry);
    final field = await makeField(joined: true);
    facade.attachActiveField(field); // production wiring: facade rides active field
    final presence = makePresence(registry, facade);
    final beacon = _makeBeacon(presence, field);
    final checkpoint = makeCheckpoint(facade);
    addTearDown(() async {
      beacon.dispose();
      await facade.dispose();
      await registry.dispose();
      field.dispose();
    });

    await tester.pumpWidget(
      _wrap(const DebugShell(), presence, field, beacon, checkpoint),
    );
    await tester.pump();

    await tester.tap(find.text('發 PRESENCE'));
    await tester.pump(); // run the async publish + setState
    await tester.pump(const Duration(milliseconds: 50));

    // It must NOT be the old placeholder snackbar, nor the no-field prompt.
    expect(find.textContaining('尚未接線'), findsNothing);
    // Active field + no peer → queued; the shell says so.
    expect(find.textContaining('PRESENCE'), findsWidgets);
    expect(find.textContaining('佇列'), findsOneWidget);

    // The publish actually reached the facade (queued in its pending queue).
    expect(facade.pendingQueueDepth, 1);
  });
}
