// Field scoping & membership auth for EventEnvelope v3 (Phase 0b #4-3).
//
// Spec: docs/specs/envelope_v2_spec_2026-05-13.md §21.
//
// Two independent proofs ride a v3 envelope:
//   - Ed25519 signature → AUTHOR IDENTITY  (who signed; see canonical_encoder_v2)
//   - field_mac (HMAC)  → FIELD MEMBERSHIP (the signer holds the field secret)
//
// This module is the field-membership half. `field_id` is a PUBLIC scope label
// derived one-way from the per-field shared secret; `field_mac` is an HMAC over
// the SAME canonical bytes the Ed25519 signature covers (but the field_mac is
// NOT itself part of those bytes — see §21.4, no circular dependency).
//
//   field_id      = SHA-256(field_join_secret)[0..15]
//   field_mac_key = HKDF-SHA256(ikm=field_join_secret, salt=∅, info=INFO, L=32)
//   field_mac     = HMAC-SHA256(field_mac_key, canonical_sig_input_v3)[0..15]
//
// The join/rotation flow that distributes `field_join_secret` is out of scope
// here (a later phase); §21 fixes only the on-wire crypto contract.

import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

class FieldAuthV2 {
  /// 16 zero bytes — the control-frame / "no field" `field_id` (spec §21.7).
  static Uint8List zeroFieldId() => Uint8List(FieldAuthV2.fieldIdBytes);

  /// HKDF domain-separation label (spec §21.3). MUST match across
  /// Dart/Kotlin/Swift/MCU or the derived MAC keys diverge.
  static const String hkdfInfo = 'ignirelay/field-mac/v3';

  /// HKDF domain-separation label for the LoRa link MAC key
  /// (`lora_wire_v1.md` §6 / MASTER §6 B1). Derived from the SAME
  /// `field_join_secret` but a DIFFERENT `info` than [hkdfInfo], so the BLE
  /// field-membership key and the LoRa link key are cryptographically
  /// independent (domain separation). MUST match across Dart/Python/MCU.
  static const String loraMacHkdfInfo = 'ignirelay/lora-mac/v1';

  static const int fieldIdBytes = 16;
  static const int fieldMacBytes = 16;

  /// `field_id = SHA-256(field_join_secret)[0..15]`. One-way and public:
  /// knowing field_id does not reveal the secret.
  static Future<Uint8List> deriveFieldId(List<int> fieldJoinSecret) async {
    final digest = await Sha256().hash(fieldJoinSecret);
    return Uint8List.fromList(digest.bytes.sublist(0, fieldIdBytes));
  }

  /// `field_mac_key = HKDF-SHA256(ikm=secret, salt=empty, info=hkdfInfo, L=32)`.
  /// Empty salt → RFC 5869 substitutes HashLen (32) zero bytes.
  static Future<Uint8List> deriveFieldMacKey(List<int> fieldJoinSecret) async {
    final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
    final secretKey = await hkdf.deriveKey(
      secretKey: SecretKey(fieldJoinSecret),
      nonce: const <int>[], // salt = empty
      info: utf8.encode(hkdfInfo),
    );
    return Uint8List.fromList(await secretKey.extractBytes());
  }

  /// `lora_mac_key = HKDF-SHA256(ikm=secret, salt=empty, info=loraMacHkdfInfo,
  /// L=32)`. Same construction as [deriveFieldMacKey] but a different `info`
  /// label → a different key (domain separation; `lora_wire_v1.md` §6). The
  /// author Ed25519 signature does NOT ride LoRa (OD-2); LoRa authenticity is
  /// this field-scoped HMAC plus the originating node's identity.
  static Future<Uint8List> deriveLoraMacKey(List<int> fieldJoinSecret) async {
    final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
    final secretKey = await hkdf.deriveKey(
      secretKey: SecretKey(fieldJoinSecret),
      nonce: const <int>[], // salt = empty
      info: utf8.encode(loraMacHkdfInfo),
    );
    return Uint8List.fromList(await secretKey.extractBytes());
  }

  /// `field_mac = HMAC-SHA256(field_mac_key, canonicalSigInput)[0..15]`.
  static Future<Uint8List> computeFieldMac(
    List<int> fieldMacKey,
    List<int> canonicalSigInput,
  ) async {
    final mac = await Hmac.sha256().calculateMac(
      canonicalSigInput,
      secretKey: SecretKey(fieldMacKey),
    );
    return Uint8List.fromList(mac.bytes.sublist(0, fieldMacBytes));
  }

  /// Verify a received `field_mac` against the expected MAC over
  /// [canonicalSigInput]. Length-checks first, then a constant-time compare.
  static Future<bool> verifyFieldMac(
    List<int> fieldMacKey,
    List<int> canonicalSigInput,
    List<int> fieldMac,
  ) async {
    if (fieldMac.length != fieldMacBytes) return false;
    final expected = await computeFieldMac(fieldMacKey, canonicalSigInput);
    return constantTimeEquals(expected, fieldMac);
  }

  /// Control-range event types (100–129) are link negotiation, not field
  /// events; the dispatcher exempts them from field-scope / field-mac (§21.7).
  static bool isControlEventType(int eventType) =>
      eventType >= 100 && eventType <= 129;

  /// Whether [fieldId] is all zeros (the control-frame / "no field" marker).
  static bool isZeroFieldId(List<int> fieldId) {
    for (final b in fieldId) {
      if (b != 0) return false;
    }
    return true;
  }

  static bool constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}
