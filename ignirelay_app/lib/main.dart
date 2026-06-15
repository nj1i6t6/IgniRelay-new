import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ignirelay_app/l10n/generated/app_localizations.dart';
import 'package:ignirelay_app/app/emergency/emergency_mode_controller.dart';
import 'package:ignirelay_app/ui/secondary/battery_optimization_guide.dart';
import 'package:ignirelay_app/ui/theme/app_theme.dart';
import 'package:ignirelay_app/ui/theme/igni_text_scale.dart';
import 'package:ignirelay_app/ui/secondary/onboarding_screen.dart';
import 'package:ignirelay_app/ui/screens/design_showcase_screen.dart';
import 'package:ignirelay_app/ui/shell/debug_shell.dart';
import 'package:ignirelay_app/app/db/database_helper.dart';
import 'package:ignirelay_app/app/crypto/identity_manager.dart';
import 'package:ignirelay_app/app/mesh/event_manager.dart';
import 'package:ignirelay_app/app/mesh/mesh_constants.dart';
import 'package:ignirelay_app/app/geo/village_geofence.dart';
import 'package:ignirelay_app/platform/mesh_transport.dart';
import 'package:ignirelay_app/app/mesh/transport_factory.dart';
import 'package:ignirelay_app/platform/native_bridge.dart';
import 'package:ignirelay_app/app/controllers/message_publisher_v2.dart';
import 'package:ignirelay_app/app/controllers/v2_pipeline_factory.dart';
import 'package:ignirelay_app/app/proto/event_envelope_v2.dart';
import 'package:ignirelay_app/app/services/adapter_health_monitor.dart';
import 'package:ignirelay_app/app/services/author_rate_limiter.dart';
import 'package:ignirelay_app/app/services/ble_v2_bridge.dart';
import 'package:ignirelay_app/app/services/envelope_store_v2.dart';
import 'package:ignirelay_app/app/services/event_publisher_v2_facade.dart';
import 'package:ignirelay_app/app/services/mesh_debug_controller.dart';
import 'package:ignirelay_app/app/services/mesh_trace_writer.dart';
import 'package:ignirelay_app/app/services/peer_capability_registry.dart';
import 'package:ignirelay_app/app/services/protocol_hello_service.dart';
import 'package:ignirelay_app/app/services/v2_inbound_projector.dart';
import 'package:ignirelay_app/app/controllers/event_publisher.dart';
import 'package:ignirelay_app/app/controllers/event_stream.dart';
import 'package:ignirelay_app/app/controllers/presence_controller.dart';
import 'package:ignirelay_app/app/controllers/sos_controller.dart';
import 'package:ignirelay_app/app/controllers/active_field_controller.dart';
import 'package:ignirelay_app/app/services/anon_identity.dart';
import 'package:ignirelay_app/app/services/field_session_store.dart';
import 'package:ignirelay_app/app/services/location_evidence_builder.dart';
import 'package:ignirelay_app/app/controllers/ble_scan_controller.dart';
import 'package:ignirelay_app/app/controllers/device_info_controller.dart';
import 'package:ignirelay_app/app/controllers/handoff_controller.dart';
import 'package:ignirelay_app/app/controllers/tier_manager.dart';
import 'package:ignirelay_app/app/services/event_decoder.dart';
import 'package:ignirelay_app/app/services/event_store.dart';
import 'package:ignirelay_app/app/services/location_service.dart';
import 'package:ignirelay_app/app/mesh/mesh_event_handler.dart';
import 'package:ignirelay_app/app/controllers/mesh_runtime_controller.dart';
import 'package:ignirelay_app/app/crdt/hlc.dart';
import 'package:ignirelay_app/l10n/l10n_ext.dart';

/// 版本字面值（與 pubspec.yaml 的 `version:` 對齊）。
///
/// 沒有引入 `package_info_plus` 是因為 Stage 2 整理依賴清單時已決定避開，
/// 而我們又不希望走「在每個顯示版本的位置都各自寫一次」的舊路。
/// 規範：每次 release bump 同步更新 [kAppVersionName] / [kAppBuildNumber]。
const String kAppVersionName = '0.2.0';
const String kAppBuildNumber = '30';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // BUILD_TIMESTAMP fallback：跟隨 release 節奏更新，HLC 偏差保護用。
  // 正式 build 應透過 `--dart-define=BUILD_TIMESTAMP=$(date +%s%3N)` 注入；
  // 詳見 README「Release build」一節。fallback 設為「靠近今天」即可，
  // 因為 HLC 只用它做「不可低於此基準」的鬆綁判斷，過大反而傷及格 1。
  const buildTimestamp = int.fromEnvironment(
    'BUILD_TIMESTAMP',
    defaultValue: 1777334400000, // 2026-04-28 fallback (v0.2.0)
  );
  HLC.setAppBuildTimestamp(buildTimestamp);
  final transport = TransportFactory.create();
  // UI 層透過 MeshRuntimeController 操作 transport，不直接持有實例。
  MeshRuntimeController.instance.attachTransport(transport);

  // 啟動時自動清 24h 前的 Debug_Logs，避免正式版無限增長。
  // 在 background 跑，不阻塞 UI 啟動。
  unawaited(_purgeOldDebugLogs());

  // v0.3 Stage 0c wave 3B — wire the v2 EventEnvelope trusted pipeline into
  // the native BLE event stream. Construction is async because the Ed25519
  // keypair has to be loaded from secure storage; we fire-and-forget so the
  // UI doesn't have to wait. The bridge is retained at module scope so its
  // EventChannel subscription survives.
  unawaited(_startV2Bridge());

  runApp(IgniRelayApp(transport: transport));
}

Future<void> _purgeOldDebugLogs() async {
  try {
    final n = await DatabaseHelper().purgeDebugLogs();
    if (n > 0) debugPrint('[main] purged $n old debug logs');
  } catch (e) {
    debugPrint('[main] purgeDebugLogs failed: $e');
  }
}

/// v0.3 Stage 0c wave 3B — module-level handle so the v2 bridge is not
/// garbage-collected after construction. Kept module-private; UI does not
/// touch it directly in wave 3B (no Provider wiring yet — UI integration
/// is wave 3C+).
BleV2Bridge? _v2Bridge;

/// v0.3 Stage 0c wave 3E — adapter health monitor + debug controller, also
/// retained at module scope. Both are constructed inside [_startV2Bridge]
/// so they share the same MeshTraceWriter / native event stream.
AdapterHealthMonitor? _adapterHealthMonitor;
MeshDebugController? _meshDebugController;

/// v0.3 Stage 0c — projects v2-received envelopes (post-dispatcher accept)
/// into the v1 `Event_Logs` read-model so `EventStream` / UI sees them.
/// Closes the "v2 inbound dead-ends in Envelopes_V2" gap. Retained at module
/// scope so its dispatcher subscription survives.
V2InboundProjector? _v2InboundProjector;

/// v0.3 Stage 0c wave 3E — shared PeerCapabilityRegistry. Created eagerly
/// at app startup so the v2 publish facade can hold a non-null reference
/// from the first frame (Stage 0c wave 3E-r2 Provider-lifecycle fix). The
/// async [_startV2Bridge] later constructs the bridge against this same
/// registry instance.
final PeerCapabilityRegistry _peerCapabilityRegistry = PeerCapabilityRegistry();

/// v0.3 Stage 0c wave 3E — v2 publish facade. Exposed to the UI via
/// Provider (see MultiProvider below). UI / app services use this in place
/// of (or in addition to) `EventPublisher` for the 0d-eligible event types
/// (SOS_RED STATUS_UPDATE, STATUS_UPDATE, HAZARD_MARKER, PRESENCE).
/// (CHAT_MESSAGE was one too until A6/OD-6 retired it.)
///
/// Stage 0c wave 3E-r2: now constructed EAGERLY at module-load time with
/// just the registry; [BleV2Bridge] is attached later via
/// [EventPublisherV2Facade.attachBridge] inside [_startV2Bridge]. Sends
/// issued before the bridge attaches are held in an in-memory pending
/// queue and drained when the first peer becomes ready for traffic. This
/// makes the Provider non-nullable from the first build() and removes the
/// silent "UI reads null forever" failure mode of 3E-r1.
/// Wave 3F — pass `DatabaseHelper()` so the facade mirrors its pending
/// queue to the `Outbox_V2` SQLite table and re-hydrates on next launch.
/// Tests construct the facade with `db: null` to opt out (in-memory only).
final EventPublisherV2Facade _eventPublisherV2 = EventPublisherV2Facade(
  registry: _peerCapabilityRegistry,
  db: DatabaseHelper(),
);

/// v0.3 Phase 0b #4-7 (A5) — the active-field source. Constructed EAGERLY
/// (empty) at module load so the Provider is non-null from the first frame
/// (the debug field card reads + listens to it). Its persisted fields are
/// loaded — and its shared FieldKeyStore populated — asynchronously inside
/// [_startV2Bridge] via [ActiveFieldController.initialize], before the
/// production dispatcher is built against that same key store.
final ActiveFieldController _activeFieldController = ActiveFieldController(
  store: FieldSessionStore(db: DatabaseHelper()),
);

/// Visible-for-test accessors so the 0d-gate test runner can drive the
/// debug controller without reaching into module state. UI MUST NOT call
/// these (the controllers are not Provider-wired; they are infrastructure).
@visibleForTesting
AdapterHealthMonitor? get debugAdapterHealthMonitor => _adapterHealthMonitor;
@visibleForTesting
MeshDebugController? get debugMeshDebugController => _meshDebugController;
@visibleForTesting
V2InboundProjector? get debugV2InboundProjector => _v2InboundProjector;

Future<void> _startV2Bridge() async {
  if (_v2Bridge != null) return;
  try {
    final identity = IdentityManager();
    final keyPair = await identity.getOrCreateKeyPair();
    final pubKey = Uint8List.fromList(await identity.getPublicKeyBytes());
    final dbHelper = DatabaseHelper();
    final store = EnvelopeStoreV2(dbHelper);
    final trace = MeshTraceWriter(dbHelper);
    final rateLimiter = AuthorRateLimiter();

    // A5 (4-7, 施工筆記 4) — load the persisted joined fields into the active
    // -field controller BEFORE building the dispatcher: secure storage →
    // re-derive (field_id, mac_key) → populate the shared FieldKeyStore. The
    // dispatcher then enforces field-scope (§21.6) against that live store, and
    // the publish facade signs every non-control envelope under the active
    // field (no field joined → publish rejected with noField).
    await _activeFieldController.initialize();
    _eventPublisherV2.attachActiveField(_activeFieldController);

    final dispatcher = createProductionDispatcherV2(
      store: store,
      trace: trace,
      rateLimiter: rateLimiter,
      // A5 DoD D1 — field-scope check ON + the live, shared FieldKeyStore. The
      // three production flags (clock expiry, max-hops, field-scope) are pinned
      // inside the factory so they can't be silently flipped off (施工筆記 5).
      fieldKeys: _activeFieldController.keyStore,
    );
    final publisher = MessagePublisherV2(
      keyPair: keyPair,
      authorPublicKey: pubKey,
      trace: trace,
    );
    // Stage 0c wave 3E-r2 — re-use the module-level registry so the
    // eagerly-constructed [_eventPublisherV2] facade and the bridge share
    // the same per-peer state. Building a fresh PeerCapabilityRegistry()
    // here (the wave 3E-r1 behavior) split state in two and made the
    // facade's drain trigger never fire.
    final registry = _peerCapabilityRegistry;
    final bridge = BleV2Bridge(
      store: store,
      dispatcher: dispatcher,
      publisher: publisher,
      registry: registry,
      selfHelloFactory: () => buildSelfHello(
        peerKind: PeerKind.phoneV1,
        maxRxEnvelopeBytes: kMaxEnvelopeBytes,
        supportsIblt: true,
        supportsBloomV2: true,
        supportsChunking: true,
        // v0.3 Stage 0c wave 3E — `min_negotiated_mtu` per spec §5.4 is a
        // CAPABILITY COMMITMENT ("lowest MTU the peer commits to handle"),
        // not the per-connection negotiated MTU. PhoneV1 (§6.1.2) commits
        // to MTU 185-512, so the spec-correct floor is 185 — NOT 247. The
        // previous hardcoded 247 was a latent contract violation: on a
        // link that negotiated MTU=185, we would advertise "I commit to
        // 247" while actually handling 185, confusing capability-aware
        // peers (e.g., BleNodeV1 declining to send chunks they think we
        // can handle in one notify). The actual per-connection negotiated
        // MTU is plumbed through `peer_ready_for_hello` → BleV2Bridge
        // ._peerMtu map and used by `publisher.send(negotiatedMtu: ...)`;
        // the HELLO field declares the COMMITMENT, not the live value.
        minNegotiatedMtu: 185,
        bgState: BgState.foreground,
      ),
      nativeEventStream: NativeBridge.nativeEventStream,
      writeEventToPeer: NativeBridge.nordicWriteEvent,
      notifyEventToPeer: NativeBridge.notifyEventChunk,
    );
    bridge.start();
    _v2Bridge = bridge;

    // Stage 0c wave 3E — adapter health observability + debug hooks.
    // Both run unconditionally in dev builds; the native debug hooks are
    // deliberately UNGATED on release too so the QA agent can drive the
    // 0d gate against release binaries (see MainActivity.kt /
    // BlePlugin.swift). Their impact is bounded (MTU clamp + tick
    // suppression only — no wire-format mutation, no signature bypass).
    //
    // Stage 0c wave 3F — wire the Dart-side §8.3 step 1 recovery action.
    // The native FS (Android) owns the advertise bounce; the Dart monitor
    // owns the scan bounce because `NordicMeshManager` is held by
    // `MainActivity`, not the foreground service. On iOS the BlePlugin's
    // own native watchdog bounces both managers — the Dart callback is
    // redundant but harmless (startScan/stopScan are idempotent there).
    final healthMonitor = AdapterHealthMonitor(
      nativeEventStream: NativeBridge.nativeEventStream,
      trace: trace,
      onIdleDetected: () async {
        // 300 ms gap between stop and start — long enough for the BLE
        // scanner to actually release, short enough that scenario #11's
        // 60 s recovery budget is not eaten by housekeeping.
        await NativeBridge.stopNordicScan();
        await Future<void>.delayed(const Duration(milliseconds: 300));
        await NativeBridge.startNordicScan();
      },
    );
    healthMonitor.start();
    _adapterHealthMonitor = healthMonitor;
    _meshDebugController = MeshDebugController(trace: trace);

    // v0.3 Stage 0c — project accepted v2 envelopes into the v1 Event_Logs
    // read-model. Without this, anything received over the v0.3 wire lands in
    // Envelopes_V2 and never reaches EventStream / the UI. Shares the same
    // MeshEventHandler singleton whose `.events` stream EventStream listens to.
    final projector = V2InboundProjector(
      outcomes: dispatcher.outcomes,
      handler: MeshEventHandler(),
    );
    projector.start();
    _v2InboundProjector = projector;
    // Stage 0c wave 3E-r2 — attach the bridge to the EAGERLY-constructed
    // facade. Any sends issued before now have been buffered in the
    // facade's in-memory pending queue; attachBridge schedules a drain
    // attempt immediately so the queue clears as soon as a peer reaches
    // isReadyForTraffic.
    _eventPublisherV2.attachBridge(bridge);

    debugPrint('[main] v2 bridge started');
  } catch (e, st) {
    debugPrint('[main] v2 bridge start failed: $e\n$st');
  }
}

class IgniRelayApp extends StatefulWidget {
  final MeshTransport transport;
  const IgniRelayApp({super.key, required this.transport});

  static void setLocale(BuildContext context, Locale locale) {
    context.findAncestorStateOfType<_IgniRelayAppState>()?.setLocale(locale);
  }

  static void setThemeMode(BuildContext context, ThemeMode mode) {
    context.findAncestorStateOfType<_IgniRelayAppState>()?.setThemeMode(mode);
  }

  /// Stage 7-r3：accent 固定 amber，不再讓使用者切換。Profile 設定頁的
  /// `_AccentPicker` 已移除，但若日後產品再需要 multi-brand，這裡可以再開回。
  static void setTextScale(BuildContext context, IgniTextScale scale) {
    context.findAncestorStateOfType<_IgniRelayAppState>()?.setTextScale(scale);
  }

  static IgniTextScale textScaleOf(BuildContext context) {
    return context.findAncestorStateOfType<_IgniRelayAppState>()?._textScale ??
        IgniTextScale.standard;
  }

  @override
  State<IgniRelayApp> createState() => _IgniRelayAppState();
}

class _IgniRelayAppState extends State<IgniRelayApp> {
  Locale? _locale;
  // Stage 7-r3：預設改為 light（產品決策：第一次使用較舒適；急難模式仍會
  // 在 build() 動態切回深色高對比）。
  ThemeMode _themeMode = ThemeMode.light;
  IgniTextScale _textScale = IgniTextScale.standard;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString('app_language');
    final themeStr = prefs.getString('app_theme_mode');
    final textScaleStr = prefs.getString('app_text_scale');
    if (!mounted) return;
    setState(() {
      if (code != null) _locale = Locale(code);
      _themeMode = _parseThemeMode(themeStr);
      _textScale = IgniTextScale.parse(textScaleStr);
    });
  }

  static ThemeMode _parseThemeMode(String? s) {
    switch (s) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      case 'system':
      default:
        // Stage 7-r3：未設定過時預設淺色。
        return ThemeMode.light;
    }
  }

  void setThemeMode(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('app_theme_mode', mode.name);
    if (mounted) setState(() => _themeMode = mode);
  }

  void setLocale(Locale locale) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('app_language', locale.languageCode);
    if (mounted) setState(() => _locale = locale);
  }

  void setTextScale(IgniTextScale scale) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('app_text_scale', scale.storageKey);
    if (mounted) setState(() => _textScale = scale);
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<EventDecoder>(
          create: (_) => EventDecoder(),
        ),
        // v0.3 Stage 0c wave 3E-r2 — v2 publish facade. NON-NULLABLE:
        // constructed eagerly at module load with the shared
        // PeerCapabilityRegistry, then has its BLE bridge attached
        // asynchronously inside [_startV2Bridge]. Sends issued before the
        // bridge attaches are buffered in the facade's pending queue and
        // drained automatically when the first peer becomes ready for
        // traffic. UI / EventPublisher receive a usable facade from the
        // first frame; no nullable-Provider gymnastics required.
        Provider<EventPublisherV2Facade>.value(value: _eventPublisherV2),
        Provider<EventPublisher>(
          create: (_) => EventPublisher(
            eventManager: EventManager(),
            v2Facade: _eventPublisherV2,
          ),
        ),
        Provider<EventStore>(
          create: (_) => EventStore(databaseHelper: DatabaseHelper()),
        ),
        // Phase 0b #3A: 舊產品 repo provider（match/supply/negotiation/medical/
        // profile）已移除 — UI 消費端在 #2 刪除後不再被讀取。服務檔案暫留（仍被
        // database_helper / event_manager / mesh_event_handler 等 kept core 直接
        // import,屬 wire/event-model 耦合,留待後續重構）。見 REBUILD_PLAN §4。
        Provider<IdentityManager>(
          create: (_) => IdentityManager(),
        ),
        Provider<LocationService>(
          create: (_) => LocationService(),
        ),
        Provider<DeviceInfoController>(
          create: (_) => DeviceInfoController.instance,
        ),
        Provider<BleScanController>(
          create: (_) => BleScanController.instance,
        ),
        Provider<MeshRuntimeController>(
          create: (_) => MeshRuntimeController.instance,
        ),
        // EmergencyModeController 是 ChangeNotifier，必須用 ListenableProvider
        // 才不會被 Provider.debugCheckInvalidValueType 在 dev/test 攔下。
        // 不能用 ChangeNotifierProvider — 它會在 provider 移除時呼叫 dispose()，
        // 破壞 static singleton 生命週期。
        ListenableProvider<EmergencyModeController>(
          create: (_) => EmergencyModeController.instance,
        ),
        Provider<HandoffController>(
          create: (_) => HandoffController.instance,
        ),
        Provider<TierManager>(
          create: (_) => TierManager(),
        ),
        Provider<EventStream>(
          create: (context) => EventStream(
            handler: MeshEventHandler(),
            decoder: context.read<EventDecoder>(),
            store: context.read<EventStore>(),
          )..start(),
          dispose: (_, stream) => stream.dispose(),
        ),
        // #4-4 (A2) — PRESENCE publish orchestrator. Assembles anon_user_id +
        // GPS evidence in the app layer so the UI never touches app/proto.
        Provider<PresenceController>(
          create: (context) => PresenceController(
            facade: context.read<EventPublisherV2Facade>(),
            anonIdentity: AnonIdentityService(),
            locationBuilder: LocationEvidenceBuilder(
              currentLocation: () =>
                  context.read<LocationService>().currentLocation,
            ),
          ),
        ),
        // A8 — SOS publish state machine (long-press → countdown → send-with-
        // location → 我安全了). ChangeNotifierProvider so its countdown timers
        // are disposed with the provider; it is screen-scoped state, not a
        // shared module singleton.
        ChangeNotifierProvider<SosController>(
          create: (context) => SosController(
            facade: context.read<EventPublisherV2Facade>(),
            locationBuilder: LocationEvidenceBuilder(
              currentLocation: () =>
                  context.read<LocationService>().currentLocation,
            ),
          ),
        ),
        // #4-7 (A5) — active-field source. Long-lived module-level instance
        // (loaded in [_startV2Bridge]); ListenableProvider (not
        // ChangeNotifierProvider) so provider removal does NOT dispose the
        // shared singleton — same rationale as EmergencyModeController above.
        // The debug field card watches it; the publish facade reads it.
        ListenableProvider<ActiveFieldController>.value(
          value: _activeFieldController,
        ),
        Provider<MeshTransport>.value(
          value: widget.transport,
        ),
      ],
      child: Consumer<EmergencyModeController>(
        builder: (context, emergencyController, _) {
          // EmergencyModeController 仍是 ChangeNotifier，需要透過 AnimatedBuilder
          // 訂閱才能在 isEmergency 變動時 rebuild MaterialApp 主題。Provider 在這
          // 層只負責「把 controller 從 tree 拿出來」；不直接呼叫 `.instance`。
          return AnimatedBuilder(
            animation: emergencyController,
            builder: (innerContext, _) {
              final inEmergency = emergencyController.isEmergency;
              // 急難模式一律套用高對比主題，忽略 light/dark 偏好以保肌肉記憶。
              final themeMode = inEmergency ? ThemeMode.dark : _themeMode;
              return _buildMaterialApp(innerContext, inEmergency, themeMode);
            },
          );
        },
      ),
    );
  }

  Widget _buildMaterialApp(
      BuildContext context, bool inEmergency, ThemeMode themeMode) {
    return MaterialApp(
      title: '烽傳 IgniRelay',
      debugShowCheckedModeBanner: false,
      locale: _locale,
      supportedLocales: S.supportedLocales,
      localizationsDelegates: const [
        S.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      localeResolutionCallback: (locale, supportedLocales) {
        if (_locale != null) return _locale;
        if (locale != null && locale.languageCode == 'zh') {
          return const Locale('zh');
        }
        return const Locale('en');
      },
      theme: AppTheme.light(),
      darkTheme: inEmergency ? AppTheme.emergency() : AppTheme.dark(),
      themeMode: themeMode,
      // Stage 7-r3：以 [MediaQuery] 包一層，把使用者設定的字體大小（取代
      // 舊的「密度」）套到整個 widget 樹。系統字體偏好仍會被尊重——
      // 我們是在系統 textScaler 之上再乘一個係數。
      builder: (ctx, child) {
        final base = MediaQuery.textScalerOf(ctx);
        final scaled = TextScaler.linear(base.scale(1.0) * _textScale.factor);
        return MediaQuery(
          data: MediaQuery.of(ctx).copyWith(textScaler: scaled),
          child: child ?? const SizedBox.shrink(),
        );
      },
      routes: {
        // 設計系統預覽頁：計畫 §Stage 2「Debug-only」要求，release build
        // 不註冊此路由以免誤入。kDebugMode 與 kProfileMode 皆視為「非正式」環境。
        if (kDebugMode || kProfileMode)
          '/design-showcase': (_) => const DesignShowcaseScreen(),
      },
      home: const _StartupRouter(),
    );
  }
}

/// 啟動時路由：檢查 onboarding 與權限
class _StartupRouter extends StatefulWidget {
  const _StartupRouter();

  @override
  State<_StartupRouter> createState() => _StartupRouterState();
}

class _StartupRouterState extends State<_StartupRouter> {
  bool _initialized = false;
  bool _showOnboarding = false;

  late final MeshTransport _transport;

  @override
  void initState() {
    super.initState();
    _transport = Provider.of<MeshTransport>(context, listen: false);
    _init();
  }

  Future<void> _init() async {
    try {
      // ── 階段 1：核心基礎（失敗 = 無法啟動）──
      await DatabaseHelper().database;
      await IdentityManager().initialize();
      await VillageGeofence.init();

      // ── 階段 2：先確定 onboarding 狀態（不依賴後續服務）──
      final prefs = await SharedPreferences.getInstance();
      final done = prefs.getBool('onboarding_done') ?? false;
      if (mounted) {
        setState(() {
          _showOnboarding = !done;
          _initialized = true;
        });
      }

      // ── 階段 3：位置服務（延後到 onboarding 完成 + 首幀後才啟動）──
      // 已 onboarded 的舊使用者：MainShell 首幀畫完後才開始 GPS。
      // 新使用者：等 _onOnboardingComplete() 觸發。

      // ── 階段 4：權限（必須在 LocationService.init 之前完成）──
      await _requestPermissions();

      if (done) {
        _deferLocationInit();
      }

      // ── 階段 5：（已移除）Mesh 服務啟動清理 ──
      // Phase 0b #3B-2：原本在此呼叫 EventPublisher.expireStaleMatches() 清過期
      // match negotiation（舊媒合產品）— 已隨 send path 一併下線。

      // ── 階段 6：BLE ──
      bool btOn = false;
      try {
        btOn = await NativeBridge.isBluetoothEnabled();
      } catch (_) {}

      if (!btOn && mounted) {
        await _showBluetoothEnableDialog();
        try {
          btOn = await NativeBridge.isBluetoothEnabled();
        } catch (_) {}
      }

      if (btOn) {
        try {
          await _transport.initialize();
          await _transport.start();
        } catch (e) {
          debugPrint('[Init] Mesh transport start failed: $e');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                  content: Text(context.l10n.mainBleFailSnack(e.toString())),
                  backgroundColor: Colors.red),
            );
          }
        }
      }

      if (Platform.isAndroid) {
        NativeBridge.startMeshForegroundService().catchError((e) {
          debugPrint('[Init] Foreground service failed: $e');
          return false;
        });
      }
    } catch (e) {
      debugPrint('[Init] Startup error: $e');
      if (mounted && !_initialized) {
        setState(() {
          _initialized = true;
          _showOnboarding = true;
        });
      }
    }
  }

  Future<void> _showBluetoothEnableDialog() async {
    if (!mounted) return;
    final shouldEnable = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a2e),
        title: Row(
          children: [
            const Icon(Icons.bluetooth_disabled, color: Colors.orangeAccent),
            const SizedBox(width: 8),
            Text(ctx.l10n.mainBluetoothDialogTitle,
                style: const TextStyle(color: Colors.white)),
          ],
        ),
        content: Text(
          ctx.l10n.mainBluetoothDialogContent,
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(ctx.l10n.mainBluetoothDialogCancel,
                style: const TextStyle(color: Colors.white38)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blueAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(ctx.l10n.mainBluetoothDialogConfirm),
          ),
        ],
      ),
    );
    if (shouldEnable == true) {
      await NativeBridge.requestBluetoothEnable();
      await Future.delayed(const Duration(seconds: 2));
    }
  }

  Future<bool> _requestPermissions() async {
    final permissions = <Permission>[
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.bluetoothAdvertise,
      Permission.locationWhenInUse,
    ];

    if (Platform.isAndroid) {
      permissions.add(Permission.notification);
    }

    final statuses = await permissions.request();

    final allGranted = statuses.values.every(
      (s) => s.isGranted || s.isLimited,
    );

    if (!allGranted && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.mainPermissionSnack),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 5),
        ),
      );
    }

    return allGranted;
  }

  /// 延後啟動 LocationService：等 MainShell 首幀畫完後才開始 GPS，
  /// 避免 onboarding → map 切換時與 MapScreenController 並發操作平台層。
  void _deferLocationInit() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _initLocationService();
    });
  }

  Future<void> _initLocationService() async {
    if (!mounted) return;
    try {
      // Phase 0b: 舊「GPS 就緒 → 自動加入村里聊天室」已移除（chat 產品下線）。
      // 位置服務仍啟動 — mapless 定位的 GPS evidence 來源（REBUILD_PLAN §3.6）。
      final locService = context.read<LocationService>();
      await locService.init();
    } catch (e) {
      debugPrint('[Init] Location init failed: $e');
    }
  }

  void _onOnboardingComplete() {
    setState(() => _showOnboarding = false);
    // GPS 延後到 onboarding 動畫結束 + MainShell 首幀畫完後才啟動
    _deferLocationInit();
    if (Platform.isAndroid) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          BatteryOptimizationGuide.checkAndGuide(context);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      final theme = Theme.of(context);
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: theme.colorScheme.primary),
              const SizedBox(height: 16),
              Text(
                S.of(context)?.mainStartupLoading ?? '烽傳 啟動中...',
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      );
    }

    if (_showOnboarding) {
      return OnboardingScreen(
        onComplete: _onOnboardingComplete,
      );
    }

    // Phase 0b：舊 `MainShell`（地圖優先 tab 殼）已不再是入口,改用 mapless
    // debug shell。MainShell 與其 tab 子畫面(match/supply/chat/map)成為待刪
    // orphan,將在後續 consumers-first commit 移除。見 docs/REBUILD_PLAN.md §4。
    return const DebugShell();
  }
}
