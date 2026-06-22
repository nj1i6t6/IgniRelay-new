import 'dart:typed_data';

/// Invertible Bloom Lookup Table for BLE mesh differential sync.
/// 56 buckets × 9 bytes = 504 bytes (fits in 1 MTU of 517)
/// Bucket: count(1B signed) + keySum(4B CRC32) + hashSum(4B checksum)
/// Tolerates ~38 item differences (56 / 1.5 safety factor)
///
/// Contract `iblt-keyhash-v2` (IBLT-fix): EVERYTHING `peel()` needs is
/// reconstructable from a pure cell's `keySum` (= CRC32(eventId)), because peel
/// no longer has the original event id. Both the bucket indices and the
/// checksum are therefore derived from `keyHash`, NOT from the raw event id:
///
///   keyHash  = CRC32(eventId)
///   keyBytes = uint32_le(keyHash)            // 4 little-endian bytes
///   checkHash= FNV1a(keyBytes)               // hashSum
///   indices  = MurmurHash(keyBytes, seed 0/1/2) % 56
///
/// This replaces the pre-`v2` quirk where `insert` indexed by
/// `MurmurHash(eventId.codeUnits)` and `hashSum = FNV1a(eventId)`, while `peel`
/// re-derived indices by CRC bit-extraction and `verifyChecksum` used
/// `FNV1a(uint32_le(keySum))` — two mismatched derivations that made peel fail
/// on almost every real difference, forcing the Bloom slow path. The external
/// shape (504 bytes, keySum=CRC32 XOR, peel result = uint32 CRC32 hashes) is
/// unchanged; only the internal index/checksum derivation changed, so the wire
/// bucket bytes differ from `v1` and the parity fixture + conformance corpus
/// were regenerated. Must stay bit-identical with IBLT.kt / IBLT.swift.
class IBLT {
  static const int bucketCount = 56;
  static const int bucketSize = 9; // 1 + 4 + 4
  static const int totalBytes = bucketCount * bucketSize; // 504
  static const int hashFunctions = 3;

  /// Capability string advertised in PROTOCOL_HELLO (`capabilities`) by peers
  /// that speak this peel contract. A node attempts the IBLT fast path only
  /// when the peer advertises this; otherwise it uses the Bloom slow path
  /// (mixed old/new builds stay correct via Bloom, never via a peel that would
  /// silently mis-reconcile across the two contracts).
  static const String keyHashContractV2 = 'iblt-keyhash-v2';

  final List<IBLTBucket> buckets;

  IBLT() : buckets = List.generate(bucketCount, (_) => IBLTBucket());

  IBLT._(this.buckets);

  /// Insert an event ID into the IBLT
  void insert(String eventId) {
    final keyHash = _crc32(eventId);
    final checkHash = _checksumFromKeyHash(keyHash);
    final indices = _indicesFromKeyHash(keyHash);
    for (final idx in indices) {
      buckets[idx].count += 1;
      buckets[idx].keySum ^= keyHash;
      buckets[idx].hashSum ^= checkHash;
    }
  }

  /// Remove an event ID from the IBLT
  void remove(String eventId) {
    final keyHash = _crc32(eventId);
    final checkHash = _checksumFromKeyHash(keyHash);
    final indices = _indicesFromKeyHash(keyHash);
    for (final idx in indices) {
      buckets[idx].count -= 1;
      buckets[idx].keySum ^= keyHash;
      buckets[idx].hashSum ^= checkHash;
    }
  }

  /// Subtract another IBLT from this one (this - other)
  IBLT subtract(IBLT other) {
    final result = IBLT();
    for (int i = 0; i < bucketCount; i++) {
      result.buckets[i].count = buckets[i].count - other.buckets[i].count;
      result.buckets[i].keySum = buckets[i].keySum ^ other.buckets[i].keySum;
      result.buckets[i].hashSum = buckets[i].hashSum ^ other.buckets[i].hashSum;
    }
    return result;
  }

  /// Peel the IBLT to extract differences
  /// Returns null if peeling fails (too many differences, need Slow Path)
  IBLTPeelResult? peel() {
    final onlyInA = <int>{}; // keyHashes only in self
    final onlyInB = <int>{}; // keyHashes only in other

    // Create working copy
    final work = List.generate(bucketCount, (i) => IBLTBucket()
      ..count = buckets[i].count
      ..keySum = buckets[i].keySum
      ..hashSum = buckets[i].hashSum);

    bool changed = true;
    int iterations = 0;
    const maxIterations = 1000;

    while (changed && iterations < maxIterations) {
      changed = false;
      iterations++;
      for (int i = 0; i < bucketCount; i++) {
        if (work[i].count == 1) {
          // Pure cell: element only in A
          final key = work[i].keySum;
          final check = work[i].hashSum;
          if (_verifyChecksum(key, check)) {
            onlyInA.add(key);
            // Remove from all buckets that contain this key
            final indices = _indicesFromKeyHash(key);
            for (final idx in indices) {
              work[idx].count -= 1;
              work[idx].keySum ^= key;
              work[idx].hashSum ^= check;
            }
            changed = true;
          }
        } else if (work[i].count == -1) {
          // Pure cell: element only in B
          final key = work[i].keySum;
          final check = work[i].hashSum;
          if (_verifyChecksum(key, check)) {
            onlyInB.add(key);
            final indices = _indicesFromKeyHash(key);
            for (final idx in indices) {
              work[idx].count += 1;
              work[idx].keySum ^= key;
              work[idx].hashSum ^= check;
            }
            changed = true;
          }
        }
      }
    }

    // Check if fully peeled
    for (int i = 0; i < bucketCount; i++) {
      if (work[i].count != 0) return null; // Failed to peel
    }

    return IBLTPeelResult(onlyInA: onlyInA, onlyInB: onlyInB);
  }

  /// Serialize to bytes (504 bytes)
  Uint8List toBytes() {
    final data = ByteData(totalBytes);
    for (int i = 0; i < bucketCount; i++) {
      final offset = i * bucketSize;
      data.setInt8(offset, buckets[i].count);
      data.setUint32(offset + 1, buckets[i].keySum, Endian.little);
      data.setUint32(offset + 5, buckets[i].hashSum, Endian.little);
    }
    return data.buffer.asUint8List();
  }

  /// Deserialize from bytes
  static IBLT fromBytes(Uint8List bytes) {
    if (bytes.length < totalBytes) {
      throw ArgumentError('IBLT data too short: ${bytes.length} < $totalBytes');
    }
    final data = ByteData.sublistView(bytes);
    final buckets = <IBLTBucket>[];
    for (int i = 0; i < bucketCount; i++) {
      final offset = i * bucketSize;
      buckets.add(IBLTBucket()
        ..count = data.getInt8(offset)
        ..keySum = data.getUint32(offset + 1, Endian.little)
        ..hashSum = data.getUint32(offset + 5, Endian.little));
    }
    return IBLT._(buckets);
  }

  /// The IBLT key hash for an event id: `CRC32(eventId)`. This is exactly what
  /// `peel()` returns in its onlyInA/onlyInB sets, so tests and the parity
  /// fixture/corpus generators use it to compute expected hashes. Mirrors the
  /// public `crc32` on the Kotlin/Swift siblings.
  static int keyHashOf(String eventId) => _crc32(eventId);

  /// The 4 little-endian bytes of a CRC32 `keyHash`. This is the SOLE input to
  /// both the checksum and the bucket indices under `iblt-keyhash-v2`, so peel
  /// (which only has `keySum`) reconstructs them identically to insert.
  static List<int> _keyBytes(int keyHash) => [
        keyHash & 0xFF,
        (keyHash >> 8) & 0xFF,
        (keyHash >> 16) & 0xFF,
        (keyHash >> 24) & 0xFF,
      ];

  /// Checksum (`hashSum`) for a `keyHash` — FNV-1a over its 4 LE bytes.
  /// Reconstructable during peel from `keySum` alone.
  static int _checksumFromKeyHash(int keyHash) => _fnv1aBytes(_keyBytes(keyHash));

  /// Bucket indices for a `keyHash` — MurmurHash over its 4 LE bytes with
  /// seeds 0/1/2. Used by BOTH insert/remove and peel, so the index space is
  /// identical (the `iblt-keyhash-v2` fix to the pre-v2 mismatch).
  List<int> _indicesFromKeyHash(int keyHash) {
    final kb = _keyBytes(keyHash);
    return [
      _murmurHash(kb, 0) % bucketCount,
      _murmurHash(kb, 1) % bucketCount,
      _murmurHash(kb, 2) % bucketCount,
    ];
  }

  /// Verify a pure cell: FNV-1a of the keySum's 4 LE bytes must equal hashSum.
  bool _verifyChecksum(int keySum, int hashSum) =>
      _checksumFromKeyHash(keySum) == hashSum;

  // ── Hash Functions ──

  /// CRC32 for keySum
  static int _crc32(String s) {
    int crc = 0xFFFFFFFF;
    for (final b in s.codeUnits) {
      crc ^= b;
      for (int j = 0; j < 8; j++) {
        crc = (crc & 1) == 1 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1;
      }
    }
    return crc ^ 0xFFFFFFFF;
  }

  /// FNV-1a over raw bytes (the `iblt-keyhash-v2` checksum input is the keyHash
  /// LE bytes, not the event-id string).
  static int _fnv1aBytes(List<int> bytes) {
    int h = 0x811c9dc5;
    for (final b in bytes) {
      h ^= b & 0xFF;
      h = (h * 0x01000193) & 0xFFFFFFFF;
    }
    return h;
  }

  /// MurmurHash3-like for bucket index selection
  static int _murmurHash(List<int> bytes, int seed) {
    int h = seed & 0xFFFFFFFF;
    for (int i = 0; i < bytes.length; i++) {
      int k = bytes[i];
      k = (k * 0xcc9e2d51) & 0xFFFFFFFF;
      k = ((k << 15) | (k >> 17)) & 0xFFFFFFFF;
      k = (k * 0x1b873593) & 0xFFFFFFFF;
      h ^= k;
      h = ((h << 13) | (h >> 19)) & 0xFFFFFFFF;
      h = (h * 5 + 0xe6546b64) & 0xFFFFFFFF;
    }
    h ^= bytes.length;
    h ^= h >> 16;
    h = (h * 0x85ebca6b) & 0xFFFFFFFF;
    h ^= h >> 13;
    h = (h * 0xc2b2ae35) & 0xFFFFFFFF;
    h ^= h >> 16;
    return h;
  }
}

class IBLTBucket {
  int count = 0;    // signed byte (-128 to 127)
  int keySum = 0;   // uint32
  int hashSum = 0;  // uint32
}

class IBLTPeelResult {
  final Set<int> onlyInA; // keyHashes only in self (peer needs these)
  final Set<int> onlyInB; // keyHashes only in other (we need these)

  IBLTPeelResult({required this.onlyInA, required this.onlyInB});

  bool get isEmpty => onlyInA.isEmpty && onlyInB.isEmpty;
}
