// UI-H1 / UI-H2a — SettingsSection (語言 / 字體大小) pure-widget tests.
//
// SettingsSection is a value+callback widget: it does not import main.dart, hold
// state, or touch SharedPreferences, so its interaction can be pumped in
// isolation. UI-H2a localized its section/label/size strings via context.l10n,
// so the harness now supplies the S delegates + an explicit locale. 中文 /
// English chips are language endonyms — stable across locales — so selected
// state is asserted via the IgniChip.tone seam (brand = selected).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ignirelay_app/l10n/generated/app_localizations.dart';
import 'package:ignirelay_app/ui/shell/tabs/settings_section.dart';
import 'package:ignirelay_app/ui/theme/igni_text_scale.dart';
import 'package:ignirelay_app/ui/widgets/igni_chip.dart';

Finder _chip(String label, IgniChipTone tone) => find.byWidgetPredicate(
      (w) => w is IgniChip && w.label == label && w.tone == tone,
      description: 'IgniChip "$label" tone=$tone',
    );

Widget _app(Widget child, {Locale locale = const Locale('zh')}) => MaterialApp(
      locale: locale,
      supportedLocales: S.supportedLocales,
      localizationsDelegates: S.localizationsDelegates,
      home: Scaffold(body: child),
    );

Future<void> _pumpSection(
  WidgetTester tester, {
  required String languageCode,
  required IgniTextScale textScale,
  Locale locale = const Locale('zh'),
  ValueChanged<Locale>? onLanguage,
  ValueChanged<IgniTextScale>? onTextScale,
}) {
  return tester.pumpWidget(_app(
    SettingsSection(
      languageCode: languageCode,
      textScale: textScale,
      onLanguageSelected: onLanguage ?? (_) {},
      onTextScaleSelected: onTextScale ?? (_) {},
    ),
    locale: locale,
  ));
}

void main() {
  testWidgets('zh: renders 設定 / 語言 / 字體大小 and every choice', (tester) async {
    await _pumpSection(tester,
        languageCode: 'zh', textScale: IgniTextScale.standard);

    expect(find.text('設定'), findsOneWidget);
    expect(find.text('語言'), findsOneWidget);
    expect(find.text('字體大小'), findsOneWidget);
    expect(find.text('中文'), findsOneWidget);
    expect(find.text('English'), findsOneWidget);
    for (final label in const ['標準', '大字', '特大字', '超大字']) {
      expect(find.text(label), findsOneWidget, reason: 'text-size choice $label');
    }
  });

  testWidgets('en: renders English section + size labels, no Chinese chrome',
      (tester) async {
    await _pumpSection(tester,
        languageCode: 'en',
        textScale: IgniTextScale.standard,
        locale: const Locale('en'));

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Language'), findsOneWidget);
    expect(find.text('Text size'), findsOneWidget);
    for (final label in const ['Standard', 'Large', 'X-Large', 'Huge']) {
      expect(find.text(label), findsOneWidget, reason: 'text-size choice $label');
    }
    // 中文 / English chips stay (endonyms); but localized chrome is English.
    expect(find.text('中文'), findsOneWidget);
    expect(find.text('English'), findsOneWidget);
    expect(find.text('設定'), findsNothing);
    expect(find.text('標準'), findsNothing);
  });

  testWidgets('language selector reflects the current language', (tester) async {
    await _pumpSection(tester,
        languageCode: 'zh', textScale: IgniTextScale.standard);
    expect(_chip('中文', IgniChipTone.brand), findsOneWidget);
    expect(_chip('English', IgniChipTone.neutral), findsOneWidget);

    await _pumpSection(tester,
        languageCode: 'en',
        textScale: IgniTextScale.standard,
        locale: const Locale('en'));
    expect(_chip('English', IgniChipTone.brand), findsOneWidget);
    expect(_chip('中文', IgniChipTone.neutral), findsOneWidget);
  });

  testWidgets('text-size selector reflects the current size (zh)',
      (tester) async {
    await _pumpSection(tester,
        languageCode: 'zh', textScale: IgniTextScale.xLarge);
    expect(_chip('特大字', IgniChipTone.brand), findsOneWidget);
    for (final label in const ['標準', '大字', '超大字']) {
      expect(_chip(label, IgniChipTone.neutral), findsOneWidget);
    }
  });

  testWidgets('tapping a language fires onLanguageSelected with the right Locale',
      (tester) async {
    Locale? picked;
    await _pumpSection(tester,
        languageCode: 'zh',
        textScale: IgniTextScale.standard,
        onLanguage: (l) => picked = l);

    await tester.tap(find.text('English'));
    expect(picked, const Locale('en'));

    await tester.tap(find.text('中文'));
    expect(picked, const Locale('zh'));
  });

  testWidgets('tapping a text size fires onTextScaleSelected', (tester) async {
    IgniTextScale? picked;
    await _pumpSection(tester,
        languageCode: 'zh',
        textScale: IgniTextScale.standard,
        onTextScale: (s) => picked = s);

    await tester.tap(find.text('超大字'));
    expect(picked, IgniTextScale.huge);
  });

  testWidgets('selecting a text size updates the visible selected state',
      (tester) async {
    // The stateful host mirrors production wiring (callback drives the value,
    // the widget re-renders the new selection) — proving the seam end-to-end.
    await tester.pumpWidget(_app(const _Host()));

    expect(_chip('標準', IgniChipTone.brand), findsOneWidget);
    expect(_chip('大字', IgniChipTone.neutral), findsOneWidget);

    await tester.tap(find.text('大字'));
    await tester.pump();

    expect(_chip('大字', IgniChipTone.brand), findsOneWidget);
    expect(_chip('標準', IgniChipTone.neutral), findsOneWidget);
  });

  testWidgets('no overflow at huge (1.45) text scale in a phone-width column',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('zh'),
      supportedLocales: S.supportedLocales,
      localizationsDelegates: S.localizationsDelegates,
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.45)),
          child: const Scaffold(
            body: SizedBox(
              width: 360,
              child: SingleChildScrollView(child: _Host()),
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}

/// Mirrors MyTab's production wiring: a parent holding the current values and
/// updating them from the section's callbacks.
class _Host extends StatefulWidget {
  const _Host();
  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  String _lang = 'zh';
  IgniTextScale _scale = IgniTextScale.standard;

  @override
  Widget build(BuildContext context) => SettingsSection(
        languageCode: _lang,
        textScale: _scale,
        onLanguageSelected: (l) => setState(() => _lang = l.languageCode),
        onTextScaleSelected: (s) => setState(() => _scale = s),
      );
}
