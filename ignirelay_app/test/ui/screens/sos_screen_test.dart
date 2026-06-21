// A8 — SosScreen widget test: the long-press(1.5s) → choose → 5s countdown →
// cancel / send state machine (DoD D1). The receiver projection→stream path is
// covered by v2_inbound_projector_test; here we assert the empty receiver state.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:ignirelay_app/app/controllers/event_stream.dart';
import 'package:ignirelay_app/app/controllers/sos_controller.dart';
import 'package:ignirelay_app/app/db/database_helper.dart';
import 'package:ignirelay_app/app/mesh/mesh_event_handler.dart';
import 'package:ignirelay_app/app/services/anon_identity.dart';
import 'package:ignirelay_app/app/controllers/active_field_controller.dart';
import 'package:ignirelay_app/app/services/event_decoder.dart';
import 'package:ignirelay_app/app/services/event_publisher_v2_facade.dart';
import 'package:ignirelay_app/app/services/event_store.dart';
import 'package:ignirelay_app/app/services/field_session_store.dart';
import 'package:ignirelay_app/app/services/location_evidence_builder.dart';
import 'package:ignirelay_app/app/services/peer_capability_registry.dart';
import 'package:ignirelay_app/l10n/generated/app_localizations.dart';
import 'package:ignirelay_app/ui/screens/sos/sos_hold_button.dart';
import 'package:ignirelay_app/ui/screens/sos/sos_screen.dart';

class _Kv implements SecureKvStore {
  final Map<String, String> _m = {};
  @override
  Future<String?> read(String k) async => _m[k];
  @override
  Future<void> write(String k, String v) async => _m[k] = v;
  @override
  Future<void> delete(String k) async => _m.remove(k);
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    DatabaseHelper.testDatabasePathOverride = inMemoryDatabasePath;
  });

  setUp(() async {
    await DatabaseHelper().resetForTest();
  });

  Future<({SosController sos, EventStream events})> harness(
      {required Duration countdown}) async {
    final registry = PeerCapabilityRegistry(
      helloTimeout: const Duration(seconds: 5),
    );
    final facade =
        EventPublisherV2Facade(registry: registry, db: DatabaseHelper());
    final field = ActiveFieldController(
      store: FieldSessionStore(db: DatabaseHelper(), secureStore: _Kv()),
    );
    await field.joinBySecret(
      Uint8List.fromList(List<int>.filled(32, 0x44)),
      displayName: 'f',
    );
    facade.attachActiveField(field);
    final sos = SosController(
      facade: facade,
      locationBuilder: LocationEvidenceBuilder(currentLocation: () => null),
      countdownDuration: countdown,
    );
    final events = EventStream(
      handler: MeshEventHandler(),
      decoder: EventDecoder(),
      store: EventStore(databaseHelper: DatabaseHelper()),
    );
    addTearDown(() async {
      sos.dispose();
      await events.dispose();
      await facade.dispose();
      await registry.dispose();
      field.dispose();
    });
    return (sos: sos, events: events);
  }

  Widget wrap(SosController sos, EventStream events,
          {Locale locale = const Locale('zh')}) =>
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SosController>.value(value: sos),
          Provider<EventStream>.value(value: events),
        ],
        child: MaterialApp(
          locale: locale,
          supportedLocales: S.supportedLocales,
          localizationsDelegates: S.localizationsDelegates,
          home: const SosScreen(),
        ),
      );

  // Drive the 1.5s press-and-hold to completion and pick a severity.
  Future<void> holdAndChoose(WidgetTester tester, String choiceLabel) async {
    final gesture =
        await tester.startGesture(tester.getCenter(find.byType(SosHoldButton)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1600)); // hold completes
    await tester.pumpAndSettle(); // severity chooser opens
    await gesture.up();
    await tester.tap(find.text(choiceLabel));
    await tester.pumpAndSettle();
  }

  testWidgets('renders the trigger + empty receiver state', (tester) async {
    final h = await harness(countdown: const Duration(seconds: 5));
    await tester.pumpWidget(wrap(h.sos, h.events));
    await tester.pump();

    expect(find.text('緊急求救'), findsOneWidget);
    expect(find.byType(SosHoldButton), findsOneWidget);
    expect(find.textContaining('目前沒有收到求救訊號'), findsOneWidget);
  });

  testWidgets('hold 1.5s → choose → countdown → cancel (misfire guard)',
      (tester) async {
    final h = await harness(countdown: const Duration(seconds: 5));
    await tester.pumpWidget(wrap(h.sos, h.events));
    await tester.pump();

    await holdAndChoose(tester, '受困（最高優先）');
    expect(h.sos.isCountingDown, isTrue);
    expect(find.text('受困求救'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pump();
    expect(h.sos.phase, SosPhase.idle);
    expect(find.byType(SosHoldButton), findsOneWidget); // back to the trigger
  });

  testWidgets('countdown elapses → SOS sent banner + 我安全了', (tester) async {
    final h = await harness(countdown: const Duration(milliseconds: 200));
    await tester.pumpWidget(wrap(h.sos, h.events));
    await tester.pump();

    // The long-press→choose→countdown path is covered by the test above; here
    // we focus on the countdown-elapses→sent transition. runAsync gives the
    // real countdown Timer AND the no-isolate FFI DB write real time so the
    // publish actually completes.
    await tester.runAsync(() async {
      h.sos.arm(SosSeverity.injured);
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
    await tester.pumpAndSettle(); // rebuild into the "sent" banner

    expect(h.sos.hasActiveSos, isTrue);
    expect(find.text('你已發出求救'), findsOneWidget);
    expect(find.text('我安全了'), findsOneWidget);
  });

  testWidgets('en: trigger + empty receiver render English (UI-H2c)',
      (tester) async {
    final h = await harness(countdown: const Duration(seconds: 5));
    await tester.pumpWidget(wrap(h.sos, h.events, locale: const Locale('en')));
    await tester.pump();

    expect(find.text('Emergency SOS'), findsOneWidget);
    expect(find.textContaining('No SOS signals received'), findsOneWidget);
    expect(find.text('緊急求救'), findsNothing);
  });

  // ── UI-H3 — large-text / text-scale stress ─────────────────────────────────
  // SOS is the highest-stakes screen: it must stay legible and unbroken at the
  // 1.45 app factor AND an effective ~2.0 composite (system × app), on a narrow
  // phone width where horizontal overflow bites first. Drives the trigger card
  // and the countdown card (big number + title row + ≥64dp cancel).
  Widget wrapScaled(SosController sos, EventStream events, double scale) =>
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SosController>.value(value: sos),
          Provider<EventStream>.value(value: events),
        ],
        child: MaterialApp(
          locale: const Locale('zh'),
          supportedLocales: S.supportedLocales,
          localizationsDelegates: S.localizationsDelegates,
          home: Builder(
            builder: (ctx) => MediaQuery(
              data: MediaQuery.of(ctx)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: const SosScreen(),
            ),
          ),
        ),
      );

  testWidgets('large text (UI-H3): trigger + countdown survive 1.15–2.0',
      (tester) async {
    tester.view.physicalSize = const Size(360, 820);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final h = await harness(countdown: const Duration(seconds: 5));
    for (final scale in const [1.15, 1.30, 1.45, 2.0]) {
      await tester.pumpWidget(wrapScaled(h.sos, h.events, scale));
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'SOS trigger @ $scale');

      h.sos.arm(SosSeverity.trapped); // → countdown card
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'SOS countdown @ $scale');

      h.sos.cancelCountdown();
      await tester.pump();
    }
  });

  // ── A11-live-fix — receiver mount backfill ─────────────────────────────────
  // A SOS that landed in the read-model while this page was NOT in the
  // foreground must show when the page is (re)opened. Live broadcast streams do
  // not replay, so the fix hydrates from recentSos()/recentSosResolutions() on
  // mount. Confirmed on real devices (2026-06-21 A11 live test): with the SOS
  // page open the alert showed; navigating away+back showed 附近求救（0） while
  // the row was still in Event_Logs — this guards that regression.
  Widget wrapBackfill(
    SosController sos, {
    List<SosAlert> alerts = const [],
    List<SosResolved> resolutions = const [],
  }) =>
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SosController>.value(value: sos),
        ],
        child: MaterialApp(
          locale: const Locale('zh'),
          supportedLocales: S.supportedLocales,
          localizationsDelegates: S.localizationsDelegates,
          home: SosScreen(
            alertSource: const Stream<SosAlert>.empty(),
            resolvedSource: const Stream<SosResolved>.empty(),
            alertBackfill: () async => alerts,
            resolvedBackfill: () async => resolutions,
          ),
        ),
      );

  // sender_pub_key 0xAB 0xCD 0x12 0x34 → hex 'abcd1234' (matches SosResolved).
  final author = Uint8List.fromList([0xAB, 0xCD, 0x12, 0x34]);
  SosAlert sosAt(DateTime t, {String eventId = 'sos-1'}) => SosAlert(
        eventId: eventId,
        urgency: 3, // TRAPPED → 受困
        description: '',
        lat: 25.0339805,
        lng: 121.5654177,
        senderPubKey: author,
        timestamp: t,
      );

  testWidgets('mount backfill shows a SOS already in the read-model',
      (tester) async {
    final h = await harness(countdown: const Duration(seconds: 5));
    await tester.pumpWidget(wrapBackfill(
      h.sos,
      alerts: [sosAt(DateTime(2026, 6, 21, 23, 24))],
    ));
    await tester.pumpAndSettle();

    expect(find.text('附近求救（1）'), findsOneWidget);
    expect(find.textContaining('目前沒有收到求救訊號'), findsNothing);
    expect(find.text('受困'), findsWidgets); // alert chip (+ maybe title)
    expect(find.textContaining('25.03398'), findsOneWidget); // received coords
  });

  testWidgets('backfill: SAFE after SOS (same author) → 已解除', (tester) async {
    final h = await harness(countdown: const Duration(seconds: 5));
    await tester.pumpWidget(wrapBackfill(
      h.sos,
      alerts: [sosAt(DateTime(2026, 6, 21, 23, 24))],
      resolutions: [
        SosResolved(
          authorKeyHex: 'abcd1234',
          timestamp: DateTime(2026, 6, 21, 23, 26), // later than the SOS
        ),
      ],
    ));
    await tester.pumpAndSettle();

    expect(find.text('附近求救（1）'), findsOneWidget);
    expect(find.text('已解除'), findsOneWidget);
  });

  testWidgets('backfill: SOS after SAFE (same author) → still active',
      (tester) async {
    final h = await harness(countdown: const Duration(seconds: 5));
    await tester.pumpWidget(wrapBackfill(
      h.sos,
      alerts: [sosAt(DateTime(2026, 6, 21, 23, 26))], // later than the SAFE
      resolutions: [
        SosResolved(
          authorKeyHex: 'abcd1234',
          timestamp: DateTime(2026, 6, 21, 23, 24),
        ),
      ],
    ));
    await tester.pumpAndSettle();

    expect(find.text('附近求救（1）'), findsOneWidget);
    expect(find.text('已解除'), findsNothing); // newer SOS un-resolves
  });
}
