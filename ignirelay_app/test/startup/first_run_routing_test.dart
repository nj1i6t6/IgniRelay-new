// A11-preflight-fix — fresh-install routing guard.
//
// Before UI-F1 the production home was already the AppShell, but main.dart's
// `_StartupRouter` still gated it behind the legacy OnboardingScreen (read of
// the `onboarding_done` pref) and auto-launched BatteryOptimizationGuide right
// after onboarding. So a fresh install actually ran:
//   permissions → OnboardingScreen → BatteryOptimizationGuide → AppShell
// which contradicts UI-F/UI-G and the A11 runbook (Step 1 must land on the
// no-field entry: 加入場域 / 建立場域 / 先看功能).
//
// `_StartupRouter` itself can't be pumped here — its initState drives real
// native plugins (DatabaseHelper, IdentityManager, permission_handler,
// NativeBridge). So this is a SOURCE guard over lib/main.dart proving the
// production startup path no longer routes through OnboardingScreen and no
// longer auto-invokes BatteryOptimizationGuide, and lands on AppShell.
//
// The behavioural half — AppShell with no active field shows the three no-field
// entries — is covered by test/ui/shell/app_shell_test.dart.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  // Under `flutter test` the cwd is the package root, so this resolves.
  final mainSource = File('lib/main.dart').readAsStringSync();
  final allLines = const LineSplitter().convert(mainSource);

  // Code only: drop the `//` comment portion of every line (full-line AND
  // trailing). The new code keeps the words "OnboardingScreen" /
  // "BatteryOptimizationGuide" in explanatory comments — those must NOT trip
  // the guard, only live code references should.
  String codeOf(String line) {
    final i = line.indexOf('//');
    return i >= 0 ? line.substring(0, i) : line;
  }

  final codeLines = allLines.map(codeOf).toList();
  final codeText = codeLines.join('\n');
  final importLines =
      allLines.where((l) => l.trimLeft().startsWith('import '));

  test('main.dart does not import the legacy onboarding / battery-guide screens',
      () {
    for (final line in importLines) {
      expect(line.contains('onboarding_screen.dart'), isFalse,
          reason: 'fresh install must not depend on OnboardingScreen: $line');
      expect(line.contains('battery_optimization_guide.dart'), isFalse,
          reason: 'first run must not auto-show BatteryOptimizationGuide: $line');
    }
  });

  test('production startup path no longer routes through OnboardingScreen', () {
    expect(codeText.contains('OnboardingScreen'), isFalse,
        reason: 'no OnboardingScreen construction may remain in the live path');
    expect(codeText.contains('_showOnboarding'), isFalse,
        reason: 'the onboarding gate field must be gone');
    expect(codeText.contains('onboarding_done'), isFalse,
        reason: 'the onboarding_done pref gate must be gone');
  });

  test('first run does not auto-invoke BatteryOptimizationGuide', () {
    expect(codeText.contains('.checkAndGuide('), isFalse,
        reason: 'BatteryOptimizationGuide.checkAndGuide must not fire on '
            'first run before the AppShell is shown');
  });

  test('the startup router lands on the production AppShell', () {
    expect(codeText.contains('return const AppShell();'), isTrue,
        reason: 'fresh install (permissions done) must render AppShell');
  });
}
