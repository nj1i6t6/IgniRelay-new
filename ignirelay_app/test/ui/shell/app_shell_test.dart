// UI-F1 — AppShell smoke tests.
//
// Locks the UI-F1 DoD in widget tests (the four hard requirements pinned by
// UI-F0 §4.0.1 F0-1):
//   • production home is the AppShell, NOT DebugShell;
//   • the no-field entry shows 加入場域 / 建立場域 / 先看功能;
//   • the five tab labels are exactly 安全 / 位置 / 事件 / 協助 / 我的 (no 地圖);
//   • global SOS is reachable from every tab.
//
// AppShell only reads ActiveFieldController (a ChangeNotifier) and navigates on
// tap, so the harness just provides a real in-memory ActiveFieldController —
// no facade / mesh / SOS providers are needed (we never tap INTO SosScreen /
// FieldScreen here). kDebugMode is true under `flutter test`, so the
// developer-diagnostics entry renders and can be asserted.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:ignirelay_app/app/controllers/active_field_controller.dart';
import 'package:ignirelay_app/app/db/database_helper.dart';
import 'package:ignirelay_app/app/services/anon_identity.dart';
import 'package:ignirelay_app/app/services/field_session_store.dart';
import 'package:ignirelay_app/ui/shell/app_shell.dart';
import 'package:ignirelay_app/ui/shell/debug_shell.dart';

/// In-memory secure store so the field secret never touches the platform plugin.
class _FakeKvStore implements SecureKvStore {
  final Map<String, String> _m = {};
  @override
  Future<String?> read(String key) async => _m[key];
  @override
  Future<void> write(String key, String value) async => _m[key] = value;
  @override
  Future<void> delete(String key) async => _m.remove(key);
}

Widget _wrap(Widget child, ActiveFieldController field) {
  return ListenableProvider<ActiveFieldController>.value(
    value: field,
    child: MaterialApp(home: child),
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
    final field = await _makeField(joined: false);
    addTearDown(field.dispose);

    await tester.pumpWidget(_wrap(const AppShell(), field));
    await tester.pump();

    expect(find.byType(NoFieldEntry), findsOneWidget);
    expect(find.text('加入場域'), findsOneWidget);
    expect(find.text('建立場域'), findsOneWidget);
    expect(find.text('先看功能'), findsOneWidget);
    // production home is never the debug shell.
    expect(find.byType(DebugShell), findsNothing);
  });

  testWidgets('active field renders the five tabs exactly, no 地圖, no DebugShell',
      (tester) async {
    final field = await _makeField(joined: true);
    addTearDown(field.dispose);

    await tester.pumpWidget(_wrap(const AppShell(), field));
    await tester.pump();

    expect(find.byType(NoFieldEntry), findsNothing);
    for (final label in kAppShellTabLabels) {
      expect(find.text(label), findsOneWidget, reason: 'tab "$label"');
    }
    // the five labels are exactly these — and never the retired 地圖 tab.
    expect(kAppShellTabLabels, <String>['安全', '位置', '事件', '協助', '我的']);
    expect(find.text('地圖'), findsNothing);
    expect(find.byType(DebugShell), findsNothing);
  });

  testWidgets('global SOS is reachable from every tab', (tester) async {
    final field = await _makeField(joined: true);
    addTearDown(field.dispose);

    await tester.pumpWidget(_wrap(const AppShell(), field));
    await tester.pump();

    for (final label in kAppShellTabLabels) {
      await tester.tap(find.text(label));
      await tester.pump();
      expect(find.text('SOS'), findsOneWidget,
          reason: 'global SOS missing on "$label" tab');
    }
  });

  testWidgets('我的 tab exposes the debug-only diagnostics entry (debug build)',
      (tester) async {
    final field = await _makeField(joined: true);
    addTearDown(field.dispose);

    await tester.pumpWidget(_wrap(const AppShell(), field));
    await tester.pump();

    // Before selecting 我的, the (offstage) diagnostics entry is not found.
    expect(find.text('開發者診斷（DebugShell）'), findsNothing);

    await tester.tap(find.text('我的'));
    await tester.pump();

    // kDebugMode is true under flutter test → the entry renders. It only ever
    // navigates via the debug-only named route; the shell never embeds
    // DebugShell as a production surface.
    expect(find.text('開發者診斷（DebugShell）'), findsOneWidget);
    expect(find.byType(DebugShell), findsNothing);
  });
}
