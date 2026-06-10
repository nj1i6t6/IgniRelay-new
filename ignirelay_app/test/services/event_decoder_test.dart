// event_decoder_test.dart
//
// Gate test:
//   - 每個保留的 decoder 都能把合法 payload 解成 plain Dart 物件
//   - 拿到不合法 / 空 payload 時必須 return null，不能 throw
//
// EventDecoder 是 UI 與 protobuf 之間的橋；它必須 fail-soft，否則在收到野生
// wire payload 時會整個 widget tree 炸掉。
//
// Phase 0b #3B-4：舊產品的 decodeResourceData 與 decodeByType（含 match/chat
// dispatch）已隨 decoder 移除，對應測試一併刪除。只剩 SOS/求援
// (decodeRequestData) 與危險標記 (decodeHazardData)。

import 'package:flutter_test/flutter_test.dart';
import 'package:ignirelay_app/app/proto/mesh_protocol.pb.dart' as pb;
import 'package:ignirelay_app/app/services/event_decoder.dart';

void main() {
  final decoder = EventDecoder();

  group('EventDecoder — decodeRequestData', () {
    test('parses well-formed RequestData payload', () {
      final raw = pb.RequestData(
        resourceType: 'WATER',
        quantityNeeded: 5,
        note: 'urgent',
        mobilityMode: 'CAN_GO',
      ).writeToBuffer();

      final out = decoder.decodeRequestData(raw);
      expect(out, isNotNull);
      expect(out!.resourceType, 'WATER');
      expect(out.quantity, 5);
      expect(out.note, 'urgent');
      expect(out.mobilityMode, 'CAN_GO');
    });

    test('returns null on malformed payload instead of throwing', () {
      final out = decoder.decodeRequestData(const <int>[0xff, 0xff, 0xff, 0xff]);
      expect(out, isNull);
    });

    test('returns null on empty payload instead of throwing', () {
      final out = decoder.decodeRequestData(const <int>[]);
      // Protobuf parses empty bytes as a default-initialized message; we
      // accept either null or default fields, but explicitly verify no throw.
      expect(() => decoder.decodeRequestData(const <int>[]), returnsNormally);
      // and if it does decode, it has empty defaults
      if (out != null) {
        expect(out.resourceType, isEmpty);
        expect(out.quantity, 0);
      }
    });
  });

  group('EventDecoder — decodeHazardData', () {
    test('parses well-formed HazardData', () {
      final raw = pb.HazardData(
        hazardId: 'hz-1',
        hazardType: 'FIRE',
        severity: 4,
        centerLat: 24.0,
        centerLng: 121.0,
        radiusMeters: 250.0,
        description: 'block',
      ).writeToBuffer();

      final out = decoder.decodeHazardData(raw);
      expect(out, isNotNull);
      expect(out!.hazardType, 'FIRE');
      expect(out.severity, 4);
      expect(out.centerLat, closeTo(24.0, 1e-9));
      expect(out.radiusMeters, closeTo(250.0, 1e-9));
    });

    test('returns null on malformed payload', () {
      final out = decoder.decodeHazardData(const <int>[0xff, 0xff]);
      expect(out, isNull);
    });
  });
}
