// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class SZh extends S {
  SZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => '烽傳 IgniRelay';

  @override
  String get mainStartupLoading => '烽傳 啟動中...';

  @override
  String get mainBluetoothDialogTitle => '需要開啟藍牙';

  @override
  String get mainBluetoothDialogContent =>
      '烽傳使用藍牙建立 Mesh 離線網路，\n用於傳遞求救訊號與物資媒合。\n\n請開啟藍牙以啟用完整功能。';

  @override
  String get mainBluetoothDialogCancel => '稍後';

  @override
  String get mainBluetoothDialogConfirm => '開啟藍牙';

  @override
  String mainBleFailSnack(String error) {
    return 'BLE Mesh 啟動失敗：$error';
  }

  @override
  String get mainPermissionSnack => '需要藍牙與位置權限才能啟用 Mesh 網路';

  @override
  String get commonCancel => '取消';

  @override
  String get tierLabel1Standard => '標準模式 (Tier 1)';

  @override
  String get tierLabel1Force => '全速模式 (Tier 1)';

  @override
  String get tierLabel2EcoRelay => '省電中繼模式 (Tier 2)';

  @override
  String get tierLabel3UltraEco => '極省電模式 (Tier 3)';

  @override
  String get shellTabSafety => '安全';

  @override
  String get shellTabPosition => '位置';

  @override
  String get shellTabEvents => '事件';

  @override
  String get shellTabAssist => '協助';

  @override
  String get shellTabMine => '我的';

  @override
  String get noFieldTitle => '烽傳 IgniRelay';

  @override
  String get noFieldSubtitle => '加入或建立一個場域，開始被看見、能求救、留下最後足跡。';

  @override
  String get noFieldJoin => '加入場域';

  @override
  String get noFieldCreate => '建立場域';

  @override
  String get noFieldPreview => '先看功能';

  @override
  String get myTitle => '我的';

  @override
  String get mySubtitle => '場域、身分與設定';

  @override
  String get myFieldSection => '場域';

  @override
  String get myFieldManage => '場域管理';

  @override
  String myCurrentField(String name) {
    return '目前場域：$name';
  }

  @override
  String get myFieldUnnamed => '（未命名）';

  @override
  String myFieldJoinedCount(int count) {
    return '已加入 $count 個';
  }

  @override
  String get myNoField => '尚未加入場域。';

  @override
  String get myRoleSection => '身分與角色';

  @override
  String get myRoleEmptyHint => '加入或建立場域後顯示。';

  @override
  String get myRoleOwnerDesc => '你建立了這個場域，可分享加入 QR。';

  @override
  String get myRoleParticipantDesc => '你已加入這個場域。';

  @override
  String get roleHost => '主辦';

  @override
  String get roleMember => '成員';

  @override
  String get myPermissionSection => '權限狀態';

  @override
  String get myComingSoon => '即將提供';

  @override
  String get myDeveloperDiagnostics => '開發者診斷';

  @override
  String get settingsSection => '設定';

  @override
  String get settingsLanguage => '語言';

  @override
  String get settingsTextSize => '字體大小';

  @override
  String get settingsTextSizeStandard => '標準';

  @override
  String get settingsTextSizeLarge => '大字';

  @override
  String get settingsTextSizeXLarge => '特大字';

  @override
  String get settingsTextSizeHuge => '超大字';

  @override
  String get fieldTitle => '場域';

  @override
  String get fieldSubtitle => '加入場域後才能收發事件';

  @override
  String get fieldNoneTitle => '尚未加入任何場域';

  @override
  String get fieldNoneBody => '掃描主辦方的場域 QR、輸入加入代碼，或自行建立一個場域。';

  @override
  String get fieldUnnamed => '（未命名場域）';

  @override
  String get fieldActiveChip => '作用中';

  @override
  String get fieldScanJoin => '掃碼加入';

  @override
  String get fieldEnterCode => '輸入代碼';

  @override
  String get fieldCreateNew => '建立新場域';

  @override
  String fieldJoinedHeader(int count) {
    return '已加入的場域（$count）';
  }

  @override
  String get fieldShowQr => '顯示 QR';

  @override
  String get fieldLeave => '離開場域';

  @override
  String fieldCreateFailed(String error) {
    return '建立場域失敗：$error';
  }

  @override
  String get fieldSecretNotFound => '找不到此場域的密鑰，無法顯示 QR';

  @override
  String get fieldCodeTitle => '輸入場域代碼';

  @override
  String get fieldCodeBody => '貼上 IGNI1 場域代碼，或輸入 64 個十六進位字元的場域密鑰。';

  @override
  String get fieldCodeHint => 'IGNI1:… 或 a1b2c3…';

  @override
  String get fieldCancel => '取消';

  @override
  String get fieldJoin => '加入';

  @override
  String get fieldScannedName => '掃碼場域';

  @override
  String get fieldCodeUnrecognized => '代碼格式無法辨識：需為 IGNI1 代碼或 64 個十六進位字元';

  @override
  String fieldDefaultNamePrefix(String prefix) {
    return '場域-$prefix';
  }

  @override
  String fieldJoinedSnack(String id) {
    return '已加入場域 $id…';
  }

  @override
  String fieldJoinFailed(String error) {
    return '加入場域失敗：$error';
  }

  @override
  String get fieldLeaveTitle => '離開場域？';

  @override
  String fieldLeaveBody(String name) {
    return '即將離開「$name」。此動作不可復原，將從本機刪除此場域的密鑰，需重新掃碼 / 輸入代碼才能再次加入。';
  }

  @override
  String get fieldLeaveConfirm => '離開';

  @override
  String get fieldLeftSnack => '已離開場域';

  @override
  String fieldLeaveFailed(String error) {
    return '離開場域失敗：$error';
  }

  @override
  String get fieldCreateTitle => '建立新場域';

  @override
  String get fieldNameLabel => '場域名稱';

  @override
  String get fieldNameHint => '例：台北車站避難所';

  @override
  String get fieldCreateConfirm => '建立';

  @override
  String get fieldDefaultName => '新場域';

  @override
  String get fieldErrEmpty => '代碼是空的';

  @override
  String get fieldErrBadPrefix => '這不是 IgniRelay 場域代碼（前綴不符）';

  @override
  String get fieldErrTooFewSegments => '代碼不完整';

  @override
  String get fieldErrBadSecret => '代碼的場域密鑰格式錯誤';

  @override
  String get fieldErrBadCloudUrl => '代碼的雲端網址無效（僅接受 https://）';

  @override
  String get fieldErrStaffWithoutCloud => '代碼格式錯誤：含 staff token 卻缺雲端網址';

  @override
  String get fieldErrMalformed => '代碼內容毀損，無法解析';

  @override
  String get fieldScanBack => '返回';

  @override
  String get fieldScanTitle => '掃描場域 QR';

  @override
  String get fieldScanHint => '對準主辦方的場域 QR 即可自動加入';

  @override
  String get fieldScanReject => '這不是 IgniRelay 場域 QR，請換一個';

  @override
  String get fieldScanNoCameraTitle => '無法開啟相機';

  @override
  String get fieldScanNoCameraBody => '請確認已授予相機權限，或改用「輸入代碼」加入場域。';

  @override
  String get fieldQrTitle => '場域 QR';

  @override
  String get fieldQrSubtitle => '讓對方掃描即可加入同一場域';

  @override
  String get fieldQrDebugWarning => '（debug）此代碼含場域密鑰，請勿外流：';

  @override
  String get fieldQrDone => '完成';

  @override
  String get previewModeSubtitle => '示範模式 · 不會送出任何資料';

  @override
  String get previewBadge => '示範資料';

  @override
  String get previewBack => '返回';

  @override
  String get previewPrev => '上一步';

  @override
  String get previewNext => '下一步';

  @override
  String get previewDemoChip => '示範';

  @override
  String get previewJoinIntro =>
      '掃描主辦者的 QR 或輸入密鑰即可加入一個場域。場域決定你和誰互通——只有同一個場域的人，才看得到彼此。';

  @override
  String get previewSafetyTitle => '安全：被看見 + 求救';

  @override
  String get previewSafetyIntro =>
      '加入後，App 會定期留下你的足跡，讓場域裡的人知道你還在、在哪附近。需要時可以長按發出 SOS。';

  @override
  String get previewSafetyFootprintTitle => '自動足跡（被看見）';

  @override
  String get previewSafetyFootprintBody =>
      '靜止時省電、移動時更頻繁地留下足跡。不需要一直盯著手機，別人也能看到你最後的位置。';

  @override
  String get previewSafetySosTitle => '求救 SOS';

  @override
  String get previewSafetySosBody =>
      '長按求救鍵，選擇紅色（受困）或黃色（受傷）。送出前有 5 秒可取消，避免誤觸。（示範不會真的送出）';

  @override
  String get previewPositionTitle => '位置：最後可信位置';

  @override
  String get previewPositionIntro =>
      '看見附近成員「最後可信的位置」與相對方位。雷達固定北朝上，越靠近中心代表離你越近。（這裡顯示的是示範資料）';

  @override
  String previewFootprintLine(String ago) {
    return '最後可信位置 · $ago';
  }

  @override
  String get previewEventsTitle => '事件：危害 / 廣播 / 打卡';

  @override
  String get previewEventsIntro => '場域裡的重要訊息會集中在事件：危害提醒、管理者廣播、平安打卡，讓你快速掌握現場狀況。';

  @override
  String get previewAssistTitle => '協助 + 離線也能用';

  @override
  String get previewAssistIntro =>
      '需要或能提供協助時，可以在「協助」裡媒合。最重要的是——沒有網路時，App 仍透過近距離轉傳運作。';

  @override
  String get previewAssistMatchTitle => '協助媒合';

  @override
  String get previewAssistMatchBody => '提出需求或回應他人需求，讓資源在場域內就近流動。';

  @override
  String get previewAssistOfflineTitle => '離線降級';

  @override
  String get previewAssistOfflineBody =>
      '沒有基地台或網路時，訊息會透過附近的裝置一手接一手傳遞；收訊恢復時自動補送，不會憑空捏造位置。';

  @override
  String get previewToneSos => '求救';

  @override
  String get previewToneWarn => '危害';

  @override
  String get previewToneInfo => '廣播';

  @override
  String get previewToneOk => '平安';

  @override
  String get previewToneNeutral => '事件';

  @override
  String get previewFieldLabel => '示範場域 · DEMO-FIELD';

  @override
  String previewAlias(String alias) {
    return '化名 $alias';
  }

  @override
  String get previewFpAgo1 => '1 分鐘前';

  @override
  String get previewFpAgo4 => '4 分鐘前';

  @override
  String get previewFpAgoTrapped => '受困 · 2 分鐘前';

  @override
  String get previewSosTitle => '求救 · 受困';

  @override
  String get previewSosAgo => '2 分鐘前';

  @override
  String get previewHazardTitle => '危害 · 火災 FIRE';

  @override
  String get previewHazardDetail => 'sev 2 · 巷口濃煙';

  @override
  String get previewHazardAgo => '6 分鐘前';

  @override
  String get previewBroadcastTitle => '管理廣播';

  @override
  String get previewBroadcastDetail => '集合點改至北側出口';

  @override
  String get previewBroadcastAgo => '10 分鐘前';

  @override
  String get previewCheckpointTitle => '打卡 · 平安';

  @override
  String get previewCheckpointAgo => '12 分鐘前';

  @override
  String get commonSend => '送出';

  @override
  String get noCoordinate => '無座標';

  @override
  String get noCoordinateParen => '（無座標）';

  @override
  String get timeJustNow => '剛剛';

  @override
  String timeAgoSeconds(int seconds) {
    return '$seconds 秒前';
  }

  @override
  String timeAgoMinutes(int minutes) {
    return '$minutes 分鐘前';
  }

  @override
  String timeAgoHours(int hours) {
    return '$hours 小時前';
  }

  @override
  String timeAgoDays(int days) {
    return '$days 天前';
  }

  @override
  String get safetyTitle => '我的安全';

  @override
  String get safetySubtitle => '通訊與足跡';

  @override
  String safetyToggleFailed(String error) {
    return '通訊切換失敗：$error';
  }

  @override
  String get safetyUpdateNoField => '尚未加入場域 — 請先到「我的」加入或建立場域';

  @override
  String safetyUpdateSent(int count) {
    return '已更新足跡（$count 個鄰近裝置）';
  }

  @override
  String get safetyUpdateQueued => '足跡已排入佇列，待鄰近裝置上線後送出';

  @override
  String get safetyUpdateAttempted => '已嘗試更新足跡';

  @override
  String safetyUpdateFailed(String error) {
    return '更新足跡失敗：$error';
  }

  @override
  String get safetyCommsOn => '近距離通訊：開啟';

  @override
  String get safetyCommsOff => '近距離通訊：關閉';

  @override
  String get safetyTurnOn => '開啟';

  @override
  String get safetyTurnOff => '關閉';

  @override
  String safetyCurrentPath(String path) {
    return '目前路徑：$path';
  }

  @override
  String get safetyStatPeers => '鄰近裝置';

  @override
  String get safetyStatSent => '已送';

  @override
  String get safetyStatReceived => '已收';

  @override
  String get safetyStatQueued => '待送';

  @override
  String safetyLastFootprint(String time) {
    return '最後足跡：$time';
  }

  @override
  String get safetyFootprintTitle => '足跡';

  @override
  String get safetyFootprintBody => '讓附近的人看見你最後可信的位置。';

  @override
  String get safetyUpdateNow => '立即更新足跡';

  @override
  String get safetyAutoBeacon => '自動足跡信標';

  @override
  String safetyMotion(String state) {
    return '動作偵測：$state';
  }

  @override
  String safetyGpsFix(String age) {
    return 'GPS 定位：$age';
  }

  @override
  String safetyGpsPolicy(String reason) {
    return '定位策略：$reason';
  }

  @override
  String get safetyRecentTitle => '最近足跡';

  @override
  String get safetyNoFootprint => '尚無足跡';

  @override
  String get commsPathNoField => '尚未加入場域';

  @override
  String get commsPathOffline => '離線（近距離通訊未開啟）';

  @override
  String get commsPathWaiting => '等待鄰近裝置…';

  @override
  String get commsPathMesh => '近距離網狀傳遞';

  @override
  String get cloudOffline => '雲端：離線';

  @override
  String get cloudConfigured => '雲端：已設定（尚未啟用）';

  @override
  String get gpsNoFix => '尚無定位';

  @override
  String get gpsReasonMovingRefresh => '移動時更新';

  @override
  String get gpsReasonMovingReuse => '移動中沿用新定位';

  @override
  String get gpsReasonStationary => '靜止沿用上次';

  @override
  String get gpsReasonUnknown => '沿用上次';

  @override
  String get gpsReasonManual => '手動更新';

  @override
  String get gpsReasonUnavailable => '定位不可用';

  @override
  String get beaconOff => '已關閉';

  @override
  String beaconStatus(int secs, int count, String low) {
    return '每 $secs 秒 · 已更新 $count 次$low';
  }

  @override
  String get beaconLowSuffix => '（低電量降頻）';

  @override
  String get motionMoving => '移動中';

  @override
  String get motionStationary => '靜止';

  @override
  String get motionUnknown => '尚未啟用';

  @override
  String get eventsTitle => '事件';

  @override
  String get eventsSubtitle => '危害、廣播、定點與系統事件';

  @override
  String get eventsRecentTitle => '最近事件';

  @override
  String get eventsRefresh => '重新整理';

  @override
  String get eventsEmpty => '尚無事件';

  @override
  String eventsRowType(String type) {
    return '類型 $type';
  }

  @override
  String get assistTitle => '協助';

  @override
  String get assistSubtitle => '離線協助與求助資源';

  @override
  String get assistOfflineTitle => '離線協助';

  @override
  String get assistOfflineBody => '離線求助資源與求救後續引導即將提供。需要緊急求救時，可隨時使用畫面上的全域求救鍵。';

  @override
  String get hazardCardTitleFormal => '危害回報';

  @override
  String get hazardCardTitleDebug => '危害（HAZARD）';

  @override
  String get hazardCardReport => '回報危害';

  @override
  String get hazardCardManualDebug => '手動 HAZARD';

  @override
  String get hazardCardManualDebugTitle => '手動 HAZARD（debug）';

  @override
  String get hazardCardDebugSampleDesc => '測試危害（debug）';

  @override
  String get hazardCardBodyFormal => '附近的危害事件。回報時座標取自本機定位；無定位時無法回報，請先取得位置。';

  @override
  String get hazardCardBodyDebug =>
      '收到的 typed HAZARD 事件（A3 接收側）。手動送出為 debug 占位（座標取本機 GPS，無定位則不送）。';

  @override
  String get hazardCardDescLabel => '描述（≤800B）';

  @override
  String get hazardCardNoLocation => '目前沒有位置，請取得位置後再回報';

  @override
  String hazardCardSentFormal(String type) {
    return '已回報危害「$type」· 需已加入場域才會廣播';
  }

  @override
  String hazardCardSentDebug(String type, String id) {
    return 'HAZARD「$type」已送出（id $id） · 需已加入場域才會實際廣播';
  }

  @override
  String hazardCardSendFailed(String error) {
    return 'HAZARD 送出失敗: $error';
  }

  @override
  String get hazardCardEmpty => '（尚無 HAZARD）';

  @override
  String get hazardCardTypeFire => '火災 FIRE';

  @override
  String get hazardCardTypeFlood => '淹水 FLOOD';

  @override
  String get hazardCardTypeCollapse => '倒塌 COLLAPSE';

  @override
  String get hazardCardTypeChemical => '化學 CHEMICAL';

  @override
  String get hazardCardTypeRoadblock => '路阻 ROADBLOCK';

  @override
  String get hazardCardTypeOther => '其他 OTHER';

  @override
  String get checkpointCardTitle => 'CHECKPOINT（點名通過）';

  @override
  String get checkpointCardManual => '手動 CHECKPOINT';

  @override
  String get checkpointCardIdHint => '點名點 / Field Node 錨點 id';

  @override
  String get checkpointCardBody => '收到的點名通過事件（非 LWW，每次通過皆獨立保留）。';

  @override
  String get checkpointCardEmpty => '（尚無 CHECKPOINT）';

  @override
  String get checkpointCardNoField => '尚未加入場域 — 請先在「場域」卡片加入或產生一個場域';

  @override
  String checkpointCardSent(String id, int count) {
    return 'CHECKPOINT「$id」已送出（$count peer）';
  }

  @override
  String checkpointCardQueued(String id, int depth) {
    return 'CHECKPOINT「$id」已排入佇列（無在線 peer，深度 $depth）';
  }

  @override
  String checkpointCardAttempted(String id, int count) {
    return 'CHECKPOINT「$id」已嘗試送出（$count peer，無人接受）';
  }

  @override
  String checkpointCardSendFailed(String error) {
    return 'CHECKPOINT 送出失敗: $error';
  }

  @override
  String get adminScopeField => '本場域公告';

  @override
  String get adminScopeAll => '全網公告';

  @override
  String get adminScopeDefault => '公告';

  @override
  String adminExpiry(String time) {
    return '至 $time';
  }

  @override
  String get adminPublishTest => '發測試 ADMIN 廣播';

  @override
  String adminTestMessage(String time) {
    return '測試管理廣播 $time';
  }

  @override
  String get adminNoField => '尚未加入場域 — 請先加入或產生一個場域';

  @override
  String adminSent(int count) {
    return 'ADMIN 廣播已送出（$count peer）';
  }

  @override
  String adminQueued(int depth) {
    return 'ADMIN 廣播已排入佇列（深度 $depth）';
  }

  @override
  String adminAttempted(int count) {
    return 'ADMIN 廣播已嘗試送出（$count peer）';
  }

  @override
  String adminSendFailed(String error) {
    return 'ADMIN 廣播送出失敗: $error';
  }

  @override
  String get sosTitle => '緊急求救';

  @override
  String get sosSubtitle => '長按求救鈕 1.5 秒，選擇狀態後 5 秒內可取消';

  @override
  String sosNearbyHeader(int count) {
    return '附近求救（$count）';
  }

  @override
  String get sosNoneNearby => '目前沒有收到求救訊號。';

  @override
  String get sosSending => '求救傳送中…';

  @override
  String get sosTriggerTitle => '發出求救';

  @override
  String get sosTriggerBody => '長按下方按鈕 1.5 秒，再選擇你的狀態。送出前還有 5 秒可取消。';

  @override
  String get sosHoldButton => '按住求救';

  @override
  String get sosCountdownTrapped => '受困求救';

  @override
  String get sosCountdownInjured => '受傷求救';

  @override
  String get sosCountdownHint => '秒後送出 — 仍可取消';

  @override
  String get sosActiveTitle => '你已發出求救';

  @override
  String get sosChipTrapped => '受困';

  @override
  String get sosChipInjured => '受傷';

  @override
  String get sosMarkSafe => '我安全了';

  @override
  String get sosChooseStatus => '選擇你的狀態';

  @override
  String get sosSeverityTrapped => '受困（最高優先）';

  @override
  String get sosMarkSafeNoField => '尚未加入場域 — 無法送出狀態更新';

  @override
  String get sosMarkSafeSent => '已送出「我安全了」';

  @override
  String get sosResolvedChip => '已解除';

  @override
  String get sosOutcomeSent => '已送出。';

  @override
  String get sosOutcomeNoField => '尚未加入場域 — 求救未送出，請先加入場域。';

  @override
  String sosOutcomeAccepted(int count) {
    return '已送達 $count 個鄰近裝置。';
  }

  @override
  String sosOutcomeQueued(int depth) {
    return '已排入佇列（無在線鄰近裝置，深度 $depth）。';
  }

  @override
  String sosOutcomeAttempted(int count) {
    return '已嘗試送出（$count 個，暫無人接收）。';
  }

  @override
  String get lastSeenTitle => '最後可信位置';

  @override
  String get lastSeenSubtitle => '依足跡 / 點名通過推估，非即時定位';

  @override
  String get lastSeenNeedLocalPosition => '需要本機位置才能顯示相對方位';

  @override
  String get lastSeenToggleList => '列表';

  @override
  String get lastSeenToggleRadar => '雷達';

  @override
  String get lastSeenEmpty =>
      '尚無位置證據 — 收到足跡（PRESENCE）或點名通過（CHECKPOINT）後，這裡會列出每人的最後可信位置。';

  @override
  String lastSeenUncertainty(int meters) {
    return '誤差 ~$meters m';
  }

  @override
  String lastSeenAnchor(String id) {
    return '錨點 $id';
  }

  @override
  String get confidenceHigh => '可信度 高';

  @override
  String get confidenceMedium => '可信度 中';

  @override
  String get confidenceLow => '可信度 低';

  @override
  String radarCaption(String range) {
    return '北朝上 · 外環 $range · 圓心為本機（最後可信位置投影）';
  }
}
