// A7 — FieldScreen widget test: empty state, code-input join (the upgraded A5
// hex dialog, now also accepting an IGNI1 QR string), active-field summary, and
// QR display. The camera scan path (FieldScanScreen / mobile_scanner) needs a
// real camera and is verified by the A11 USER-GATE, not here.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:ignirelay_app/app/controllers/active_field_controller.dart';
import 'package:ignirelay_app/app/db/database_helper.dart';
import 'package:ignirelay_app/app/services/anon_identity.dart';
import 'package:ignirelay_app/app/services/field_qr_codec.dart';
import 'package:ignirelay_app/app/services/field_session_store.dart';
import 'package:ignirelay_app/l10n/generated/app_localizations.dart';
import 'package:ignirelay_app/ui/screens/field/field_screen.dart';

class _FakeKvStore implements SecureKvStore {
  final Map<String, String> _m = {};
  @override
  Future<String?> read(String key) async => _m[key];
  @override
  Future<void> write(String key, String value) async => _m[key] = value;
  @override
  Future<void> delete(String key) async => _m.remove(key);
}

Future<ActiveFieldController> _makeController() async => ActiveFieldController(
      store: FieldSessionStore(
        db: DatabaseHelper(),
        secureStore: _FakeKvStore(),
      ),
    );

Widget _wrap(ActiveFieldController field,
        {Locale locale = const Locale('zh')}) =>
    MultiProvider(
      providers: [
        ListenableProvider<ActiveFieldController>.value(value: field),
      ],
      child: MaterialApp(
        locale: locale,
        supportedLocales: S.supportedLocales,
        localizationsDelegates: S.localizationsDelegates,
        home: const FieldScreen(),
      ),
    );

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

  testWidgets('empty state when no field joined', (tester) async {
    final field = await _makeController();
    addTearDown(field.dispose);
    await tester.pumpWidget(_wrap(field));
    await tester.pump();

    expect(find.text('場域'), findsOneWidget);
    expect(find.text('尚未加入任何場域'), findsOneWidget);
    expect(find.text('掃碼加入'), findsOneWidget);
    expect(find.text('輸入代碼'), findsOneWidget);
    expect(find.text('建立新場域'), findsOneWidget);
    // No joined-field section.
    expect(find.textContaining('已加入的場域'), findsNothing);
  });

  testWidgets('en: empty state renders English (UI-H2b)', (tester) async {
    final field = await _makeController();
    addTearDown(field.dispose);
    await tester.pumpWidget(_wrap(field, locale: const Locale('en')));
    await tester.pump();

    expect(find.text('Field'), findsOneWidget);
    expect(find.text('Not in any field yet'), findsOneWidget);
    expect(find.text('Scan to join'), findsOneWidget);
    expect(find.text('Enter code'), findsOneWidget);
    expect(find.text('Create field'), findsOneWidget);
    expect(find.text('場域'), findsNothing);
    expect(find.text('掃碼加入'), findsNothing);
  });

  testWidgets('active field summary + joined list render', (tester) async {
    final field = await _makeController();
    addTearDown(field.dispose);
    await field.joinBySecret(
      Uint8List.fromList(List<int>.filled(32, 0x5C)),
      displayName: '中正紀念堂站',
    );

    await tester.pumpWidget(_wrap(field));
    await tester.pump();

    // Active card: name + 作用中 chip. Joined (not created) ⇒ participant 成員.
    expect(find.text('中正紀念堂站'), findsWidgets);
    expect(find.text('作用中'), findsOneWidget);
    expect(find.text('已加入的場域（1）'), findsOneWidget);
    expect(find.text('成員'), findsWidgets);
  });

  testWidgets('code input joins from a valid IGNI1 code', (tester) async {
    final field = await _makeController();
    addTearDown(field.dispose);
    await tester.pumpWidget(_wrap(field));
    await tester.pump();

    final code = FieldQrCodec.encode(FieldQrPayload(
      secret: Uint8List.fromList(List<int>.generate(32, (i) => i)),
      displayName: '南港展覽館',
    ));

    await tester.tap(find.text('輸入代碼'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), code);
    await tester.tap(find.text('加入'));
    await tester.pumpAndSettle();

    expect(field.joinedFieldCount, 1);
    expect(field.active?.displayName, '南港展覽館');
    expect(find.text('南港展覽館'), findsWidgets);
  });

  testWidgets('bad code prompts and does not crash or join', (tester) async {
    final field = await _makeController();
    addTearDown(field.dispose);
    await tester.pumpWidget(_wrap(field));
    await tester.pump();

    // Well-formed prefix but a corrupt secret segment → decode error prompt.
    await tester.tap(find.text('輸入代碼'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'IGNI1:!!!notb64!!!:name');
    await tester.tap(find.text('加入'));
    await tester.pumpAndSettle();

    expect(field.joinedFieldCount, 0);
    expect(find.textContaining('密鑰格式錯誤'), findsOneWidget);
  });

  testWidgets('QR sheet shows a QrImageView for an owned field', (tester) async {
    final field = await _makeController();
    addTearDown(field.dispose);
    // Created locally ⇒ owner ⇒ the row exposes the 顯示 QR action.
    await field.createField(displayName: 'QR 場域');
    await tester.pumpWidget(_wrap(field));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.qr_code_2));
    await tester.pumpAndSettle();

    expect(find.byType(QrImageView), findsOneWidget);
    expect(find.text('完成'), findsOneWidget);
  });

  testWidgets('owner-only share: owned row shows 顯示 QR, participant row hides it',
      (tester) async {
    final field = await _makeController();
    addTearDown(field.dispose);
    await field.createField(displayName: '我建立的'); // owner
    await field.joinBySecret(
      Uint8List.fromList(List<int>.filled(32, 0x5C)),
      displayName: '我加入的',
    ); // participant
    await tester.pumpWidget(_wrap(field));
    await tester.pump();

    // Exactly one share button across the two joined rows — the owner's.
    expect(find.byIcon(Icons.qr_code_2), findsOneWidget);
    // Both roles are visible.
    expect(find.text('主辦'), findsWidgets);
    expect(find.text('成員'), findsWidgets);
  });

  // ── UI-H3 — large-text / text-scale stress ─────────────────────────────────
  // A joined field renders the active card (name + role chip + 作用中 chip) and
  // a joined-row (name + role chip + QR action) — name/chip rows that can
  // overflow under 1.45 / effective 2.0 on a narrow phone width. A long field
  // name pushes the worst case.
  testWidgets('large text (UI-H3): active + joined rows survive 1.45 / 2.0',
      (tester) async {
    tester.view.physicalSize = const Size(360, 820);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final field = await _makeController();
    addTearDown(field.dispose);
    await field.createField(displayName: '中正紀念堂臨時避難收容場域站點'); // long name

    for (final scale in const [1.45, 2.0]) {
      await tester.pumpWidget(MultiProvider(
        providers: [
          ListenableProvider<ActiveFieldController>.value(value: field),
        ],
        child: MaterialApp(
          locale: const Locale('zh'),
          supportedLocales: S.supportedLocales,
          localizationsDelegates: S.localizationsDelegates,
          home: Builder(
            builder: (ctx) => MediaQuery(
              data: MediaQuery.of(ctx)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: const FieldScreen(),
            ),
          ),
        ),
      ));
      await tester.pump();
      expect(find.byType(FieldScreen), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'field overflow @ $scale');
    }
  });
}
