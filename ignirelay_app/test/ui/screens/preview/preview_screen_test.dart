// UI-G — PreviewScreen guided-preview tests.
//
// Two concerns:
//  1) Zero-provider group — PreviewScreen pumps with NO providers, proving it is
//     structurally incapable of publishing a real event (fixture-only; holds no
//     publisher / controller / location). It also walks the 5-page tour, renders
//     the radar in a bounded box, and asserts the position copy never says
//     「目前位置」 (§3.6). This group does NOT tap a CTA into FieldScreen.
//  2) Import guard — the preview sources import no real controller / publisher /
//     location / transport code (Owner boundary ④), checked by parsing imports.
//
// The CTA→FieldScreen navigation (which needs the app providers) lives in
// app_shell_test.dart under the full provider harness (Owner boundary ②).

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ignirelay_app/l10n/generated/app_localizations.dart';
import 'package:ignirelay_app/ui/screens/position/relative_radar.dart';
import 'package:ignirelay_app/ui/screens/preview/preview_screen.dart';

// UI-H2b: PreviewScreen now localizes via context.l10n, so the harness supplies
// the S delegates + an explicit zh locale. This adds NO provider — the
// fixture-only / zero-provider property the import-guard test enforces is intact.
Widget _previewApp({Locale locale = const Locale('zh')}) => MaterialApp(
      locale: locale,
      supportedLocales: S.supportedLocales,
      localizationsDelegates: S.localizationsDelegates,
      home: const PreviewScreen(),
    );

void main() {
  group('PreviewScreen — fixture-only render (no providers)', () {
    testWidgets('renders the 示範資料 badge + first page with zero providers',
        (tester) async {
      await tester.pumpWidget(_previewApp());
      await tester.pumpAndSettle();

      expect(find.byType(PreviewScreen), findsOneWidget);
      expect(find.text('示範資料'), findsOneWidget); // unmistakably a preview
      expect(find.text('加入場域'), findsWidgets); // page-1 title/CTA
    });

    testWidgets('guided tour covers the five concepts; radar bounded; no 目前位置',
        (tester) async {
      await tester.pumpWidget(_previewApp());
      await tester.pumpAndSettle();

      // p1 — 加入場域
      expect(find.text('加入場域'), findsWidgets);

      // p2 — 安全（被看見 + SOS）
      await tester.tap(find.text('下一步'));
      await tester.pumpAndSettle();
      expect(find.textContaining('被看見'), findsWidgets);

      // p3 — 位置：radar in a bounded box; copy is 最後可信位置, NEVER 目前位置
      await tester.tap(find.text('下一步'));
      await tester.pumpAndSettle();
      expect(find.byType(RelativeRadar), findsOneWidget);
      expect(find.textContaining('最後可信位置'), findsWidgets);
      expect(find.textContaining('目前位置'), findsNothing);

      // p4 — 事件
      await tester.tap(find.text('下一步'));
      await tester.pumpAndSettle();
      expect(find.textContaining('危害'), findsWidgets);

      // p5 — 協助 + 離線（last page: nav-right becomes 加入場域, so 下一步 is gone）
      await tester.tap(find.text('下一步'));
      await tester.pumpAndSettle();
      expect(find.textContaining('離線'), findsWidgets);
      expect(find.text('下一步'), findsNothing);
    });

    testWidgets('en: badge + first page render English (UI-H2b)',
        (tester) async {
      await tester.pumpWidget(_previewApp(locale: const Locale('en')));
      await tester.pumpAndSettle();

      expect(find.text('Demo data'), findsOneWidget);
      expect(find.text('Join field'), findsWidgets); // page-1 title/CTA
      expect(find.text('Next'), findsOneWidget);
      expect(find.text('示範資料'), findsNothing);
    });

    // ── UI-H3 — large-text / text-scale stress ───────────────────────────────
    // Walk all five tour pages (incl. the radar page + event/footprint rows) at
    // 1.45 and effective 2.0 on a narrow phone width, asserting no overflow.
    // Still zero-provider (the MediaQuery wrapper adds no provider).
    testWidgets('large text (UI-H3): five pages survive 1.45 / 2.0',
        (tester) async {
      tester.view.physicalSize = const Size(360, 820);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      for (final scale in const [1.45, 2.0]) {
        await tester.pumpWidget(MaterialApp(
          locale: const Locale('zh'),
          supportedLocales: S.supportedLocales,
          localizationsDelegates: S.localizationsDelegates,
          home: Builder(
            builder: (ctx) => MediaQuery(
              data: MediaQuery.of(ctx)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              // Fresh State per scale so the PageController doesn't carry the
              // previous run's page index into this one.
              child: PreviewScreen(key: ValueKey('h3-$scale')),
            ),
          ),
        ));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'preview p1 @ $scale');

        // Advance until the last page (its nav-right becomes 加入場域, so 下一步
        // disappears) — checking every page for overflow on the way.
        var page = 1;
        while (find.text('下一步').evaluate().isNotEmpty) {
          await tester.tap(find.text('下一步'));
          await tester.pumpAndSettle();
          page++;
          expect(tester.takeException(), isNull,
              reason: 'preview p$page @ $scale');
        }
        expect(page, 5, reason: 'walked all five tour pages @ $scale');
      }
    });
  });

  // Owner boundary ④ — fixture-only means NO real controller imports at all.
  test('preview sources import no real controller/publisher/location/transport',
      () {
    final dir = Directory('lib/ui/screens/preview');
    expect(dir.existsSync(), isTrue);
    final dartFiles =
        dir.listSync().whereType<File>().where((f) => f.path.endsWith('.dart'));
    expect(dartFiles, isNotEmpty);

    const forbidden = <String>[
      'event_publisher',
      'presence_beacon_controller',
      'presence_controller',
      'sos_controller',
      'checkpoint_controller',
      'location_service',
      'location_refresh_coordinator',
      'active_field_controller',
      'mesh_runtime_controller',
      'app/mesh',
      'app/proto',
      'app/db',
      'platform/',
    ];
    for (final f in dartFiles) {
      final importLines = const LineSplitter()
          .convert(f.readAsStringSync())
          .where((l) => l.trimLeft().startsWith('import '));
      for (final line in importLines) {
        for (final bad in forbidden) {
          expect(line.contains(bad), isFalse,
              reason: '${f.path} must not import "$bad": $line');
        }
      }
    }
  });
}
