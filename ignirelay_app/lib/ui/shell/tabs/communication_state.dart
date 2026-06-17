// CommunicationState — UI-F4「安全」分頁通訊狀態彙整。
//
// 把既有來源（mesh/BLE、本地 outbox、足跡、cloud 設定）聚合成一眼可讀的狀態：一行
// 「最佳路徑」+ cloud 狀態 + 待送筆數 + 最後足跡時間。**純資料 + 純函式推導**，零 widget、
// 零 app/ui import，沿用 A10/A10b（position_estimator / relative_position）的純函式風格，
// 可獨立單元測試。
//
// Stage A 誠實邊界：cloud 永遠 stub/off（雲端串接留 Stage E），best path 與 cloud 文案
// 一律不宣稱「可達/已連線」。不上 wire/DB——這裡只讀別人算好的數字。

/// 訊息目前最可能的送出路徑。Stage A 只有近距離網狀；雲端待 Stage E，故不在此列。
enum CommsPath {
  /// 尚未加入場域 —— 非控制事件無法送出（A5 §21.6）。
  noField,

  /// 已加入場域但近距離通訊未開啟。
  offline,

  /// 通訊已開、尚無鄰近裝置可接力。
  waitingPeers,

  /// 通訊已開且有鄰近裝置 —— 近距離網狀接力。
  meshRelay,
}

/// 一次彙整的通訊狀態快照（immutable）。由 [CommunicationState.from] 從原始數值推導。
class CommunicationState {
  final bool hasField;
  final bool meshRunning;
  final int peers;
  final int sentCount;
  final int receivedCount;

  /// 本地待送 outbox 深度（已排隊、尚未送出的封包數）。
  final int outboxDepth;

  /// 最後一次足跡送出時間（自動信標或手動更新，取較新者）；從未送出則為 null。
  final DateTime? lastPresenceAt;

  /// 此場域是否設定了 cloud_base_url（Stage E 用）。Stage A 永遠「未啟用」。
  final bool cloudConfigured;

  /// 推導出的最佳送出路徑。
  final CommsPath bestPath;

  const CommunicationState({
    required this.hasField,
    required this.meshRunning,
    required this.peers,
    required this.sentCount,
    required this.receivedCount,
    required this.outboxDepth,
    required this.lastPresenceAt,
    required this.cloudConfigured,
    required this.bestPath,
  });

  factory CommunicationState.from({
    required bool hasField,
    required bool meshRunning,
    required int peers,
    required int sentCount,
    required int receivedCount,
    required int outboxDepth,
    required DateTime? lastPresenceAt,
    required bool cloudConfigured,
  }) {
    final CommsPath path;
    if (!hasField) {
      path = CommsPath.noField;
    } else if (!meshRunning) {
      path = CommsPath.offline;
    } else if (peers > 0) {
      path = CommsPath.meshRelay;
    } else {
      path = CommsPath.waitingPeers;
    }
    return CommunicationState(
      hasField: hasField,
      meshRunning: meshRunning,
      peers: peers,
      sentCount: sentCount,
      receivedCount: receivedCount,
      outboxDepth: outboxDepth,
      lastPresenceAt: lastPresenceAt,
      cloudConfigured: cloudConfigured,
      bestPath: path,
    );
  }

  /// 一行最佳路徑文案（產品語，無工程/階段名）。
  String get bestPathLabel {
    switch (bestPath) {
      case CommsPath.noField:
        return '尚未加入場域';
      case CommsPath.offline:
        return '離線（近距離通訊未開啟）';
      case CommsPath.waitingPeers:
        return '等待鄰近裝置…';
      case CommsPath.meshRelay:
        return '近距離網狀傳遞';
    }
  }

  /// Cloud 狀態一行 —— Stage A 永不宣稱可達/已連線。
  String get cloudLabel =>
      cloudConfigured ? '雲端：已設定（尚未啟用）' : '雲端：離線';
}

/// 一次足跡發佈是否算「真的送出」——只有被接受或排入佇列才算（UI-F4 / Owner req 1）。
/// `noField`、僅嘗試未被接受、以及拋例外的失敗路徑都回 `false`，呼叫端據此決定是否
/// 更新「最後足跡」時間，避免把失敗/未加入場域偽裝成已送出。
bool presenceCountsAsSent({required bool anyAccepted, required bool queued}) =>
    anyAccepted || queued;
