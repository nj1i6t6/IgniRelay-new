import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ignirelay_app/app/crdt/hlc.dart';
// SecureKvStore / FlutterSecureKvStore are the shared secure-storage seam
// (introduced for AnonIdentityService, A2). IdentityManager reuses it so the
// BAD_DECRYPT self-heal (A11-debug-3) is unit-testable without the
// flutter_secure_storage platform channel — identical base64 read/write
// semantics, no change to the stored key format.
import 'package:ignirelay_app/app/services/anon_identity.dart'
    show SecureKvStore, FlutterSecureKvStore;

class IdentityManager {
  static final IdentityManager _instance = IdentityManager._internal();
  factory IdentityManager() => _instance;
  IdentityManager._internal();

  SimpleKeyPair? _keyPair;
  int _identityLevel = 0; // Default: Level 0 (Anonymous)
  bool _initialized = false;

  /// Test seam: inject a fake [SecureKvStore] so the BAD_DECRYPT recovery path
  /// can be exercised without the platform channel. Mirrors
  /// `DatabaseHelper.testDatabasePathOverride`. Production leaves it null and
  /// uses the real `flutter_secure_storage`-backed store.
  @visibleForTesting
  static SecureKvStore? debugSecureStoreOverride;

  SecureKvStore get _secure =>
      debugSecureStoreOverride ?? const FlutterSecureKvStore();

  static const _privKeyKey = 'ed25519_private_key';
  static const _pubKeyKey = 'ed25519_public_key';

  /// 初始化：從持久化儲存中恢復金鑰對與身分等級
  /// 應在 main() 中呼叫一次
  Future<void> initialize() async {
    if (_initialized) return;
    final prefs = await SharedPreferences.getInstance();

    // 恢復身分等級
    _identityLevel = prefs.getInt('identity_level') ?? 0;

    // 嘗試從 Secure Storage 恢復金鑰（Android Keystore / iOS Keychain）
    String? savedPrivateKey;
    String? savedPublicKey;
    try {
      savedPrivateKey = await _secure.read(_privKeyKey);
      savedPublicKey = await _secure.read(_pubKeyKey);
    } catch (e) {
      // A11-debug-3: a persisted key that can no longer be decrypted (Android
      // Keystore BAD_DECRYPT — e.g. cloud/D2D restore before allowBackup=false,
      // or a Keystore key invalidated by an OS credential / biometric change)
      // must NOT brick startup (this read runs in main.dart Stage 1 = "失敗 =
      // 無法啟動"). Treat both as absent; _generateAndSave() below mints a fresh
      // identity and OVERWRITES the unreadable ciphertext. A fresh identity is
      // the same state as a clean install — acceptable degradation, never a
      // crash. Scope is narrow: only the persisted read is caught, recovery is
      // logged, and no other error is swallowed.
      debugPrint('[IdentityManager] secure-storage read failed ($e); '
          'regenerating identity');
      savedPrivateKey = null;
      savedPublicKey = null;
    }

    if (savedPrivateKey != null && savedPublicKey != null) {
      try {
        final privBytes = base64Decode(savedPrivateKey);
        final pubBytes = base64Decode(savedPublicKey);
        final publicKey = SimplePublicKey(pubBytes, type: KeyPairType.ed25519);
        _keyPair = SimpleKeyPairData(
          privBytes,
          publicKey: publicKey,
          type: KeyPairType.ed25519,
        );
      } catch (_) {
        // 恢復失敗，重新生成
        _keyPair = null;
      }
    }

    // 從舊版 SharedPreferences 遷移到 Secure Storage
    if (_keyPair == null) {
      final legacyPriv = prefs.getString(_privKeyKey);
      final legacyPub = prefs.getString(_pubKeyKey);
      if (legacyPriv != null && legacyPub != null) {
        try {
          final privBytes = base64Decode(legacyPriv);
          final pubBytes = base64Decode(legacyPub);
          final publicKey = SimplePublicKey(pubBytes, type: KeyPairType.ed25519);
          _keyPair = SimpleKeyPairData(
            privBytes,
            publicKey: publicKey,
            type: KeyPairType.ed25519,
          );
          // 遷移至 Secure Storage 並清除舊存儲
          await _secure.write(_privKeyKey, legacyPriv);
          await _secure.write(_pubKeyKey, legacyPub);
          await prefs.remove(_privKeyKey);
          await prefs.remove(_pubKeyKey);
        } catch (_) {
          _keyPair = null;
        }
      }
    }

    // 若沒有已儲存的金鑰，生成新的
    if (_keyPair == null) {
      await _generateAndSave();
    }

    // 設定 HLC nodeId = 公鑰前 8 bytes hex
    // 注意：直接從 _keyPair 取公鑰，避免透過 getOrCreateKeyPair() 造成遞迴
    final extractedPubKey = await _keyPair!.extractPublicKey();
    final pubKeyBytes = extractedPubKey.bytes;
    final nodeId = pubKeyBytes
        .take(8)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    HLC.setNodeId(nodeId);

    _initialized = true;
  }

  Future<void> _generateAndSave() async {
    final algorithm = Ed25519();
    _keyPair = await algorithm.newKeyPair();

    // 持久化至 Secure Storage（Android Keystore / iOS Keychain）
    final privData = await _keyPair!.extractPrivateKeyBytes();
    final pubKey = await _keyPair!.extractPublicKey();
    final pubData = pubKey.bytes;
    await _secure.write(_privKeyKey, base64Encode(privData));
    await _secure.write(_pubKeyKey, base64Encode(pubData));
  }

  /// 獲取或產生本機金鑰對 (Ed25519)
  Future<SimpleKeyPair> getOrCreateKeyPair() async {
    if (!_initialized) await initialize();
    return _keyPair!;
  }

  /// 獲取本機公鑰 (32 bytes)
  Future<List<int>> getPublicKeyBytes() async {
    final pair = await getOrCreateKeyPair();
    final pubKey = await pair.extractPublicKey();
    return pubKey.bytes;
  }

  /// 獲取公鑰的 hex 字串表示
  Future<String> getPublicKeyHex() async {
    final bytes = await getPublicKeyBytes();
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// 獲取本機目前的 Trust Ladder 等級 (0 ~ 3)
  int getIdentityLevel() {
    return _identityLevel;
  }

  /// 升級身分 (例如完成 SMS OTP 或收到 3 個背書後)
  Future<void> upgradeIdentityLevel(int newLevel) async {
    if (newLevel > _identityLevel && newLevel <= 3) {
      _identityLevel = newLevel;
      // 持久化
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('identity_level', newLevel);
    }
  }

  /// 計算 Quarantine 投票權重
  double getQuarantineVoteWeight() {
    switch (_identityLevel) {
      case 0:
        return 0.2;
      case 1:
        return 0.5;
      case 2:
        return 0.8;
      case 3:
        return 1.0;
      default:
        return 0.2;
    }
  }
}
