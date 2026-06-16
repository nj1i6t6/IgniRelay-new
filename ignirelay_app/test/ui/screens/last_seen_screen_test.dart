// A10 / A10b — LastSeenScreen widget tests. Drives the typed streams + clock +
// local-origin via the injection seams so no EventStream / LocalPositionSource
// provider and no real time are needed.
//
// Covers: the empty state + §3.6 copy rule (A10, NEVER 「目前位置」); a rendered
// estimate card (A10); the 列表⇄雷達 toggle (A10b D2); the "no local position"
// degrade path (A10b D3); and an SOS alert surfacing as a card.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ignirelay_app/app/controllers/event_stream.dart';
import 'package:ignirelay_app/app/services/position_estimator.dart';
import 'package:ignirelay_app/ui/screens/position/last_seen_screen.dart';
import 'package:ignirelay_app/ui/screens/position/relative_radar.dart';
import 'package:ignirelay_app/ui/widgets/status_chip.dart';

void main() {
  // Shared stream controllers + helper so each test wires all three seams.
  late StreamController<PresenceUpdate> pres;
  late StreamController<CheckpointCrossing> cp;
  late StreamController<SosAlert> sos;

  setUp(() {
    pres = StreamController<PresenceUpdate>.broadcast();
    cp = StreamController<CheckpointCrossing>.broadcast();
    sos = StreamController<SosAlert>.broadcast();
  });
  tearDown(() {
    pres.close();
    cp.close();
    sos.close();
  });

  Widget screen({
    DateTime Function()? now,
    PositionEstimate? Function()? localEstimate,
  }) =>
      MaterialApp(
        home: LastSeenScreen(
          presenceSource: pres.stream,
          checkpointSource: cp.stream,
          sosSource: sos.stream,
          now: now,
          localEstimate: localEstimate,
          refreshInterval: Duration.zero, // no timer
        ),
      );

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
      home: LastSeenScreen(
        presenceSource: pres.stream,
        checkpointSource: cp.stream,
        sosSource: sos.stream,
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
}
