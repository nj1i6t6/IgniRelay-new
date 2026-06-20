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
import 'package:ignirelay_app/l10n/generated/app_localizations.dart';
import 'package:ignirelay_app/ui/screens/field/field_screen.dart';
import 'package:ignirelay_app/ui/screens/position/last_seen_screen.dart';
import 'package:ignirelay_app/ui/screens/preview/preview_screen.dart';
import 'package:ignirelay_app/ui/shell/app_shell.dart';
import 'package:ignirelay_app/ui/shell/debug_shell.dart';
import 'package:ignirelay_app/ui/shell/tabs/events_tab.dart';
import 'package:ignirelay_app/ui/shell/tabs/my_tab.dart';
import 'package:ignirelay_app/ui/shell/tabs/safety_tab.dart';
import 'package:ignirelay_app/ui/shell/tabs/settings_section.dart';
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
  Locale locale = const Locale('zh'),
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
    child: MaterialApp(
      locale: locale,
      supportedLocales: S.supportedLocales,
      localizationsDelegates: S.localizationsDelegates,
      home: child,
    ),
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
///
/// When [textScale] is non-null the AppShell is wrapped in a MediaQuery applying
/// `TextScaler.linear(textScale)`, so the UI-H3 large-text stress tests exercise
/// the real shell (no-field entry / bottom nav / global SOS) at composite scales
/// rather than an isolated tab.
Future<void> _pumpShell(WidgetTester tester,
    {required bool joined,
    Locale locale = const Locale('zh'),
    double? textScale}) async {
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

  const shell = AppShell();
  await tester.pumpWidget(_wrap(
    textScale == null
        ? shell
        : Builder(
            builder: (ctx) => MediaQuery(
              data: MediaQuery.of(ctx)
                  .copyWith(textScaler: TextScaler.linear(textScale)),
              child: shell,
            ),
          ),
    field: field,
    presence: presence,
    checkpoint: checkpoint,
    beacon: beacon,
    facade: facade,
    locale: locale,
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
    // UI-H2a: labels come from ARB. Order is fixed by appShellTabLabels(); zh
    // values are the canonical 安全/位置/事件/協助/我的, never 地圖.
    expect(appShellTabLabels(lookupS(const Locale('zh'))),
        <String>['安全', '位置', '事件', '協助', '我的']);
    for (final label in const ['安全', '位置', '事件', '協助', '我的']) {
      expect(find.text(label), findsOneWidget, reason: 'tab "$label"');
    }
    expect(find.text('地圖'), findsNothing);
    expect(find.byKey(kGlobalSosButtonKey), findsOneWidget);
    expect(find.byType(DebugShell), findsNothing);
  });

  testWidgets('global SOS is reachable from every tab', (tester) async {
    await _pumpShell(tester, joined: true);

    for (final label in const ['安全', '位置', '事件', '協助', '我的']) {
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

  testWidgets('UI-H1: 我的 tab shows the 設定 section (語言 / 字體大小)',
      (tester) async {
    await _pumpShell(tester, joined: true);

    await tester.tap(find.text('我的'));
    await tester.pump();

    expect(find.byType(SettingsSection), findsOneWidget);
    expect(find.text('設定'), findsOneWidget);
    expect(find.text('語言'), findsOneWidget);
    expect(find.text('字體大小'), findsOneWidget);
    expect(find.text('中文'), findsOneWidget);
    expect(find.text('English'), findsOneWidget);
    expect(find.text('標準'), findsOneWidget);
    expect(find.text('超大字'), findsOneWidget);
  });

  testWidgets('UI-H1: 我的 has no overflow at huge (1.45) text scale',
      (tester) async {
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

    // MyTab in isolation under the huge effective scale. MyTab is a ListView, so
    // vertical growth scrolls; this guards horizontal overflow in its rows +
    // the new SettingsSection chips.
    await tester.pumpWidget(_wrap(
      Builder(
        builder: (ctx) => MediaQuery(
          data: MediaQuery.of(ctx)
              .copyWith(textScaler: const TextScaler.linear(1.45)),
          child: const Scaffold(body: MyTab()),
        ),
      ),
      field: field,
      presence: presence,
      checkpoint: checkpoint,
      beacon: beacon,
      facade: facade,
    ));
    await tester.pump();

    expect(find.byType(MyTab), findsOneWidget);
    expect(find.text('設定'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // ── UI-H3 — large-text / text-scale stress on the 安全 tab ────────────────
  // The comms card packs an icon + status title + a toggle button into one Row,
  // and a stat Wrap — the kind of layout that overflows horizontally first under
  // the 1.45 app factor and an effective ~2.0 composite on a narrow phone width.
  testWidgets('large text (UI-H3): 安全 tab has no overflow at 1.45 / 2.0',
      (tester) async {
    tester.view.physicalSize = const Size(360, 820);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

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

    for (final scale in const [1.45, 2.0]) {
      await tester.pumpWidget(_wrap(
        Builder(
          builder: (ctx) => MediaQuery(
            data: MediaQuery.of(ctx)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: const Scaffold(body: SafetyTab()),
          ),
        ),
        field: field,
        presence: presence,
        checkpoint: checkpoint,
        beacon: beacon,
        facade: facade,
      ));
      await tester.pump();
      expect(find.byType(SafetyTab), findsOneWidget);
      expect(tester.takeException(), isNull, reason: '安全 overflow @ $scale');
    }
  });

  // ── UI-H3-polish — plan §UI-H3 "Required Screens" coverage that the first
  // UI-H3 cut left to the SafetyTab/Field/Preview/LastSeen/SOS set. These close
  // the remaining named surfaces: the no-field entry, the full AppShell bottom
  // navigation, and the MyTab settings — all under the effective ~2.0 composite
  // on a narrow phone width.

  // no-field entry (plan §Required Screens + DoD "No-field entry still presents
  // all three actions"): the three actions survive 1.45 AND ~2.0 without
  // overflow and all three stay present.
  testWidgets('large text (UI-H3-polish): no-field entry survives 1.45 / 2.0',
      (tester) async {
    tester.view.physicalSize = const Size(360, 820);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final scale in const [1.45, 2.0]) {
      await _pumpShell(tester, joined: false, textScale: scale);
      expect(find.byType(NoFieldEntry), findsOneWidget,
          reason: 'no-field @ $scale');
      expect(find.text('加入場域'), findsOneWidget, reason: '加入場域 @ $scale');
      expect(find.text('建立場域'), findsOneWidget, reason: '建立場域 @ $scale');
      expect(find.text('先看功能'), findsOneWidget, reason: '先看功能 @ $scale');
      expect(tester.takeException(), isNull,
          reason: 'no-field overflow @ $scale');
    }
  });

  // full AppShell bottom navigation + global SOS reachability (plan §Required
  // Screens "AppShell bottom navigation" + §Tests "global SOS reachability under
  // the composite stress scale" + DoD "Global SOS remains reachable"). The
  // IndexedStack builds all five tab bodies at once, so a single 2.0 pump
  // stresses every tab; switching tabs must keep SOS reachable and never
  // overflow.
  testWidgets('large text (UI-H3-polish): joined AppShell bottom nav + SOS @ 2.0',
      (tester) async {
    tester.view.physicalSize = const Size(360, 820);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpShell(tester, joined: true, textScale: 2.0);
    expect(tester.takeException(), isNull, reason: 'initial joined shell @ 2.0');

    // All five tab labels render in the bottom bar at 2.0.
    for (final label in const ['安全', '位置', '事件', '協助', '我的']) {
      expect(find.text(label), findsOneWidget, reason: 'tab "$label" @ 2.0');
    }
    // Global SOS stays reachable through every tab switch, and no tab body
    // (all live in the IndexedStack) overflows at 2.0.
    for (final label in const ['安全', '位置', '事件', '協助', '我的']) {
      await tester.tap(find.text(label));
      await tester.pump();
      expect(find.byKey(kGlobalSosButtonKey), findsOneWidget,
          reason: 'global SOS missing on "$label" tab @ 2.0');
      expect(tester.takeException(), isNull, reason: '$label tab overflow @ 2.0');
    }
  });

  // MyTab formal settings (plan §Required Screens "MyTab settings"). MyTab is a
  // ListView so vertical growth scrolls; this guards the SettingsSection chips +
  // header rows horizontally and proves every language / text-size choice stays
  // reachable (visible or scrollable-to), never hidden by the large scale.
  testWidgets('large text (UI-H3-polish): MyTab settings reachable @ 2.0',
      (tester) async {
    tester.view.physicalSize = const Size(360, 820);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

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
      Builder(
        builder: (ctx) => MediaQuery(
          data: MediaQuery.of(ctx)
              .copyWith(textScaler: const TextScaler.linear(2.0)),
          child: const Scaffold(body: MyTab()),
        ),
      ),
      field: field,
      presence: presence,
      checkpoint: checkpoint,
      beacon: beacon,
      facade: facade,
    ));
    await tester.pump();

    expect(find.byType(MyTab), findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'MyTab overflow @ 2.0');

    // The settings section + every language / text-size choice is in the tree
    // and the lowest chip can be scrolled into view (reachable, not clipped).
    expect(find.byType(SettingsSection), findsOneWidget);
    for (final label in const ['設定', '語言', '字體大小', '中文', 'English', '超大字']) {
      expect(find.text(label), findsWidgets, reason: 'settings "$label" @ 2.0');
    }
    await tester.ensureVisible(find.text('超大字').first);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'settings scroll @ 2.0');
  });

  // ── UI-H2a English-locale smoke ──────────────────────────────────────────

  testWidgets('en: no-field entry shows English entries (no Chinese)',
      (tester) async {
    await _pumpShell(tester, joined: false, locale: const Locale('en'));

    expect(find.byType(NoFieldEntry), findsOneWidget);
    expect(find.text('IgniRelay'), findsOneWidget);
    expect(find.text('Join field'), findsOneWidget);
    expect(find.text('Create field'), findsOneWidget);
    expect(find.text('Guided preview'), findsOneWidget);
    expect(find.text('加入場域'), findsNothing);
    expect(find.text('先看功能'), findsNothing);
  });

  testWidgets('en: five tabs render English labels, no 安全 / 地圖',
      (tester) async {
    await _pumpShell(tester, joined: true, locale: const Locale('en'));

    expect(appShellTabLabels(lookupS(const Locale('en'))),
        <String>['Safety', 'Location', 'Events', 'Assist', 'Me']);
    for (final label in const ['Safety', 'Location', 'Events', 'Assist', 'Me']) {
      expect(find.text(label), findsOneWidget, reason: 'en tab "$label"');
    }
    expect(find.text('安全'), findsNothing);
    expect(find.text('地圖'), findsNothing);
    expect(find.text('Map'), findsNothing);
  });

  testWidgets('en: 我的 settings section is localized', (tester) async {
    await _pumpShell(tester, joined: true, locale: const Locale('en'));

    await tester.tap(find.text('Me'));
    await tester.pump();

    expect(find.byType(SettingsSection), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Language'), findsOneWidget);
    expect(find.text('Text size'), findsOneWidget);
    // role chip for a joined (not created) field → Member, not 成員.
    expect(find.text('Member'), findsOneWidget);
    expect(find.text('設定'), findsNothing);
    expect(find.text('成員'), findsNothing);
  });
}
