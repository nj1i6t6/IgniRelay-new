// debug_shell_smoke_test.dart
//
// Phase 0b #2: 最小 smoke test for the mapless DebugShell（取代被刪掉的舊產品
// screen smoke tests）。只驗證殼能 render 且核心區塊存在;不驗證 wire 送出
// (PRESENCE/SOS 仍是 placeholder)。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:ignirelay_app/app/controllers/event_stream.dart';
import 'package:ignirelay_app/app/controllers/mesh_runtime_controller.dart';
import 'package:ignirelay_app/app/db/database_helper.dart';
import 'package:ignirelay_app/app/mesh/mesh_event_handler.dart';
import 'package:ignirelay_app/app/services/event_decoder.dart';
import 'package:ignirelay_app/app/services/event_publisher_v2_facade.dart';
import 'package:ignirelay_app/app/services/event_store.dart';
import 'package:ignirelay_app/app/services/peer_capability_registry.dart';
import 'package:ignirelay_app/ui/shell/debug_shell.dart';

Widget _wrap(Widget child) {
  return MultiProvider(
    providers: [
      Provider<MeshRuntimeController>(
        // 不 attachTransport：DebugShell 對未注入 transport 是 null-safe 的。
        create: (_) => MeshRuntimeController.instance,
      ),
      Provider<EventStore>(
        create: (_) => EventStore(databaseHelper: DatabaseHelper()),
      ),
      Provider<EventPublisherV2Facade>(
        create: (_) => EventPublisherV2Facade(
          registry: PeerCapabilityRegistry(),
        ),
      ),
      Provider<EventStream>(
        create: (ctx) => EventStream(
          handler: MeshEventHandler(),
          decoder: EventDecoder(),
          store: ctx.read<EventStore>(),
        ),
        dispose: (_, s) => s.dispose(),
      ),
    ],
    child: MaterialApp(home: child),
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

  testWidgets('DebugShell renders mesh control, send buttons, event log',
      (tester) async {
    await tester.pumpWidget(_wrap(const DebugShell()));
    await tester.pump();

    // shell renders
    expect(find.byType(DebugShell), findsOneWidget);
    expect(find.text('IgniRelay · Phase 0b'), findsOneWidget);

    // BLE mesh toggle button（未注入 transport → 顯示「啟動」）
    expect(find.byType(FilledButton), findsOneWidget);
    expect(find.text('啟動'), findsOneWidget);

    // PRESENCE / SOS buttons — PRESENCE is now real, SOS still placeholder
    expect(find.text('發 PRESENCE'), findsOneWidget);
    expect(find.text('發 SOS'), findsOneWidget);

    // position card — shows "尚無 PRESENCE evidence" initially
    expect(find.text('最後可信位置'), findsOneWidget);
    expect(find.text('尚無 PRESENCE evidence'), findsOneWidget);

    // event log section
    expect(find.text('事件 log（最新 50）'), findsOneWidget);
  });
}
