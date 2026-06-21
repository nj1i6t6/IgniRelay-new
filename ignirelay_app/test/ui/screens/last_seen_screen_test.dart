// A10 / A10b — LastSeenScreen widget tests. Drives the typed streams + clock +
// local-origin via the injection seams so no EventStream / LocalPositionSource
// provider and no real time are needed.
//
// Covers: the empty state + §3.6 copy rule (A10, NEVER 「目前位置」); a rendered
// estimate card (A10); the 列表⇄雷達 toggle (A10b D2); the "no local position"
// degrade path (A10b D3); an SOS alert surfacing as a card; and the SOS-resolve
// (SAFE) path clearing that author's SOS (A11 fix).

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ignirelay_app/app/controllers/event_stream.dart';
import 'package:ignirelay_app/app/services/position_estimator.dart';
import 'package:ignirelay_app/l10n/generated/app_localizations.dart';
import 'package:ignirelay_app/ui/screens/position/last_seen_screen.dart';
import 'package:ignirelay_app/ui/screens/position/relative_radar.dart';
import 'package:ignirelay_app/ui/widgets/status_chip.dart';

void main() {
  // Shared stream controllers + helper so each test wires all four seams.
  late StreamController<PresenceUpdate> pres;
  late StreamController<CheckpointCrossing> cp;
  late StreamController<SosAlert> sos;
  late StreamController<SosResolved> sosRes;

  setUp(() {
    pres = StreamController<PresenceUpdate>.broadcast();
    cp = StreamController<CheckpointCrossing>.broadcast();
    sos = StreamController<SosAlert>.broadcast();
    sosRes = StreamController<SosResolved>.broadcast();
  });
  tearDown(() {
    pres.close();
    cp.close();
    sos.close();
    sosRes.close();
  });

  Widget screen({
    DateTime Function()? now,
    PositionEstimate? Function()? localEstimate,
    Locale locale = const Locale('zh'),
    Future<List<PresenceUpdate>> Function()? presenceBackfill,
    Future<List<CheckpointCrossing>> Function()? checkpointBackfill,
    Future<List<SosAlert>> Function()? sosBackfill,
    Future<List<SosResolved>> Function()? sosResolvedBackfill,
  }) =>
      MaterialApp(
        locale: locale,
        supportedLocales: S.supportedLocales,
        localizationsDelegates: S.localizationsDelegates,
        home: LastSeenScreen(
          presenceSource: pres.stream,
          checkpointSource: cp.stream,
          sosSource: sos.stream,
          sosResolvedSource: sosRes.stream,
          // Mount backfill seams default to empty so these stream-driven tests
          // never reach for an EventStream provider (A11-debug-4-fix).
          presenceBackfill: presenceBackfill ?? () async => <PresenceUpdate>[],
          checkpointBackfill:
              checkpointBackfill ?? () async => <CheckpointCrossing>[],
          sosBackfill: sosBackfill ?? () async => <SosAlert>[],
          sosResolvedBackfill:
              sosResolvedBackfill ?? () async => <SosResolved>[],
          now: now,
          localEstimate: localEstimate,
          refreshInterval: Duration.zero, // no timer
        ),
      );

  // Helper hex of a fake sender_pub_key (the key both SosAlert and SosResolved
  // share). LastSeenScreen pads each byte to two hex chars.
  String hexOf(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  testWidgets('empty state renders the 推估 hint (no 目前位置 copy)',
      (tester) async {
    await tester.pumpWidget(screen());
    await tester.pump();

    expect(find.text('最後可信位置'), findsOneWidget); // header only
    expect(find.textContaining('尚無位置證據'), findsOneWidget);
    expect(find.textContaining('目前位置'), findsNothing);
  });

  testWidgets('a PRESENCE fix renders a 最後可信位置 card with confidence',
      (tester) async {
    final now = DateTime(2026, 6, 15, 12, 0, 0);
    await tester.pumpWidget(screen(now: () => now));
    await tester.pump();

    pres.add(PresenceUpdate(
      eventId: 'v2-1',
      anon8: 'a0a1a2a3',
      source: 1,
      lat: 25.0339805,
      lng: 121.5654177,
      accuracyM: 12,
      observedAt: now.subtract(const Duration(seconds: 30)),
    ));
    await tester.pump(); // deliver the stream event
    await tester.pump(); // rebuild after setState

    expect(find.text('a0a1a2a3'), findsOneWidget);
    // 「最後可信位置」appears twice now: page header + the card's section label.
    expect(find.text('最後可信位置'), findsWidgets);
    expect(find.text('可信度 高'), findsOneWidget); // 30s old → HIGH
    expect(find.textContaining('25.03398'), findsOneWidget);
    expect(find.textContaining('目前位置'), findsNothing);
  });

  testWidgets('列表⇄雷達 toggle: radar shows when a local origin exists',
      (tester) async {
    final now = DateTime(2026, 6, 15, 12, 0, 0);
    // A fixed local origin so the radar is available.
    const origin = PositionEstimate(
      lat: 25.0,
      lng: 121.0,
      confidence: PositionConfidence.high,
      uncertaintyM: 15,
      ageSeconds: 0,
    );
    await tester.pumpWidget(
      screen(now: () => now, localEstimate: () => origin),
    );
    await tester.pump();

    pres.add(PresenceUpdate(
      eventId: 'v2-1',
      anon8: 'b0b1b2b3',
      source: 1,
      lat: 25.01,
      lng: 121.0,
      accuracyM: 10,
      observedAt: now.subtract(const Duration(seconds: 10)),
    ));
    await tester.pump();
    await tester.pump();

    // Default = list → the card is visible, no radar.
    expect(find.byType(RelativeRadar), findsNothing);
    expect(find.text('b0b1b2b3'), findsOneWidget);

    // Switch to radar.
    await tester.tap(find.text('雷達'));
    await tester.pump();
    expect(find.byType(RelativeRadar), findsOneWidget);
    expect(find.textContaining('需要本機位置'), findsNothing);

    // Switch back to list.
    await tester.tap(find.text('列表'));
    await tester.pump();
    expect(find.byType(RelativeRadar), findsNothing);
    expect(find.text('b0b1b2b3'), findsOneWidget);
  });

  testWidgets('no local position → radar degrades to list with a hint',
      (tester) async {
    final now = DateTime(2026, 6, 15, 12, 0, 0);
    await tester.pumpWidget(
      // localEstimate returns null → "no local position".
      screen(now: () => now, localEstimate: () => null),
    );
    await tester.pump();

    pres.add(PresenceUpdate(
      eventId: 'v2-1',
      anon8: 'c0c1c2c3',
      source: 1,
      lat: 25.01,
      lng: 121.0,
      observedAt: now.subtract(const Duration(seconds: 10)),
    ));
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('雷達'));
    await tester.pump();

    // Degraded: hint shown, no radar, list still visible.
    expect(find.textContaining('需要本機位置才能顯示相對方位'), findsOneWidget);
    expect(find.byType(RelativeRadar), findsNothing);
    expect(find.text('c0c1c2c3'), findsOneWidget);
  });

  testWidgets('an SOS alert surfaces as a card with an SOS chip',
      (tester) async {
    final now = DateTime(2026, 6, 15, 12, 0, 0);
    await tester.pumpWidget(screen(now: () => now));
    await tester.pump();

    sos.add(SosAlert(
      eventId: 'sos-1',
      urgency: 3,
      description: '受困',
      lat: 25.02,
      lng: 121.01,
      timestamp: now.subtract(const Duration(seconds: 20)),
    ));
    await tester.pump();
    await tester.pump();

    expect(find.widgetWithText(StatusChip, 'SOS'), findsOneWidget);
    expect(find.textContaining('目前位置'), findsNothing);
  });

  testWidgets('A11 fix: SAFE (SosResolved) clears that author\'s SOS',
      (tester) async {
    final now = DateTime(2026, 6, 15, 12, 0, 0);
    await tester.pumpWidget(screen(now: () => now));
    await tester.pump();

    // SOS keyed by sender_pub_key — the SAME identity SosResolved carries.
    final pubKey = Uint8List.fromList(const [0xAB, 0xCD, 0xEF, 0x01, 0x23]);
    sos.add(SosAlert(
      eventId: 'sos-9',
      urgency: 3,
      description: '受困',
      lat: 25.02,
      lng: 121.01,
      senderPubKey: pubKey,
      timestamp: now.subtract(const Duration(seconds: 20)),
    ));
    await tester.pump();
    await tester.pump();
    expect(find.widgetWithText(StatusChip, 'SOS'), findsOneWidget);

    // The author reports SAFE → its SOS leaves the position view.
    sosRes.add(SosResolved(
      authorKeyHex: hexOf(pubKey),
      timestamp: now.subtract(const Duration(seconds: 5)),
    ));
    await tester.pump();
    await tester.pump();
    expect(find.widgetWithText(StatusChip, 'SOS'), findsNothing,
        reason: 'resolved SOS must no longer show on the position screen');
  });

  testWidgets('A11 fix: a SAFE for a DIFFERENT author leaves the SOS standing',
      (tester) async {
    final now = DateTime(2026, 6, 15, 12, 0, 0);
    await tester.pumpWidget(screen(now: () => now));
    await tester.pump();

    final pubKey = Uint8List.fromList(const [0x11, 0x22, 0x33, 0x44]);
    sos.add(SosAlert(
      eventId: 'sos-7',
      urgency: 3,
      description: '受困',
      lat: 25.02,
      lng: 121.01,
      senderPubKey: pubKey,
      timestamp: now.subtract(const Duration(seconds: 20)),
    ));
    await tester.pump();
    await tester.pump();
    expect(find.widgetWithText(StatusChip, 'SOS'), findsOneWidget);

    // A resolve for someone else must not clear this SOS.
    sosRes.add(SosResolved(
      authorKeyHex: hexOf(Uint8List.fromList(const [0x99, 0x88])),
      timestamp: now,
    ));
    await tester.pump();
    await tester.pump();
    expect(find.widgetWithText(StatusChip, 'SOS'), findsOneWidget);
  });

  testWidgets('a CHECKPOINT (anchor) subject draws as a node on the radar',
      (tester) async {
    final now = DateTime(2026, 6, 15, 12, 0, 0);
    const origin = PositionEstimate(
      lat: 25.0,
      lng: 121.0,
      confidence: PositionConfidence.high,
      uncertaintyM: 15,
      ageSeconds: 0,
    );
    await tester.pumpWidget(
      screen(now: () => now, localEstimate: () => origin),
    );
    await tester.pump();

    cp.add(CheckpointCrossing(
      eventId: 'cp-1',
      checkpointId: 'CP-7',
      anon8: 'd0d1d2d3',
      lat: 25.01,
      lng: 121.0,
      observedAt: now.subtract(const Duration(seconds: 10)),
    ));
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('雷達'));
    await tester.pump();

    final nodes =
        find.byWidgetPredicate((w) => w is RadarMarker && w.isNode);
    expect(nodes, findsOneWidget);
  });

  testWidgets('origin lost while in radar mode → degrades to list + hint',
      (tester) async {
    final now = DateTime(2026, 6, 15, 12, 0, 0);
    PositionEstimate? originVal = const PositionEstimate(
      lat: 25.0,
      lng: 121.0,
      confidence: PositionConfidence.high,
      uncertaintyM: 15,
      ageSeconds: 0,
    );
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('zh'),
      supportedLocales: S.supportedLocales,
      localizationsDelegates: S.localizationsDelegates,
      home: LastSeenScreen(
        presenceSource: pres.stream,
        checkpointSource: cp.stream,
        sosSource: sos.stream,
        sosResolvedSource: sosRes.stream,
        presenceBackfill: () async => <PresenceUpdate>[],
        checkpointBackfill: () async => <CheckpointCrossing>[],
        sosBackfill: () async => <SosAlert>[],
        sosResolvedBackfill: () async => <SosResolved>[],
        now: () => now,
        localEstimate: () => originVal,
        refreshInterval: Duration.zero,
      ),
    ));
    await tester.pump();

    pres.add(PresenceUpdate(
      eventId: 'v2-1',
      anon8: 'e0e1e2e3',
      source: 1,
      lat: 25.01,
      lng: 121.0,
      observedAt: now.subtract(const Duration(seconds: 10)),
    ));
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('雷達'));
    await tester.pump();
    expect(find.byType(RelativeRadar), findsOneWidget); // radar active

    // Lose the local fix; a fresh event forces a rebuild (no user toggle).
    originVal = null;
    pres.add(PresenceUpdate(
      eventId: 'v2-2',
      anon8: 'e0e1e2e3',
      source: 1,
      lat: 25.02,
      lng: 121.0,
      observedAt: now.subtract(const Duration(seconds: 5)),
    ));
    await tester.pump();
    await tester.pump();

    expect(find.byType(RelativeRadar), findsNothing);
    expect(find.textContaining('需要本機位置才能顯示相對方位'), findsOneWidget);
  });

  testWidgets('en: empty state renders English copy (UI-H2c)', (tester) async {
    await tester.pumpWidget(screen(locale: const Locale('en')));
    await tester.pump();

    expect(find.text('Last trusted position'), findsOneWidget); // header
    expect(find.textContaining('No position evidence yet'), findsOneWidget);
    expect(find.textContaining('目前位置'), findsNothing);
    expect(find.text('最後可信位置'), findsNothing);
  });

  // ── A11-debug-4-fix — mount backfill (read-model hydrate) ───────────────────
  // The view must populate on mount from the Event_Logs read-model, not stay
  // blank after a restart until the next live event.

  testWidgets('mount backfill renders PRESENCE with NO live event',
      (tester) async {
    final now = DateTime(2026, 6, 15, 12, 0, 0);
    await tester.pumpWidget(screen(
      now: () => now,
      presenceBackfill: () async => [
        PresenceUpdate(
          eventId: 'v2-bf-1',
          anon8: 'f0f1f2f3',
          source: 1,
          lat: 25.05,
          lng: 121.55,
          accuracyM: 10,
          observedAt: now.subtract(const Duration(seconds: 30)),
        ),
      ],
    ));
    await tester.pump(); // let _hydrate() resolve
    await tester.pump(); // rebuild after setState

    expect(find.text('f0f1f2f3'), findsOneWidget);
    expect(find.textContaining('25.05'), findsOneWidget);
    expect(find.textContaining('目前位置'), findsNothing);
  });

  testWidgets('mount backfill renders SOS WITH coordinates (received_lat/lng)',
      (tester) async {
    final now = DateTime(2026, 6, 15, 12, 0, 0);
    await tester.pumpWidget(screen(
      now: () => now,
      sosBackfill: () async => [
        SosAlert(
          eventId: 'v2-sos-bf',
          urgency: 3,
          description: '受困',
          lat: 25.0339805,
          lng: 121.5654177,
          senderPubKey: Uint8List.fromList(const [0x0A, 0x0B, 0x0C, 0x0D]),
          timestamp: now.subtract(const Duration(seconds: 20)),
        ),
      ],
    ));
    await tester.pump();
    await tester.pump();

    expect(find.widgetWithText(StatusChip, 'SOS'), findsOneWidget);
    expect(find.textContaining('25.03398'), findsOneWidget); // coords surfaced
    expect(find.textContaining('目前位置'), findsNothing);
  });

  testWidgets('backfill timeline: old SOS + later SAFE → SOS cleared',
      (tester) async {
    final now = DateTime(2026, 6, 15, 12, 0, 0);
    final pubKey = Uint8List.fromList(const [0x22, 0x33, 0x44, 0x55]);
    await tester.pumpWidget(screen(
      now: () => now,
      sosBackfill: () async => [
        SosAlert(
          eventId: 'sos-old',
          urgency: 3,
          description: '受困',
          lat: 25.02,
          lng: 121.01,
          senderPubKey: pubKey,
          timestamp: now.subtract(const Duration(minutes: 5)), // older
        ),
      ],
      sosResolvedBackfill: () async => [
        SosResolved(
          authorKeyHex: hexOf(pubKey),
          timestamp: now.subtract(const Duration(minutes: 1)), // later SAFE
        ),
      ],
    ));
    await tester.pump();
    await tester.pump();

    expect(find.widgetWithText(StatusChip, 'SOS'), findsNothing,
        reason: 'a later SAFE supersedes the older SOS (author-LWW)');
  });

  testWidgets('backfill timeline: old SAFE + later SOS → SOS shown',
      (tester) async {
    final now = DateTime(2026, 6, 15, 12, 0, 0);
    final pubKey = Uint8List.fromList(const [0x66, 0x77, 0x88, 0x99]);
    await tester.pumpWidget(screen(
      now: () => now,
      sosBackfill: () async => [
        SosAlert(
          eventId: 'sos-new',
          urgency: 3,
          description: '受困',
          lat: 25.02,
          lng: 121.01,
          senderPubKey: pubKey,
          timestamp: now.subtract(const Duration(minutes: 1)), // later SOS
        ),
      ],
      sosResolvedBackfill: () async => [
        SosResolved(
          authorKeyHex: hexOf(pubKey),
          timestamp: now.subtract(const Duration(minutes: 5)), // older SAFE
        ),
      ],
    ));
    await tester.pump();
    await tester.pump();

    expect(find.widgetWithText(StatusChip, 'SOS'), findsOneWidget,
        reason: 'a later SOS stands despite an older SAFE');
  });

  testWidgets('same eventId via backfill + live is applied once (dedup)',
      (tester) async {
    final now = DateTime(2026, 6, 15, 12, 0, 0);
    await tester.pumpWidget(screen(
      now: () => now,
      presenceBackfill: () async => [
        PresenceUpdate(
          eventId: 'v2-dup',
          anon8: 'aaaaaaaa',
          source: 1,
          lat: 25.05,
          lng: 121.55,
          observedAt: now.subtract(const Duration(seconds: 30)),
        ),
      ],
    ));
    await tester.pump(); // backfill applied → _seenPresence = {v2-dup}
    await tester.pump();
    expect(find.text('aaaaaaaa'), findsOneWidget);

    // SAME eventId arrives live with a different anon8 → dedup must drop it.
    pres.add(PresenceUpdate(
      eventId: 'v2-dup',
      anon8: 'bbbbbbbb',
      source: 1,
      lat: 25.06,
      lng: 121.56,
      observedAt: now.subtract(const Duration(seconds: 10)),
    ));
    await tester.pump();
    await tester.pump();

    expect(find.text('aaaaaaaa'), findsOneWidget);
    expect(find.text('bbbbbbbb'), findsNothing,
        reason: 'eventId dedup ignores the duplicate regardless of payload');
  });

  testWidgets(
      'backfill > _maxObsPerSubject keeps the NEWEST fix (oldest-first replay)',
      (tester) async {
    // A11-debug-4-polish: backfill is returned newest-first; _cap() trims the
    // list FRONT. If replayed in that order the freshest fix would be capped
    // away. 13 observations (> the 12 cap) for one anon — the newest carries a
    // distinctive coordinate that must survive and be displayed. (CHECKPOINT
    // shares this `_byAnon` / `_cap` path.)
    final now = DateTime(2026, 6, 15, 12, 0, 0);
    final obs = <PresenceUpdate>[
      // Newest-first, as queryByType (hlc_timestamp DESC) would return them.
      for (var i = 12; i >= 0; i--)
        PresenceUpdate(
          eventId: 'cap-$i',
          anon8: 'cap00001',
          source: 1,
          lat: 25.0 + i * 0.00001, // i=12 → 25.00012 (newest, distinctive)
          lng: 121.0,
          observedAt: now.subtract(Duration(minutes: 13 - i)), // i=12 → now-1m
        ),
    ];
    await tester.pumpWidget(screen(
      now: () => now,
      presenceBackfill: () async => obs,
    ));
    await tester.pump();
    await tester.pump();

    // The freshest fix (i=12 → 25.00012) survives the cap and is shown; the
    // next-newest (25.00011) would only show if the newest had been dropped.
    expect(find.textContaining('25.00012'), findsOneWidget);
    expect(find.textContaining('25.00011'), findsNothing);
  });

  // ── UI-H3 — large-text / text-scale stress ─────────────────────────────────
  // The estimate card crams a mono label + an SOS chip + a confidence chip into
  // one Row, plus an age/uncertainty meta Row and the 列表/雷達 toggle — all
  // overflow candidates under 1.45 / effective 2.0 on a narrow phone width.
  testWidgets('large text (UI-H3): estimate cards survive 1.15–2.0',
      (tester) async {
    tester.view.physicalSize = const Size(360, 820);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final now = DateTime(2026, 6, 15, 12, 0, 0);
    for (final scale in const [1.15, 1.30, 1.45, 2.0]) {
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('zh'),
        supportedLocales: S.supportedLocales,
        localizationsDelegates: S.localizationsDelegates,
        home: Builder(
          builder: (ctx) => MediaQuery(
            data: MediaQuery.of(ctx)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: LastSeenScreen(
              presenceSource: pres.stream,
              checkpointSource: cp.stream,
              sosSource: sos.stream,
              sosResolvedSource: sosRes.stream,
              presenceBackfill: () async => <PresenceUpdate>[],
              checkpointBackfill: () async => <CheckpointCrossing>[],
              sosBackfill: () async => <SosAlert>[],
              sosResolvedBackfill: () async => <SosResolved>[],
              now: () => now,
              refreshInterval: Duration.zero,
            ),
          ),
        ),
      ));
      await tester.pump();

      pres.add(PresenceUpdate(
        eventId: 'v2-1',
        anon8: 'a0a1a2a3',
        source: 1,
        lat: 25.0339805,
        lng: 121.5654177,
        accuracyM: 12,
        observedAt: now.subtract(const Duration(seconds: 30)),
      ));
      sos.add(SosAlert(
        eventId: 'sos-1',
        urgency: 3,
        description: '受困待援的較長描述以製造壓力',
        lat: 25.02,
        lng: 121.01,
        timestamp: now.subtract(const Duration(seconds: 20)),
      ));
      await tester.pump();
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'last-seen list @ $scale');
    }
  });
}
