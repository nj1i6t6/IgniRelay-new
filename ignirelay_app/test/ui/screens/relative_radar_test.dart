// A10b — RelativeRadar widget smoke (DoD D2). Renders n = 0 / 1 / 8 subjects
// without crashing, asserts an SOS subject yields a sos-tone marker, and that a
// beyond-outer-ring subject is pinned (`>` label). The radar is given a bounded
// box so its Column/Expanded/LayoutBuilder lay out.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ignirelay_app/app/services/position_estimator.dart';
import 'package:ignirelay_app/l10n/generated/app_localizations.dart';
import 'package:ignirelay_app/ui/screens/position/relative_radar.dart';
import 'package:ignirelay_app/ui/widgets/status_chip.dart';

const PositionEstimate _origin = PositionEstimate(
  lat: 25.0,
  lng: 121.0,
  confidence: PositionConfidence.high,
  uncertaintyM: 15,
  ageSeconds: 0,
);

PositionEstimate _at(double lat, double lng,
        {PositionConfidence c = PositionConfidence.high}) =>
    PositionEstimate(
      lat: lat,
      lng: lng,
      confidence: c,
      uncertaintyM: 20,
      ageSeconds: 30,
    );

Future<void> _pump(WidgetTester tester, List<RadarSubject> subjects,
    {Locale locale = const Locale('zh')}) async {
  await tester.pumpWidget(MaterialApp(
    locale: locale,
    supportedLocales: S.supportedLocales,
    localizationsDelegates: S.localizationsDelegates,
    home: Scaffold(
      body: SizedBox(
        width: 400,
        height: 600,
        child: RelativeRadar(origin: _origin, subjects: subjects),
      ),
    ),
  ));
  await tester.pump();
}

void main() {
  testWidgets('n = 0 subjects renders the radar (rings only), no crash',
      (tester) async {
    await _pump(tester, const []);
    expect(find.byType(RelativeRadar), findsOneWidget);
    expect(find.byType(RadarMarker), findsNothing);
    expect(find.textContaining('北朝上'), findsOneWidget);
  });

  testWidgets('n = 1 subject renders exactly one marker', (tester) async {
    await _pump(tester, [
      RadarSubject(key: 'p1', label: 'aaaa', estimate: _at(25.01, 121.0)),
    ]);
    expect(find.byType(RadarMarker), findsOneWidget);
  });

  testWidgets('n = 8 subjects all render', (tester) async {
    final subjects = <RadarSubject>[
      for (var i = 0; i < 8; i++)
        RadarSubject(
          key: 'p$i',
          label: 'node$i',
          estimate: _at(25.0 + 0.002 * (i + 1), 121.0 + 0.001 * i),
          isNode: i.isEven,
        ),
    ];
    await _pump(tester, subjects);
    expect(find.byType(RadarMarker), findsNWidgets(8));
  });

  testWidgets('an SOS subject yields a sos-tone marker', (tester) async {
    await _pump(tester, [
      RadarSubject(
        key: 'p-ok',
        label: 'okok',
        estimate: _at(25.005, 121.0),
      ),
      RadarSubject(
        key: 's-1',
        label: 'sos1',
        estimate: _at(25.003, 121.002),
        baseTone: StatusTone.sos,
      ),
    ]);
    final sosMarkers = find.byWidgetPredicate(
        (w) => w is RadarMarker && w.tone == StatusTone.sos);
    expect(sosMarkers, findsOneWidget);
  });

  testWidgets('a LOW-confidence non-SOS subject is shown stale (neutral tone)',
      (tester) async {
    await _pump(tester, [
      RadarSubject(
        key: 'stale',
        label: 'old1',
        estimate: _at(25.001, 121.0, c: PositionConfidence.low),
      ),
    ]);
    final neutral = find.byWidgetPredicate(
        (w) => w is RadarMarker && w.tone == StatusTone.neutral);
    expect(neutral, findsOneWidget);
  });

  testWidgets('a far subject (beyond the outer ring) is pinned with a > label',
      (tester) async {
    // ~280 km north → past the largest ring tier (outer 200 km); the radar pins
    // it to the rim and labels it ">200 km".
    await _pump(tester, [
      RadarSubject(key: 'p-near', label: 'near', estimate: _at(25.0005, 121.0)),
      RadarSubject(key: 'p-far', label: 'far', estimate: _at(27.5, 121.0)),
    ]);
    expect(find.textContaining('>'), findsWidgets);
  });

  testWidgets('en: caption renders English (UI-H2c)', (tester) async {
    await _pump(tester, const [], locale: const Locale('en'));
    expect(find.textContaining('North up'), findsOneWidget);
    expect(find.textContaining('北朝上'), findsNothing);
  });
}
