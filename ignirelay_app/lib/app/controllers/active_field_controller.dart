// ActiveFieldController — the runtime "which field am I in" state (A5 / 4-7).
//
// Spec: docs/specs/envelope_v2_spec_2026-05-13.md §21;
//        docs/MASTER_EXECUTION_PLAN.md A5 steps 2–4, 施工筆記 4 & 6.
//
// Two roles, one source of truth:
//   • SEND side — the single "active field" supplies the (field_id, mac_key)
//     the publish facade signs every non-control envelope under. v1 has ONE
//     active field for sending; the multi-field switcher UI lands in A7. When
//     no field is joined the facade rejects non-control publishes (`noField`).
//   • RECEIVE side — ALL joined fields are exposed through a single mutable
//     [FieldKeyStore] shared by reference with the production
//     `EnvelopeDispatcherV2` (field-scope + field-mac check, §21.6). A runtime
//     join / leave mutates that same store, so the receive side starts / stops
//     accepting a field immediately without rebuilding the dispatcher.
//
// Secrets never live here. The `field_join_secret` stays in secure storage
// (FieldSessionStore); this controller derives the public `field_id` and the
// `field_mac_key` from it on load / join and holds only those derived values.

import 'dart:math';

import 'package:flutter/foundation.dart';

import 'package:ignirelay_app/app/crypto/field_auth_v2.dart';
import 'package:ignirelay_app/app/services/field_key_store.dart';
import 'package:ignirelay_app/app/services/field_session_store.dart';

/// Stage A field membership role (UI-F3). Derived purely from local
/// create-vs-join — `owner` = this device created the field, `participant` =
/// it joined an existing one — never from a second field secret (RD-1 / F0-7).
///
/// `staff` is a RESERVED future role (Stage E cloud staff-token); it is
/// intentionally NOT an enum case here so Stage A can never fabricate it from
/// an offline field. Add it only when the cloud staff path lands.
enum FieldRole { owner, participant }

/// One joined field's derived crypto + display state, as the publish path and
/// the debug / field UI consume it. Never carries the `field_join_secret`.
class ActiveField {
  /// Lowercase hex of `field_id = SHA-256(secret)[0..15]` (32 hex chars).
  final String fieldIdHex;

  /// `field_id` bytes (16) — the public scope label signed into the envelope.
  final Uint8List fieldId;

  /// `field_mac_key` (32) — HKDF(secret); MACs the canonical sig input (§21.5).
  final Uint8List macKey;

  /// Human-readable field name (debug card / field list). NOT a secret.
  final String displayName;

  /// (v1.2) Cloud base URL for this field; null for offline fields. Unused
  /// before Stage E (E4).
  final String? cloudBaseUrl;

  /// (v14 / UI-F3) Membership role for this device in this field. Defaults to
  /// `participant`; `owner` only when this device created the field.
  final FieldRole role;

  const ActiveField({
    required this.fieldIdHex,
    required this.fieldId,
    required this.macKey,
    required this.displayName,
    this.cloudBaseUrl,
    this.role = FieldRole.participant,
  });

  /// First 8 hex chars of the field_id — the short label the debug card shows.
  String get shortId =>
      fieldIdHex.length <= 8 ? fieldIdHex : fieldIdHex.substring(0, 8);

  /// `true` when this device owns (created) the field — gates owner-only UI
  /// such as re-sharing the join QR (UI-F3 / D5).
  bool get isOwner => role == FieldRole.owner;
}

class ActiveFieldController extends ChangeNotifier {
  final FieldSessionStore _store;

  /// Mutable membership key store shared (by reference) with the production
  /// dispatcher. Joins / leaves mutate this in place so the receive-side
  /// field-scope check reflects them immediately.
  final FieldKeyStore _keyStore;

  final List<ActiveField> _fields = <ActiveField>[];
  String? _activeHex;

  ActiveFieldController({
    required FieldSessionStore store,
    FieldKeyStore? keyStore,
  })  : _store = store,
        _keyStore = keyStore ?? FieldKeyStore.empty();

  /// The shared receive-side key store to hand the dispatcher
  /// (`fieldKeys: controller.keyStore`).
  FieldKeyStore get keyStore => _keyStore;

  /// The currently active sending field, or `null` when no field is joined.
  ActiveField? get active {
    final hex = _activeHex;
    if (hex == null) return null;
    for (final f in _fields) {
      if (f.fieldIdHex == hex) return f;
    }
    return null;
  }

  bool get hasActiveField => active != null;

  /// All joined fields, in join order (oldest first).
  List<ActiveField> get joinedFields => List<ActiveField>.unmodifiable(_fields);

  int get joinedFieldCount => _fields.length;

  /// Load persisted sessions → re-derive (field_id, mac_key) from each secret →
  /// populate the shared key store + the field list. The active sending field
  /// becomes the first joined field (or none). Safe to call once at startup;
  /// rebuilds from scratch if called again.
  Future<void> initialize() async {
    _fields.clear();
    final sessions = await _store.loadAll();
    for (final s in sessions) {
      final secret = await _store.secretFor(s.fieldIdHex);
      if (secret == null) {
        // Metadata row without a recoverable secret (secure-storage cleared /
        // corrupt). Skip — it can't sign or verify. A later A7 "repair" flow
        // may prune the orphan row; A5 just ignores it.
        continue;
      }
      final field =
          await _deriveField(secret, s.displayName, s.cloudBaseUrl, s.createdHere);
      _keyStore.addDerived(field.fieldId, field.macKey);
      _fields.add(field);
    }
    _activeHex = _fields.isNotEmpty ? _fields.first.fieldIdHex : null;
    notifyListeners();
  }

  /// Join a field by its raw 32-byte `field_join_secret` (A5 debug card; A7 QR
  /// / code). Persists it, derives keys, adds it to the shared key store + the
  /// field list, and makes it the active sending field. Idempotent on field_id.
  Future<ActiveField> joinBySecret(
    List<int> secret, {
    required String displayName,
    String? cloudBaseUrl,
    bool createdHere = false,
  }) async {
    final session = await _store.join(
      secret,
      displayName: displayName,
      cloudBaseUrl: cloudBaseUrl,
      createdHere: createdHere,
    );
    // Derive the role from the store's EFFECTIVE (merged) flag, not the
    // incoming param: a re-join of an owned field keeps owner in memory too.
    final field = await _deriveField(
      secret,
      session.displayName,
      session.cloudBaseUrl,
      session.createdHere,
    );
    _keyStore.addDerived(field.fieldId, field.macKey);
    _fields.removeWhere((f) => f.fieldIdHex == field.fieldIdHex);
    _fields.add(field);
    _activeHex = field.fieldIdHex;
    notifyListeners();
    return field;
  }

  /// Create a brand-new field: generate a fresh random 32-byte
  /// `field_join_secret`, join it (persist + derive + make active), and return
  /// both the joined field AND that secret so the caller can render its join
  /// QR (A7 "建立場域→顯示 QR"). The secret is handed back exactly once for
  /// display; it otherwise lives only in secure storage (see
  /// [exportSecretForQr]) and must never be logged or copied to the clipboard.
  Future<({ActiveField field, Uint8List secret})> createField({
    required String displayName,
    String? cloudBaseUrl,
  }) async {
    final secret = _randomSecret();
    final field = await joinBySecret(
      secret,
      displayName: displayName,
      cloudBaseUrl: cloudBaseUrl,
      createdHere: true, // creator → role owner (UI-F3 / D5).
    );
    return (field: field, secret: secret);
  }

  /// Re-read a JOINED field's `field_join_secret` from secure storage so the UI
  /// can re-display its join QR to another device. Returns `null` if the field
  /// is not joined or its secret is missing. For QR rendering only — the secret
  /// must not be logged or placed on the clipboard.
  Future<Uint8List?> exportSecretForQr(String fieldIdHex) =>
      _store.secretFor(fieldIdHex.toLowerCase());

  /// Switch the active sending field to a joined field. No-op (no notify) when
  /// [fieldIdHex] is not joined.
  void setActive(String fieldIdHex) {
    final hex = fieldIdHex.toLowerCase();
    if (hex == _activeHex) return;
    if (_fields.any((f) => f.fieldIdHex == hex)) {
      _activeHex = hex;
      notifyListeners();
    }
  }

  /// Leave a field: drop its secret + metadata (FieldSessionStore) and its
  /// derived key (shared key store) so the receive side stops accepting it.
  /// Irreversible. When the active field is left, the active slot falls back to
  /// the first remaining joined field (or none).
  Future<void> leave(String fieldIdHex) async {
    final hex = fieldIdHex.toLowerCase();
    await _store.leave(hex);
    _keyStore.removeByHex(hex);
    _fields.removeWhere((f) => f.fieldIdHex == hex);
    if (_activeHex == hex) {
      _activeHex = _fields.isNotEmpty ? _fields.first.fieldIdHex : null;
    }
    notifyListeners();
  }

  /// Resolve a JOINED field's `field_mac_key` by its `field_id` — used by the
  /// publish facade at drain time to re-bind a queued envelope to the field it
  /// was enqueued under (returns `null` if that field has since been left).
  Uint8List? macKeyForFieldId(Uint8List fieldId) =>
      _keyStore.macKeyFor(fieldId);

  static Uint8List _randomSecret() {
    final rng = Random.secure();
    final out = Uint8List(32);
    for (var i = 0; i < out.length; i++) {
      out[i] = rng.nextInt(256);
    }
    return out;
  }

  static Future<ActiveField> _deriveField(
    List<int> secret,
    String displayName,
    String? cloudBaseUrl,
    bool createdHere,
  ) async {
    final fieldId = await FieldAuthV2.deriveFieldId(secret);
    final macKey = await FieldAuthV2.deriveFieldMacKey(secret);
    return ActiveField(
      fieldIdHex: _hex(fieldId),
      fieldId: fieldId,
      macKey: macKey,
      displayName: displayName,
      cloudBaseUrl: cloudBaseUrl,
      role: createdHere ? FieldRole.owner : FieldRole.participant,
    );
  }

  static String _hex(List<int> bytes) {
    final sb = StringBuffer();
    for (final b in bytes) {
      sb.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }
}
