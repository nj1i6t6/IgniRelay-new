// A11-prep — HazardCard widget tests. Drives the receive stream + the publish
// seam + the local-origin seam directly (no EventStream / EventPublisher /
// LocalPositionSource provider needed), mirroring the LastSeenScreen seams.
//
// Covers: a received typed HAZARD renders a row; the kDebugMode send button
// publishes via the seam with the chosen type + the device's own coordinate
// (injected through the `localEstimate` seam); and the no-GPS case refuses to
// publish on BOTH the debug and the formal path (UI-F5b-polish / Owner rule: no
// fake/sample/default coordinate in any runtime path, incl. the debug shell).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ignirelay_app/app/controllers/event_stream.dart';
import 'package:ignirelay_app/app/services/position_estimator.dart';
import 'package:ignirelay_app/l10n/generated/app_localizations.dart';
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

  Widget card(
          {PositionEstimate? Function()? localEstimate,
          Future<List<HazardEvent>> Function()? hazardBackfill,
          Locale locale = const Locale('zh')}) =>
      MaterialApp(
        locale: locale,
        supportedLocales: S.supportedLocales,
        localizationsDelegates: S.localizationsDelegates,
        home: Scaffold(
          body: HazardCard(
            hazardSource: hz.stream,
            // Inject the backfill seam too so no EventStream provider is needed
            // (default = empty: existing tests keep their original behaviour).
            hazardBackfill: hazardBackfill ?? () async => <HazardEvent>[],
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

  testWidgets(
      'A11 fix: a HAZARD that already exists before mount is backfilled, and a '
      'live HAZARD still appends', (tester) async {
    // The 事件 tab opens AFTER a hazard was already received — the broadcast
    // stream won't replay it, so the card must backfill from the read-model.
    await tester.pumpWidget(card(hazardBackfill: () async => [
          HazardEvent(
            eventId: 'pre-1',
            type: 'FLOOD',
            severity: 2,
            lat: 24.5,
            lng: 120.5,
            radiusMeters: 200,
            description: '既有淹水',
          ),
        ]));
    await tester.pump(); // mount + subscribe
    await tester.pump(); // backfill future resolves + setState

    expect(find.text('FLOOD'), findsOneWidget,
        reason: 'pre-existing HAZARD must show on mount via backfill');

    // A live HAZARD arriving after mount still appends (deduped by eventId).
    hz.add(HazardEvent(
      eventId: 'live-1',
      type: 'FIRE',
      severity: 3,
      lat: 25.0,
      lng: 121.0,
      radiusMeters: 200,
      description: '即時火災',
    ));
    await tester.pump();
    await tester.pump();

    expect(find.text('FIRE'), findsOneWidget);
    expect(find.text('FLOOD'), findsOneWidget,
        reason: 'backfilled HAZARD remains after a live one arrives');
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

  testWidgets('no GPS fix → DEBUG send also does NOT publish; shows the prompt',
      (tester) async {
    // UI-F5b-polish: the sample coordinate is gone — the debug stand-in now
    // refuses without a real fix, exactly like the formal path (no fake/sample/
    // default coordinate anywhere in app runtime, including the debug shell).
    await tester.pumpWidget(card(localEstimate: () => null));
    await tester.pump();

    await tester.tap(find.text('手動 HAZARD'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('送出'));
    await tester.pumpAndSettle();

    expect(publishCalls, 0,
        reason: 'no fake/sample coordinate in the debug path either');
    expect(find.text('目前沒有位置，請取得位置後再回報'), findsOneWidget);
  });

  // ── UI-F5b — FORMAL path: NO fake/sample coordinate (Owner boundary 1) ──────

  Widget formalCard({
    PositionEstimate? Function()? localEstimate,
    Future<void> Function()? ensureFreshLocation,
    Future<List<HazardEvent>> Function()? hazardBackfill,
    Locale locale = const Locale('zh'),
  }) =>
      MaterialApp(
        locale: locale,
        supportedLocales: S.supportedLocales,
        localizationsDelegates: S.localizationsDelegates,
        home: Scaffold(
          body: HazardCard(
            hazardSource: hz.stream,
            hazardBackfill: hazardBackfill ?? () async => <HazardEvent>[],
            onPublish: spy,
            localEstimate: localEstimate ?? () => origin,
            ensureFreshLocation: ensureFreshLocation ?? () async {},
            formalSend: true,
          ),
        ),
      );

  testWidgets('formal send WITH a fix publishes the REAL coordinate',
      (tester) async {
    await tester.pumpWidget(formalCard());
    await tester.pump();

    await tester.tap(find.text('回報危害')); // the button
    await tester.pumpAndSettle();
    await tester.tap(find.text('送出'));
    await tester.pumpAndSettle();

    expect(publishCalls, 1);
    expect(capturedLat, 25.0); // the device's own fix — never the sample
    expect(capturedLng, 121.0);
  });

  testWidgets('formal send with NO fix does NOT publish; shows the prompt',
      (tester) async {
    await tester.pumpWidget(formalCard(localEstimate: () => null));
    await tester.pump();

    await tester.tap(find.text('回報危害'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('送出'));
    await tester.pumpAndSettle();

    expect(publishCalls, 0,
        reason: 'no fake/sample coordinate in the production path');
    expect(find.text('目前沒有位置，請取得位置後再回報'), findsOneWidget);
  });

  testWidgets('formal: a refresh that yields a fix → publishes the real coord '
      '(hook awaited before reading the origin)', (tester) async {
    PositionEstimate? est; // null until the bounded refresh runs
    await tester.pumpWidget(formalCard(
      localEstimate: () => est,
      ensureFreshLocation: () async => est = origin,
    ));
    await tester.pump();

    await tester.tap(find.text('回報危害'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('送出'));
    await tester.pumpAndSettle();

    expect(publishCalls, 1, reason: 'fresh fix obtained before reading origin');
    expect(capturedLat, 25.0);
    expect(capturedLng, 121.0);
  });

  testWidgets('en: formal card renders English report entry (UI-H2c)',
      (tester) async {
    await tester.pumpWidget(formalCard(locale: const Locale('en')));
    await tester.pump();

    expect(find.text('Hazard report'), findsOneWidget); // card title
    expect(find.text('Report hazard'), findsOneWidget); // formal button
    expect(find.text('危害回報'), findsNothing);
  });
}
