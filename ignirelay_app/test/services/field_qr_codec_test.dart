// A7 — FieldQrCodec: the field-join code wire format (string layer = the
// automatable half of A7 DoD D1; real camera scan is the A11 USER-GATE).
//
// Covers: 3/4/5-segment roundtrip, bad prefix / bad length reject, seg3 non-
// https reject, "seg4 without seg3" reject, and the forward-compat iron rule
// (unknown 6th+ segment still parses).

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:ignirelay_app/app/services/field_qr_codec.dart';

void main() {
  // Distinct 32-byte secret (0..31) so roundtrips assert byte-exactness.
  final secret32 = Uint8List.fromList(List<int>.generate(32, (i) => i));

  group('roundtrip', () {
    test('3-segment (offline field, no cloud / staff)', () {
      final code = FieldQrCodec.encode(FieldQrPayload(
        secret: secret32,
        displayName: '台北車站避難所',
      ));
      expect(code.startsWith('IGNI1:'), isTrue);
      expect(code.split(':').length, 3);

      final r = FieldQrCodec.tryDecode(code);
      expect(r.ok, isTrue);
      expect(r.payload!.secret, orderedEquals(secret32));
      expect(r.payload!.displayName, '台北車站避難所');
      expect(r.payload!.cloudBaseUrl, isNull);
      expect(r.payload!.staffInviteToken, isNull);
    });

    test('4-segment (cloud base url, https)', () {
      final code = FieldQrCodec.encode(FieldQrPayload(
        secret: secret32,
        displayName: 'A 場域',
        cloudBaseUrl: 'https://relay.ignirelay.network',
      ));
      expect(code.split(':').length, 4);

      final r = FieldQrCodec.tryDecode(code);
      expect(r.ok, isTrue);
      expect(r.payload!.cloudBaseUrl, 'https://relay.ignirelay.network');
      expect(r.payload!.staffInviteToken, isNull);
    });

    test('5-segment (cloud + staff token)', () {
      final code = FieldQrCodec.encode(FieldQrPayload(
        secret: secret32,
        displayName: 'B 場域',
        cloudBaseUrl: 'https://relay.example.org',
        staffInviteToken: 'inv_abc123',
      ));
      expect(code.split(':').length, 5);

      final r = FieldQrCodec.tryDecode(code);
      expect(r.ok, isTrue);
      expect(r.payload!.cloudBaseUrl, 'https://relay.example.org');
      expect(r.payload!.staffInviteToken, 'inv_abc123');
    });

    test('display name with colon / spaces survives urlencoding', () {
      const tricky = 'Sector 7 : North Gate';
      final code = FieldQrCodec.encode(
          FieldQrPayload(secret: secret32, displayName: tricky));
      // The literal ':' in the name must NOT add a segment.
      expect(code.split(':').length, 3);
      final r = FieldQrCodec.tryDecode(code);
      expect(r.ok, isTrue);
      expect(r.payload!.displayName, tricky);
    });
  });

  group('reject', () {
    test('empty / whitespace input', () {
      expect(FieldQrCodec.tryDecode('').error, FieldQrError.empty);
      expect(FieldQrCodec.tryDecode('   ').error, FieldQrError.empty);
    });

    test('wrong / unknown version prefix', () {
      expect(FieldQrCodec.tryDecode('IGNI2:abc:name').error,
          FieldQrError.badPrefix);
      expect(FieldQrCodec.tryDecode('garbage-no-colons').error,
          FieldQrError.badPrefix);
    });

    test('too few segments (prefix only / prefix+secret)', () {
      expect(FieldQrCodec.tryDecode('IGNI1').error,
          FieldQrError.tooFewSegments);
      final b64 = FieldQrCodec.encode(
              FieldQrPayload(secret: secret32, displayName: 'x'))
          .split(':')[1];
      expect(FieldQrCodec.tryDecode('IGNI1:$b64').error,
          FieldQrError.tooFewSegments);
    });

    test('secret of wrong byte length', () {
      // 16 bytes instead of 32.
      final shortB64 = FieldQrCodec.encode(FieldQrPayload(
        secret: secret32,
        displayName: 'x',
      ));
      // Hand-build a code whose seg1 decodes to <32 bytes.
      final r = FieldQrCodec.tryDecode('IGNI1:AAAA:name'); // 3 bytes
      expect(r.error, FieldQrError.badSecret);
      // Sanity: the valid one is fine.
      expect(FieldQrCodec.tryDecode(shortB64).ok, isTrue);
    });

    test('seg1 not valid base64url', () {
      expect(FieldQrCodec.tryDecode('IGNI1:!!!notb64!!!:name').error,
          FieldQrError.badSecret);
    });

    test('seg3 cloud url is plaintext http:// (prohibited)', () {
      // Hand-build the http:// code directly — encode() now refuses to emit
      // one (see encode-guard test below), so we craft the segment manually.
      final b64 = FieldQrCodec.encode(
              FieldQrPayload(secret: secret32, displayName: 'x'))
          .split(':')[1];
      final httpSeg = Uri.encodeComponent('http://insecure.example');
      final r = FieldQrCodec.tryDecode('IGNI1:$b64:x:$httpSeg');
      expect(r.error, FieldQrError.badCloudUrl);
    });

    test('seg4 staff token present while seg3 cloud is empty', () {
      // 5 segments where seg3 is empty → reject.
      final b64 = FieldQrCodec.encode(
              FieldQrPayload(secret: secret32, displayName: 'x'))
          .split(':')[1];
      final r = FieldQrCodec.tryDecode('IGNI1:$b64:name::inv_token');
      expect(r.error, FieldQrError.staffWithoutCloud);
    });
  });

  group('forward compat (iron rule)', () {
    test('unknown 6th+ segment is ignored, code still parses', () {
      final fiveSeg = FieldQrCodec.encode(FieldQrPayload(
        secret: secret32,
        displayName: 'B',
        cloudBaseUrl: 'https://relay.example.org',
        staffInviteToken: 'inv_x',
      ));
      final withFuture = '$fiveSeg:future_field_v9:another';
      final r = FieldQrCodec.tryDecode(withFuture);
      expect(r.ok, isTrue);
      expect(r.payload!.cloudBaseUrl, 'https://relay.example.org');
      expect(r.payload!.staffInviteToken, 'inv_x');
    });

    test('a 3-segment legacy code with a trailing unknown segment parses '
        'as offline (4th seg empty ⇒ no cloud)', () {
      final b64 = FieldQrCodec.encode(
              FieldQrPayload(secret: secret32, displayName: 'x'))
          .split(':')[1];
      // seg3 present-but-empty ⇒ offline; no staff ⇒ ok.
      final r = FieldQrCodec.tryDecode('IGNI1:$b64:x:');
      expect(r.ok, isTrue);
      expect(r.payload!.cloudBaseUrl, isNull);
    });
  });

  group('encode guards', () {
    test('rejects non-32-byte secret', () {
      expect(
        () => FieldQrCodec.encode(FieldQrPayload(
            secret: Uint8List(16), displayName: 'x')),
        throwsArgumentError,
      );
    });

    test('rejects staff token without cloud url', () {
      expect(
        () => FieldQrCodec.encode(FieldQrPayload(
            secret: secret32, displayName: 'x', staffInviteToken: 't')),
        throwsArgumentError,
      );
    });

    test('rejects non-https cloud url (encoder mirrors decoder)', () {
      expect(
        () => FieldQrCodec.encode(FieldQrPayload(
            secret: secret32,
            displayName: 'x',
            cloudBaseUrl: 'http://insecure.example')),
        throwsArgumentError,
      );
      // https:// is accepted.
      expect(
        FieldQrCodec.encode(FieldQrPayload(
            secret: secret32,
            displayName: 'x',
            cloudBaseUrl: 'https://relay.example.org')),
        contains(':'),
      );
    });
  });
}
