// A11-debug-3 — source guard: the Android manifest MUST disable auto-backup so
// flutter_secure_storage ciphertext is never cloud/D2D-restored onto a device
// with a different Android Keystore key (the BAD_DECRYPT that bricked identity /
// field-secret reads in the A11 device test). This is a plain source assertion
// (no platform channel) so the regression is caught in CI without a device.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  // `flutter test` runs from the package root (ignirelay_app/), so this relative
  // path resolves to the production manifest.
  final manifest = File('android/app/src/main/AndroidManifest.xml');

  test('production AndroidManifest sets android:allowBackup="false"', () {
    expect(manifest.existsSync(), isTrue,
        reason: 'main AndroidManifest must exist at the expected path');
    final xml = manifest.readAsStringSync();

    expect(xml.contains('android:allowBackup="false"'), isTrue,
        reason: 'allowBackup must be explicitly false to prevent secure-storage '
            'ciphertext backup/restore (BAD_DECRYPT root cause)');
    // Defends against a regression that flips it back on.
    expect(xml.contains('android:allowBackup="true"'), isFalse,
        reason: 'allowBackup must never be true for this app');
  });
}
