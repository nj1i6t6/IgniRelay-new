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
import 'package:ignirelay_app/app/services/location_refresh_coordinator.dart';
import 'package:ignirelay_app/app/services/peer_capability_registry.dart';
import 'package:ignirelay_app/ui/screens/field/field_screen.dart';
import 'package:ignirelay_app/ui/screens/position/last_seen_screen.dart';
import 'package:ignirelay_app/ui/screens/preview/preview_screen.dart';
import 'package:ignirelay_app/ui/shell/app_shell.dart';
import 'package:ignirelay_app/ui/shell/debug_shell.dart';
import 'package:ignirelay_app/ui/shell/tabs/events_tab.dart';
import 'package:ignirelay_app/ui/shell/tabs/my_tab.dart';
import 'package:ignirelay_app/ui/shell/tabs/safety_tab.dart';
import 'package:ignirelay_app/ui/widgets/igni_button.dart';

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
      // UI-F5b — SafetyTab reads the coordinator for the GPS diagnostic; the
      // formal HazardCard reads it lazily at send time. No fix in the harness.
      Provider<LocationRefreshCoordinator>(
        create: (_) => LocationRefreshCoordinator(
          lastFixAt: () => null,
          refreshOnce: (timeout) async => null,
        ),
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

    // UI-F2-polish: no internal build-stage / debug copy may leak onto the
    // production no-field surface.
    expect(find.textContaining('UI-G'), findsNothing);
    expect(find.textContaining('UI-F'), findsNothing);
    expect(find.textContaining('將於'), findsNothing);
  });

  // UI-G — the「先看功能」entry now opens the real PreviewScreen (not a SnackBar),
  // and its exit CTAs reach FieldScreen / pop back. These run under the full
  // AppShell provider harness because FieldScreen depends on providers (Owner
  // boundary ②); the standalone fixture-only render lives in preview_screen_test.
  testWidgets('先看功能 opens PreviewScreen (not the old SnackBar)',
      (tester) async {
    await _pumpShell(tester, joined: false);

    await tester.tap(find.text('先看功能'));
    await tester.pumpAndSettle();

    expect(find.byType(PreviewScreen), findsOneWidget);
    expect(find.byType(NoFieldEntry), findsNothing);
    expect(find.text('先看功能即將提供。'), findsNothing); // placeholder retired
  });

  testWidgets('preview CTA 加入場域 pushReplacement → FieldScreen',
      (tester) async {
    await _pumpShell(tester, joined: false);

    await tester.tap(find.text('先看功能'));
    await tester.pumpAndSettle();
    // Page 1 (加入場域) carries the join CTA. Target the BUTTON specifically —
    // the page title is also「加入場域」, so a bare text finder is ambiguous.
    await tester.tap(find.widgetWithText(IgniButton, '加入場域'));
    await tester.pumpAndSettle();

    expect(find.byType(FieldScreen), findsOneWidget);
    expect(find.byType(PreviewScreen), findsNothing); // replaced, not stacked
  });

  testWidgets('preview 返回 pops back to the no-field entry', (tester) async {
    await _pumpShell(tester, joined: false);

    await tester.tap(find.text('先看功能'));
    await tester.pumpAndSettle();
    expect(find.byType(PreviewScreen), findsOneWidget);

    await tester.tap(find.text('返回')); // page-0 nav-left
    await tester.pumpAndSettle();

    expect(find.byType(PreviewScreen), findsNothing);
    expect(find.byType(NoFieldEntry), findsOneWidget);
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
    // UI-F4: the CommunicationState summary replaced the 即將提供 placeholder.
    expect(find.textContaining('目前路徑'), findsOneWidget);
    expect(find.text('通訊狀態彙整 — 即將提供'), findsNothing);
    expect(find.textContaining('待送'), findsWidgets);
    // UI-F5a: no motion source in the harness ⇒ diagnostic reads 尚未啟用,
    // NEVER 靜止 (Owner boundary 2).
    expect(find.text('動作偵測：尚未啟用'), findsOneWidget);
    expect(find.text('動作偵測：靜止'), findsNothing);
    // UI-F5b: §4.2 GPS diagnostics — fix age + honest policy reason. No fix in
    // the harness ⇒ 尚無定位; the reason line is present and never low-battery.
    expect(find.text('GPS 定位：尚無定位'), findsOneWidget);
    expect(find.textContaining('定位策略：'), findsOneWidget);
  });

  testWidgets('安全 tab cancels its 5s refresh timer on dispose (no leak)',
      (tester) async {
    // Build SafetyTab in isolation so only ITS periodic timer is in play.
    final registry = PeerCapabilityRegistry();
    final facade = EventPublisherV2Facade(registry: registry);
    final field = await _makeField(joined: true);
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
      const Scaffold(body: SafetyTab()),
      field: field,
      presence: presence,
      checkpoint: checkpoint,
      beacon: beacon,
      facade: facade,
    ));
    await tester.pump();
    expect(find.byType(SafetyTab), findsOneWidget);

    // Dispose SafetyTab, then advance well past the 5s tick. A leaked periodic
    // timer would be flagged pending at teardown, and a setState-after-dispose
    // would throw — so reaching the end cleanly proves dispose() cancelled it.
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    expect(find.byType(SafetyTab), findsNothing);
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('安全 tab pauses its 5s refresh while offstage (AppShell context)',
      (tester) async {
    // UI-F5a / Owner boundary 6 — proven in the real IndexedStack context, not
    // an isolated SafetyTab. The refresh-tick counter only advances when the
    // mounted + TickerMode guard passes (i.e. while 安全 is the visible tab).
    SafetyTab.debugRefreshTicks = 0;
    await _pumpShell(tester, joined: true); // 安全 onstage (index 0)

    await tester.pump(const Duration(seconds: 6)); // one 5 s tick fires
    expect(SafetyTab.debugRefreshTicks, greaterThan(0),
        reason: 'refresh runs while 安全 is visible');

    // Switch to 位置 → 安全 offstage (AppShell sets TickerMode(enabled:false)).
    await tester.tap(find.text('位置'));
    await tester.pump();
    final whileOffstage = SafetyTab.debugRefreshTicks;

    await tester.pump(const Duration(seconds: 12)); // two ticks would fire
    expect(SafetyTab.debugRefreshTicks, whileOffstage,
        reason: 'the 5 s timer fires but runs no setState while offstage');
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
    // UI-F3: 身分與角色 is now a real role card. The harness joins (not creates)
    // ⇒ participant 成員 chip, replacing the old 即將提供 placeholder.
    expect(find.text('身分與角色'), findsOneWidget);
    expect(find.text('成員'), findsOneWidget);
    // kDebugMode is true under flutter test → the developer entry renders.
    expect(find.text('開發者診斷'), findsOneWidget);
  });
}
