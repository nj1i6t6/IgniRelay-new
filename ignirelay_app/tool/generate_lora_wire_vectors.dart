// LORA-WIRE v1 conformance vector generator (Stage B / B1).
//
// Spec: docs/specs/lora_wire_v1.md  (this script is the SOLE source of truth
// for the LoRa link-frame test vectors — MASTER_EXECUTION_PLAN §6 B1, G7).
// Sibling implementations (lab/gateway Python in B2+, field-node C in B6+)
// CONSUME docs/specs/lora_wire_v1_vectors.json and MUST NOT regenerate it.
//
// The TEST-ONLY `field_join_secret` is NOT defined here: it is read from the
// already-frozen wire conformance corpus (docs/specs/wire_conformance_v1.json
// #test_field) so the envelope corpus and these LoRa vectors share one key and
// can be cross-checked (MASTER §6 B1 施工筆記 5). This generator touches NONE of
// the A12-frozen envelope contract — it only derives a NEW, domain-separated
// LoRa MAC key from that same secret (info = "ignirelay/lora-mac/v1").
//
// Output: ../docs/specs/lora_wire_v1_vectors.json  (byte-deterministic; no
// wall-clock fields; revision tracked via meta.spec_rev).
//
// Usage:
//   dart run tool/generate_lora_wire_vectors.dart           # write to disk
//   dart run tool/generate_lora_wire_vectors.dart --check   # exit 2 on drift
//
// Exit codes:
//   0 — vectors regenerated + written (or --check passed)
//   1 — input corpus missing/malformed
//   2 — output unwritable / --check detected drift
//   3 — built-in self-check failed (encode→decode→re-encode mismatch, or a
//       positive vector did not verify, or a negative did not reject with its
//       declared reason). This is the DoD-D2 invariant.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto_pkg;
import 'package:ignirelay_app/app/crypto/field_auth_v2.dart';
import 'package:ignirelay_app/app/proto/event_envelope_v2.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Constants — single source = docs/specs/lora_wire_v1.md
// ─────────────────────────────────────────────────────────────────────────────

const String _outputPath = '../docs/specs/lora_wire_v1_vectors.json';
const String _corpusPath = '../docs/specs/wire_conformance_v1.json';
const String _specPath = 'docs/specs/lora_wire_v1.md';

/// Frozen vectors revision. Bumping requires Owner approval (G6).
const String _specRev = 'lora-wire-v1-1';

/// LoRa frame layout (lora_wire_v1.md §3). All multi-byte integers little-endian.
const int _kWireVersion = 0x1; // high nibble of ver_ptype
const int _kPtypeEvent = 0x1; // low nibble
const int _kPtypeAck = 0x2;
const int _kHdrBytes = 11;
const int _kMac8Bytes = 8;
const int _kCrc16Bytes = 2;
const int _kEventIdBytes = 16;
const int _kAckBodyBytes = 11; // ack_seq(2)+event_id_prefix(8)+status(1)
const int _kAckFrameBytes =
    _kHdrBytes + _kAckBodyBytes + _kMac8Bytes + _kCrc16Bytes; // 32
const int _kMaxPayloadBytes = 64;

/// EVENT body bytes up to & including payload_len (event_id+et+pri+hlc+len).
const int _kEventPrefixBytes = _kEventIdBytes + 1 + 1 + 8 + 1; // 27
const int _kEventMinFrameBytes =
    _kHdrBytes + _kEventPrefixBytes + _kMac8Bytes + _kCrc16Bytes; // 48 (payload=0)

/// flags bitfield (§3.1).
const int _kFlagHlcSynced = 0x01; // bit0
const int _kFlagRetransmission = 0x02; // bit1
const int _kFlagMuleOrigin = 0x04; // bit2

/// HLC replay window for `hlc_synced` EVENT frames (§7). 48 hours in ms.
const int _kHlcReplayWindowMs = 48 * 60 * 60 * 1000;

/// CRC-16/CCITT-FALSE standard check value: "123456789" → 0x29B1.
const String _kCrcCheckInput = '123456789';
const int _kCrcCheckExpected = 0x29B1;

const int _baseHlcMs = 1747350000000; // 2026-05-15 13:00:00 UTC (corpus anchor)

// ─────────────────────────────────────────────────────────────────────────────
// main()
// ─────────────────────────────────────────────────────────────────────────────

Future<int> main(List<String> args) async {
  final checkMode = args.contains('--check');

  late Map<String, dynamic> vectors;
  try {
    vectors = await buildLoraVectors();
  } on FormatException catch (e) {
    stderr.writeln('generate_lora_wire_vectors: $e');
    return 1;
  }

  // DoD D2: built-in self-check runs in BOTH modes before anything is written.
  final selfCheck = _runSelfCheck(vectors);
  if (selfCheck != null) {
    stderr.writeln('generate_lora_wire_vectors: self-check FAILED — $selfCheck');
    return 3;
  }

  final encoded = const JsonEncoder.withIndent('  ').convert(vectors);
  final outFile = File(_outputPath);

  if (checkMode) {
    if (!outFile.existsSync()) {
      stderr.writeln('generate_lora_wire_vectors: --check failed; '
          'vectors file missing at ${outFile.path}');
      return 2;
    }
    if (outFile.readAsStringSync() != encoded) {
      stderr.writeln('generate_lora_wire_vectors: --check failed; '
          'regenerated vectors differ from disk. Run without --check to '
          'update, then re-run tests.');
      return 2;
    }
    stdout.writeln('generate_lora_wire_vectors: --check OK '
        '(vectors deterministic + up to date; self-check passed)');
    return 0;
  }

  outFile.parent.createSync(recursive: true);
  outFile.writeAsStringSync(encoded);
  stdout.writeln('generate_lora_wire_vectors: wrote ${outFile.path}');
  stdout.writeln('  frames=${(vectors['frames'] as List).length}');
  stdout.writeln('  negative=${(vectors['negative'] as List).length}');
  stdout.writeln('  self-check: PASS');
  return 0;
}

// ─────────────────────────────────────────────────────────────────────────────
// buildLoraVectors() — reads the frozen corpus for the TEST key, derives the
// (domain-separated) LoRa key, emits frames + negatives. No writes. Called by
// main() and by test/conformance/lora_wire_vectors_test.dart.
// ─────────────────────────────────────────────────────────────────────────────

Future<Map<String, dynamic>> buildLoraVectors() async {
  final corpusFile = File(_corpusPath);
  if (!corpusFile.existsSync()) {
    throw const FormatException('wire conformance corpus missing: $_corpusPath '
        '(LoRa vectors reuse its TEST-ONLY field_join_secret)');
  }
  final corpus =
      jsonDecode(corpusFile.readAsStringSync()) as Map<String, dynamic>;
  final testField = corpus['test_field'] as Map<String, dynamic>?;
  if (testField == null || testField['field_join_secret_hex'] == null) {
    throw const FormatException(
        'corpus test_field.field_join_secret_hex missing in $_corpusPath');
  }
  final secret = _hexDecode(testField['field_join_secret_hex'] as String);
  final fieldId = await FieldAuthV2.deriveFieldId(secret);
  final loraMacKey = await FieldAuthV2.deriveLoraMacKey(secret);
  final fieldTag = Uint8List.fromList(fieldId.sublist(0, 4));

  // Sanity: the LoRa key MUST differ from the BLE field-mac key (domain
  // separation). If a refactor ever collapses the two `info` labels this throws.
  final fieldMacKey = await FieldAuthV2.deriveFieldMacKey(secret);
  if (_constantTimeEq(loraMacKey, fieldMacKey)) {
    throw const FormatException('domain separation broken: lora_mac_key == '
        'field_mac_key (info labels collided)');
  }

  final frames = _buildPositiveFrames(loraMacKey, fieldTag);
  final negative = _buildNegativeFrames(loraMacKey, fieldTag);

  return <String, dynamic>{
    'meta': <String, dynamic>{
      'spec': _specPath,
      'spec_rev': _specRev,
      'generated_by': 'tool/generate_lora_wire_vectors.dart',
      'wire_version': _kWireVersion,
      'crc16_algorithm': 'CRC-16/CCITT-FALSE',
      'crc16_params':
          'poly=0x1021 init=0xFFFF refin=false refout=false xorout=0x0000',
      'crc16_serialization': 'little-endian (low byte first)',
      'crc16_self_test': <String, dynamic>{
        'input_ascii': _kCrcCheckInput,
        'expected_hex': _u16hex(_kCrcCheckExpected),
        'actual_hex': _u16hex(crc16Ccitt(utf8.encode(_kCrcCheckInput))),
      },
      'hlc_replay_window_ms': _kHlcReplayWindowMs,
    },
    'test_field': <String, dynamic>{
      'source': 'docs/specs/wire_conformance_v1.json#test_field (TEST-ONLY)',
      'field_join_secret_hex': testField['field_join_secret_hex'],
      'field_id_hex': _hex(fieldId),
      'field_tag_hex': _hex(fieldTag),
      'lora_mac_key_hex': _hex(loraMacKey),
      'lora_mac_hkdf_info': FieldAuthV2.loraMacHkdfInfo,
    },
    'frames': frames,
    'negative': negative,
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// Positive frames (≥40) — every ptype, every translated event type, boundary
// payload lengths, every flag bit (alone + combined), ttl extremes.
// ─────────────────────────────────────────────────────────────────────────────

List<Map<String, dynamic>> _buildPositiveFrames(
  Uint8List macKey,
  Uint8List fieldTag,
) {
  final out = <Map<String, dynamic>>[];

  // Compact payload variants (lora_wire_v1.md §5).
  final variants = <_PayloadVariant>[
    _PayloadVariant(
        'presence',
        EventTypeV2.presence,
        PriorityV2.normal,
        _presencePayload(
            anon: _anon8(0x11), battery: 87, evidSrc: LocationSource.gps)),
    _PayloadVariant(
        'sos_trapped_fix',
        EventTypeV2.statusUpdate,
        PriorityV2.sosRed,
        _sosPayload(
            anon: _anon8(0x22),
            safety: SafetyState.trapped,
            locSrc: LocationSource.gps,
            latE7: 250339805,
            lngE7: 1215654177,
            accM: 12,
            ageS: 30)),
    _PayloadVariant(
        'sos_safe_nofix',
        EventTypeV2.statusUpdate,
        PriorityV2.sosYellow,
        _sosPayload(
            anon: _anon8(0x23),
            safety: SafetyState.safe,
            locSrc: LocationSource.unknown,
            latE7: 0,
            lngE7: 0,
            accM: 0,
            ageS: 0)),
    _PayloadVariant(
        'sos_injured_south',
        EventTypeV2.statusUpdate,
        PriorityV2.sosRed,
        _sosPayload(
            anon: _anon8(0x24),
            safety: SafetyState.injured,
            locSrc: LocationSource.fieldNode,
            latE7: -250339805, // southern/western → exercises signed i32
            lngE7: -1215654177,
            accM: 65535,
            ageS: 65535)),
    _PayloadVariant('checkpoint', EventTypeV2.checkpoint, PriorityV2.status,
        _checkpointPayload(anon: _anon8(0x33), checkpointNode: 7)),
    _PayloadVariant(
        'heartbeat',
        EventTypeV2.heartbeat,
        PriorityV2.normal,
        _heartbeatPayload(
            battery: 73,
            solar: 40,
            uptimeH: 1234,
            queue: 5,
            storagePct: 88,
            fw: 0x0102)),
    _PayloadVariant(
        'hazard_empty_desc',
        EventTypeV2.hazardMarker,
        PriorityV2.alert,
        _hazardPayload(
            type: HazardType.flood,
            sev: 3,
            locSrc: LocationSource.gps,
            latE7: 250339805,
            lngE7: 1215654177,
            accM: 25,
            ageS: 120,
            desc: '')),
    _PayloadVariant(
        'hazard_max_desc',
        EventTypeV2.hazardMarker,
        PriorityV2.alert,
        _hazardPayload(
            type: HazardType.fire,
            sev: 4,
            locSrc: LocationSource.gps,
            latE7: 250339805,
            lngE7: 1215654177,
            accM: 10,
            ageS: 5,
            // 24 ASCII bytes — the §5 HAZARD desc maximum.
            desc: 'collapsed-bridge-on-rt12')),
    _PayloadVariant(
        'hazard_mid_desc',
        EventTypeV2.hazardMarker,
        PriorityV2.alert,
        _hazardPayload(
            type: HazardType.chemical,
            sev: 2,
            locSrc: LocationSource.manual,
            latE7: 250000000,
            lngE7: 1210000000,
            accM: 50,
            ageS: 600,
            desc: 'gas-leak')),
  ];

  // Flag combos: covers each bit alone, none, and all together (§3.1).
  const flagCombos = <int>[
    0x00,
    _kFlagHlcSynced,
    _kFlagRetransmission,
    _kFlagMuleOrigin,
    _kFlagHlcSynced | _kFlagRetransmission | _kFlagMuleOrigin,
  ];

  var seq = 1;
  for (var vi = 0; vi < variants.length; vi++) {
    final v = variants[vi];
    for (var fi = 0; fi < flagCombos.length; fi++) {
      final flags = flagCombos[fi];
      final ttl = _ttlForIndex(vi * flagCombos.length + fi);
      final eventId = _eventId(0x1000 + vi * 16 + fi);
      final hlcMs = _baseHlcMs + (vi * 1000 + fi) * 1000;
      final hlcCtr = fi;
      final srcNode = 7 + vi;
      final frame = encodeEventFrame(
        macKey: macKey,
        flags: flags,
        fieldTag: fieldTag,
        srcNode: srcNode,
        packetSeq: seq,
        ttl: ttl,
        eventId: eventId,
        eventType: v.eventType,
        priority: v.priority,
        hlcMs: hlcMs,
        hlcCtr: hlcCtr,
        payload: v.payload,
      );
      out.add(_frameSample(
        name: '${v.label}_flags${_u8hex(flags)}_ttl$ttl',
        ptype: _kPtypeEvent,
        frame: frame,
        extra: <String, dynamic>{
          'flags': flags,
          'src_node': srcNode,
          'packet_seq': seq,
          'ttl': ttl,
          'event_id_hex': _hex(eventId),
          'event_type': v.eventType,
          'priority': v.priority,
          'hlc_ms': hlcMs,
          'hlc_counter': hlcCtr,
          'payload_len': v.payload.length,
          'payload_hex': _hex(v.payload),
        },
      ));
      seq++;
    }
  }

  // ACK frames — status 0/1/2, a couple of seqs, plus one retransmission flag.
  final ackCases = <List<int>>[
    // [ackSeq, status, flags]
    [1, 0, 0x00],
    [2, 1, 0x00],
    [3, 2, 0x00],
    [258, 0, _kFlagRetransmission],
    [65535, 2, 0x00],
    [0, 0, 0x00],
  ];
  for (var i = 0; i < ackCases.length; i++) {
    final ackSeq = ackCases[i][0];
    final status = ackCases[i][1];
    final flags = ackCases[i][2];
    final prefix = _eventId(0x2000 + i).sublist(0, 8);
    final frame = encodeAckFrame(
      macKey: macKey,
      flags: flags,
      fieldTag: fieldTag,
      srcNode: 99,
      packetSeq: seq,
      ttl: 3,
      ackSeq: ackSeq,
      eventIdPrefix: Uint8List.fromList(prefix),
      status: status,
    );
    out.add(_frameSample(
      name: 'ack_seq${ackSeq}_status$status',
      ptype: _kPtypeAck,
      frame: frame,
      extra: <String, dynamic>{
        'flags': flags,
        'src_node': 99,
        'packet_seq': seq,
        'ttl': 3,
        'ack_seq': ackSeq,
        'event_id_prefix_hex': _hex(prefix),
        'status': status,
      },
    ));
    seq++;
  }

  return out;
}

// ─────────────────────────────────────────────────────────────────────────────
// Negative frames (≥10) — each mutates a valid base so exactly ONE check fires
// (the receive pipeline order is fixed in lora_wire_v1.md §8).
// ─────────────────────────────────────────────────────────────────────────────

List<Map<String, dynamic>> _buildNegativeFrames(
  Uint8List macKey,
  Uint8List fieldTag,
) {
  final out = <Map<String, dynamic>>[];

  final basePayload = _sosPayload(
    anon: _anon8(0x55),
    safety: SafetyState.trapped,
    locSrc: LocationSource.gps,
    latE7: 250339805,
    lngE7: 1215654177,
    accM: 12,
    ageS: 30,
  );
  const baseHlc = 1747350123000;
  Uint8List mkBase({int ttl = 5, int flags = _kFlagHlcSynced}) =>
      encodeEventFrame(
        macKey: macKey,
        flags: flags,
        fieldTag: fieldTag,
        srcNode: 7,
        packetSeq: 4242,
        ttl: ttl,
        eventId: _eventId(0x5555),
        eventType: EventTypeV2.statusUpdate,
        priority: PriorityV2.sosRed,
        hlcMs: baseHlc,
        hlcCtr: 0,
        payload: basePayload,
      );

  // 1) bad_crc — flip a CRC byte only → caught at the CRC step.
  {
    final f = mkBase();
    f[f.length - 1] ^= 0xFF;
    out.add(_negative('bad_crc', f, 'crc-mismatch'));
  }

  // 2) body_corrupt_caught_by_crc — flip a payload byte, leave CRC stale.
  {
    final f = mkBase();
    f[_kHdrBytes + _kEventIdBytes + 4] ^= 0xFF; // a payload byte
    out.add(_negative('body_corrupt_caught_by_crc', f, 'crc-mismatch'));
  }

  // 3) bad_mac — flip a MAC8 byte AND recompute CRC so it survives to the MAC
  // step (models forgery, not corruption).
  {
    final f = mkBase();
    final macOff = f.length - _kMac8Bytes - _kCrc16Bytes;
    f[macOff] ^= 0xFF;
    _restampCrc(f);
    out.add(_negative('bad_mac', f, 'mac-mismatch'));
  }

  // 4) ttl_zero — valid integrity, ttl=0 → dropped (never relayed further).
  {
    final f = mkBase(ttl: 0);
    out.add(_negative('ttl_zero', f, 'ttl-expired'));
  }

  // 5) hlc_window_out — hlc_synced frame whose hlc is > 48h from local_est.
  {
    final f = encodeEventFrame(
      macKey: macKey,
      flags: _kFlagHlcSynced,
      fieldTag: fieldTag,
      srcNode: 7,
      packetSeq: 4243,
      ttl: 5,
      eventId: _eventId(0x5556),
      eventType: EventTypeV2.statusUpdate,
      priority: PriorityV2.sosRed,
      hlcMs: baseHlc,
      hlcCtr: 0,
      payload: basePayload,
    );
    out.add(_negative('hlc_window_out', f, 'replay-window',
        localEstMs: baseHlc + _kHlcReplayWindowMs + 60000));
  }

  // 6) replay_duplicate — valid frame; precondition: event_id already seen.
  {
    final f = mkBase();
    out.add(_negative('replay_duplicate', f, 'replay-duplicate',
        seenEventIdHex: _hex(_eventId(0x5555))));
  }

  // 7) truncated — cut below the 11-byte header.
  {
    final f = mkBase();
    out.add(_negative(
        'truncated', Uint8List.fromList(f.sublist(0, 10)), 'truncated'));
  }

  // 8) length_mismatch — valid EVENT plus one trailing junk byte.
  {
    final f = mkBase();
    final padded = Uint8List(f.length + 1)..setRange(0, f.length, f);
    padded[f.length] = 0xAB;
    out.add(_negative('length_mismatch', padded, 'length-mismatch'));
  }

  // 9) unknown_ptype — low nibble = 0x3 (reserved); restamp MAC + CRC so the
  // structural ptype check is what rejects it.
  {
    final f = mkBase();
    f[0] = (_kWireVersion << 4) | 0x3;
    _restampMacCrc(f, macKey);
    out.add(_negative('unknown_ptype', f, 'unknown-ptype'));
  }

  // 10) unknown_version — high nibble = 0x9; restamp MAC + CRC.
  {
    final f = mkBase();
    f[0] = (0x9 << 4) | _kPtypeEvent;
    _restampMacCrc(f, macKey);
    out.add(_negative('unknown_version', f, 'unknown-version'));
  }

  // 11) payload_too_long — declared payload_len = 65 (> 64). Built so integrity
  // passes and the §8 payload-len bound is what rejects it.
  {
    final payload = Uint8List(65);
    for (var i = 0; i < payload.length; i++) {
      payload[i] = (i * 7 + 3) & 0xFF;
    }
    final f = encodeEventFrame(
      macKey: macKey,
      flags: 0x00,
      fieldTag: fieldTag,
      srcNode: 7,
      packetSeq: 4244,
      ttl: 5,
      eventId: _eventId(0x5557),
      eventType: EventTypeV2.statusUpdate,
      priority: PriorityV2.normal,
      hlcMs: baseHlc,
      hlcCtr: 0,
      payload: payload,
      allowOversizePayload: true, // generator-only escape hatch for this vector
    );
    out.add(_negative('payload_too_long', f, 'payload-too-long'));
  }

  return out;
}

// ─────────────────────────────────────────────────────────────────────────────
// Built-in self-check (DoD D2). For every positive: verify accepts, decode →
// re-encode is bit-identical, MAC + CRC verify. For every negative: verify()
// returns exactly the declared reason. Returns null on success, else a message.
// ─────────────────────────────────────────────────────────────────────────────

String? _runSelfCheck(Map<String, dynamic> vectors) {
  final macKey = _hexDecode(
      (vectors['test_field'] as Map<String, dynamic>)['lora_mac_key_hex']
          as String);

  final crcSelf = (vectors['meta'] as Map<String, dynamic>)['crc16_self_test']
      as Map<String, dynamic>;
  if (crcSelf['actual_hex'] != crcSelf['expected_hex'] ||
      crcSelf['expected_hex'] != _u16hex(_kCrcCheckExpected)) {
    return 'CRC-16/CCITT-FALSE check value wrong: ${crcSelf['actual_hex']} '
        '(want ${_u16hex(_kCrcCheckExpected)})';
  }

  final frames = vectors['frames'] as List;
  if (frames.length < 40) {
    return 'need >=40 positive frames, got ${frames.length}';
  }
  for (final raw in frames) {
    final s = raw as Map<String, dynamic>;
    final name = s['name'];
    final frame = _hexDecode(s['frame_hex'] as String);
    final v = verifyLoraFrame(
      frame,
      loraMacKey: macKey,
      localEstMs: s['hlc_ms'] is int ? s['hlc_ms'] as int : null,
      seenEventIds: <String>{},
    );
    if (v.reason != null) {
      return 'positive "$name" rejected: ${v.reason}';
    }
    final reencoded = reencodeLoraFrame(v.parsed!, macKey);
    if (!_bytesEq(reencoded, frame)) {
      return 'positive "$name" re-encode mismatch';
    }
  }

  final negatives = vectors['negative'] as List;
  if (negatives.length < 10) {
    return 'need >=10 negative frames, got ${negatives.length}';
  }
  for (final raw in negatives) {
    final n = raw as Map<String, dynamic>;
    final name = n['name'];
    final frame = _hexDecode(n['frame_hex'] as String);
    final expect = n['expect_reason'] as String;
    final seen = <String>{};
    if (n['precondition_seen_event_id_hex'] != null) {
      seen.add((n['precondition_seen_event_id_hex'] as String).toLowerCase());
    }
    final v = verifyLoraFrame(
      frame,
      loraMacKey: macKey,
      localEstMs: n['local_est_ms'] as int?,
      seenEventIds: seen,
    );
    if (v.reason != expect) {
      return 'negative "$name" expected "$expect" got "${v.reason}"';
    }
  }
  return null;
}

// ─────────────────────────────────────────────────────────────────────────────
// LoRa codec — encode / decode / verify / re-encode (lora_wire_v1.md §3, §8).
// Reference implementation the vectors lock; sibling repos reproduce it.
// ─────────────────────────────────────────────────────────────────────────────

/// Parsed structural view of a frame (no MAC/CRC verdict). Re-encodes
/// bit-identically given the same MAC key.
class LoraParsedFrame {
  final int version;
  final int ptype;
  final int flags;
  final Uint8List fieldTag;
  final int srcNode;
  final int packetSeq;
  final int ttl;
  // EVENT only:
  final Uint8List? eventId;
  final int? eventType;
  final int? priority;
  final int? hlcMs;
  final int? hlcCtr;
  final Uint8List? payload;
  // ACK only:
  final int? ackSeq;
  final Uint8List? eventIdPrefix;
  final int? status;

  LoraParsedFrame({
    required this.version,
    required this.ptype,
    required this.flags,
    required this.fieldTag,
    required this.srcNode,
    required this.packetSeq,
    required this.ttl,
    this.eventId,
    this.eventType,
    this.priority,
    this.hlcMs,
    this.hlcCtr,
    this.payload,
    this.ackSeq,
    this.eventIdPrefix,
    this.status,
  });
}

/// Result of [verifyLoraFrame]: `reason == null` ⇒ accepted (`parsed` set).
class LoraVerifyResult {
  final String? reason;
  final LoraParsedFrame? parsed;
  LoraVerifyResult.accept(this.parsed) : reason = null;
  LoraVerifyResult.reject(this.reason) : parsed = null;
}

Uint8List encodeEventFrame({
  required Uint8List macKey,
  required int flags,
  required Uint8List fieldTag,
  required int srcNode,
  required int packetSeq,
  required int ttl,
  required Uint8List eventId,
  required int eventType,
  required int priority,
  required int hlcMs,
  required int hlcCtr,
  required Uint8List payload,
  bool allowOversizePayload = false,
}) {
  if (eventId.length != _kEventIdBytes) {
    throw const FormatException('event_id must be 16 bytes');
  }
  if (!allowOversizePayload && payload.length > _kMaxPayloadBytes) {
    throw FormatException('payload ${payload.length} > $_kMaxPayloadBytes');
  }
  final b = BytesBuilder();
  b.add(_hdr(_kPtypeEvent, flags, fieldTag, srcNode, packetSeq, ttl));
  b.add(eventId);
  b.addByte(eventType & 0xFF);
  b.addByte(priority & 0xFF);
  b.add(_u48le(hlcMs));
  b.add(_u16le(hlcCtr));
  b.addByte(payload.length & 0xFF);
  b.add(payload);
  return _sealFrame(b.toBytes(), macKey);
}

Uint8List encodeAckFrame({
  required Uint8List macKey,
  required int flags,
  required Uint8List fieldTag,
  required int srcNode,
  required int packetSeq,
  required int ttl,
  required int ackSeq,
  required Uint8List eventIdPrefix,
  required int status,
}) {
  if (eventIdPrefix.length != 8) {
    throw const FormatException('event_id_prefix must be 8 bytes');
  }
  final b = BytesBuilder();
  b.add(_hdr(_kPtypeAck, flags, fieldTag, srcNode, packetSeq, ttl));
  b.add(_u16le(ackSeq));
  b.add(eventIdPrefix);
  b.addByte(status & 0xFF);
  return _sealFrame(b.toBytes(), macKey);
}

/// Append mac8 = HMAC-SHA256(key, hdr‖body)[0..7] then crc16 over hdr‖body‖mac8.
Uint8List _sealFrame(Uint8List hdrBody, Uint8List macKey) {
  final mac8 = _loraMac8(macKey, hdrBody);
  final body = Uint8List.fromList([...hdrBody, ...mac8]);
  final crc = crc16Ccitt(body);
  return Uint8List.fromList([...body, ..._u16le(crc)]);
}

/// Re-seal an already-parsed frame; deterministic inverse of decode.
Uint8List reencodeLoraFrame(LoraParsedFrame f, Uint8List macKey) {
  if (f.ptype == _kPtypeEvent) {
    return encodeEventFrame(
      macKey: macKey,
      flags: f.flags,
      fieldTag: f.fieldTag,
      srcNode: f.srcNode,
      packetSeq: f.packetSeq,
      ttl: f.ttl,
      eventId: f.eventId!,
      eventType: f.eventType!,
      priority: f.priority!,
      hlcMs: f.hlcMs!,
      hlcCtr: f.hlcCtr!,
      payload: f.payload!,
    );
  }
  return encodeAckFrame(
    macKey: macKey,
    flags: f.flags,
    fieldTag: f.fieldTag,
    srcNode: f.srcNode,
    packetSeq: f.packetSeq,
    ttl: f.ttl,
    ackSeq: f.ackSeq!,
    eventIdPrefix: f.eventIdPrefix!,
    status: f.status!,
  );
}

/// Full receive pipeline in the §8 fixed order. Mutates [seenEventIds] on
/// accept (adds the EVENT's event_id). [localEstMs] is required to evaluate the
/// hlc replay window for `hlc_synced` EVENT frames (null ⇒ window not checked).
LoraVerifyResult verifyLoraFrame(
  Uint8List frame, {
  required Uint8List loraMacKey,
  int? localEstMs,
  Set<String>? seenEventIds,
  int hlcReplayWindowMs = _kHlcReplayWindowMs,
}) {
  // 1) structural: minimum header
  if (frame.length < _kHdrBytes) {
    return LoraVerifyResult.reject('truncated');
  }
  final verByte = frame[0];
  final version = (verByte >> 4) & 0x0F;
  final ptype = verByte & 0x0F;
  // 2) version
  if (version != _kWireVersion) {
    return LoraVerifyResult.reject('unknown-version');
  }
  // 3) ptype
  if (ptype != _kPtypeEvent && ptype != _kPtypeAck) {
    return LoraVerifyResult.reject('unknown-ptype');
  }
  final flags = frame[1];
  final fieldTag = Uint8List.fromList(frame.sublist(2, 6));
  final srcNode = _rdU16le(frame, 6);
  final packetSeq = _rdU16le(frame, 8);
  final ttl = frame[10];

  // 4) length determination
  late int expectedLen;
  int? payloadLen;
  if (ptype == _kPtypeAck) {
    expectedLen = _kAckFrameBytes;
    if (frame.length < expectedLen) {
      return LoraVerifyResult.reject('truncated');
    }
    if (frame.length != expectedLen) {
      return LoraVerifyResult.reject('length-mismatch');
    }
  } else {
    if (frame.length < _kEventMinFrameBytes) {
      return LoraVerifyResult.reject('truncated');
    }
    payloadLen = frame[_kHdrBytes + _kEventPrefixBytes - 1]; // the len byte
    if (payloadLen > _kMaxPayloadBytes) {
      return LoraVerifyResult.reject('payload-too-long');
    }
    expectedLen = _kEventMinFrameBytes + payloadLen;
    if (frame.length < expectedLen) {
      return LoraVerifyResult.reject('truncated');
    }
    if (frame.length != expectedLen) {
      return LoraVerifyResult.reject('length-mismatch');
    }
  }

  // 5) CRC16 over hdr‖body‖mac8
  final crcGot = _rdU16le(frame, frame.length - _kCrc16Bytes);
  final crcWant = crc16Ccitt(frame.sublist(0, frame.length - _kCrc16Bytes));
  if (crcGot != crcWant) {
    return LoraVerifyResult.reject('crc-mismatch');
  }

  // 6) MAC8 over hdr‖body
  final macOff = frame.length - _kMac8Bytes - _kCrc16Bytes;
  final macGot = frame.sublist(macOff, macOff + _kMac8Bytes);
  final macWant = _loraMac8(loraMacKey, frame.sublist(0, macOff));
  if (!_constantTimeEq(macGot, macWant)) {
    return LoraVerifyResult.reject('mac-mismatch');
  }

  // 7) TTL
  if (ttl == 0) {
    return LoraVerifyResult.reject('ttl-expired');
  }

  if (ptype == _kPtypeAck) {
    final ackSeq = _rdU16le(frame, _kHdrBytes);
    final prefix = frame.sublist(_kHdrBytes + 2, _kHdrBytes + 10);
    final status = frame[_kHdrBytes + 10];
    // ACK frames carry no event_id / hlc → no replay-window or dedupe.
    return LoraVerifyResult.accept(LoraParsedFrame(
      version: version,
      ptype: ptype,
      flags: flags,
      fieldTag: fieldTag,
      srcNode: srcNode,
      packetSeq: packetSeq,
      ttl: ttl,
      ackSeq: ackSeq,
      eventIdPrefix: Uint8List.fromList(prefix),
      status: status,
    ));
  }

  final eventId = frame.sublist(_kHdrBytes, _kHdrBytes + 16);
  final eventType = frame[_kHdrBytes + 16];
  final priority = frame[_kHdrBytes + 17];
  final hlcMs = _rdU48le(frame, _kHdrBytes + 18);
  final hlcCtr = _rdU16le(frame, _kHdrBytes + 24);
  final payload = frame.sublist(_kHdrBytes + _kEventPrefixBytes,
      _kHdrBytes + _kEventPrefixBytes + payloadLen!);

  // 8) HLC replay window (synced EVENT only)
  if ((flags & _kFlagHlcSynced) != 0 && localEstMs != null) {
    if ((hlcMs - localEstMs).abs() > hlcReplayWindowMs) {
      return LoraVerifyResult.reject('replay-window');
    }
  }

  // 9) event_id dedupe
  final idHex = _hex(eventId);
  if (seenEventIds != null && seenEventIds.contains(idHex)) {
    return LoraVerifyResult.reject('replay-duplicate');
  }
  seenEventIds?.add(idHex);

  return LoraVerifyResult.accept(LoraParsedFrame(
    version: version,
    ptype: ptype,
    flags: flags,
    fieldTag: fieldTag,
    srcNode: srcNode,
    packetSeq: packetSeq,
    ttl: ttl,
    eventId: Uint8List.fromList(eventId),
    eventType: eventType,
    priority: priority,
    hlcMs: hlcMs,
    hlcCtr: hlcCtr,
    payload: Uint8List.fromList(payload),
  ));
}

Uint8List _hdr(int ptype, int flags, Uint8List fieldTag, int srcNode,
    int packetSeq, int ttl) {
  if (fieldTag.length != 4) {
    throw const FormatException('field_tag must be 4 bytes');
  }
  return Uint8List.fromList([
    (_kWireVersion << 4) | (ptype & 0x0F),
    flags & 0xFF,
    ...fieldTag,
    ..._u16le(srcNode),
    ..._u16le(packetSeq),
    ttl & 0xFF,
  ]);
}

// ─────────────────────────────────────────────────────────────────────────────
// CRC-16/CCITT-FALSE  (poly 0x1021, init 0xFFFF, no reflection, xorout 0).
// Standard check: "123456789" → 0x29B1.
// ─────────────────────────────────────────────────────────────────────────────

int crc16Ccitt(List<int> data) {
  var crc = 0xFFFF;
  for (final raw in data) {
    crc ^= (raw & 0xFF) << 8;
    for (var i = 0; i < 8; i++) {
      if ((crc & 0x8000) != 0) {
        crc = ((crc << 1) ^ 0x1021) & 0xFFFF;
      } else {
        crc = (crc << 1) & 0xFFFF;
      }
    }
  }
  return crc & 0xFFFF;
}

/// mac8 = HMAC-SHA256(key, data)[0..7]. Synchronous (package:crypto).
Uint8List _loraMac8(Uint8List key, Uint8List data) {
  final mac = crypto_pkg.Hmac(crypto_pkg.sha256, key).convert(data);
  return Uint8List.fromList(mac.bytes.sublist(0, _kMac8Bytes));
}

// ─────────────────────────────────────────────────────────────────────────────
// Compact payload builders (lora_wire_v1.md §5). All multi-byte LE; lat/lng are
// signed i32 (two's complement) degrees×1e7.
// ─────────────────────────────────────────────────────────────────────────────

Uint8List _presencePayload(
        {required Uint8List anon, required int battery, required int evidSrc}) =>
    Uint8List.fromList([...anon, battery & 0xFF, evidSrc & 0xFF]);

Uint8List _loc13({
  required int src,
  required int latE7,
  required int lngE7,
  required int accM,
  required int ageS,
}) =>
    Uint8List.fromList([
      src & 0xFF,
      ..._i32le(latE7),
      ..._i32le(lngE7),
      ..._u16le(accM),
      ..._u16le(ageS),
    ]);

Uint8List _sosPayload({
  required Uint8List anon,
  required int safety,
  required int locSrc,
  required int latE7,
  required int lngE7,
  required int accM,
  required int ageS,
}) =>
    Uint8List.fromList([
      ...anon,
      safety & 0xFF,
      ..._loc13(
          src: locSrc, latE7: latE7, lngE7: lngE7, accM: accM, ageS: ageS),
    ]);

Uint8List _checkpointPayload(
        {required Uint8List anon, required int checkpointNode}) =>
    Uint8List.fromList([...anon, ..._u16le(checkpointNode)]);

Uint8List _heartbeatPayload({
  required int battery,
  required int solar,
  required int uptimeH,
  required int queue,
  required int storagePct,
  required int fw,
}) =>
    Uint8List.fromList([
      battery & 0xFF,
      solar & 0xFF,
      ..._u16le(uptimeH),
      queue & 0xFF,
      storagePct & 0xFF,
      ..._u16le(fw),
    ]);

Uint8List _hazardPayload({
  required int type,
  required int sev,
  required int locSrc,
  required int latE7,
  required int lngE7,
  required int accM,
  required int ageS,
  required String desc,
}) {
  final descBytes = utf8.encode(desc);
  if (descBytes.length > 24) {
    throw const FormatException('hazard desc > 24 bytes');
  }
  return Uint8List.fromList([
    type & 0xFF,
    sev & 0xFF,
    ..._loc13(src: locSrc, latE7: latE7, lngE7: lngE7, accM: accM, ageS: ageS),
    descBytes.length & 0xFF,
    ...descBytes,
  ]);
}

Uint8List _anon8(int seed) =>
    Uint8List.fromList(List<int>.generate(8, (i) => (seed + i * 17) & 0xFF));

Uint8List _eventId(int seed) {
  final out = Uint8List(16);
  for (var i = 0; i < 16; i++) {
    out[i] = ((seed + i * 31) * 13) & 0xFF;
  }
  return out;
}

int _ttlForIndex(int i) {
  const ladder = [1, 3, 7, 15, 255];
  return ladder[i % ladder.length];
}

class _PayloadVariant {
  final String label;
  final int eventType;
  final int priority;
  final Uint8List payload;
  _PayloadVariant(this.label, this.eventType, this.priority, this.payload);
}

// ─────────────────────────────────────────────────────────────────────────────
// Sample/JSON shaping
// ─────────────────────────────────────────────────────────────────────────────

Map<String, dynamic> _frameSample({
  required String name,
  required int ptype,
  required Uint8List frame,
  required Map<String, dynamic> extra,
}) {
  final macOff = frame.length - _kMac8Bytes - _kCrc16Bytes;
  return <String, dynamic>{
    'name': name,
    'ptype': ptype,
    'ptype_name': ptype == _kPtypeEvent ? 'EVENT' : 'ACK',
    ...extra,
    'frame_len': frame.length,
    'mac8_hex': _hex(frame.sublist(macOff, macOff + _kMac8Bytes)),
    'crc16_hex': _hex(frame.sublist(frame.length - _kCrc16Bytes)),
    'frame_hex': _hex(frame),
  };
}

Map<String, dynamic> _negative(
  String name,
  Uint8List frame,
  String reason, {
  int? localEstMs,
  String? seenEventIdHex,
}) {
  final m = <String, dynamic>{
    'name': name,
    'frame_hex': _hex(frame),
    'expect_reason': reason,
  };
  if (localEstMs != null) m['local_est_ms'] = localEstMs;
  if (seenEventIdHex != null) {
    m['precondition_seen_event_id_hex'] = seenEventIdHex.toLowerCase();
  }
  return m;
}

// Recompute only the CRC trailer (used by bad_mac to survive to the MAC step).
void _restampCrc(Uint8List frame) {
  final crc = crc16Ccitt(frame.sublist(0, frame.length - _kCrc16Bytes));
  final le = _u16le(crc);
  frame[frame.length - 2] = le[0];
  frame[frame.length - 1] = le[1];
}

// Recompute MAC8 + CRC after a header mutation so a structural check (not
// integrity) is what rejects the negative.
void _restampMacCrc(Uint8List frame, Uint8List macKey) {
  final macOff = frame.length - _kMac8Bytes - _kCrc16Bytes;
  final mac8 = _loraMac8(macKey, frame.sublist(0, macOff));
  frame.setRange(macOff, macOff + _kMac8Bytes, mac8);
  _restampCrc(frame);
}

// ─────────────────────────────────────────────────────────────────────────────
// LE / hex helpers
// ─────────────────────────────────────────────────────────────────────────────

List<int> _u16le(int v) => [v & 0xFF, (v >> 8) & 0xFF];

List<int> _u48le(int v) => [
      v & 0xFF,
      (v >> 8) & 0xFF,
      (v >> 16) & 0xFF,
      (v >> 24) & 0xFF,
      (v >> 32) & 0xFF,
      (v >> 40) & 0xFF,
    ];

List<int> _i32le(int v) {
  final u = v & 0xFFFFFFFF; // two's complement
  return [u & 0xFF, (u >> 8) & 0xFF, (u >> 16) & 0xFF, (u >> 24) & 0xFF];
}

int _rdU16le(Uint8List b, int off) => b[off] | (b[off + 1] << 8);

int _rdU48le(Uint8List b, int off) =>
    b[off] |
    (b[off + 1] << 8) |
    (b[off + 2] << 16) |
    (b[off + 3] << 24) |
    (b[off + 4] << 32) |
    (b[off + 5] << 40);

String _hex(List<int> bytes) {
  final sb = StringBuffer();
  for (final b in bytes) {
    sb.write((b & 0xFF).toRadixString(16).padLeft(2, '0'));
  }
  return sb.toString();
}

String _u8hex(int v) => (v & 0xFF).toRadixString(16).padLeft(2, '0');
String _u16hex(int v) => (v & 0xFFFF).toRadixString(16).padLeft(4, '0');

Uint8List _hexDecode(String hex) {
  final clean = hex.replaceAll(RegExp(r'\s+'), '');
  if (clean.length.isOdd) {
    throw FormatException('odd hex length: $hex');
  }
  final out = Uint8List(clean.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(clean.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

bool _bytesEq(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _constantTimeEq(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var d = 0;
  for (var i = 0; i < a.length; i++) {
    d |= a[i] ^ b[i];
  }
  return d == 0;
}
