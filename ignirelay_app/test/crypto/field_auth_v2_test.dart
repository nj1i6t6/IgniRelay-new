// Phase 0b #4-3 — field scoping & membership auth crypto (spec §21).

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ignirelay_app/app/crypto/field_auth_v2.dart';

void main() {
  final secret = Uint8List.fromList(List.generate(24, (i) => i + 1));
  final canonical = Uint8List.fromList(List.generate(141, (i) => (i * 3) & 0xFF));

  group('FieldAuthV2', () {
    test('field_id is SHA-256(secret)[0..15], 16 bytes, deterministic', () async {
      final a = await FieldAuthV2.deriveFieldId(secret);
      final b = await FieldAuthV2.deriveFieldId(secret);
      expect(a.length, 16);
      expect(a, b, reason: 'deterministic');
    });

    test('different secrets yield different field_ids', () async {
      final a = await FieldAuthV2.deriveFieldId(secret);
      final b = await FieldAuthV2.deriveFieldId(
          Uint8List.fromList(List.generate(24, (i) => i + 2)));
      expect(a, isNot(b));
    });

    test('field_mac_key is 32 bytes and deterministic', () async {
      final k1 = await FieldAuthV2.deriveFieldMacKey(secret);
      final k2 = await FieldAuthV2.deriveFieldMacKey(secret);
      expect(k1.length, 32);
      expect(k1, k2);
    });

    test('lora_mac_key is 32 bytes and deterministic', () async {
      final k1 = await FieldAuthV2.deriveLoraMacKey(secret);
      final k2 = await FieldAuthV2.deriveLoraMacKey(secret);
      expect(k1.length, 32);
      expect(k1, k2);
    });

    test('lora_mac_key != field_mac_key from the SAME secret '
        '(domain separation — B1)', () async {
      final loraKey = await FieldAuthV2.deriveLoraMacKey(secret);
      final fieldKey = await FieldAuthV2.deriveFieldMacKey(secret);
      expect(loraKey, isNot(fieldKey),
          reason: 'different HKDF info labels MUST yield different keys');
      expect(FieldAuthV2.loraMacHkdfInfo, isNot(FieldAuthV2.hkdfInfo));
    });

    test('different secrets yield different lora_mac_keys', () async {
      final a = await FieldAuthV2.deriveLoraMacKey(secret);
      final b = await FieldAuthV2.deriveLoraMacKey(
          Uint8List.fromList(List.generate(24, (i) => i + 5)));
      expect(a, isNot(b));
    });

    test('field_mac round-trips: compute → verify true', () async {
      final key = await FieldAuthV2.deriveFieldMacKey(secret);
      final mac = await FieldAuthV2.computeFieldMac(key, canonical);
      expect(mac.length, 16);
      expect(await FieldAuthV2.verifyFieldMac(key, canonical, mac), true);
    });

    test('verify fails on tampered canonical', () async {
      final key = await FieldAuthV2.deriveFieldMacKey(secret);
      final mac = await FieldAuthV2.computeFieldMac(key, canonical);
      final tampered = Uint8List.fromList(canonical)..[0] ^= 0xFF;
      expect(await FieldAuthV2.verifyFieldMac(key, tampered, mac), false);
    });

    test('verify fails on wrong field_mac_key (non-member)', () async {
      final key = await FieldAuthV2.deriveFieldMacKey(secret);
      final wrongKey = await FieldAuthV2.deriveFieldMacKey(
          Uint8List.fromList(List.generate(24, (i) => 0xAA ^ i)));
      final mac = await FieldAuthV2.computeFieldMac(key, canonical);
      expect(await FieldAuthV2.verifyFieldMac(wrongKey, canonical, mac), false);
    });

    test('verify rejects wrong-length field_mac', () async {
      final key = await FieldAuthV2.deriveFieldMacKey(secret);
      expect(await FieldAuthV2.verifyFieldMac(key, canonical, Uint8List(15)),
          false);
    });

    test('field_id derived from a secret is NOT all-zero', () async {
      final id = await FieldAuthV2.deriveFieldId(secret);
      expect(FieldAuthV2.isZeroFieldId(id), false);
      expect(FieldAuthV2.isZeroFieldId(FieldAuthV2.zeroFieldId()), true);
    });

    test('control range 100-129 is exempt; others are not', () {
      expect(FieldAuthV2.isControlEventType(100), true);
      expect(FieldAuthV2.isControlEventType(102), true);
      expect(FieldAuthV2.isControlEventType(129), true);
      expect(FieldAuthV2.isControlEventType(3), false);
      expect(FieldAuthV2.isControlEventType(50), false);
      expect(FieldAuthV2.isControlEventType(99), false);
    });
  });
}
