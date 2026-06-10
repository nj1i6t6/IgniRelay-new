// provider_wiring_smoke_test.dart
//
// Root-wiring sanity gate:
//   - 最小 widget pump 一個 MultiProvider tree，**鏡像 main.dart 現在實際提供的
//     root providers**（_IgniRelayAppState.build 的 providers 清單）。
//   - 從子 widget 用 context.read<T>() 取出每一個 root provider。
//   - 任一個 Provider 沒接好都會 throw → 測試會失敗。
//
// 為什麼這份測試是 mandatory：整合層級的 sanity gate — 確保「UI 改用
// context.read<T>() 拿不到東西」這個最常見的回歸不會混到 release。
//
// Phase 0b #3A：原本檢查的是 Stage 1 的 facade/repo 清單（含 StationSupplyRepo /
// ProfileRepo / MedicalCardRepo / NegotiationRepo / ChatService）。那批舊產品
// repo 的 root provider 已在 #3A 從 main.dart 移除（UI 消費端在 #2 已刪），故
// 本測試同步改為只檢查 main.dart 現存的 root providers。服務檔案本身暫留
// （仍被 kept core import,屬 wire/event-model 耦合,留到 #3B 處理）。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:ignirelay_app/app/controllers/ble_scan_controller.dart';
import 'package:ignirelay_app/app/controllers/device_info_controller.dart';
import 'package:ignirelay_app/app/controllers/event_publisher.dart';
import 'package:ignirelay_app/app/controllers/event_stream.dart';
import 'package:ignirelay_app/app/controllers/handoff_controller.dart';
import 'package:ignirelay_app/app/controllers/mesh_runtime_controller.dart';
import 'package:ignirelay_app/app/controllers/tier_manager.dart';
import 'package:ignirelay_app/app/crypto/identity_manager.dart';
import 'package:ignirelay_app/app/db/database_helper.dart';
import 'package:ignirelay_app/app/emergency/emergency_mode_controller.dart';
import 'package:ignirelay_app/app/mesh/event_manager.dart';
import 'package:ignirelay_app/app/mesh/mesh_event_handler.dart';
import 'package:ignirelay_app/app/mesh/transport_factory.dart';
import 'package:ignirelay_app/app/services/event_decoder.dart';
import 'package:ignirelay_app/app/services/event_publisher_v2_facade.dart';
import 'package:ignirelay_app/app/services/event_store.dart';
import 'package:ignirelay_app/app/services/location_service.dart';
import 'package:ignirelay_app/app/services/peer_capability_registry.dart';
import 'package:ignirelay_app/platform/mesh_transport.dart';

class _ProbeWidget extends StatelessWidget {
  const _ProbeWidget({required this.onRead});

  final void Function(BuildContext context) onRead;

  @override
  Widget build(BuildContext context) {
    // 把 read 推到 build 之後，避免 setUp 的 ProviderNotFoundException 包裝。
    WidgetsBinding.instance.addPostFrameCallback((_) => onRead(context));
    return const SizedBox.shrink();
  }
}

Widget _wrapWithRootProviders(Widget child) {
  // 鏡像 main.dart `_IgniRelayAppState.build()` 的 root provider 清單。
  // 測試版差異（刻意）：
  //   - EventPublisherV2Facade 用 `db: null` 走純記憶體（不碰 Outbox_V2 SQLite）。
  //   - MeshTransport 用 TransportFactory.create()（構造不開原生通道）。
  return MultiProvider(
    providers: [
      Provider<EventDecoder>(
        create: (_) => EventDecoder(),
      ),
      Provider<EventPublisherV2Facade>(
        create: (_) => EventPublisherV2Facade(
          registry: PeerCapabilityRegistry(),
          db: null,
        ),
      ),
      Provider<EventPublisher>(
        create: (ctx) => EventPublisher(
          eventManager: EventManager(),
          v2Facade: ctx.read<EventPublisherV2Facade>(),
        ),
      ),
      Provider<EventStore>(
        create: (_) => EventStore(databaseHelper: DatabaseHelper()),
      ),
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
        ),
        dispose: (_, s) => s.dispose(),
      ),
      Provider<MeshTransport>.value(
        value: TransportFactory.create(),
      ),
    ],
    child: MaterialApp(home: Scaffold(body: child)),
  );
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    DatabaseHelper.testDatabasePathOverride = inMemoryDatabasePath;
    SharedPreferences.setMockInitialValues({});
  });

  setUp(() async {
    await DatabaseHelper().resetForTest();
  });

  testWidgets(
      'root providers expose every main.dart facade/controller to UI via context.read',
      (tester) async {
    final reads = <Type, Object?>{};
    await tester.pumpWidget(_wrapWithRootProviders(
      _ProbeWidget(onRead: (ctx) {
        reads[EventDecoder] = ctx.read<EventDecoder>();
        reads[EventPublisherV2Facade] = ctx.read<EventPublisherV2Facade>();
        reads[EventPublisher] = ctx.read<EventPublisher>();
        reads[EventStore] = ctx.read<EventStore>();
        reads[IdentityManager] = ctx.read<IdentityManager>();
        reads[LocationService] = ctx.read<LocationService>();
        reads[DeviceInfoController] = ctx.read<DeviceInfoController>();
        reads[BleScanController] = ctx.read<BleScanController>();
        reads[MeshRuntimeController] = ctx.read<MeshRuntimeController>();
        reads[EmergencyModeController] = ctx.read<EmergencyModeController>();
        reads[HandoffController] = ctx.read<HandoffController>();
        reads[TierManager] = ctx.read<TierManager>();
        reads[EventStream] = ctx.read<EventStream>();
        reads[MeshTransport] = ctx.read<MeshTransport>();
      }),
    ));
    // 觸發 postFrameCallback。
    await tester.pump();

    for (final entry in reads.entries) {
      expect(entry.value, isNotNull,
          reason: '${entry.key} not provided at app root');
    }
  });
}
