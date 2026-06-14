// Local field-membership key store for EventEnvelope v3 (Phase 0b #4-3).
//
// Spec: docs/specs/envelope_v2_spec_2026-05-13.md §21.6.
//
// Holds the set of fields this device has joined, keyed by the public
// `field_id`, with the derived `field_mac_key` precomputed so the dispatcher's
// per-envelope membership check (`FieldAuthV2.verifyFieldMac`) is synchronous.
//
// The join/rotation flow that supplies `field_join_secret`s lands in A5
// (FieldSessionStore + ActiveFieldController). Production now wires a store
// populated from the persisted joined fields and flips the dispatcher's
// field-scope check ON (spec §21.6). The store is MUTABLE so a runtime join /
// leave (A5 debug card, A7 QR) updates the SAME instance the dispatcher holds
// by reference — the receive side starts/stops accepting that field's
// envelopes immediately, without rebuilding the dispatcher.

import 'dart:typed_data';

import 'package:ignirelay_app/app/crypto/field_auth_v2.dart';

class FieldKeyStore {
  /// field_id (lowercase hex) → field_mac_key (32 bytes), precomputed.
  final Map<String, Uint8List> _macKeyByFieldIdHex;

  FieldKeyStore._(this._macKeyByFieldIdHex);

  /// No fields joined. Production default until the join flow lands.
  factory FieldKeyStore.empty() => FieldKeyStore._(<String, Uint8List>{});

  /// Build from a list of `field_join_secret`s, deriving field_id + mac_key for
  /// each (spec §21.3). Async because key derivation is async.
  static Future<FieldKeyStore> fromSecrets(List<List<int>> secrets) async {
    final map = <String, Uint8List>{};
    for (final secret in secrets) {
      final fieldId = await FieldAuthV2.deriveFieldId(secret);
      final macKey = await FieldAuthV2.deriveFieldMacKey(secret);
      map[_hex(fieldId)] = macKey;
    }
    return FieldKeyStore._(map);
  }

  /// True when [fieldId] is one of the locally joined fields.
  bool isJoined(Uint8List fieldId) =>
      _macKeyByFieldIdHex.containsKey(_hex(fieldId));

  /// The precomputed field_mac_key for [fieldId], or null when not joined.
  Uint8List? macKeyFor(Uint8List fieldId) => _macKeyByFieldIdHex[_hex(fieldId)];

  int get joinedFieldCount => _macKeyByFieldIdHex.length;

  /// Add a joined field from its ALREADY-DERIVED `field_id` + `field_mac_key`
  /// (A5 runtime join). The caller — [ActiveFieldController] — derives both
  /// once and shares them here so we don't re-run HKDF. Idempotent: re-adding
  /// the same field overwrites with the identical mac key.
  void addDerived(Uint8List fieldId, Uint8List macKey) {
    _macKeyByFieldIdHex[_hex(fieldId)] = Uint8List.fromList(macKey);
  }

  /// Remove a joined field by its lowercase `field_id` hex (A5 leave-field).
  /// No-op when the field was not joined.
  void removeByHex(String fieldIdHex) {
    _macKeyByFieldIdHex.remove(fieldIdHex.toLowerCase());
  }

  static String _hex(List<int> bytes) {
    final sb = StringBuffer();
    for (final b in bytes) {
      sb.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }
}
