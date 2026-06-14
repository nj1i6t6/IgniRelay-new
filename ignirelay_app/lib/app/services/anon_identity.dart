// AnonIdentityService — the device's anonymous, rotatable user id (OD-7).
//
// Spec / design: MASTER_EXECUTION_PLAN §5 A2 step 1, PHASE0B4_WIRE_DESIGN §4.
//
// PRESENCE / CHECKPOINT footprints are keyed by a 16-byte `anon_user_id` that
// is DELIBERATELY DECOUPLED from the Ed25519 author key (privacy separation —
// the footprint stream must not be linkable to the signing identity). This
// service mints that id once on first launch and persists it in
// `flutter_secure_storage` (key `anon_user_id_v1`).
//
// Rotation (privacy hygiene — change the id periodically so long-term motion
// can't be reconstructed) is declared here as an interface only; the real
// re-key + grace-window logic lands in a later phase. See [rotate].
//
// CONTRACT (do NOT weaken):
//   • 16 bytes, generated from a CSPRNG (`Random.secure`).
//   • NEVER the Ed25519 public key or any derivative of it.
//   • Persisted in secure storage, stable across launches until rotation.

import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Minimal secure key/value abstraction so [AnonIdentityService] is unit
/// testable without the `flutter_secure_storage` platform channel. Production
/// uses [FlutterSecureKvStore] (wraps the real plugin); tests inject an
/// in-memory fake.
abstract class SecureKvStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// Production [SecureKvStore] backed by `flutter_secure_storage`.
class FlutterSecureKvStore implements SecureKvStore {
  const FlutterSecureKvStore([this._storage = const FlutterSecureStorage()]);

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

class AnonIdentityService {
  /// Secure-storage key for the persisted anon_user_id (hex-encoded). Versioned
  /// so a future rotation scheme can migrate without colliding.
  static const String storageKey = 'anon_user_id_v1';

  /// Wire-fixed length of `anon_user_id` (spec / PresenceData contract).
  static const int idBytes = 16;

  AnonIdentityService({SecureKvStore? store, Random? random})
      : _store = store ?? const FlutterSecureKvStore(),
        _random = random ?? Random.secure();

  final SecureKvStore _store;
  final Random _random;

  Uint8List? _cached;

  /// Return the device's anon_user_id, minting + persisting one on first call.
  /// Stable across launches; cached in memory after first read.
  Future<Uint8List> getOrCreate() async {
    final cached = _cached;
    if (cached != null) return cached;

    final existing = await _store.read(storageKey);
    if (existing != null) {
      final bytes = _tryDecodeHex(existing);
      if (bytes != null && bytes.length == idBytes) {
        _cached = bytes;
        return bytes;
      }
      // Corrupt / wrong-length value — overwrite with a fresh id below.
    }

    final fresh = _random16();
    await _store.write(storageKey, _encodeHex(fresh));
    _cached = fresh;
    return fresh;
  }

  /// Rotate the anon_user_id (privacy hygiene). INTERFACE ONLY for A2; the
  /// re-key + grace-window implementation lands in Phase 2. Wiring callers
  /// against this now keeps the rotation seam explicit.
  Future<Uint8List> rotate() {
    throw UnimplementedError(
      'anon_user_id rotation (re-key + grace window) lands in Phase 2',
    );
  }

  Uint8List _random16() {
    final out = Uint8List(idBytes);
    for (var i = 0; i < idBytes; i++) {
      out[i] = _random.nextInt(256);
    }
    return out;
  }

  static String _encodeHex(Uint8List bytes) {
    final sb = StringBuffer();
    for (final b in bytes) {
      sb.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }

  static Uint8List? _tryDecodeHex(String hex) {
    if (hex.length.isOdd) return null;
    final out = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      final byte = int.tryParse(hex.substring(i * 2, i * 2 + 2), radix: 16);
      if (byte == null) return null;
      out[i] = byte;
    }
    return out;
  }
}
