// A11-prep — HazardCard widget tests. Drives the receive stream + the publish
// seam + the local-origin seam directly (no EventStream / EventPublisher /
// LocalPositionSource provider needed), mirroring the LastSeenScreen seams.
//
// Covers: a received typed HAZARD renders a row; the kDebugMode send button
// publishes via the seam with the chosen type + the device's own coordinate;
// and the no-GPS fallback uses the sample coordinate (never a peer).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ignirelay_app/app/controllers/event_stream.dart';
import 'package:ignirelay_app/app/services/position_estimator.dart';
import 'package:ignirelay_app/ui/shell/hazard_card.dart';

void main() {
  late StreamController<HazardEvent> hz;

  // Captured publish args (the spy seam).
  String? capturedType;
  int? capturedSeverity;
  double? capturedLat;
  double? capturedLng;
  String? capturedDesc;
  int publishCalls = 0;

  Future<String> spy({
    required String type,
    required int severity,
    required double lat,
    required double lng,
    double radiusMeters = 200.0,
    String description = '',
  }) async {
    publishCalls++;
    capturedType = type;
    capturedSeverity = severity;
    capturedLat = lat;
    capturedLng = lng;
    capturedDesc = description;
    return 'hz-evt-0001';
  }

  setUp(() {
    hz = StreamController<HazardEvent>.broadcast();
    capturedType = null;
    capturedSeverity = null;
    capturedLat = null;
    capturedLng = null;
    capturedDesc = null;
    publishCalls = 0;
  });
  tearDown(() => hz.close());

  const origin = PositionEstimate(
    lat: 25.0,
    lng: 121.0,
    confidence: PositionConfidence.high,
    uncertaintyM: 15,
    ageSeconds: 0,
  );

  Widget card({PositionEstimate? Function()? localEstimate}) => MaterialApp(
        home: Scaffold(
          body: HazardCard(
            hazardSource: hz.stream,
            onPublish: spy,
            localEstimate: localEstimate ?? () => origin,
          ),
        ),
      );

  testWidgets('empty state renders the HAZARD card with no rows',
      (tester) async {
    await tester.pumpWidget(card());
    await tester.pump();
    expect(find.text('危害（HAZARD）'), findsOneWidget);
    expect(find.textContaining('尚無 HAZARD'), findsOneWidget);
  });

  testWidgets('a received typed HAZARD renders a row', (tester) async {
    await tester.pumpWidget(card());
    await tester.pump();

    hz.add(HazardEvent(
      eventId: 'h1',
      type: 'FIRE',
      severity: 3,
      lat: 25.0339,
      lng: 121.5645,
      radiusMeters: 200,
      description: '火災',
    ));
    await tester.pump(); // deliver
    await tester.pump(); // rebuild

    expect(find.text('FIRE'), findsOneWidget);
    expect(find.textContaining('sev 3'), findsOneWidget);
    expect(find.textContaining('25.03390'), findsOneWidget);
  });

  testWidgets('the kDebugMode send button publishes via the seam (default FIRE)',
      (tester) async {
    await tester.pumpWidget(card());
    await tester.pump();

    await tester.tap(find.text('手動 HAZARD'));
    await tester.pumpAndSettle(); // dialog in

    expect(find.text('手動 HAZARD（debug）'), findsOneWidget);
    await tester.tap(find.text('送出'));
    await tester.pumpAndSettle(); // publish + dialog out

    expect(publishCalls, 1);
    expect(capturedType, 'FIRE'); // default dropdown value
    expect(capturedSeverity, 2);
    expect(capturedLat, 25.0); // from the local origin (the device's own fix)
    expect(capturedLng, 121.0);
    expect(capturedDesc, isNotEmpty);
  });

  testWidgets('no GPS fix → send falls back to the sample coordinate',
      (tester) async {
    await tester.pumpWidget(card(localEstimate: () => null));
    await tester.pump();

    await tester.tap(find.text('手動 HAZARD'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('送出'));
    await tester.pumpAndSettle();

    expect(publishCalls, 1);
    // The documented debug fallback (NOT a peer's position).
    expect(capturedLat, closeTo(25.0339, 1e-9));
    expect(capturedLng, closeTo(121.5645, 1e-9));
  });
}
