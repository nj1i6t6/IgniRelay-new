import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:ignirelay_app/app/mesh/event_types.dart';
import 'package:ignirelay_app/app/mesh/mesh_event_handler.dart';
import 'package:ignirelay_app/app/services/event_decoder.dart';
import 'package:ignirelay_app/app/services/event_store.dart';

class SosAlert {
  final String eventId;
  final int urgency;
  final String description;
  final double? lat;
  final double? lng;
  final Uint8List? senderPubKey;
  final DateTime timestamp;
  SosAlert(
      {required this.eventId,
      required this.urgency,
      required this.description,
      this.lat,
      this.lng,
      this.senderPubKey,
      required this.timestamp});
}

class HazardEvent {
  final String eventId;
  final String type;
  final int severity;
  final double lat;
  final double lng;
  final double radiusMeters;
  final String description;
  HazardEvent(
      {required this.eventId,
      required this.type,
      required this.severity,
      required this.lat,
      required this.lng,
      required this.radiusMeters,
      required this.description});
}

class PresenceUpdate {
  final String eventId;
  final String anon8;
  final int source;
  final double? lat;
  final double? lng;
  final int? accuracy;
  final int? battery;
  final int observedMs;
  PresenceUpdate({
    required this.eventId,
    required this.anon8,
    required this.source,
    this.lat,
    this.lng,
    this.accuracy,
    this.battery,
    required this.observedMs,
  });
}

/// 通用「事件日誌變動」通知。
///
/// 給只關心「某個事件剛剛抵達/落地，請我重整自己這份 view」的 UI 使用。內容
/// 是純 Dart 型別，不含 protobuf。提供這個 stream 是為了讓 production UI 不再
/// 需要依賴 `rawEvents` 做「any event arrived」訊號，符合 Stage 1 spec 對 raw
/// stream 僅限 debug 使用的要求。
class EventLogChanged {
  /// 此批至少包含一筆新事件的 hint event id；UI 通常用不到具體值，主要
  /// 訊號是「stream 有 push」這件事本身。
  final String latestEventId;
  EventLogChanged({required this.latestEventId});
}

/// EventStream — 把 `MeshEventHandler` 的原始事件 stream 投影成 UI 需要的
/// typed streams。
///
/// Phase 0b #3B-4：舊產品的 `matchUpdates` / `supplyChanges` / `chatMessages`
/// typed streams（與對應的 `MatchUpdate` / `SupplyChange` / `ChatMessage`
/// wrapper、dispatch 分支）已移除。保留 `sosAlerts`（requestBroadcast urgency≥2，
/// 含 v2 SOS-class 投影）、`hazardEvents`、通用 `anyEventChanges`、debug 用
/// `rawEvents` / `debugLogs`。
class EventStream {
  EventStream({
    required MeshEventHandler handler,
    required EventDecoder decoder,
    required EventStore store,
  })  : _handler = handler,
        _decoder = decoder,
        _store = store;

  final MeshEventHandler _handler;
  final EventDecoder _decoder;
  final EventStore _store;
  StreamSubscription<MeshDataReceived>? _subscription;
  final Set<String> _dispatchedEventIds = <String>{};

  final StreamController<SosAlert> _sosController =
      StreamController<SosAlert>.broadcast();
  final StreamController<HazardEvent> _hazardController =
      StreamController<HazardEvent>.broadcast();
  final StreamController<PresenceUpdate> _presenceController =
      StreamController<PresenceUpdate>.broadcast();
  final StreamController<EventLogChanged> _anyEventController =
      StreamController<EventLogChanged>.broadcast();

  Stream<SosAlert> get sosAlerts => _sosController.stream;
  Stream<HazardEvent> get hazardEvents => _hazardController.stream;
  Stream<PresenceUpdate> get presenceUpdates => _presenceController.stream;

  /// 「事件日誌有新東西」的通用通知 stream。UI 若只需要「something 變了，
  /// 請重新跑 query」的訊號，就訂閱這個 stream，不要再用 [rawEvents]。
  Stream<EventLogChanged> get anyEventChanges => _anyEventController.stream;

  /// Raw stream passthrough — **debug 專用**。Production UI 一律走上面的 typed
  /// streams 或 [anyEventChanges]，由 Stage 1 acceptance gate 強制執行。
  Stream<MeshDataReceived> get rawEvents => _handler.events;

  List<String> get debugLogs => _handler.debugLogs;

  void start() {
    _subscription ??= _handler.events.listen((_) {
      unawaited(_dispatchRecentEvents());
    });
  }

  Future<void> _dispatchRecentEvents() async {
    final rows = await _store.queryRecent(limit: 50);
    String? latestNewEventId;
    for (final row in rows.reversed) {
      final eventId = row['event_id'] as String? ?? '';
      if (eventId.isEmpty || !_dispatchedEventIds.add(eventId)) continue;
      latestNewEventId = eventId;

      final eventType = row['event_type'] as int? ?? -1;
      final urgency = row['urgency'] as int? ?? 0;
      final payload = row['payload'] as Uint8List?;
      final timestamp = DateTime.fromMillisecondsSinceEpoch(
        (row['hlc_timestamp'] as int?) ?? DateTime.now().millisecondsSinceEpoch,
      );

      switch (eventType) {
        case EventType.requestBroadcast:
          // requestBroadcast urgency≥2 = SOS-class（含 V2InboundProjector 投影的
          // v2 SOS）。urgency<2 的請求不再有 typed stream（supplyChanges 已下線）。
          if (urgency >= 2) {
            final data =
                payload == null ? null : _decoder.decodeRequestData(payload);
            _sosController.add(SosAlert(
              eventId: eventId,
              urgency: urgency,
              description: data?.note ?? '',
              lat: row['lat'] as double?,
              lng: row['lng'] as double?,
              senderPubKey: row['sender_pub_key'] as Uint8List?,
              timestamp: timestamp,
            ));
          }
          break;
        case EventType.hazardMarker:
          final data =
              payload == null ? null : _decoder.decodeHazardData(payload);
          if (data != null) {
            _hazardController.add(HazardEvent(
              eventId: eventId,
              type: data.hazardType,
              severity: data.severity,
              lat: data.centerLat,
              lng: data.centerLng,
              radiusMeters: data.radiusMeters,
              description: data.description,
            ));
          }
          break;
        case EventType.presence:
          if (payload != null) {
            try {
              final j = jsonDecode(utf8.decode(payload)) as Map<String, dynamic>;
              _presenceController.add(PresenceUpdate(
                eventId: eventId,
                anon8: (j['anon8'] as String?) ?? '',
                source: (j['src'] as int?) ?? 0,
                lat: (j['lat'] as num?)?.toDouble(),
                lng: (j['lng'] as num?)?.toDouble(),
                accuracy: (j['acc'] as num?)?.toInt(),
                battery: (j['battery'] as num?)?.toInt(),
                observedMs: (j['observed_ms'] as int?) ?? 0,
              ));
            } catch (_) {
              // malformed presence payload — skip silently
            }
          }
          break;
        default:
          break;
      }
    }
    if (latestNewEventId != null) {
      _anyEventController.add(EventLogChanged(latestEventId: latestNewEventId));
    }
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    await _sosController.close();
    await _hazardController.close();
    await _presenceController.close();
    await _anyEventController.close();
  }
}
