// A11-debug-3 — IdentityManager must survive an Android Keystore BAD_DECRYPT on
// the persisted Ed25519 key. This read runs in main.dart Stage 1 ("失敗 = 無法
// 啟動"), so a thrown PlatformException there would brick startup. The recovery
// is to regenerate a fresh identity (== clean-install state) and overwrite the
// unreadable ciphertext — never crash.

import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';
import 'package:ignirelay_app/app/crypto/identity_manager.dart';
import 'package:ignirelay_app/app/services/anon_identity.dart' show SecureKvStore;
import 'package:shared_preferences/shared_preferences.dart';

/// Secure store whose [read] always throws BAD_DECRYPT; [write] records so we
/// can assert the regenerated identity is persisted.
class _ThrowingReadKv implements SecureKvStore {
  final Map<String, String> written = <String, String>{};

  @override
  Future<String?> read(String key) async {
    throw PlatformException(
        code: 'Exception encountered', message: 'BAD_DECRYPT');
  }

  @override
  Future<void> write(String key, String value) async => written[key] = value;

  @override
  Future<void> delete(String key) async => written.remove(key);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    IdentityManager.debugSecureStoreOverride = null;
  });

  test('A11-debug-3: secure-storage read BAD_DECRYPT regenerates, no crash',
      () async {
    // No legacy SharedPreferences keys either → only path out is regeneration.
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final kv = _ThrowingReadKv();
    IdentityManager.debugSecureStoreOverride = kv;

    // Must NOT throw despite every read throwing BAD_DECRYPT.
    await IdentityManager().initialize();

    // A fresh, usable keypair exists (32-byte pubkey → 64 hex chars).
    final hex = await IdentityManager().getPublicKeyHex();
    expect(hex.length, 64);

    // The fresh identity was persisted (overwrites the unreadable ciphertext).
    expect(kv.written.containsKey('ed25519_private_key'), isTrue);
    expect(kv.written.containsKey('ed25519_public_key'), isTrue);
  });
}
