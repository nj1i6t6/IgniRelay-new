// FieldQrCodec — IgniRelay field-join QR / code wire format (A7).
//
// Spec: docs/MASTER_EXECUTION_PLAN.md A7 step 2 (frozen, v1.2 five-segment).
//
// A field-join code is a single `:`-separated string:
//
//   IGNI1:<base64url(secret 32B)>:<urlencode(displayName)>
//        [:<urlencode(cloud_base_url)>[:<urlencode(staff_invite_token)>]]
//
//   seg0  "IGNI1"           version prefix — MUST match exactly (unknown → reject)
//   seg1  base64url 32 B    field_join_secret — MUST decode to exactly 32 bytes
//   seg2  urlencoded        field display name (required; may be empty)
//   seg3  urlencoded        cloud base URL — OPTIONAL, "https://" ONLY (else
//                           reject the whole code). Stage E (E4) consumes it;
//                           offline fields omit it.
//   seg4  urlencoded        staff invite token — OPTIONAL (staff QR only).
//                           seg4 present while seg3 missing/empty → reject.
//   seg5+ anything          UNKNOWN trailing segments — IGNORED, never an error
//                           (forward-compat iron rule: future fields must not
//                           break old apps). Three-segment legacy codes parse.
//
// urlencode (Uri.encodeComponent) escapes `:` → `%3A`, so no segment can contain
// a bare `:`; base64url uses only `[A-Za-z0-9_-=]`; therefore a plain `split(':')`
// recovers the exact segment list. Decoding NEVER throws — callers get a typed
// [FieldQrError] so the UI can prompt instead of crashing (A7 DoD D2).
//
// The secret is sensitive: this codec only (de)serialises it. It must never be
// written to a log or the clipboard buffer (A7 prohibition).

import 'dart:convert';
import 'dart:typed_data';

/// A successfully parsed (or to-be-encoded) field-join payload.
class FieldQrPayload {
  /// `field_join_secret` — exactly 32 bytes.
  final Uint8List secret;

  /// Field display name. Not a secret; the only PII the code may carry.
  final String displayName;

  /// Cloud base URL (`https://…`) or `null` for an offline field. Maps to
  /// `FieldSession.cloudBaseUrl`; unused before Stage E.
  final String? cloudBaseUrl;

  /// Staff invite token or `null`. Semantics defined by Stage E (E1); A7 only
  /// transports it. Only ever present alongside a [cloudBaseUrl].
  final String? staffInviteToken;

  FieldQrPayload({
    required this.secret,
    required this.displayName,
    this.cloudBaseUrl,
    this.staffInviteToken,
  });
}

/// Why a field-join code was rejected. Every value maps to a user-facing prompt
/// (A7 DoD D2 — bad payload must not crash and must tell the user).
enum FieldQrError {
  /// Empty / whitespace-only input.
  empty,

  /// seg0 is not the `IGNI1` version prefix (unknown format / wrong app).
  badPrefix,

  /// Fewer than the 3 required segments (prefix + secret + name).
  tooFewSegments,

  /// seg1 is not base64url, or does not decode to exactly 32 bytes.
  badSecret,

  /// seg3 is present and non-empty but is not an `https://` URL (plaintext
  /// `http://` is explicitly rejected — A7 prohibition).
  badCloudUrl,

  /// seg4 (staff token) is present while seg3 (cloud URL) is missing/empty.
  staffWithoutCloud,

  /// A segment was not valid percent-encoding (corrupt payload).
  malformed,
}

/// Result of [FieldQrCodec.tryDecode]: exactly one of [payload] / [error] is set.
class FieldQrParseResult {
  final FieldQrPayload? payload;
  final FieldQrError? error;

  const FieldQrParseResult._(this.payload, this.error);

  factory FieldQrParseResult.success(FieldQrPayload payload) =>
      FieldQrParseResult._(payload, null);

  factory FieldQrParseResult.failure(FieldQrError error) =>
      FieldQrParseResult._(null, error);

  bool get ok => payload != null;
}

class FieldQrCodec {
  FieldQrCodec._();

  /// Version prefix (seg0). Frozen — bumping it is a wire-format change.
  static const String prefix = 'IGNI1';

  /// Required `field_join_secret` length in bytes.
  static const int secretLengthBytes = 32;

  /// Build the join code for [payload].
  ///
  /// Throws [ArgumentError] when the payload is internally inconsistent, so the
  /// builder can never emit a code the parser would reject:
  ///   • the secret must be exactly 32 bytes;
  ///   • a [FieldQrPayload.cloudBaseUrl], when present, must be an `https://`
  ///     URL (plaintext `http://` is prohibited — A7 禁止事項; mirrors the
  ///     [tryDecode] `badCloudUrl` rule);
  ///   • a [FieldQrPayload.staffInviteToken] may not be set without a
  ///     [FieldQrPayload.cloudBaseUrl] (seg4 needs seg3).
  static String encode(FieldQrPayload payload) {
    if (payload.secret.length != secretLengthBytes) {
      throw ArgumentError.value(
          payload.secret.length, 'secret.length', 'must be $secretLengthBytes');
    }
    final staff = payload.staffInviteToken;
    final cloud = payload.cloudBaseUrl;
    if (cloud != null && cloud.isNotEmpty && !cloud.startsWith('https://')) {
      throw ArgumentError.value(
          cloud, 'cloudBaseUrl', 'must be an https:// URL');
    }
    if (staff != null && (cloud == null || cloud.isEmpty)) {
      throw ArgumentError(
          'staffInviteToken requires a cloudBaseUrl (seg4 needs seg3)');
    }

    final segments = <String>[
      prefix,
      base64Url.encode(payload.secret),
      Uri.encodeComponent(payload.displayName),
    ];
    if (cloud != null) segments.add(Uri.encodeComponent(cloud));
    if (staff != null) segments.add(Uri.encodeComponent(staff));
    return segments.join(':');
  }

  /// Parse a scanned / typed join code. Never throws.
  static FieldQrParseResult tryDecode(String raw) {
    final input = raw.trim();
    if (input.isEmpty) {
      return FieldQrParseResult.failure(FieldQrError.empty);
    }

    final segments = input.split(':');
    if (segments[0] != prefix) {
      return FieldQrParseResult.failure(FieldQrError.badPrefix);
    }
    if (segments.length < 3) {
      return FieldQrParseResult.failure(FieldQrError.tooFewSegments);
    }

    final secret = _tryDecodeSecret(segments[1]);
    if (secret == null) {
      return FieldQrParseResult.failure(FieldQrError.badSecret);
    }

    final displayName = _tryDecodeComponent(segments[2]);
    if (displayName == null) {
      return FieldQrParseResult.failure(FieldQrError.malformed);
    }

    // seg3 (cloud) / seg4 (staff). Empty string counts as "absent" so that a
    // 4-segment code with an empty seg3 is just an offline field, and a staff
    // token sitting behind an empty seg3 is the rejected "seg4 without seg3".
    final cloudRaw = segments.length >= 4 ? segments[3] : null;
    final staffRaw = segments.length >= 5 ? segments[4] : null;
    final hasCloud = cloudRaw != null && cloudRaw.isNotEmpty;
    final hasStaff = staffRaw != null && staffRaw.isNotEmpty;

    if (hasStaff && !hasCloud) {
      return FieldQrParseResult.failure(FieldQrError.staffWithoutCloud);
    }

    String? cloudBaseUrl;
    if (hasCloud) {
      final url = _tryDecodeComponent(cloudRaw);
      if (url == null) {
        return FieldQrParseResult.failure(FieldQrError.malformed);
      }
      if (!url.startsWith('https://')) {
        return FieldQrParseResult.failure(FieldQrError.badCloudUrl);
      }
      cloudBaseUrl = url;
    }

    String? staffInviteToken;
    if (hasStaff) {
      final token = _tryDecodeComponent(staffRaw);
      if (token == null) {
        return FieldQrParseResult.failure(FieldQrError.malformed);
      }
      staffInviteToken = token;
    }

    // segments[5..] are unknown future extensions — ignored on purpose.
    return FieldQrParseResult.success(FieldQrPayload(
      secret: secret,
      displayName: displayName,
      cloudBaseUrl: cloudBaseUrl,
      staffInviteToken: staffInviteToken,
    ));
  }

  static Uint8List? _tryDecodeSecret(String b64url) {
    try {
      var s = b64url;
      final mod = s.length % 4;
      if (mod != 0) s = s + ('=' * (4 - mod)); // tolerate stripped padding
      final bytes = base64Url.decode(s);
      if (bytes.length != secretLengthBytes) return null;
      return bytes;
    } catch (_) {
      return null;
    }
  }

  static String? _tryDecodeComponent(String s) {
    try {
      return Uri.decodeComponent(s);
    } catch (_) {
      return null;
    }
  }
}
