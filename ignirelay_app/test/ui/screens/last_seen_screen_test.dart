// A10 — LastSeenScreen widget smoke (DoD D2). Drives the typed streams + clock
// via the injection seams so no EventStream provider / real time is needed.
// Asserts the empty state, a rendered estimate card, and the §3.6 copy rule
// (NEVER 「目前位置」).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ignirelay_app/app/controllers/event_stream.dart';
import 'package:ignirelay_app/ui/screens/position/last_seen_screen.dart';

void main() {
  testWidgets('empty state renders the 推估 hint (no 目前位置 copy)',
      (tester) async {
    final pres = StreamController<PresenceUpdate>.broadcast();
    final cp = StreamController<CheckpointCrossing>.broadcast();
    addTearDown(() {
      pres.close();
      cp.close();
    });

    await tester.pumpWidget(MaterialApp(
      home: LastSeenScreen(
        presenceSource: pres.stream,
        checkpointSource: cp.stream,
        refreshInterval: Duration.zero, // no timer
      ),
    ));
    await tester.pump();

    expect(find.text('最後可信位置'), findsOneWidget); // header only
    expect(find.textContaining('尚無位置證據'), findsOneWidget);
    expect(find.textContaining('目前位置'), findsNothing);
  });

  testWidgets('a PRESENCE fix renders a 最後可信位置 card with confidence',
      (tester) async {
    final now = DateTime(2026, 6, 15, 12, 0, 0);
    final pres = StreamController<PresenceUpdate>.broadcast();
    final cp = StreamController<CheckpointCrossing>.broadcast();
    addTearDown(() {
      pres.close();
      cp.close();
    });

    await tester.pumpWidget(MaterialApp(
      home: LastSeenScreen(
        presenceSource: pres.stream,
        checkpointSource: cp.stream,
        now: () => now,
        refreshInterval: Duration.zero,
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
    await tester.pump(); // deliver the stream event
    await tester.pump(); // rebuild after setState

    expect(find.text('a0a1a2a3'), findsOneWidget);
    // 「最後可信位置」appears twice now: page header + the card's section label.
    expect(find.text('最後可信位置'), findsWidgets);
    expect(find.text('可信度 高'), findsOneWidget); // 30s old → HIGH
    expect(find.textContaining('25.03398'), findsOneWidget);
    expect(find.textContaining('目前位置'), findsNothing);
  });
}
