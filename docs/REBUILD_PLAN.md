# 烽傳 IgniRelay — 場域型重建計畫（交 GPT 審）

> 文件用途：把「從現有 IgniRelay app fork 出來、依《技術白皮書 v2.0》重建成精實場域型
> App」的完整計畫攤開,供獨立審查（GPT）批評。**讀者沒有原始對話脈絡,本文力求自含。**
> 範圍鎖定（user 親口）：① fork 成獨立新 repo ② 為 Mode B 預留 Field Node 協定
> ③ 全新獨立網路、wire 格式可自由改。

---

## 0. TL;DR

- 現有 app 是「災難**資源媒合 + 物資 + 聊天 + 社群**」產品(Mode A 手機對手機 BLE mesh)。
- 白皮書要的是「**被看見、SOS、最後足跡、危險、公告、點名**」的場域型離線中繼 App。
- **傳輸層(BLE mesh + 同步 + 去重 + HLC + crypto + 優先佇列)兩者共用且最難重寫 → 保留。**(離線地圖**降為 optional/future**,MVP 走 mapless 位置證據模型,見 §3.6)
- **語意事件模型 + services/repos + 整個 UI 跟新產品不符 → 砍掉重做。**
- 切線:`MeshTransport` 介面 + wire 信封(現以 v2 `EventEnvelopeV2` 為準)以下全留;語意事件 payload 以上全換。

---

## 0.1 範圍與用詞（硬規則 — GPT 審查後加入）

1. **本 repo 的 Phase 0b/1 是 App 軟體核心驗證（software-core proof），不是白皮書定義的 MVP。** App-only / Android 雙機驗證只證明軟體核心,不等於場域 MVP。
2. **白皮書 MVP exit 必須是 Mode B:Field Node + LoRa + Gateway + 本地事件後台/匯出。** 這些是 out-of-repo sibling work（見 §7.1）,本 App repo 不負責,但計畫不得低估 MVP 全貌。
3. **`field_id` 單獨不足以做場域 scope。** 場域隔離必須由「被簽章/MAC 綁定的事件 scope」強制（進 `EventEnvelopeV2` canonical 簽章位元組,見 §3.1/§3.4）;BLE/GATT service-data 預過濾只是**附加最佳化**,不可取代 wire-level scope。
4. **MVP 是「位置證據產品」,不是「地圖產品」。** App 端 P0 不內建離線地圖、不打包 MBTiles;定位走「節點 anchor + GPS + 相對位置 + 可信度」(§3.6)。基礎離線地圖降為 P1+ optional/future module。

> 對外一律稱「App repo Phase 0b」,不要稱「做白皮書 MVP」,以免偏航。
>
> **手機對手機 BLE 角色**:保留手機↔手機 BLE exchange / mesh / Data Mule,作為 App repo 的 software proof、fallback relay、近距離補充同步與 Data Mule path;**保留但不定位為白皮書 MVP 主線**(主線仍是 Mode B:Field Node + LoRa + Gateway)。
> *EN:* Phone-to-phone BLE remains as the App repo's software proof, fallback relay, and Data Mule path; it is retained, but not positioned as the whitepaper MVP backbone.

---

## 1. 已完成：Phase 0a（複製 + 改名 + 改 id）

| 項目 | 內容 |
|---|---|
| 新 repo | `IgniRelay/`（從 `CoReM` fork,clean ~219MB，排除 build/.dart_tool/workspace junk） |
| 資料夾改名 | Flutter 專案 `resqmesh_app/` → `ignirelay_app/`（殺掉死掉的 "ResQMesh" 舊名） |
| package id | Android `applicationId` 與 iOS bundle → **`network.ignirelay.field`**（與原 app `network.ignirelay` 區隔,可同機並存；Kotlin namespace `network.ignirelay.ignirelay_app` 不動,MethodChannel 名 `network.ignirelay/native` 不動） |
| 功能性參照修正 | `.github/workflows/ci.yml` working-dir、根 `CLAUDE.md` 路徑 |
| 大檔處理 | 200MB `taiwan_ignirelay.mbtiles` 不入版控（沿用原 repo 政策） |
| git | `git init -b main` + 首 commit `30eed86`（fork point `CoReM@f2d227f` / V0.2.5） |
| 驗證 | `flutter pub get` ✅ · `dart run tool/check_layers.dart --strict` ✅（no boundary violations）· `flutter analyze` 0 errors（7 個 pre-existing info-level lint，都在待砍的 chat/secondary 畫面） |

> 之後（Phase 0b 起）**暫不動工**,等本計畫過審。

---

## 2. 架構切線：保留 / 砍除

> 路徑相對 `ignirelay_app/`。

### 2.1 保留（最值錢、最依賴真機、最難重寫）

| 區塊 | 檔案 | 說明 |
|---|---|---|
| Transport 介面 | `lib/platform/mesh_transport.dart` | 乾淨抽象（broadcast / onDataReceived / peer 事件）—切線就在這 |
| Native 橋接 | `lib/platform/native_bridge.dart`、`native_bridge_facade.dart` | MethodChannel/EventChannel,Nordic 掃描/連線/GATT 寫入/Bloom/Outbox/前景服務/電池豁免/handoff |
| Transport 實作 | `lib/app/mesh/native_ble_transport_adapter.dart`、`ble_manager.dart`、`transport_factory.dart` | 雙角色（Central 掃描 + Peripheral GATT Server） |
| Mesh 機制 | `lib/app/mesh/{mesh_event_handler, chunker, reassembler, iblt, triage_queue, mesh_constants, mesh_router, capability_profile}.dart` | framing/去重/重組/Bloom 差量/P0–P4 優先佇列 |
| 原生 Android | `android/.../kotlin/{NordicMeshManager, IBLT, Chunker, Reassembler, IgniRelayConstants, MainActivity, IgniRelayForegroundService}.kt` | Nordic BLE Library（跨廠牌相容、MediaTek/OPPO workaround）、背景常駐 |
| 原生 iOS | `ios/Runner/{BlePlugin, IBLT, Chunker, Reassembler, IgniRelayConstants}.swift` | CoreBluetooth 對位（**code-wired,未真機驗證** — 見風險 R3） |
| 時鐘/合併 | `lib/app/crdt/{hlc, conflict_resolver}.dart` | HLC 排序、CRDT 合併 |
| 身分/簽章 | `lib/app/crypto/{identity_manager, crypto_utils}.dart` | 匿名 pubkey 身分、事件簽章 |
| ~~離線地圖~~ → **optional/future** | `lib/app/map/*`、`assets/maps/*` | **MVP 不內建地圖、不打包 MBTiles**（產品決策,見 §3.6）。code 保留為 future module、deps 於 Phase 0b 從 `pubspec` 移除;`assets/geodata/*`(村里界/POI 名稱解析)視 §3.6 定位需求決定去留 |
| Wire 信封 | **v2(live)**:`event_envelope_v2.dart` + `canonical_encoder_v2.dart` + `signer.dart`;v1(legacy 參考):`proto/mesh_protocol` 的 `MeshEvent`/`BloomFilterSync` | 保留信封機制;只換內層 payload + 加 `field_id`(綁 v2 簽章) |
| Event log 儲存 | `lib/app/db/database_helper.dart` 的 `Event_Logs` 表 + `lib/app/services/event_store.dart` | 事件 log 持久化 |

### 2.2 砍除（跟新產品不符）

| 區塊 | 內容 |
|---|---|
| 語意事件 | `lib/app/mesh/event_types.dart` 內 resource/match/station/chat/quarantine 全部 → 重寫成白皮書事件 |
| Proto payload | `ResourceData`、`RequestData`、`Match*Data`、`Station*Data`、`ChatMessageData`、`MatchInquiry*`、`QuarantineVoteData`、`MatchCancelData` … → 換成新 payload 集 |
| Services | `match_service`、`negotiation_*`、`station_supply_repo`、`negotiation_repo`、chat 相關 |
| DB 表 | `Match_Negotiations`、`Station_Quotas` → drop。**medical card 降級**:不留主線,只保留「SOS 時可選揭露緊急身份/備註」窄版(白皮書只談 SOS/匿名 ID/緊急授權,無醫療卡核心) |
| UI | `lib/ui/` 幾乎全部（match tabs、supply、chat、community、現行 map_screen 的媒合面板）→ 依「掃碼加入場域 + 模組化」重做 |

### 2.3 「保留但要改 API 面」（关键灰区）

`event_manager.dart` 與 `mesh_event_handler.dart` 是「部分邏輯層」:**框架機制（enqueue / decode / dedup / chunk / 簽章驗證）保留,但其 `publishResourceRegister()/publishMatchOffer()/...` 這類語意 API 換成 `publishPresence()/publishSos()/publishHazard()/publishAdminBroadcast()/publishCheckpoint()`。** `NativeBleTransport.broadcast()` 目前呼叫 `MeshEventHandler.decodeWirePayload()` 取 `eventId/urgency/eventType` 再 enqueue 到 `EventManager().queue`(singleton)—此耦合保留(它只認 wire 欄位,不認語意),但 singleton 化要在 fork 裡決定是否改注入（見風險 R4）。

---

## 3. 新事件模型與 wire schema（核心設計，最需要審）

### 3.1 信封：以 v2（EventEnvelopeV2）為準,加 `field_id`

⚠️ wire 層正在 v1→v2 遷移:**legacy proto `MeshEvent`(v1)** 與 **手寫 `EventEnvelopeV2` + canonical 簽章(v2,live)** 並存（`lib/app/proto/event_envelope_v2.dart`、`lib/app/crypto/canonical_encoder_v2.dart`、`lib/app/crypto/signer.dart`）。新事件**以 v2 信封為準**。**`field_id` 必須進 v2 canonical 簽章位元組**（`canonical_encoder_v2` → `signer` MAC/簽章綁定）,否則可被竄改跨場域注入。下方 v1 欄位表作為欄位語意參考保留:

```
MeshEvent {
  string eventId; bytes senderPubKey; int identityLevel;
  EventType type; UrgencyLevel urgency;
  int64 hlcTimestamp; int64 hlcCounter;
  int ttl; int chunkIndex; int totalChunks;
  bytes payload; bytes signature;
  double receivedLat/Lng; double originLat/Lng;
}   // v1 legacy — 僅欄位語意參考;field_id 與新 EventType 改在 v2 EventEnvelopeV2
```

### 3.2 新 EventType（非連續編號 — GPT Q1 定案）

`0` 留 `UNSPECIFIED`;主事件用 10 的倍數、之間留 gap,之後加 `SOS_CANCELLED`、`PRESENCE_LOST`、`CHECKPOINT_MISSED` 不破壞編號。

| # | EventType | payload 重點欄位 | urgency | 白皮書 |
|---|---|---|---|---|
| 0 | `UNSPECIFIED` | —（proto3 default,收到即拒） | — | — |
| 10 | `PRESENCE` | anonUserId, nodeId, rssi, batteryHint | P3 | 最後足跡 |
| 20 | `SOS` | anonUserId, level(YELLOW/RED), lastNodeId, note? | P0(RED)/P1(YELLOW) | 求救 |
| 30 | `HAZARD` | hazardType, severity, nodeId? | P2 | 危險標記 |
| 40 | `ADMIN_BROADCAST` | scope, message, expiresAt | P1 | 公告 |
| 50 | `CHECKPOINT` | anonUserId, checkpointId | P3 | 點名/檢查點 |
| 60 | `NODE_HEARTBEAT` | nodeId, battery, solar, storage, rssiAvg, firmware | P4 | 節點心跳 |
| 70 | `SENSOR`（保留,Phase 2/3） | sensorId, sensorType, rawPayload | 可變 | 433MHz RF |
| 100–129 | protocol/control 保留 | HELLO / Bloom-sync / ACK 等控制框 | — | — |
| 1000+ | experimental 保留 | — | — | — |

優先級沿用信封 `urgency` + `TriageQueue`(P0–P4)現成機制,不必改佇列。PRESENCE/SOS/CHECKPOINT 的位置欄位統一改用 §3.6 `LocationEvidence`(observer/subject frame)。

### 3.3 payload 設計原則（MCU 友善,為 Mode B）

- 保持**小而固定**;白皮書 §8.1 建議 binary/CBOR。**v2 信封是 canonical 手寫編碼(MCU 比照 Kotlin/Swift parity 實作,非 protoc 生成)**;內層 payload 用 protobuf,Field Node MCU 端以 **nanopb** 共用同一份 payload `.proto`。
- 避免長字串/巢狀;`message`、`note` 設長度上限。
- 一律可離線保存、可延遲同步、可去重(eventId)、可合併(HLC/CRDT)。

### 3.4 新核心概念：場域（field / site）

現有程式**沒有**「場域」概念,這是新邏輯層主軸:

- `FieldSession` / `FieldConfig` 模型:fieldId、名稱、有效時間、啟用模組清單、緊急聯絡流程、資料保存期。
- **加入方式**:掃 QR / 輸入場域代碼 / 邀請連結（現有 `chat_join_screen` + `handoff` PIN 交換可作 primitive 參考,但要重寫）。
- **場域金鑰(場域 scope)**:白皮書 §13.3 — 同場域內才交換事件。`field_id` 必須綁進 v2 canonical 簽章(§3.1、硬規則 #3);GATT service-data 預過濾為附加最佳化,不取代 wire scope。
- **模組化載入**:依場域類型啟用對應功能組合（登山步道 / 礦場 / 工地 / 野外活動 / 巡檢路線各一組）。

### 3.5 Mode B / Field Node 契約（要凍結的東西）

要讓未來 MCU 韌體能跟 App 互通,**這幾項要先凍結成版本化契約文件**（基礎在現有 `docs/specs/`）:

1. GATT service / characteristic UUID（`IgniRelayConstants.kt/.swift`）。
2. Chunk framing（`Chunker`）。
3. IBLT Bloom 差量同步格式（`IBLT`）。
4. **v2 `EventEnvelopeV2`** canonical binary layout（含 `field_id`）+ 新 EventType 編號（legacy `MeshEvent` 僅遷移參照）。
5. 簽章 / 場域金鑰 MAC 演算法。

現有 `docs/specs/{native_transport_v1, envelope_v2_spec, wire_conformance_v1.json}` 是契約基礎,**新事件集定稿後要同步更新**,並用現有的 wire-conformance 測試（Dart oracle ↔ Kotlin/Swift parity）守住。**契約 v0 草案要在 Phase 1 結束前產出（不等 Phase 2),讓硬體/後端 sibling 團隊並行起步。**

---

### 3.6 定位模型：mapless「位置證據」而非「地圖產品」（產品決策 2026-06-04）

**決策:MVP App 端不內建離線地圖、不打包 MBTiles。** 預設 UI 不走 map-first,改走「節點座標 + GPS + 相對位置 + 可信度」。理由:更貼白皮書核心(§5.3「被看見 / 最後足跡」,不是手機要畫地圖)、砍掉 200MB bundle / 地圖授權 / mbtiles+sqlite 風險、P0 更輕更準焦。基礎離線地圖降為 **P1+ optional/future module**。

**定位原則（5 條）**
1. 手機 GPS 可用 → 以 GPS 為準,evidence 帶 lat/lng/accuracy/source=GPS。
2. 無 GPS 但靠近 Field Node → 以節點設定座標為 anchor,source=FIELD_NODE,顯示「最後看見:Node-07 / 時間 / RSSI / 可信半徑」。
3. 離開節點短時間內 → 手機感測器 PDR/dead-reckoning 輔助,只能當**低可信推估**(「從 Node-07 往東北約 180m」),不可當精準定位。
4. 全無 GPS/節點/可信 sensor → 退回 last known anchor,uncertainty 隨時間增加。
5. UI **不說「人在這裡」**,而說「最後可信位置 / 推估方向距離 / 可信度 / 誤差半徑」。

**資料模型**

`LocationEvidence`（單筆原始觀測 — ★Claude:**這層上 wire**,小、可簽、可合併）
- source: `GPS | FIELD_NODE | BLE_RSSI | PDR | MANUAL | UNKNOWN`
- lat / lng、accuracy_m、observed_at
- anchor_node_id / anchor_node_name、distance_from_anchor_m / bearing_deg

`PositionEstimate`（融合後最佳推估 — ★Claude:**這層不上 wire**,UI 由一組 evidence 即時推導）
- 由多筆 evidence 融合;confidence: `HIGH | MEDIUM | LOW`、uncertainty 半徑
- ★Claude 建議:**confidence 與 uncertainty 不存於 wire,顯示時依 evidence 年齡即時計算**(原則 #4「隨時間增加」);存進事件的 HIGH,30 分鐘後就是謊言。

`FieldNodeConfig`
- node_id、display_name、lat/lng、install_accuracy_m、場域內位置描述
- 可選 neighbor graph:`[{neighbor_node_id, edge_distance_m, edge_label}]`

地名 context(可選,且**非地圖**):現有 `lib/app/geo/village_geofence.dart` + `admin_name_resolver`(讀 `assets/geodata`,用 `sqlite3`)可把 anchor/位置標成「在 XX 村/區」,屬 mapless 定位的可信 context — 故 `sqlite3` **不隨地圖一起砍**(見 §4 step 7,以 compile/test 為準)。

**Topological position（拓樸位置 — future-friendly）**
白皮書多數場域不是直線距離,要的是「在 CP-03 到 CP-04 之間」。`PositionEstimate` 應允許 topological 形式 `on_edge {from, to, progress 0..1}`,與 geometric 形式並存。Phase 0b 先把資料模型留好,即使只渲染清單。

> **★Claude 三點 refinement（標記給下輪 GPT 審）**
> 1. **Evidence vs Estimate 分層**:wire 只搬 `LocationEvidence`(觀測),`PositionEstimate`(融合)是 UI 本地推導。否則把融合演算法凍進 wire 契約,而各裝置 evidence 歷史不同。Field Node MCU 只產 evidence(「我在 T 時以 RSSI -70 看到 X」),不算 estimate。
> 2. **observer-frame vs subject-frame 分清**:`GPS`=主體自報(高可信、subject frame);`FIELD_NODE`/`BLE_RSSI`=觀測者看到(可信度受 RSSI→距離 + anchor 精度限制,observer frame)。兩者 anti-spoof 與 confidence 數學不同,PRESENCE/SOS 的位置欄位要標明是哪一種。
> 3. **P1 空間視圖用 no-tiles schematic**:`CustomPaint` 把 FieldNodeConfig 畫成 node-link 示意圖(點=節點、線=edge、高亮最後 anchor),零地圖相依就有空間直覺。P0=清單、P1=schematic、真地圖=future optional。

---

## 4. Phase 0b：剝上層 + 換事件模型（接著要做的，但等審）

目標:把 fork 出來的程式從「資源媒合 app」剝成「乾淨的傳輸層 + 新事件骨架」,跑到綠燈 + 手機對手機能發 PRESENCE/SOS。

步驟：
1. **凍結保留層**:確認 §2.1 清單編譯獨立可用(暫時 stub 掉上層依賴)。
2. **砍語意層**:刪 §2.2 的 events / proto payload / services / repos / UI。`check_layers` 與 analyze 必須維持綠。
3. **重定事件 schema（v2 為主改點）**:先改 `EventEnvelopeV2` + `canonical_encoder_v2` + `signer` 加 `field_id`(綁簽章) + 新 `EventType` enum + 新 payload 訊息（§3.2）;同步更新 `docs/specs` 契約;legacy proto `MeshEvent` 只在遷移收尾期同步(非主改點),需要時才 `protoc`（`scripts/gen_proto.*`）。
4. **改 publish/handle API 面**:`event_manager` / `mesh_event_handler` 的語意方法換成新事件（§2.3）。
5. **最小 UI(mapless)**:debug 畫面 — 啟動 mesh、發 PRESENCE beacon、發 SOS、**事件列表 + 最後可信位置 / anchor 節點 / 距離方位 / 可信度**(§3.6);**不做地圖畫面**。
6. **DB**:`Event_Logs` 保留;drop match/station 表;migration 重置（新網路,無歷史包袱）。
7. **砍地圖 asset/deps（以 compile/test 為準,別誤砍）**:
   - **可砍(map-only)**:`assets/maps/`(避免 ignored 的 200MB mbtiles 被打包)、`flutter_map`、`flutter_map_marker_cluster`、`vector_map_tiles*`、`vector_tile*`、`mbtiles`。rg 確認集中在 map UI(`ui/screens/map/*`、`navigation_screen`、map widgets、theme/sprites)。
   - **⚠️ `sqlite3` / `sqlite3_flutter_libs` 不是只為 mbtiles**(已用 rg 對程式碼確認):也用於 `lib/app/geo/village_geofence.dart`(村里界/地名解析,**非地圖**)、`lib/app/map/poi_query.dart` 及數個 geo test。**以編譯/測試為準**:保留 geodata 地名/相對位置 → 留 `sqlite3`;若砍掉 geodata 後只剩 test 需要 → 移 `dev_dependencies` 或改測試 fixture。**不要為砍 map 一次砍壞非地圖定位資料。**
   - `Event_Logs` 用 `sqflite`(與 `sqlite3` 不同套件),不受影響。
   - `lib/app/map/*` 標 optional/future,依編譯影響決定移除或隔離。
   - 順手:移除 AndroidManifest 的 Impeller-disable(地圖沒了可重開 Impeller)、移除 `health` 依賴 + Health Connect 權限(medical card 降級)。

**Exit gate（Phase 0b）**：
- `dart run tool/check_layers.dart --strict` 綠、`flutter analyze` 0 errors、`flutter test --exclude-tags golden` 綠。
- 兩台 Android 實機:A 發 SOS → B 收到並顯示;A/B 互換 PRESENCE;殺進程後重啟事件不重複(去重)。
- wire-conformance 測試（Dart↔Kotlin）對新事件集綠。

---

## 5. Phase 1：場域核心 + 急難 UX

- `FieldSession`/`FieldConfig` + 掃碼/代碼加入 + 場域金鑰 scope（§3.4）。
- **SOS UX**(白皮書 §13.4):長按 + 二次確認 + 倒數取消 + 誤報回報;P0/P1 插隊。
- `HAZARD`(類型 + severity)、`ADMIN_BROADCAST`(scope/expiresAt)。
- **位置呈現(mapless,§3.6)**:事件列表 + 節點相對位置 + 距離方位 + 可信度;可加 no-tiles node-graph schematic。真離線地圖 = future optional module。
- 模組化載入:依場域類型顯示不同功能組合。

**Exit gate**：單場域 demo — 加入場域 → beacon → 收 admin 公告 → 發 SOS/HAZARD → **清單/示意圖看到最後可信位置 + 危險點(含 anchor / 距離方位 / 可信度)**。

## 6. Phase 2：點名 / 心跳 + 契約凍結

- `CHECKPOINT`(點名/檢查點)、`NODE_HEARTBEAT` 接收與顯示。
- **凍結 App↔Node GATT/wire 契約文件**（§3.5）,交付給 Field Node 韌體開發方。
- 隱私治理（白皮書 §13）:匿名 ID 預設、SOS/未返回才解鎖身分、資料保存期、權限分級。

**Exit gate**：契約文件 v1 定稿 + wire-conformance 對齊;點名/心跳在 demo 場域可用。

## 7. Phase 3：接真 Field Node（Mode B）+ 感測器

- 對接 MCU Field Node（nRF54L15 + SX1262 LoRa）— App 變 Mode B 使用者端。
- `SENSOR`(433MHz RF Sensor Bridge)、Data Mule 角色（手機把事件帶到下一個節點/Gateway）。
- 注意:LoRa / Field Node 韌體 / Gateway **不在本 repo**,是硬體側獨立工作;本 App 只負責 BLE 接入 + Data Mule。

**Exit gate**：手機 ↔ 真 Field Node 跑通 PRESENCE/SOS;事件經 Node→(LoRa)→Gateway。

### 7.1 Out-of-repo sibling work（白皮書 MVP 缺口,明寫以免低估）

白皮書 MVP 主線是 Mode B,以下**不在本 App repo**,屬硬體/後端 sibling 專案,但 MVP 全貌缺一不可:

| 缺口 | 白皮書出處 | 負責方 |
|---|---|---|
| Field Node 韌體（nRF54L15 + SX1262 LoRa,BLE 掃描/事件暫存/心跳/低電量降載） | §10.2、附錄 A.1 | 硬體/嵌入式 |
| LoRa Store-and-Forward 中繼（TTL/優先/去重） | §9.2 | 硬體/嵌入式 |
| Gateway（Pi 4,LoRa 彙整 + SQLite + 本地 Web 後台 + **事件列表 + 資料匯出 CSV/JSON/PDF**） | §10.3、§12.2 | 後端 |
| Admin Console（多場域、權限、模組設定、報表） | §12.3 | 後端 |

→ 本 App repo 只負責「使用者端 BLE 接入 + Data Mule」。**wire / GATT / field-key 契約必須早凍結**（§3.5）,讓 sibling 專案並行,而非等 App 做完才開始。

---

## 8. 風險與待審問題（請 GPT 重點批評）

| # | 風險 | 現況 / 緩解 |
|---|---|---|
| R1 | 本 repo 只有 App-only 手機對手機 BLE(=Mode A),**沒有 LoRa/Field Node/Gateway** | fork 只給 App 地基;Mode B/C 需硬體側另做。計畫已分 Phase 3 隔離 |
| R2 | App↔Field Node 是一份協定契約,不是免費 | §3.5 要凍結;MCU 端用 nanopb 共用 `.proto` |
| R3 | **iOS BLE code-wired,未真機驗證** | Q6 定案:iOS 保留不刪、**不當 Phase 0b gate**;先打通 Android 雙機 + v2 wire + Field Node 契約草案,Phase 2 前再做 macOS build + XCTest + 裝置對。**但 Swift IBLT/Chunker source parity 要持續編譯不退化**(靠 wire-conformance corpus),免得 iOS 上線變重寫 |
| R4 | 切縫上有 `EventManager`/`MeshEventHandler` 等 singleton 殘留(原 repo 正在 v0.2.5 facade 化 + v1→v2 mesh 遷移到一半) | Q5 定案:**不一次清**。Phase 0b 第一刀只求新事件骨架綠 + Android 雙機;legacy singleton 暫包在 adapter 裡,**新 public API 一律 DI、不得新增 singleton**(已是 CLAUDE.md 治理);第二刀(事件模型穩後)再清內部 singleton |
| R5 | 新事件信封改動(加 `field_id`、改 EventType 編號)會打斷舊 wire | 已確認「全新獨立網路」,可自由改;但要一次定稿,避免 Phase 間反覆 |
| R6 | `database_helper.dart` 是單檔大型 helper,含待砍的 match/station 邏輯 | Phase 0b 要小心切,別動到 `Event_Logs` |

**已由 GPT 審查定案（全數收斂）：**
- **Q1 → 定案** EventType 用**非連續編號**:`0=UNSPECIFIED`、主事件 10 的倍數(10/20/…/70)、`100–129` 控制框保留、`1000+` experimental。見 §3.2。
- **Q2 → 部分定案** 場域金鑰必須是「簽章/MAC 綁定」的 wire-level scope;HMAC vs 非對稱簽章待 MCU 功耗實測。
- **Q3 → 定案** `field_id` 進 v2 信封並綁進 canonical 簽章;GATT service-data 預過濾為附加最佳化,不取代 wire scope。
- **Q4 → 定案** medical card 降級,不留主線;只保留 SOS 時窄版可選揭露緊急身份/備註。
- **Q5 → 定案** singleton **不一次清**:Phase 0b 只求新事件骨架綠 + Android 雙機;legacy singleton 暫包 adapter,新 API 一律 DI;第二刀再清。見 R4。
- **Q6 → 定案** iOS 延後、保留不刪、不當 Phase 0b gate;先 Android 雙機 + v2 wire + Field Node 契約草案,Phase 2 前再做 iOS。見 R3。

**Phase 0b 第一刀範圍(收斂後)**:剝上層 → 定 v2 事件 schema(含 `field_id` 綁簽章 + 非連續 EventType) → 最小 debug UI → `check_layers`/`analyze`/`test` 綠 + Android 雙機 PRESENCE/SOS 行為驗證。**singleton 清理、iOS、Field Node 真機都不在第一刀。**

---

## 9. 驗證原則（每階段共用）

每個 Phase 的 exit gate 一律要過:`check_layers --strict` + `flutter analyze`(0 errors) + `flutter test --exclude-tags golden` + 至少一組**真機行為驗證**(非僅單元測試) + wire-conformance parity(動到 wire 時)。
