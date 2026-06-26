import 'dart:typed_data';

import 'package:ignirelay_app/app/proto/event_envelope_v2.dart';
import 'package:ignirelay_app/app/proto/mesh_protocol.pb.dart' as pb;

class RequestData {
  final String resourceType;
  final int quantity;
  final String note;
  final String mobilityMode;
  RequestData(
      {required this.resourceType,
      required this.quantity,
      required this.note,
      required this.mobilityMode});
}

class HazardDataDecoded {
  final String hazardId;
  final String hazardType;
  final int severity;
  final double centerLat;
  final double centerLng;
  final double radiusMeters;
  final int observedAt;
  final String description;
  final bool isConfirmation;
  HazardDataDecoded({
    required this.hazardId,
    required this.hazardType,
    required this.severity,
    required this.centerLat,
    required this.centerLng,
    required this.radiusMeters,
    required this.observedAt,
    required this.description,
    required this.isConfirmation,
  });
}

/// App↔Node first-hop receipt, decoded to plain Dart (A12 / `app_node_gatt_v1`
/// §5). The phone only RECEIVES this; [refEnvelopeIdHex] keys it back to the
/// envelope_id the sender pre-allocated, so a debug view can mark that sent row
/// "已送達節點".
class NodeReceipt {
  /// Lowercase hex of the acknowledged event's 16-byte envelope_id.
  final String refEnvelopeIdHex;

  /// [NodeReceiptStatus.*] — 0=ACCEPTED_STORED, 1=DUPLICATE, 2=REJECTED.
  /// Values outside that set are surfaced as-is and MUST NOT be treated as
  /// accepted by the UI.
  final int status;

  /// Node's forward-queue depth at receipt time (UI hint).
  final int queueDepth;

  /// When the phone observed the receipt.
  final DateTime receivedAt;

  NodeReceipt({
    required this.refEnvelopeIdHex,
    required this.status,
    required this.queueDepth,
    required this.receivedAt,
  });

  bool get isAcceptedStored => status == NodeReceiptStatus.acceptedStored;
  bool get isDuplicate => status == NodeReceiptStatus.duplicate;
  bool get isRejected => status == NodeReceiptStatus.rejected;
}

/// EventDecoder — wraps `pb.X.fromBuffer(...)` and returns plain Dart objects.
/// Fail-soft: returns null on malformed/empty payload, never throws, so a wild
/// wire payload can't blow up the widget tree.
///
/// Phase 0b #3B-4：舊產品 (resource / match / chat) 的 decode 方法、對應 plain
/// Dart wrapper、以及 `decodeByType` dispatcher 已移除。只保留 SOS/求援
/// (`decodeRequestData`) 與危險標記 (`decodeHazardData`) 兩個 read-model 仍需要
/// 的 decoder。
class EventDecoder {
  EventDecoder();

  RequestData? decodeRequestData(List<int> payload) {
    try {
      final pb.RequestData rd = pb.RequestData.fromBuffer(payload);
      return RequestData(
        resourceType: rd.resourceType,
        quantity: rd.quantityNeeded.toInt(),
        note: rd.note,
        mobilityMode: rd.mobilityMode,
      );
    } catch (_) {
      return null;
    }
  }

  /// Decode a NODE_RECEIPT (EventType 105) payload to a plain [NodeReceipt]
  /// (A12). Fail-soft: null on malformed payload. [receivedAt] defaults to now.
  NodeReceipt? decodeNodeReceipt(List<int> payload, {DateTime? receivedAt}) {
    try {
      final d = NodeReceiptData.decode(Uint8List.fromList(payload));
      final hex = d.refEnvelopeId
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();
      return NodeReceipt(
        refEnvelopeIdHex: hex,
        status: d.status,
        queueDepth: d.queueDepth,
        receivedAt: receivedAt ?? DateTime.now(),
      );
    } catch (_) {
      return null;
    }
  }

  HazardDataDecoded? decodeHazardData(List<int> payload) {
    try {
      final pb.HazardData d = pb.HazardData.fromBuffer(payload);
      return HazardDataDecoded(
        hazardId: d.hazardId,
        hazardType: d.hazardType,
        severity: d.severity,
        centerLat: d.centerLat,
        centerLng: d.centerLng,
        radiusMeters: d.radiusMeters,
        observedAt: d.observedAt.toInt(),
        description: d.description,
        isConfirmation: d.isConfirmation,
      );
    } catch (_) {
      return null;
    }
  }
}
