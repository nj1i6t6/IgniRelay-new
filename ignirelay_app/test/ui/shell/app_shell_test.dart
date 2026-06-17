// UI-F1/F2 — AppShell smoke tests.
//
// UI-F1 invariants (still enforced after UI-F2 moved real modules into the tabs):
//   • production home is the AppShell, NOT DebugShell;
//   • the no-field entry shows 加入場域 / 建立場域 / 先看功能;
//   • the five tab labels are exactly 安全 / 位置 / 事件 / 協助 / 我的 (no 地圖);
//   • the global SOS is reachable from every tab.
//
// UI-F2 per-tab coverage:
//   • 安全 shows 近距離通訊 status + 立即更新足跡 + 自動足跡信標;
//   • 位置 embeds the existing LastSeenScreen;
//   • 事件 exposes the FORMAL HAZARD report entry (no kDebugMode gate);
//   • 我的 shows the 場域管理 launcher (+ the debug-only diagnostics entry).
//
// Now that the tabs host real modules, the harness provides the full controller
// graph (mirrors debug_shell_smoke_test.dart). The global SOS is matched by key
// so a tab's own content (e.g. an 'SOS' chip) can never confuse the finder.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:ignirelay_app/app/controllers/active_field_controller.dart';
import 'package:ignirelay_app/app/controllers/checkpoint_controller.dart';
import 'package:ignirelay_app/app/controllers/event_publisher.dart';
import 'package:ignirelay_app/app/controllers/event_stream.dart';
import 'package:ignirelay_app/app/controllers/mesh_runtime_controller.dart';
import 'package:ignirelay_app/app/controllers/presence_beacon_controller.dart';
import 'package:ignirelay_app/app/controllers/presence_controller.dart';
import 'package:ignirelay_app/app/db/database_helper.dart';
import 'package:ignirelay_app/app/mesh/event_manager.dart';
import 'package:ignirelay_app/app/mesh/mesh_event_handler.dart';
import 'package:ignirelay_app/app/services/anon_identity.dart';
import 'package:ignirelay_app/app/services/event_decoder.dart';
import 'package:ignirelay_app/app/services/event_publisher_v2_facade.dart';
import 'package:ignirelay_app/app/services/event_store.dart';
import 'package:ignirelay_app/app/services/field_session_store.dart';
import 'package:ignirelay_app/app/services/local_position_source.dart';
import 'package:ignirelay_app/app/services/location_evidence_builder.dart';
import 'package:ignirelay_app/app/services/peer_capability_registry.dart';
import 'package:ignirelay_app/ui/screens/position/last_seen_screen.dart';
import 'package:ignirelay_app/ui/shell/app_shell.dart';
import 'package:ignirelay_app/ui/shell/debug_shell.dart';
import 'package:ignirelay_app/ui/shell/tabs/events_tab.dart';
import 'package:ignirelay_app/ui/shell/tabs/my_tab.dart';
import 'package:ignirelay_app/ui/shell/tabs/safety_tab.dart';

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
  Widget child, {
  required ActiveFieldController field,
  required PresenceController presence,
  required CheckpointController checkpoint,
  required PresenceBeaconController beacon,
  required EventPublisherV2Facade facade,
}) {
  return MultiProvider(
    providers: [
      Provider<MeshRuntimeController>(
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
      Provider<EventPublisher>(
        create: (_) =>
            EventPublisher(eventManager: EventManager(), v2Facade: facade),
      ),
      Provider<LocalPositionSource>(
        create: (_) => LocalPositionSource(currentLocation: () => null),
      ),
      ListenableProvider<ActiveFieldController>.value(value: field),
      ChangeNotifierProvider<PresenceBeaconController>.value(value: beacon),
    ],
    child: MaterialApp(home: child),
  );
}

PresenceController _makePresence(
    PeerCapabilityRegistry registry, EventPublisherV2Facade facade) {
  return PresenceController(
    facade: facade,
    anonIdentity: AnonIdentityService(store: _FakeKvStore()),
    locationBuilder: LocationEvidenceBuilder(currentLocation: () => null),
  );
}

CheckpointController _makeCheckpoint(EventPublisherV2Facade facade) {
  return CheckpointController(
    facade: facade,
    anonIdentity: AnonIdentityService(store: _FakeKvStore()),
    locationBuilder: LocationEvidenceBuilder(currentLocation: () => null),
  );
}

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

Future<ActiveFieldController> _makeField({bool joined = false}) async {
  final c = ActiveFieldController(
    store: FieldSessionStore(db: DatabaseHelper(), secureStore: _FakeKvStore()),
  );
  if (joined) {
    await c.joinBySecret(
      Uint8List.fromList(List<int>.filled(32, 0x5A)),
      displayName: '測試場域',
    );
  }
  return c;
}

/// Pumps the full AppShell with the production-shaped provider graph.
Future<void> _pumpShell(WidgetTester tester, {required bool joined}) async {
  final registry = PeerCapabilityRegistry();
  final facade = EventPublisherV2Facade(registry: registry);
  final field = await _makeField(joined: joined);
  final presence = _makePresence(registry, facade);
  final checkpoint = _makeCheckpoint(facade);
  final beacon = _makeBeacon(presence, field);
  addTearDown(() async {
    beacon.dispose();
    await facade.dispose();
    await registry.dispose();
    field.dispose();
  });

  await tester.pumpWidget(_wrap(
    const AppShell(),
    field: field,
    presence: presence,
    checkpoint: checkpoint,
    beacon: beacon,
    facade: facade,
  ));
  await tester.pump();
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

  testWidgets('no-field entry shows the three entries, never DebugShell',
      (tester) async {
    await _pumpShell(tester, joined: false);

    expect(find.byType(NoFieldEntry), findsOneWidget);
    expect(find.text('加入場域'), findsOneWidget);
    expect(find.text('建立場域'), findsOneWidget);
    expect(find.text('先看功能'), findsOneWidget);
    expect(find.byType(DebugShell), findsNothing);
  });

  testWidgets(
      'active field renders five exact tabs, no 地圖, global SOS, no DebugShell',
      (tester) async {
    await _pumpShell(tester, joined: true);

    expect(find.byType(NoFieldEntry), findsNothing);
    expect(kAppShellTabLabels, <String>['安全', '位置', '事件', '協助', '我的']);
    for (final label in kAppShellTabLabels) {
      expect(find.text(label), findsOneWidget, reason: 'tab "$label"');
    }
    expect(find.text('地圖'), findsNothing);
    expect(find.byKey(kGlobalSosButtonKey), findsOneWidget);
    expect(find.byType(DebugShell), findsNothing);
  });

  testWidgets('global SOS is reachable from every tab', (tester) async {
    await _pumpShell(tester, joined: true);

    for (final label in kAppShellTabLabels) {
      await tester.tap(find.text(label));
      await tester.pump();
      expect(find.byKey(kGlobalSosButtonKey), findsOneWidget,
          reason: 'global SOS missing on "$label" tab');
    }
  });

  testWidgets('安全 tab shows comms status + update footprint + beacon toggle',
      (tester) async {
    await _pumpShell(tester, joined: true); // 安全 is the default tab

    expect(find.byType(SafetyTab), findsOneWidget);
    expect(find.textContaining('近距離通訊'), findsWidgets);
    expect(find.text('立即更新足跡'), findsOneWidget);
    expect(find.text('自動足跡信標'), findsOneWidget);
  });

  testWidgets('位置 tab embeds the existing LastSeenScreen', (tester) async {
    await _pumpShell(tester, joined: true);

    await tester.tap(find.text('位置'));
    await tester.pump();

    expect(find.byType(LastSeenScreen), findsOneWidget);
  });

  testWidgets('事件 tab exposes the formal HAZARD report entry (no debug gate)',
      (tester) async {
    await _pumpShell(tester, joined: true);

    await tester.tap(find.text('事件'));
    await tester.pump();

    expect(find.byType(EventsTab), findsOneWidget);
    // formalSend → the production report action renders regardless of kDebugMode.
    expect(find.text('回報危害'), findsOneWidget);
  });

  testWidgets('我的 tab shows the 場域管理 launcher + debug diagnostics entry',
      (tester) async {
    await _pumpShell(tester, joined: true);

    await tester.tap(find.text('我的'));
    await tester.pump();

    expect(find.byType(MyTab), findsOneWidget);
    expect(find.text('場域管理'), findsOneWidget);
    // kDebugMode is true under flutter test → the developer entry renders.
    expect(find.text('開發者診斷'), findsOneWidget);
  });
}
