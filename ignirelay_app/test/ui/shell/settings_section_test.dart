// UI-H1 — SettingsSection (語言 / 字體大小) pure-widget tests.
//
// SettingsSection is a value+callback widget: it does not import main.dart, hold
// state, or touch SharedPreferences, so its interaction can be pumped in
// isolation. Selected state is asserted via the IgniChip.tone seam (brand =
// selected, neutral = not), which is unambiguous even though chip labels are
// plain Text.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ignirelay_app/ui/shell/tabs/settings_section.dart';
import 'package:ignirelay_app/ui/theme/igni_text_scale.dart';
import 'package:ignirelay_app/ui/widgets/igni_chip.dart';

Finder _chip(String label, IgniChipTone tone) => find.byWidgetPredicate(
      (w) => w is IgniChip && w.label == label && w.tone == tone,
      description: 'IgniChip "$label" tone=$tone',
    );

Future<void> _pumpSection(
  WidgetTester tester, {
  required String languageCode,
  required IgniTextScale textScale,
  ValueChanged<Locale>? onLanguage,
  ValueChanged<IgniTextScale>? onTextScale,
}) {
  return tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SettingsSection(
        languageCode: languageCode,
        textScale: textScale,
        onLanguageSelected: onLanguage ?? (_) {},
        onTextScaleSelected: onTextScale ?? (_) {},
      ),
    ),
  ));
}

void main() {
  testWidgets('renders 設定 / 語言 / 字體大小 and every choice', (tester) async {
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

  testWidgets('language selector reflects the current language', (tester) async {
    await _pumpSection(tester,
        languageCode: 'zh', textScale: IgniTextScale.standard);
    expect(_chip('中文', IgniChipTone.brand), findsOneWidget);
    expect(_chip('English', IgniChipTone.neutral), findsOneWidget);

    await _pumpSection(tester,
        languageCode: 'en', textScale: IgniTextScale.standard);
    expect(_chip('English', IgniChipTone.brand), findsOneWidget);
    expect(_chip('中文', IgniChipTone.neutral), findsOneWidget);
  });

  testWidgets('text-size selector reflects the current size', (tester) async {
    await _pumpSection(tester,
        languageCode: 'zh', textScale: IgniTextScale.xLarge);
    expect(_chip('特大字', IgniChipTone.brand), findsOneWidget);
    // every other size is unselected
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
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: _Host())));

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
