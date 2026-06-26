// LORA-WIRE v1 vectors consumer test (Stage B / B1).
//
// Pins the committed docs/specs/lora_wire_v1_vectors.json against the reference
// codec in tool/generate_lora_wire_vectors.dart:
//   1. Determinism — buildLoraVectors() is byte-identical to the committed JSON
//      (the gate against silent LoRa-frame drift; regenerate + commit on change).
//   2. Metadata — spec_rev, CRC-16/CCITT-FALSE standard check value 0x29B1,
//      count thresholds (≥40 positive / ≥10 negative).
//   3. Key derivation — lora_mac_key = HKDF(field_join_secret, "ignirelay/
//      lora-mac/v1") reproduced live, and PROVEN distinct from the BLE
//      field_mac_key (domain separation).
//   4. Positive frames — every frame verifies (reason == null), its committed
//      mac8/crc16 match a live recompute, and decode → re-encode is bit-identical.
//   5. Negative frames — every frame is rejected with exactly its declared
//      reason (bad mac / bad crc / ttl=0 / replay / hlc-window / truncated /
//      unknown ptype / unknown version / payload-too-long / length-mismatch).
//   6. Frozen specs carry no TBD / TODO_CONTRACT / PLACEHOLDER.
//
// If this fails after editing the generator or FieldAuthV2.deriveLoraMacKey,
// the codec drifted from the committed vectors. Regenerate via:
//     dart run tool/generate_lora_wire_vectors.dart
// ...then re-run this test (and the sibling B2 Python consumer once it lands).

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ignirelay_app/app/crypto/field_auth_v2.dart';

import '../../tool/generate_lora_wire_vectors.dart' as lora;

const String _vectorsPath = '../docs/specs/lora_wire_v1_vectors.json';
const String _loraSpecPath = '../docs/specs/lora_wire_v1.md';
const String _provSpecPath = '../docs/specs/node_provisioning_v1.md';

Uint8List _hexDecode(String hex) {
  final clean = hex.replaceAll(RegExp(r'\s+'), '');
  final out = Uint8List(clean.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(clean.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

String _hex(List<int> b) =>
    b.map((x) => (x & 0xFF).toRadixString(16).padLeft(2, '0')).join();

void main() {
  late Map<String, dynamic> vectors;
  late Uint8List macKey;

  setUpAll(() {
    final f = File(_vectorsPath);
    expect(f.existsSync(), isTrue,
        reason: 'vectors not generated: run '
            'dart run tool/generate_lora_wire_vectors.dart');
    vectors = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    macKey = _hexDecode(
        (vectors['test_field'] as Map<String, dynamic>)['lora_mac_key_hex']
            as String);
  });

  test('committed vectors are byte-identical to a fresh generation', () async {
    final fresh = await lora.buildLoraVectors();
    final freshJson = const JsonEncoder.withIndent('  ').convert(fresh);
    final onDisk = File(_vectorsPath).readAsStringSync();
    expect(freshJson, onDisk,
        reason: 'LoRa vectors drifted; regenerate and commit');
  });

  test('CRC-16/CCITT-FALSE standard check value "123456789" == 0x29B1', () {
    expect(lora.crc16Ccitt(utf8.encode('123456789')), 0x29B1);
    final self = (vectors['meta'] as Map<String, dynamic>)['crc16_self_test']
        as Map<String, dynamic>;
    expect(self['expected_hex'], '29b1');
    expect(self['actual_hex'], '29b1');
  });

  test('metadata + count thresholds', () {
    final meta = vectors['meta'] as Map<String, dynamic>;
    expect(meta['spec_rev'], 'lora-wire-v1-1');
    expect(meta['wire_version'], 1);
    expect(meta['crc16_algorithm'], 'CRC-16/CCITT-FALSE');
    expect((vectors['frames'] as List).length, greaterThanOrEqualTo(40));
    expect((vectors['negative'] as List).length, greaterThanOrEqualTo(10));
  });

  test('lora_mac_key is reproducible from the corpus secret AND distinct from '
      'the BLE field_mac_key (domain separation)', () async {
    final tf = vectors['test_field'] as Map<String, dynamic>;
    final secret = _hexDecode(tf['field_join_secret_hex'] as String);

    final loraKey = await FieldAuthV2.deriveLoraMacKey(secret);
    expect(_hex(loraKey), tf['lora_mac_key_hex']);

    final fieldMacKey = await FieldAuthV2.deriveFieldMacKey(secret);
    expect(_hex(loraKey) == _hex(fieldMacKey), isFalse,
        reason: 'lora_mac_key and field_mac_key MUST differ (different HKDF '
            'info labels)');

    // field_tag = first 4 bytes of field_id derived from the same secret.
    final fieldId = await FieldAuthV2.deriveFieldId(secret);
    expect(tf['field_tag_hex'], _hex(fieldId.sublist(0, 4)));
  });

  test('every positive frame: verifies, committed mac8/crc16 match, '
      'decode→re-encode is bit-identical', () {
    final frames = vectors['frames'] as List;
    var eventCount = 0;
    var ackCount = 0;
    for (final raw in frames) {
      final s = raw as Map<String, dynamic>;
      final name = s['name'] as String;
      final frame = _hexDecode(s['frame_hex'] as String);

      // Verify accepts (fresh dedupe ring; synced frames use own hlc as local).
      final res = lora.verifyLoraFrame(
        frame,
        loraMacKey: macKey,
        localEstMs: s['hlc_ms'] is int ? s['hlc_ms'] as int : null,
        seenEventIds: <String>{},
      );
      expect(res.reason, isNull, reason: 'positive "$name" rejected');
      expect(res.parsed, isNotNull);

      // Committed trailers match a live recompute.
      final macOff = frame.length - 8 - 2;
      expect(s['mac8_hex'], _hex(frame.sublist(macOff, macOff + 8)));
      expect(s['crc16_hex'], _hex(frame.sublist(frame.length - 2)));

      // Round-trip.
      final re = lora.reencodeLoraFrame(res.parsed!, macKey);
      expect(_hex(re), _hex(frame),
          reason: 'positive "$name" re-encode mismatch');

      if (s['ptype'] == 1) {
        eventCount++;
      } else {
        ackCount++;
      }
    }
    // Both ptypes are represented.
    expect(eventCount, greaterThanOrEqualTo(40));
    expect(ackCount, greaterThanOrEqualTo(3));
  });

  test('canonical compact frame lengths match LORA-WIRE 附錄 C totals', () {
    final byName = <String, Map<String, dynamic>>{
      for (final f in (vectors['frames'] as List))
        (f as Map<String, dynamic>)['name'] as String: f,
    };
    // PRESENCE 58 / SOS 70 / CHECKPOINT 58 / HEARTBEAT 56 (附錄 C).
    expect(byName['presence_flags00_ttl1']!['frame_len'], 58);
    expect(byName['sos_trapped_fix_flags01_ttl3']!['frame_len'], 70);
    expect(byName['checkpoint_flags02_ttl7']!['frame_len'], 58);
    expect(byName['heartbeat_flags04_ttl15']!['frame_len'], 56);
    // ACK fixed 32.
    expect(byName['ack_seq1_status0']!['frame_len'], 32);
  });

  test('every negative frame is rejected with its declared reason', () {
    final reasonsSeen = <String>{};
    for (final raw in (vectors['negative'] as List)) {
      final n = raw as Map<String, dynamic>;
      final name = n['name'] as String;
      final frame = _hexDecode(n['frame_hex'] as String);
      final expect0 = n['expect_reason'] as String;
      final seen = <String>{};
      if (n['precondition_seen_event_id_hex'] != null) {
        seen.add((n['precondition_seen_event_id_hex'] as String).toLowerCase());
      }
      final res = lora.verifyLoraFrame(
        frame,
        loraMacKey: macKey,
        localEstMs: n['local_est_ms'] as int?,
        seenEventIds: seen,
      );
      expect(res.reason, expect0, reason: 'negative "$name"');
      reasonsSeen.add(expect0);
    }
    // The B1 step-3 mandated negative classes are all present.
    expect(
      reasonsSeen,
      containsAll(<String>{
        'mac-mismatch',
        'crc-mismatch',
        'ttl-expired',
        'replay-duplicate',
        'replay-window',
        'truncated',
        'unknown-ptype',
        'unknown-version',
      }),
    );
  });

  test('frozen LoRa specs carry no TBD / TODO_CONTRACT / PLACEHOLDER', () {
    for (final p in [_loraSpecPath, _provSpecPath]) {
      final f = File(p);
      expect(f.existsSync(), isTrue, reason: 'missing spec $p');
      final text = f.readAsStringSync();
      for (final forbidden in ['TBD', 'TODO_CONTRACT', 'PLACEHOLDER']) {
        expect(text.contains(forbidden), isFalse,
            reason: '$p must not contain "$forbidden"');
      }
    }
  });
}
