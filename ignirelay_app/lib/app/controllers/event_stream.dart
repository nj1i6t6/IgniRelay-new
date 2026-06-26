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

/// SOS 解除（投影自 v3 STATUS_UPDATE `safetyState == SAFE`；A8 / OD-8）。
///
/// 以 author（`sender_pub_key` 的 hex）標記哪位求救者已回報「我安全了」，供
/// UI 把該 author 的 SOS 告警卡標「已解除」。wire 無 `SOS_CANCELLED` 型別——
/// 這是 LWW（spec §10.2）收斂後的 read-model 投影。
class SosResolved {
  /// 求救者公鑰 hex（對應 [SosAlert.senderPubKey] 的 hex）。空字串 = 未知 author。
  final String authorKeyHex;
  final DateTime timestamp;
  SosResolved({required this.authorKeyHex, required this.timestamp});
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

/// PRESENCE 足跡更新（投影自 v3 wire 的 `EventTypeV2.presence`）。
///
/// 內容是純 Dart 型別（由 `V2InboundProjector` 寫入 read-model 的 JSON snapshot
/// 還原而來），不含 protobuf，供 debug shell「最近 presence」清單渲染。
class PresenceUpdate {
  final String eventId;

  /// anon_user_id 前 4 bytes 的 hex 顯示把手（非完整 id、不可反推）。
  final String anon8;

  /// `LocationSource.*` 數值（0 = unknown / 無位置）。
  final int source;

  /// 經緯度（無 GPS 時為 null）。
  final double? lat;
  final double? lng;

  /// 水平誤差（公尺，null = 未知）。
  final int? accuracyM;

  /// 電量提示 0..100（null = 未提供）。
  final int? batteryHint;

  /// 觀測時間。
  final DateTime observedAt;

  PresenceUpdate({
    required this.eventId,
    required this.anon8,
    required this.source,
    required this.observedAt,
    this.lat,
    this.lng,
    this.accuracyM,
    this.batteryHint,
  });
}

/// CHECKPOINT 點名通過（投影自 v3 wire 的 `EventTypeV2.checkpoint`）。
///
/// 內容是純 Dart 型別（由 `V2InboundProjector` 寫入 read-model 的 JSON snapshot
/// 還原而來），不含 protobuf。CHECKPOINT 非 LWW（spec §10.2）——每次通過都是獨立
/// 事件，故 UI 以 `eventId` 區分、不折疊。
class CheckpointCrossing {
  final String eventId;

  /// 點名點 / Field Node 錨點 id。
  final String checkpointId;

  /// anon_user_id 前 4 bytes 的 hex 顯示把手（非完整 id、不可反推）。
  final String anon8;

  /// 經緯度（無座標時為 null）。
  final double? lat;
  final double? lng;

  /// 通過時間。
  final DateTime observedAt;

  CheckpointCrossing({
    required this.eventId,
    required this.checkpointId,
    required this.anon8,
    required this.observedAt,
    this.lat,
    this.lng,
  });
}

/// ADMIN_BROADCAST 管理廣播指令（投影自 v3 wire 的 `EventTypeV2.adminBroadcast`）。
///
/// 內容是純 Dart 型別（由 `V2InboundProjector` 寫入 read-model 的 JSON snapshot
/// 還原而來），不含 protobuf。多筆指令並存（spec §10.2 非 LWW）；UI 依 [expiresAt]
/// 自動下架（[isExpired]）。
class AdminBroadcast {
  final String eventId;

  /// `AdminScope.*` 數值（1=本場域、2=全部、0=未指定）。UI 不 import app/proto，
  /// 故以本地數值對照。
  final int scope;

  final String message;

  /// 到期時間（null = 無到期）。UI 過此時間即下架。
  final DateTime? expiresAt;

  /// 收到（投影）時間。
  final DateTime receivedAt;

  AdminBroadcast({
    required this.eventId,
    required this.scope,
    required this.message,
    required this.receivedAt,
    this.expiresAt,
  });

  /// 是否已過 [expiresAt]（無到期則永不過期）。純函式，便於測試。
  bool isExpired(DateTime now) => expiresAt != null && now.isAfter(expiresAt!);
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
    Stream<NodeReceipt>? nodeReceiptSource,
  })  : _handler = handler,
        _decoder = decoder,
        _store = store,
        _nodeReceiptSource = nodeReceiptSource;

  final MeshEventHandler _handler;
  final EventDecoder _decoder;
  final EventStore _store;

  /// A12 — upstream NODE_RECEIPT (105) source, normally
  /// `V2InboundProjector.nodeReceipts`. `null` in tests / pre-wiring → the
  /// [nodeReceipts] stream simply never emits. Forwarded into a locally-owned
  /// broadcast so this facade controls the subscriber lifecycle.
  final Stream<NodeReceipt>? _nodeReceiptSource;
  StreamSubscription<NodeReceipt>? _nodeReceiptSub;

  StreamSubscription<MeshDataReceived>? _subscription;
  final Set<String> _dispatchedEventIds = <String>{};

  final StreamController<SosAlert> _sosController =
      StreamController<SosAlert>.broadcast();
  final StreamController<SosResolved> _sosResolvedController =
      StreamController<SosResolved>.broadcast();
  final StreamController<HazardEvent> _hazardController =
      StreamController<HazardEvent>.broadcast();
  final StreamController<PresenceUpdate> _presenceController =
      StreamController<PresenceUpdate>.broadcast();
  final StreamController<CheckpointCrossing> _checkpointController =
      StreamController<CheckpointCrossing>.broadcast();
  final StreamController<AdminBroadcast> _adminController =
      StreamController<AdminBroadcast>.broadcast();
  final StreamController<EventLogChanged> _anyEventController =
      StreamController<EventLogChanged>.broadcast();
  final StreamController<NodeReceipt> _nodeReceiptController =
      StreamController<NodeReceipt>.broadcast();

  Stream<SosAlert> get sosAlerts => _sosController.stream;

  /// SOS 解除 typed stream（投影自 STATUS_UPDATE safetyState=SAFE；A8）。UI 以
  /// author 比對，把對應的 SOS 告警卡標「已解除」。
  Stream<SosResolved> get sosResolutions => _sosResolvedController.stream;

  Stream<HazardEvent> get hazardEvents => _hazardController.stream;

  /// PRESENCE 足跡更新 typed stream（投影自 v3 `EventTypeV2.presence`）。
  Stream<PresenceUpdate> get presenceUpdates => _presenceController.stream;

  /// CHECKPOINT 點名通過 typed stream（投影自 v3 `EventTypeV2.checkpoint`；A9）。
  Stream<CheckpointCrossing> get checkpointCrossings =>
      _checkpointController.stream;

  /// ADMIN_BROADCAST 管理廣播 typed stream（投影自 v3 `EventTypeV2.adminBroadcast`；
  /// A9）。UI 置頂橫幅依 `expiresAt` 自動下架。
  Stream<AdminBroadcast> get adminBroadcasts => _adminController.stream;

  /// 「事件日誌有新東西」的通用通知 stream。UI 若只需要「something 變了，
  /// 請重新跑 query」的訊號，就訂閱這個 stream，不要再用 [rawEvents]。
  Stream<EventLogChanged> get anyEventChanges => _anyEventController.stream;

  /// App↔Node first-hop receipts (NODE_RECEIPT = EventType 105; A12). Forwarded
  /// from `V2InboundProjector.nodeReceipts`. A debug view matches each by
  /// `refEnvelopeIdHex` to the sent row to show「已送達節點」. Never carries field
  /// events — receipts are transport-layer acks, not projected to `Event_Logs`.
  Stream<NodeReceipt> get nodeReceipts => _nodeReceiptController.stream;

  /// Raw stream passthrough — **debug 專用**。Production UI 一律走上面的 typed
  /// streams 或 [anyEventChanges]，由 Stage 1 acceptance gate 強制執行。
  Stream<MeshDataReceived> get rawEvents => _handler.events;

  List<String> get debugLogs => _handler.debugLogs;

  /// 讀回已落地（已投影 / 先前已收到）的 HAZARD read-model，newest-first。
  ///
  /// [hazardEvents] 是 broadcast stream、**不重播**：在某個 UI（如「事件」分頁的
  /// HazardCard）mount 之前就抵達的 HAZARD，不會再經 stream 推一次。這個一次性
  /// query 讓 UI 在 mount 時把 `Event_Logs` 中既有的 `hazardMarker` 補齊，之後仍
  /// 用 live [hazardEvents] 即時追加（UI 以 eventId 去重，HAZARD 非 LWW、每筆獨立）。
  /// 解析失敗的列略過（壞資料不致命）。
  Future<List<HazardEvent>> recentHazards({int limit = 20}) async {
    final rows = await _store.queryByType(EventType.hazardMarker, limit: limit);
    final out = <HazardEvent>[];
    for (final row in rows) {
      final payload = row['payload'] as Uint8List?;
      if (payload == null) continue;
      final data = _decoder.decodeHazardData(payload);
      if (data == null) continue;
      out.add(HazardEvent(
        eventId: (row['event_id'] as String?) ?? '',
        type: data.hazardType,
        severity: data.severity,
        lat: data.centerLat,
        lng: data.centerLng,
        radiusMeters: data.radiusMeters,
        description: data.description,
      ));
    }
    return out;
  }

  // ── Mount backfill (A11-debug-4-fix) ──────────────────────────────────────
  //
  // The typed streams above are broadcast and DO NOT replay: any event that
  // landed in `Event_Logs` before a UI mounts is never pushed again. These
  // one-shot queries let a screen (LastSeenScreen) hydrate already-stored
  // PRESENCE / SOS / SAFE / CHECKPOINT on mount, instead of staying blank after
  // a restart until the next live event. They mirror [recentHazards] and reuse
  // the SAME row→typed mappings as the live dispatch (so the two never drift).
  // Decode failures skip the row (bad data is not fatal).

  /// Already-stored PRESENCE footprints, newest-first.
  Future<List<PresenceUpdate>> recentPresence({int limit = 50}) async {
    final rows =
        await _store.queryByType(LocalReadModelType.presence, limit: limit);
    final out = <PresenceUpdate>[];
    for (final row in rows) {
      final payload = row['payload'] as Uint8List?;
      if (payload == null) continue;
      final update = _presenceFromSnapshot(_eventIdOf(row), payload, _tsOf(row));
      if (update != null) out.add(update);
    }
    return out;
  }

  /// Already-stored CHECKPOINT crossings, newest-first.
  Future<List<CheckpointCrossing>> recentCheckpoints({int limit = 50}) async {
    final rows =
        await _store.queryByType(LocalReadModelType.checkpoint, limit: limit);
    final out = <CheckpointCrossing>[];
    for (final row in rows) {
      final payload = row['payload'] as Uint8List?;
      if (payload == null) continue;
      final crossing =
          _checkpointFromSnapshot(_eventIdOf(row), payload, _tsOf(row));
      if (crossing != null) out.add(crossing);
    }
    return out;
  }

  /// Already-stored SOS-class alerts (requestBroadcast urgency≥2) within
  /// [window], newest-first. Coordinates come from `received_lat`/`received_lng`
  /// (see [_sosFromRow]).
  Future<List<SosAlert>> recentSos(
      {Duration window = const Duration(hours: 24)}) async {
    final rows = await _store.queryRecentSos(window: window);
    final out = <SosAlert>[];
    for (final row in rows) {
      final alert = _sosFromRow(row);
      if (alert != null) out.add(alert);
    }
    return out;
  }

  /// Already-stored SOS resolutions (SAFE), newest-first. The caller merges
  /// these with [recentSos] into a timestamp-ordered timeline so author-LWW
  /// converges the same way live arrival order does.
  Future<List<SosResolved>> recentSosResolutions({int limit = 50}) async {
    final rows =
        await _store.queryByType(LocalReadModelType.sosResolved, limit: limit);
    return [for (final row in rows) _sosResolvedFromRow(row)];
  }

  void start() {
    _subscription ??= _handler.events.listen((_) {
      unawaited(_dispatchRecentEvents());
    });
    // A12 — forward NODE_RECEIPT (105) from the projector into our own
    // broadcast so subscribers see receipts via this facade.
    _nodeReceiptSub ??= _nodeReceiptSource?.listen((r) {
      if (!_nodeReceiptController.isClosed) _nodeReceiptController.add(r);
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
      final payload = row['payload'] as Uint8List?;
      final timestamp = _tsOf(row);

      switch (eventType) {
        case EventType.requestBroadcast:
          // requestBroadcast urgency≥2 = SOS-class（含 V2InboundProjector 投影的
          // v2 SOS）。urgency<2 的請求不再有 typed stream（supplyChanges 已下線）。
          // 列→SosAlert 映射集中在 [_sosFromRow]，live 與 [recentSos] backfill 共用。
          final alert = _sosFromRow(row);
          if (alert != null) _sosController.add(alert);
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
        case LocalReadModelType.presence:
          // PRESENCE read-model row：payload 是純 JSON snapshot（非 protobuf），
          // 由 V2InboundProjector 寫入。這裡還原成 typed PresenceUpdate。
          final update = payload == null
              ? null
              : _presenceFromSnapshot(eventId, payload, timestamp);
          if (update != null) _presenceController.add(update);
          break;
        case LocalReadModelType.sosResolved:
          // SOS 解除 read-model row（A8）：投影自 STATUS_UPDATE safetyState=SAFE，
          // 以 sender_pub_key 標記哪位 author 已回報安全。列→SosResolved 映射集中
          // 在 [_sosResolvedFromRow]，live 與 [recentSosResolutions] backfill 共用。
          _sosResolvedController.add(_sosResolvedFromRow(row));
          break;
        case LocalReadModelType.checkpoint:
          // CHECKPOINT read-model row（A9）：payload 是純 JSON snapshot（非 protobuf），
          // 由 V2InboundProjector 寫入。還原成 typed CheckpointCrossing。
          final crossing = payload == null
              ? null
              : _checkpointFromSnapshot(eventId, payload, timestamp);
          if (crossing != null) _checkpointController.add(crossing);
          break;
        case LocalReadModelType.adminBroadcast:
          // ADMIN_BROADCAST read-model row（A9）：payload 是純 JSON snapshot，由
          // V2InboundProjector 寫入。還原成 typed AdminBroadcast（UI 依 expiresAt 下架）。
          final admin = payload == null
              ? null
              : _adminFromSnapshot(eventId, payload, timestamp);
          if (admin != null) _adminController.add(admin);
          break;
        default:
          break;
      }
    }
    if (latestNewEventId != null) {
      _anyEventController.add(EventLogChanged(latestEventId: latestNewEventId));
    }
  }

  /// 把 PRESENCE read-model 的 JSON snapshot 還原成 [PresenceUpdate]。
  /// 解析失敗回 null（debug 面，壞資料不致命）。
  PresenceUpdate? _presenceFromSnapshot(
      String eventId, Uint8List payload, DateTime fallbackTs) {
    try {
      final decoded = jsonDecode(utf8.decode(payload));
      if (decoded is! Map) return null;
      final j = Map<String, dynamic>.from(decoded);
      final observedMs = j['observed_ms'] as int?;
      return PresenceUpdate(
        eventId: eventId,
        anon8: (j['anon8'] as String?) ?? '',
        source: (j['src'] as num?)?.toInt() ?? 0,
        lat: (j['lat'] as num?)?.toDouble(),
        lng: (j['lng'] as num?)?.toDouble(),
        accuracyM: (j['acc'] as num?)?.toInt(),
        batteryHint: (j['battery'] as num?)?.toInt(),
        observedAt: observedMs != null
            ? DateTime.fromMillisecondsSinceEpoch(observedMs)
            : fallbackTs,
      );
    } catch (_) {
      return null;
    }
  }

  /// 把 CHECKPOINT read-model 的 JSON snapshot 還原成 [CheckpointCrossing]。
  /// 解析失敗回 null（debug 面，壞資料不致命）。
  CheckpointCrossing? _checkpointFromSnapshot(
      String eventId, Uint8List payload, DateTime fallbackTs) {
    try {
      final decoded = jsonDecode(utf8.decode(payload));
      if (decoded is! Map) return null;
      final j = Map<String, dynamic>.from(decoded);
      final observedMs = j['observed_ms'] as int?;
      return CheckpointCrossing(
        eventId: eventId,
        checkpointId: (j['checkpoint_id'] as String?) ?? '',
        anon8: (j['anon8'] as String?) ?? '',
        lat: (j['lat'] as num?)?.toDouble(),
        lng: (j['lng'] as num?)?.toDouble(),
        observedAt: observedMs != null
            ? DateTime.fromMillisecondsSinceEpoch(observedMs)
            : fallbackTs,
      );
    } catch (_) {
      return null;
    }
  }

  /// 把 ADMIN_BROADCAST read-model 的 JSON snapshot 還原成 [AdminBroadcast]。
  /// 解析失敗回 null（debug 面，壞資料不致命）。
  AdminBroadcast? _adminFromSnapshot(
      String eventId, Uint8List payload, DateTime receivedTs) {
    try {
      final decoded = jsonDecode(utf8.decode(payload));
      if (decoded is! Map) return null;
      final j = Map<String, dynamic>.from(decoded);
      final expiresMs = j['expires_ms'] as int?;
      return AdminBroadcast(
        eventId: eventId,
        scope: (j['scope'] as num?)?.toInt() ?? 0,
        message: (j['message'] as String?) ?? '',
        expiresAt: expiresMs != null
            ? DateTime.fromMillisecondsSinceEpoch(expiresMs)
            : null,
        receivedAt: receivedTs,
      );
    } catch (_) {
      return null;
    }
  }

  /// Build a [SosAlert] from a requestBroadcast `Event_Logs` row, or null for a
  /// non-SOS row (urgency < 2). Shared by the live dispatch and [recentSos] so
  /// the SOS read-model mapping lives in ONE place.
  ///
  /// A11-debug-4-fix: coordinates are read from `received_lat`/`received_lng` —
  /// the ONLY columns where `ingestVerifiedEvent` / the v2 projector persist a
  /// received event's location (`Event_Logs` has NO `lat`/`lng` column). The
  /// pre-fix code read `row['lat']`/`row['lng']`, which are absent → always null,
  /// so a received SOS lost its coordinates and the receiver showed「（無座標）」
  /// even when the sender had a GPS fix. This is receive/read-side only; the SOS
  /// send path is untouched.
  SosAlert? _sosFromRow(Map<String, dynamic> row) {
    final urgency = (row['urgency'] as int?) ?? 0;
    if (urgency < 2) return null;
    final payload = row['payload'] as Uint8List?;
    final data = payload == null ? null : _decoder.decodeRequestData(payload);
    return SosAlert(
      eventId: _eventIdOf(row),
      urgency: urgency,
      description: data?.note ?? '',
      lat: row['received_lat'] as double?,
      lng: row['received_lng'] as double?,
      senderPubKey: row['sender_pub_key'] as Uint8List?,
      timestamp: _tsOf(row),
    );
  }

  /// Build a [SosResolved] from a `LocalReadModelType.sosResolved` row. Shared by
  /// the live dispatch and [recentSosResolutions].
  SosResolved _sosResolvedFromRow(Map<String, dynamic> row) {
    final pubKey = row['sender_pub_key'] as Uint8List?;
    return SosResolved(
      authorKeyHex: pubKey == null ? '' : _hex(pubKey),
      timestamp: _tsOf(row),
    );
  }

  static String _eventIdOf(Map<String, dynamic> row) =>
      (row['event_id'] as String?) ?? '';

  static DateTime _tsOf(Map<String, dynamic> row) =>
      DateTime.fromMillisecondsSinceEpoch(
        (row['hlc_timestamp'] as int?) ?? DateTime.now().millisecondsSinceEpoch,
      );

  static String _hex(Uint8List bytes) {
    final sb = StringBuffer();
    for (final b in bytes) {
      sb.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    await _nodeReceiptSub?.cancel();
    await _nodeReceiptController.close();
    await _sosController.close();
    await _sosResolvedController.close();
    await _hazardController.close();
    await _presenceController.close();
    await _checkpointController.close();
    await _adminController.close();
    await _anyEventController.close();
  }
}
