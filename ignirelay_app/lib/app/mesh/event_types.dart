// A6 (OD-6) step 3 — the alias initializers below reference the (now
// @Deprecated) v1-legacy canonicals; suppress the same-package deprecation
// hint just for those internal references.
// ignore_for_file: deprecated_member_use_from_same_package

/// 事件類型常數（對應 Protobuf EventType enum）
/// 唯一定義來源 — event_manager / mesh_event_handler 皆 import 此檔
///
/// A6 (OD-6) — 多數 v1 值屬已下線產品（媒合 / 物資 / 聊天 / 據點 / 巡檢 / 導航）
/// 的 **wire-legacy**，標 `@Deprecated('v1 wire legacy')`：值與編號**保留、不刪、
/// 不重排**（v1 解碼相容期仍需 — 見 `mesh_event_handler` 的 decode switch），僅以
/// 標記引導後續閱讀。read-model 仍在用的 `requestBroadcast`(1) / `hazardMarker`(4)
/// **不標**。唯二 sanctioned 消費端（`mesh_event_handler` / `ble_manager`）以
/// file-level ignore 抑制 self-package deprecation hint。
class EventType {
  // ── Broadcast ──
  @Deprecated('v1 wire legacy')
  static const int resourceRegister = 0; // 舊：物資供給（下線）
  static const int requestBroadcast = 1; // read-model live（SOS / 求援廣播）
  // ── Match negotiation（已下線產品）──
  @Deprecated('v1 wire legacy')
  static const int matchOffer = 2; // was matchIntent
  @Deprecated('v1 wire legacy')
  static const int physicalHandshake = 3;
  @Deprecated('v1 wire legacy')
  static const int matchAccept = 8; // was matchConfirm
  @Deprecated('v1 wire legacy')
  static const int matchDecline = 9; // was matchReject
  @Deprecated('v1 wire legacy')
  static const int matchCancel = 6;
  // ── New slots（已下線產品：媒合 / 據點）──
  @Deprecated('v1 wire legacy')
  static const int matchRequest = 15;
  @Deprecated('v1 wire legacy')
  static const int handshakeComplete = 16;
  @Deprecated('v1 wire legacy')
  static const int stationClaim = 17;
  @Deprecated('v1 wire legacy')
  static const int stationResponse = 18;
  // ── Navigation（已下線）──
  @Deprecated('v1 wire legacy')
  static const int locationUpdate = 14;
  // ── Non-match ──
  static const int hazardMarker = 4; // read-model live（HAZARD）
  @Deprecated('v1 wire legacy')
  static const int quarantineVote = 5;
  @Deprecated('v1 wire legacy')
  static const int fireAlarmRf = 7;
  @Deprecated('v1 wire legacy')
  static const int chatMessage = 13; // 舊：聊天（v1 13；v3 30 已 reserved，下線）
  // ── 永久保留（legacy，ignored but don't crash）──
  @Deprecated('v1 wire legacy')
  static const int matchInquiry = 10;
  @Deprecated('v1 wire legacy')
  static const int matchAvailable = 11;
  @Deprecated('v1 wire legacy')
  static const int matchGone = 12;

  // Backward compat aliases（已下線產品）
  @Deprecated('v1 wire legacy')
  static const int matchIntent = matchOffer;
  @Deprecated('v1 wire legacy')
  static const int matchConfirm = matchAccept;
  @Deprecated('v1 wire legacy')
  static const int matchReject = matchDecline;
}

/// Local-only read-model `event_type` markers.
///
/// These values **NEVER appear on any wire** (neither the v1 EventType enum
/// above nor the v3 `EventTypeV2` enum). They exist solely to tag rows the
/// `V2InboundProjector` writes into the `Event_Logs` read-model when a wire
/// event has no matching v1 enum, so UI / typed-streams can recognise them.
/// Values are ≥9000 to stay clear of every real wire EventType / EventTypeV2.
class LocalReadModelType {
  /// Projected PRESENCE footprint. Wire source = `EventTypeV2.presence` (3);
  /// this is the *read-model* tag for the row, NOT the wire type. The row's
  /// payload column holds a plain-JSON presence snapshot (NOT a protobuf).
  static const int presence = 9001;

  /// Projected SOS resolution ("我安全了"). Wire source = `EventTypeV2.statusUpdate`
  /// with `safetyState == SAFE` (A8 / OD-8). NOT a wire type — there is no
  /// `SOS_CANCELLED` on the wire; LWW (spec §10.2) converges the author's latest
  /// status and this row lets the read-model / UI mark that author's prior SOS
  /// resolved. The row's `sender_pub_key` identifies the author; payload is a
  /// small plain-JSON snapshot.
  static const int sosResolved = 9002;

  /// Projected CHECKPOINT crossing (A9). Wire source = `EventTypeV2.checkpoint`
  /// (4); this is the *read-model* tag for the row, NOT the wire type. CHECKPOINT
  /// is NOT LWW (spec §10.2) — each crossing is a distinct event, so rows are
  /// keyed by envelope_id (never collapsed). The row's payload holds a plain-JSON
  /// crossing snapshot (checkpoint_id / anon / location), NOT a protobuf.
  static const int checkpoint = 9003;

  /// Projected ADMIN_BROADCAST directive (A9). Wire source =
  /// `EventTypeV2.adminBroadcast` (82); the *read-model* tag, NOT the wire type.
  /// Distinct directives coexist (spec §10.2 — not LWW); the UI auto-dismisses
  /// each by its payload `expires_at`. The row payload holds a plain-JSON snapshot
  /// (scope / message / expires_ms), NOT a protobuf.
  static const int adminBroadcast = 9004;
}
