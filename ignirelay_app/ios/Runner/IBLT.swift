import Foundation

/// Invertible Bloom Lookup Table for BLE mesh differential sync.
///
/// 56 buckets × 9 bytes = 504 bytes (fits in 1 MTU=517 ATT PDU).
/// Bucket layout (Little Endian on wire):
///   count   : Int8       (signed)
///   keySum  : UInt32     (CRC32 XOR-accumulator)
///   hashSum : UInt32     (FNV-1a XOR-accumulator — checksum-verifies keySum)
///
/// Tolerates ~38 item differences (56 / 1.5 safety factor) before `peel()`
/// returns nil (caller falls back to the slow path / full Bloom diff).
///
/// MUST stay bit-identical with:
///   - Kotlin: android/.../IBLT.kt   (canonical reference)
///   - Dart  : lib/app/mesh/iblt.dart (matches on ASCII inputs only)
///
/// String processing intentionally mirrors Kotlin: each UTF-16 code unit is
/// truncated to its low byte (`b.code.toLong() and 0xFFL` in Kotlin). For
/// ASCII strings (the v0.3 case — envelope IDs are hex UUIDs) this also
/// matches Dart; for non-ASCII strings Dart's CRC XORs the full uint16 and
/// diverges. Event IDs are ASCII in v0.3 so the divergence does not bite.
///
/// Spec: docs/specs/native_transport_v1_2026-05-13.md §3.2.1, §11.2.
final class IBLT {

    // MARK: - Constants (must match Kotlin/Dart)

    static let bucketCount = 56
    static let bucketSize  = 9        // 1 (count) + 4 (keySum) + 4 (hashSum)
    static let totalBytes  = bucketCount * bucketSize // 504
    static let hashFunctions = 3

    // MARK: - State

    var buckets: [IBLTBucket]

    init() {
        self.buckets = (0..<IBLT.bucketCount).map { _ in IBLTBucket() }
    }

    private init(buckets: [IBLTBucket]) {
        precondition(buckets.count == IBLT.bucketCount)
        self.buckets = buckets
    }

    // MARK: - Public API

    /// Insert an event ID into the IBLT.
    func insert(_ eventId: String) {
        let keyHash = IBLT.crc32(eventId)
        let checkHash = IBLT.checksumFromKeyHash(keyHash)
        let indices = IBLT.indicesFromKeyHash(keyHash)
        for idx in indices {
            buckets[idx].count &+= 1
            buckets[idx].keySum ^= keyHash
            buckets[idx].hashSum ^= checkHash
        }
    }

    /// Remove an event ID from the IBLT.
    func remove(_ eventId: String) {
        let keyHash = IBLT.crc32(eventId)
        let checkHash = IBLT.checksumFromKeyHash(keyHash)
        let indices = IBLT.indicesFromKeyHash(keyHash)
        for idx in indices {
            buckets[idx].count &-= 1
            buckets[idx].keySum ^= keyHash
            buckets[idx].hashSum ^= checkHash
        }
    }

    /// Subtract another IBLT from this one (self - other).
    func subtract(_ other: IBLT) -> IBLT {
        let result = IBLT()
        for i in 0..<IBLT.bucketCount {
            result.buckets[i].count = buckets[i].count &- other.buckets[i].count
            result.buckets[i].keySum = buckets[i].keySum ^ other.buckets[i].keySum
            result.buckets[i].hashSum = buckets[i].hashSum ^ other.buckets[i].hashSum
        }
        return result
    }

    /// Peel the IBLT to extract symmetric differences.
    /// Returns nil if peeling fails (too many differences — caller must use
    /// the slow path / full Bloom diff).
    func peel() -> IBLTPeelResult? {
        var onlyInA: Set<UInt32> = []  // keyHashes only in self  (peer needs these)
        var onlyInB: Set<UInt32> = []  // keyHashes only in other (we need these)

        // Working copy (mutated during peeling).
        var work = buckets.map { IBLTBucket(count: $0.count, keySum: $0.keySum, hashSum: $0.hashSum) }

        var changed = true
        var iterations = 0
        let maxIterations = 1000

        while changed && iterations < maxIterations {
            changed = false
            iterations += 1
            for i in 0..<IBLT.bucketCount {
                if work[i].count == 1 {
                    let key = work[i].keySum
                    let check = work[i].hashSum
                    if IBLT.verifyChecksum(keySum: key, hashSum: check) {
                        onlyInA.insert(key)
                        let indices = IBLT.indicesFromKeyHash(key)
                        for idx in indices {
                            work[idx].count &-= 1
                            work[idx].keySum ^= key
                            work[idx].hashSum ^= check
                        }
                        changed = true
                    }
                } else if work[i].count == -1 {
                    let key = work[i].keySum
                    let check = work[i].hashSum
                    if IBLT.verifyChecksum(keySum: key, hashSum: check) {
                        onlyInB.insert(key)
                        let indices = IBLT.indicesFromKeyHash(key)
                        for idx in indices {
                            work[idx].count &+= 1
                            work[idx].keySum ^= key
                            work[idx].hashSum ^= check
                        }
                        changed = true
                    }
                }
            }
        }

        // Fully peeled if every bucket has count==0.
        for i in 0..<IBLT.bucketCount where work[i].count != 0 {
            return nil
        }
        return IBLTPeelResult(onlyInA: onlyInA, onlyInB: onlyInB)
    }

    /// Serialize to Little-Endian 504-byte buffer.
    func toBytes() -> Data {
        var out = Data(count: IBLT.totalBytes)
        out.withUnsafeMutableBytes { (rawPtr: UnsafeMutableRawBufferPointer) in
            for i in 0..<IBLT.bucketCount {
                let offset = i * IBLT.bucketSize
                rawPtr[offset] = UInt8(bitPattern: buckets[i].count)
                IBLT.writeUInt32LE(buckets[i].keySum,  into: rawPtr, at: offset + 1)
                IBLT.writeUInt32LE(buckets[i].hashSum, into: rawPtr, at: offset + 5)
            }
        }
        return out
    }

    /// Deserialize from Little-Endian buffer (must be at least 504 bytes).
    static func fromBytes(_ data: Data) throws -> IBLT {
        guard data.count >= totalBytes else {
            throw IBLTError.tooShort(actual: data.count, required: totalBytes)
        }
        var buckets: [IBLTBucket] = []
        buckets.reserveCapacity(bucketCount)
        data.withUnsafeBytes { (rawPtr: UnsafeRawBufferPointer) in
            for i in 0..<bucketCount {
                let offset = i * bucketSize
                let count = Int8(bitPattern: rawPtr[offset])
                let keySum  = readUInt32LE(from: rawPtr, at: offset + 1)
                let hashSum = readUInt32LE(from: rawPtr, at: offset + 5)
                buckets.append(IBLTBucket(count: count, keySum: keySum, hashSum: hashSum))
            }
        }
        return IBLT(buckets: buckets)
    }

    // MARK: - Hash functions (must match Kotlin)

    /// CRC32 (poly 0xEDB88320, init 0xFFFFFFFF, final XOR with 0xFFFFFFFF).
    /// Processes UTF-16 code units truncated to 8 bits — matches Kotlin and
    /// Dart on ASCII inputs.
    static func crc32(_ s: String) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for codeUnit in s.utf16 {
            let b = UInt32(codeUnit & 0xFF)
            crc ^= b
            for _ in 0..<8 {
                if (crc & 1) == 1 {
                    crc = (crc >> 1) ^ 0xEDB88320
                } else {
                    crc >>= 1
                }
            }
        }
        return crc ^ 0xFFFFFFFF
    }

    /// Contract name advertised in PROTOCOL_HELLO `capabilities`.
    static let keyHashContractV2 = "iblt-keyhash-v2"

    /// Key hash for an event id: CRC32(eventId) — what peel() returns.
    static func keyHashOf(_ eventId: String) -> UInt32 { crc32(eventId) }

    /// FNV-1a 32-bit over raw bytes (init 0x811c9dc5, prime 0x01000193). The
    /// `iblt-keyhash-v2` checksum input is the keyHash LE bytes, not the
    /// event-id string. Matches Dart fnv1aBytes / Kotlin fnv1aBytes.
    static func fnv1aBytes(_ bytes: [UInt8]) -> UInt32 {
        var h: UInt32 = 0x811c9dc5
        for b in bytes {
            h ^= UInt32(b)
            h = h &* 0x01000193
        }
        return h
    }

    /// MurmurHash3-like with per-byte processing (one byte per UTF-16 code
    /// unit, truncated). Matches Kotlin `IBLT.murmurHash` and Dart
    /// `_murmurHash` (on ASCII inputs).
    static func murmurHash(_ bytes: [UInt8], seed: UInt32) -> UInt32 {
        var h: UInt32 = seed
        for b in bytes {
            var k = UInt32(b)
            k = k &* 0xcc9e2d51
            k = (k << 15) | (k >> 17)
            k = k &* 0x1b873593
            h ^= k
            h = (h << 13) | (h >> 19)
            h = h &* 5 &+ 0xe6546b64
        }
        h ^= UInt32(bytes.count)
        h ^= h >> 16
        h = h &* 0x85ebca6b
        h ^= h >> 13
        h = h &* 0xc2b2ae35
        h ^= h >> 16
        return h
    }

    // MARK: - Private helpers (match Kotlin)

    /// The 4 little-endian bytes of a CRC32 keyHash — the SOLE input to both
    /// the checksum and the bucket indices under `iblt-keyhash-v2`, so peel
    /// (which only has keySum) reconstructs them identically to insert.
    /// Matches Dart _keyBytes / Kotlin keyBytes.
    static func keyBytes(_ keyHash: UInt32) -> [UInt8] {
        return [
            UInt8(keyHash         & 0xFF),
            UInt8((keyHash >> 8)  & 0xFF),
            UInt8((keyHash >> 16) & 0xFF),
            UInt8((keyHash >> 24) & 0xFF),
        ]
    }

    /// Checksum (hashSum) for a keyHash — FNV-1a over its 4 LE bytes.
    static func checksumFromKeyHash(_ keyHash: UInt32) -> UInt32 {
        return fnv1aBytes(keyBytes(keyHash))
    }

    /// Bucket indices for a keyHash — MurmurHash over its 4 LE bytes with seeds
    /// 0/1/2. Used by BOTH insert/remove and peel (the `iblt-keyhash-v2` fix).
    /// Matches Dart _indicesFromKeyHash / Kotlin indicesFromKeyHash.
    static func indicesFromKeyHash(_ keyHash: UInt32) -> [Int] {
        let kb = keyBytes(keyHash)
        let bc = UInt32(bucketCount)
        return [
            Int(murmurHash(kb, seed: 0) % bc),
            Int(murmurHash(kb, seed: 1) % bc),
            Int(murmurHash(kb, seed: 2) % bc),
        ]
    }

    /// Verify a pure cell: FNV-1a of keySum's 4 LE bytes must equal hashSum.
    static func verifyChecksum(keySum: UInt32, hashSum: UInt32) -> Bool {
        return checksumFromKeyHash(keySum) == hashSum
    }

    // MARK: - Byte-level LE helpers

    private static func writeUInt32LE(_ v: UInt32,
                                      into ptr: UnsafeMutableRawBufferPointer,
                                      at offset: Int) {
        ptr[offset]     = UInt8(v         & 0xFF)
        ptr[offset + 1] = UInt8((v >> 8)  & 0xFF)
        ptr[offset + 2] = UInt8((v >> 16) & 0xFF)
        ptr[offset + 3] = UInt8((v >> 24) & 0xFF)
    }

    private static func readUInt32LE(from ptr: UnsafeRawBufferPointer,
                                     at offset: Int) -> UInt32 {
        let b0 = UInt32(ptr[offset])
        let b1 = UInt32(ptr[offset + 1]) << 8
        let b2 = UInt32(ptr[offset + 2]) << 16
        let b3 = UInt32(ptr[offset + 3]) << 24
        return b0 | b1 | b2 | b3
    }
}

/// Single IBLT bucket.
final class IBLTBucket {
    var count: Int8      // signed (-128..127); &+= / &-= are used to mirror
                         // Kotlin's arithmetic (Kotlin stores as Int, wraps
                         // on serialization).
    var keySum: UInt32
    var hashSum: UInt32

    init(count: Int8 = 0, keySum: UInt32 = 0, hashSum: UInt32 = 0) {
        self.count = count
        self.keySum = keySum
        self.hashSum = hashSum
    }
}

/// Result of `IBLT.peel()` — the symmetric differences as raw CRC keyHashes.
struct IBLTPeelResult {
    let onlyInA: Set<UInt32>   // hashes present in self  (peer needs these)
    let onlyInB: Set<UInt32>   // hashes present in other (we need these)

    var isEmpty: Bool { onlyInA.isEmpty && onlyInB.isEmpty }
}

enum IBLTError: Error {
    case tooShort(actual: Int, required: Int)
}
