import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:ignirelay_app/app/crdt/hlc.dart';
import 'package:ignirelay_app/app/crypto/identity_manager.dart';
import 'package:ignirelay_app/app/crypto/signer.dart';

import 'package:ignirelay_app/app/db/database_helper.dart';
import 'package:ignirelay_app/app/proto/mesh_protocol.pb.dart' as pb;
import 'package:ignirelay_app/app/mesh/hazard_manager.dart';
import 'package:ignirelay_app/app/mesh/triage_queue.dart';
import 'package:ignirelay_app/app/mesh/event_types.dart';
import 'package:ignirelay_app/app/services/rate_limit_exception.dart';

// Re-export so existing callers that `import event_manager.dart show RateLimitException`
// still compile during transition. New callers should import the non-mesh path directly.
export 'package:ignirelay_app/app/services/rate_limit_exception.dart' show RateLimitException;

/// 統一的 MeshEvent 建立、簽名、DB 儲存中心
///
/// Phase 0b #3B-2：舊產品 send path 已切除 — publishSupply / publishRequest /
/// publishChatMessage / publishMatch* / publishLocationUpdate / cancelSupply /
/// cancelRequest / getActiveSessions / getAvailableSupplies / expireStaleMatches
/// 與醫療卡組裝（loadMedicalCardForSos / buildMedicalPayload）全部移除，連帶
/// NegotiationManager / medical_card / handshake_schema / location_service /
/// fixnum import 一併下線。保留：SOS/求援廣播（publishEvent）、危險標記
/// （publishHazard + hazard CRUD/查詢，委派 HazardManager）、TriageQueue、
/// 速率限制、Event_Logs 核心（getRecentEvents）。對應 service 檔案與 DB schema
/// 留待 #3B-3 / #3B-4（見 docs/REBUILD_PLAN.md §4）。不碰 wire/EventType/field_id。
class EventManager {
  static final EventManager _instance = EventManager._internal();
  factory EventManager() => _instance;
  EventManager._internal();

  final _uuid = const Uuid();
  final _db = DatabaseHelper();
  final _identity = IdentityManager();
  final _queue = TriageQueue();

  TriageQueue get queue => _queue;

  /// Hazard 管理委派（publish, confirm, update, delete, query）
  final HazardManager hazards = HazardManager();

  // ── 速率限制 ────────────────────────────────────────────────────
  // 用 HLC 時間窗口（不依賴 wallclock）防止時鐘跳躍
  int _rateWindowStartHlc = 0;
  int _rateCount = 0;
  static const int _maxPerHour = 20;

  @visibleForTesting
  void resetRateLimit() {
    _rateWindowStartHlc = 0;
    _rateCount = 0;
  }
  static const int _oneHourMs = 3600000;

  Future<void> _checkRateLimit() async {
    final now = HLC.now();
    if (now.timestamp - _rateWindowStartHlc > _oneHourMs) {
      _rateWindowStartHlc = now.timestamp;
      _rateCount = 0;
    }
    if (_rateCount >= _maxPerHour) {
      throw RateLimitException(
        '已達每小時上限 $_maxPerHour 次廣播，請稍後再試。',
      );
    }
    _rateCount++;
  }

  // ── 發布求救 / 求援事件 ─────────────────────────────────────────
  Future<String> publishEvent({
    required int urgency,
    required String description,
    double? lat,
    double? lng,
    double maxRangeMeters = 1000.0,
    bool attachMedicalCard = false,
  }) async {
    await _checkRateLimit();

    final eventId = _uuid.v4();
    final hlc = HLC.now();
    final pubKeyBytes = await _identity.getPublicKeyBytes();

    // 組裝 RequestData protobuf
    final requestData = pb.RequestData()
      ..requestId = eventId
      ..description = description
      ..urgency = pb.UrgencyLevel.valueOf(urgency) ?? pb.UrgencyLevel.INFO;
    if (lat != null) requestData.lat = lat;
    if (lng != null) requestData.lng = lng;
    requestData.maxRangeMeters = maxRangeMeters.toDouble();

    // 使用 RequestData protobuf 序列化（接收端以 RequestData.fromBuffer 解碼）
    final payload = Uint8List.fromList(requestData.writeToBuffer());

    final signature = await Signer.signEvent(
      eventId: eventId, eventType: EventType.requestBroadcast, payload: payload,
    );

    final db = await _db.database;
    await db.insert('Event_Logs', {
      'event_id': eventId,
      'sender_pub_key': Uint8List.fromList(pubKeyBytes),
      'identity_level': _identity.getIdentityLevel(),
      'event_type': EventType.requestBroadcast,
      'urgency': urgency,
      'hlc_timestamp': hlc.timestamp,
      'hlc_counter': hlc.counter,
      'ttl': 10,
      'received_lat': lat,
      'received_lng': lng,
      'origin_lat': lat,
      'origin_lng': lng,
      'node_tier': 1,
      'chunk_index': 0,
      'total_chunks': 1,
      'payload': payload,
      'signature': Uint8List.fromList(signature),
      'is_synced': 0,
    });

    _queue.enqueue(MeshTask(eventId, urgency, payload, eventType: EventType.requestBroadcast));
    return eventId;
  }

  /// 發布危險標記（委派至 HazardManager，rate limit 在此檢查）
  Future<String> publishHazard({
    required String type,
    required int severity,
    required double lat,
    required double lng,
    double radiusMeters = 200.0,
    String description = '',
  }) async {
    await _checkRateLimit();
    return hazards.publishHazard(
      type: type, severity: severity, lat: lat, lng: lng,
      radiusMeters: radiusMeters, description: description,
    );
  }

  // ── Hazard 查詢（委派至 HazardManager）───────────────────────
  Future<List<Map<String, dynamic>>> getActiveHazards() => hazards.getActiveHazards();
  Future<String> getReporterHex() => hazards.getReporterHex();
  Future<Map<String, dynamic>?> findNearbyHazard(
    double lat, double lng, String type, {double searchRadius = 500.0,
  }) => hazards.findNearbyHazard(lat, lng, type, searchRadius: searchRadius);

  // ── Hazard CRUD 委派 ──────────────────────────────────────────
  Future<void> confirmHazard(String hazardId) => hazards.confirmHazard(hazardId);
  Future<void> updateHazard(String hazardId, {
    String? type, int? severity, double? lat, double? lng,
    double? radiusMeters, String? description,
  }) => hazards.updateHazard(hazardId, type: type, severity: severity,
      lat: lat, lng: lng, radiusMeters: radiusMeters, description: description);
  Future<void> deleteHazard(String hazardId) => hazards.deleteHazard(hazardId);

  // ── 查詢最近事件日誌 ──────────────────────────────────────────
  Future<List<Map<String, dynamic>>> getRecentEvents({int limit = 20}) async {
    final db = await _db.database;
    return await db.query(
      'Event_Logs',
      orderBy: 'hlc_timestamp DESC',
      limit: limit,
    );
  }
}
