// FieldSessionStore — persistence for joined field memberships (A5 / 4-7).
//
// Spec: docs/specs/envelope_v2_spec_2026-05-13.md §21;
//        docs/MASTER_EXECUTION_PLAN.md A5 step 1.
//
// Each joined field is split across TWO stores by sensitivity:
//   • field_join_secret (32 B) — SECRET. flutter_secure_storage, keyed
//     `field_secret_<field_id_hex>`. NEVER SQLite, NEVER plaintext on disk
//     (A5 DoD prohibition). The HKDF-derived mac key is as sensitive as the
//     secret, so it is never persisted either — it is re-derived on load.
//   • session metadata (field_id_hex, display_name, joined_at_ms,
//     cloud_base_url?) — NON-secret. SQLite `Field_Sessions` table so the
//     debug / UI surface can list joined fields cheaply.
//
// `field_id = SHA-256(secret)[0..15]` (FieldAuthV2) is the PUBLIC scope label
// and the join key for both stores. Deriving the field_mac_key from the secret
// is the CALLER's job ([ActiveFieldController]); this store is persistence only
// and holds no crypto state beyond the one-way field_id.

import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:sqflite/sqflite.dart' show ConflictAlgorithm;

import 'package:ignirelay_app/app/crypto/field_auth_v2.dart';
import 'package:ignirelay_app/app/db/database_helper.dart';
// SecureKvStore / FlutterSecureKvStore are the shared secure-storage seam
// introduced for AnonIdentityService (A2); reused here so FieldSessionStore is
// unit-testable without the flutter_secure_storage platform channel.
import 'package:ignirelay_app/app/services/anon_identity.dart'
    show SecureKvStore, FlutterSecureKvStore;

/// One joined field's non-secret metadata. The secret lives in secure storage
/// (see [FieldSessionStore.secretFor]); this struct never carries it.
class FieldSession {
  /// Lowercase hex of `field_id = SHA-256(secret)[0..15]` (32 hex chars).
  final String fieldIdHex;

  /// Human-readable field name (shown in the debug / field UI). NOT a secret.
  final String displayName;

  /// Wall-clock ms when this field was joined.
  final int joinedAtMs;

  /// (v1.2) Cloud service base URL for this field; `null` for offline fields.
  /// Written by A7 when parsing QR segment 3 (`https://` only). No code reads
  /// it before Stage E (E4); an offline field with `null` here behaves
  /// identically to pre-A5.
  final String? cloudBaseUrl;

  /// (v14 / UI-F3) `true` when THIS device CREATED the field (role `owner`);
  /// `false` when it JOINED an existing field (role `participant`). Derived
  /// from local create-vs-join, never from a second field secret. Monotonic:
  /// once `true` it stays `true` across re-joins (see [FieldSessionStore.join]).
  final bool createdHere;

  const FieldSession({
    required this.fieldIdHex,
    required this.displayName,
    required this.joinedAtMs,
    this.cloudBaseUrl,
    this.createdHere = false,
  });
}

class FieldSessionStore {
  /// Secure-storage key prefix for the per-field `field_join_secret` (hex).
  static const String secretKeyPrefix = 'field_secret_';

  final DatabaseHelper _db;
  final SecureKvStore _secure;

  FieldSessionStore({DatabaseHelper? db, SecureKvStore? secureStore})
      : _db = db ?? DatabaseHelper(),
        _secure = secureStore ?? const FlutterSecureKvStore();

  /// All joined sessions, oldest first (join order = `joined_at_ms ASC`).
  Future<List<FieldSession>> loadAll() async {
    final database = await _db.database;
    final rows =
        await database.query('Field_Sessions', orderBy: 'joined_at_ms ASC');
    return rows.map(_fromRow).toList(growable: false);
  }

  /// The persisted `field_join_secret` for a joined field, or `null` when the
  /// field is not joined or its secret is missing / corrupt.
  Future<Uint8List?> secretFor(String fieldIdHex) async {
    String? stored;
    try {
      stored = await _secure.read(_secretKey(fieldIdHex));
    } catch (e) {
      // A11-debug-3: an undecryptable field secret (Android Keystore BAD_DECRYPT
      // — cloud/D2D restore before allowBackup=false, or Keystore invalidation)
      // must NOT crash the field-load path. Degrade to "secret missing" (the
      // documented null contract == field unusable); the user can leave +
      // re-join. We do NOT auto-delete here: leave() is the explicit removal
      // path, and deleting on a transient platform error would be more
      // destructive than a graceful null.
      debugPrint('[FieldSessionStore] secret read failed for '
          '$fieldIdHex ($e); treating as missing');
      return null;
    }
    if (stored == null) return null;
    return _tryDecodeHex(stored);
  }

  /// Persist a newly joined field from its `field_join_secret`.
  ///
  /// Derives the public `field_id`, writes the secret to secure storage and the
  /// metadata row to SQLite, and returns the resulting [FieldSession].
  /// Re-joining an existing field replaces its row (updated name / cloud url)
  /// and refreshes its secret — idempotent on `field_id`.
  ///
  /// [createdHere] records the owner/participant role (v14 / UI-F3). It is
  /// **monotonic**: a re-join can promote participant → owner but NEVER demotes
  /// an existing owner. The returned [FieldSession.createdHere] is the EFFECTIVE
  /// (merged) value, so callers derive the role from the result, not the input.
  Future<FieldSession> join(
    List<int> secret, {
    required String displayName,
    String? cloudBaseUrl,
    int? joinedAtMs,
    bool createdHere = false,
  }) async {
    final fieldId = await FieldAuthV2.deriveFieldId(secret);
    final hex = _hex(fieldId);
    await _secure.write(
      _secretKey(hex),
      _encodeHex(Uint8List.fromList(secret)),
    );
    final database = await _db.database;
    // Sticky-owner: OR the incoming flag with any already-stored value so a
    // plain re-join (createdHere: false) of a field this device created can
    // never downgrade owner → participant.
    final existing = await database.query(
      'Field_Sessions',
      columns: <String>['created_here'],
      where: 'field_id_hex = ?',
      whereArgs: <Object?>[hex],
      limit: 1,
    );
    final existingCreatedHere =
        existing.isNotEmpty && ((existing.first['created_here'] as int?) ?? 0) == 1;
    final effectiveCreatedHere = createdHere || existingCreatedHere;
    final session = FieldSession(
      fieldIdHex: hex,
      displayName: displayName,
      joinedAtMs: joinedAtMs ?? DateTime.now().millisecondsSinceEpoch,
      cloudBaseUrl: cloudBaseUrl,
      createdHere: effectiveCreatedHere,
    );
    await database.insert(
      'Field_Sessions',
      <String, Object?>{
        'field_id_hex': hex,
        'display_name': session.displayName,
        'joined_at_ms': session.joinedAtMs,
        'cloud_base_url': session.cloudBaseUrl,
        'created_here': session.createdHere ? 1 : 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return session;
  }

  /// Leave a field: delete its secret AND its metadata row. Irreversible
  /// (A7 confirms twice before calling). No-op when not joined.
  Future<void> leave(String fieldIdHex) async {
    final hex = fieldIdHex.toLowerCase();
    await _secure.delete(_secretKey(hex));
    final database = await _db.database;
    await database.delete(
      'Field_Sessions',
      where: 'field_id_hex = ?',
      whereArgs: <Object?>[hex],
    );
  }

  String _secretKey(String fieldIdHex) =>
      '$secretKeyPrefix${fieldIdHex.toLowerCase()}';

  static FieldSession _fromRow(Map<String, Object?> row) => FieldSession(
        fieldIdHex: row['field_id_hex'] as String,
        displayName: (row['display_name'] as String?) ?? '',
        joinedAtMs: (row['joined_at_ms'] as int?) ?? 0,
        cloudBaseUrl: row['cloud_base_url'] as String?,
        createdHere: ((row['created_here'] as int?) ?? 0) == 1,
      );

  static String _hex(List<int> bytes) {
    final sb = StringBuffer();
    for (final b in bytes) {
      sb.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }

  static String _encodeHex(Uint8List bytes) => _hex(bytes);

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
