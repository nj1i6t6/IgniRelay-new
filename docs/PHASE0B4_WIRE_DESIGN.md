# Phase 0b #4 — New Event Model / Wire Design Pass（交 GPT 審）

> 文件用途：Phase 0b 清舊骨架已完成（teardown #1..#3B-4 全綠）。本文是 **#4 的 design pass**：
> 設計把白皮書事件（PRESENCE / SOS / HAZARD / ADMIN_BROADCAST / CHECKPOINT / NODE_HEARTBEAT /
> SENSOR）落到**現有 v2 wire（`EventEnvelopeV2`）**上、加入 `field_id`（綁簽章）、定 `LocationEvidence`
> payload，並列出 commit 切法與 conformance 衝擊。**這一輪只寫計畫，不改 wire code。**
> 讀者沒有原始對話脈絡 —— 本文力求自含，所有結論都對齊**實際程式碼**（非舊文件假設）。

---

## 0. 為什麼要重審：實際 wire 與 REBUILD_PLAN §3.2 不一致

審計時把實際 wire 程式碼讀過一遍（`event_envelope_v2.dart`、`canonical_encoder_v2.dart`、
`message_publisher_v2.dart`、`v2_inbound_projector.dart`、`event_publisher_v2_facade.dart`、
`docs/specs/*`、`wire_conformance_v1.json`），發現一個必須先講清楚的落差：

**REBUILD_PLAN §3.2 設計的 EventType 編號（10=PRESENCE / 20=SOS / 30=HAZARD / 40=ADMIN /
50=CHECKPOINT / 60=HEARTBEAT / 70=SENSOR）在實際 repo 裡並不存在，也跟已實作的 `EventTypeV2`
牴觸。** `EventTypeV2`（`lib/app/proto/event_envelope_v2.dart`）已經是**非連續、分段、spec 凍結、
有 conformance corpus + Kotlin/Swift parity** 的編號：

```
status/personal   1   STATUS_UPDATE     2   BATTERY_STATUS            (1–19)
coordination      20  SUPPLY_REQUEST    21  SUPPLY_OFFER  22 MATCH_INTENT
                  23  NEGOTIATION       24  RELAY_TO_CONTACT  30 CHAT_MESSAGE  (20–49)
hazard            50  HAZARD_MARKER     51  DISASTER_REPORT   52 SHELTER_STATUS (50–79)
official          80  OFFICIAL_ALERT_CAP 81 OFFICIAL_ALERT_SUMMARY               (80–99)
control           100 PROTOCOL_HELLO 101 PROTOCOL_NOTICE 102 HEARTBEAT
                  103 TRACE_PING 104 TRACE_ACK                                   (100–129)
experimental      1000+                                                          (out of tree)
```

且 **SOS 早就模型化成 `STATUS_UPDATE` + `safetyState`（TRAPPED/INJURED）+ priority（SOS_RED/
SOS_YELLOW）**，`V2InboundProjector._projectStatus` 正在用這條路把 v2 SOS 投影成 v1 read-model。

### 0.1 建議（本文核心立場）：**沿用並擴充 `EventTypeV2`，不要重新編號**

理由：
1. `EventTypeV2` 已落地且被一整套契約守著：`envelope_v2_spec` §4/§6、priority matrix
   (`priority_matrix_v2.dart`)、max_hops matrix (`EventTypeV2.maxHopsDefault`)、LWW key
   (`shelter_id`/`cap_identifier`/`notice_id`)、payload budget、**104 個 envelope conformance
   樣本 + Kotlin/Swift parity**。整碗重新編號＝把這些全部重做，純粹的自傷。
2. 白皮書事件大多**已經有對應 slot**，缺的只有 2 個：

| 白皮書事件 | 對應 `EventTypeV2` | 動作 |
|---|---|---|
| SOS（YELLOW/RED） | `STATUS_UPDATE`=1 + safetyState + priority | **已存在**，沿用（`_projectStatus` 已實作）。可選：加 location（§3）。 |
| HAZARD | `HAZARD_MARKER`=50 | **已存在**，但 payload 還是 JSON shim → 定 typed `HazardMarkerData`（§3）。 |
| NODE_HEARTBEAT | `HEARTBEAT`=102 | **已存在**（control range）。 |
| ADMIN_BROADCAST | official range 80–99 | **新增** `ADMIN_BROADCAST`=82（見 §2）。 |
| PRESENCE（最後足跡） | status range 1–19 | **新增** `PRESENCE`=3（見 §2）。 |
| CHECKPOINT（點名） | status range 1–19 | **新增** `CHECKPOINT`=4（見 §2，可能與 PRESENCE 合併 → 待 GPT）。 |
| SENSOR（433 RF） | 待定 | **延後**到 Phase 3（Field Node/SENSOR）。 |

> ⚠️ **要 GPT 拍板的第 1 件事**：接受「沿用並擴充 `EventTypeV2`」、把 REBUILD_PLAN §3.2 的
> 10/20/30 表標記為 **superseded**？（本文已在 REBUILD_PLAN §3.2 加 supersede 指標。）

---

## 1. `field_id`：放哪、怎麼進 canonical 簽章

### 1.1 現況（實際程式碼）

`EventEnvelopeV2`（proto3 手寫，欄位 1–13）目前**沒有 `field_id`**：

```
1 protocol_version(u32,==2)  2 envelope_id(bytes,16 UUIDv7)  3 event_type(enum)
4 priority(enum)  5 created_at_hlc(msg)  6 expires_at_hlc(msg)  7 max_hops(u32)
8 author_key(bytes,32)  9 sig_algo(u32,0x01)  10 signature(bytes,64)
11 payload(bytes)  12 last_relay_id(string,opt)  13 is_experimental(bool)
```

`CanonicalEncoderV2.buildSignatureInput` 是**固定 124-byte** 的手刻布局（**非** proto 序列化），
簽章蓋住：protocol_version、envelope_id、event_type、priority、兩個 HLC、max_hops、author_key、
sig_algo、`SHA-256(payload)`。**`last_relay_id` / `is_experimental` 在 wire 上但不簽**（spec §20.10）。

```
sig_input(124) = u32le(pv) ‖ u8(16)‖envelope_id ‖ u32le(event_type) ‖ u32le(priority)
               ‖ u64le(c.ms)‖u32le(c.ctr) ‖ u64le(e.ms)‖u32le(e.ctr) ‖ u32le(max_hops)
               ‖ u8(32)‖author_key ‖ u8(sig_algo) ‖ u8(32)‖SHA256(payload)
```

### 1.2 設計：`field_id` 為**已簽章**的信封欄位 + 升 `protocol_version` 2→3

硬規則 #3（GPT 已定案）：場域 scope 必須是 wire-level、綁簽章，不能只靠 GATT service-data 預過濾。
故 `field_id` 必須進 **canonical 簽章位元組**，不能只放 payload。

**提案：**
1. **信封**：新增 proto 欄位 `14 field_id (bytes)`。固定 **16 bytes**（opaque field id —
   建議 = `SHA-256(field_join_secret)[:16]` 或場域 UUIDv7；人類看到的「場域代碼」由加入流程映射到
   這 16 bytes，wire 上一律定長，與 envelope_id 對稱）。
2. **canonical 布局**：在 `u8(16)‖envelope_id` 之後插入 `u8(16)‖field_id`（兩個 16-byte 身分塊
   相鄰，語意「這是什麼事件 / 屬於哪個場域」）。`sigInputBytes` 124 → **141**。
3. **protocol_version 2 → 3**：canonical 布局變了，必須升版本當作清楚信號。`decode()` 與 dispatcher
   的 `== 2` 檢查改 `== 3`（全新獨立網路、無 back-compat 包袱，直接切 v3，不做 v2/v3 並存）。
4. **decode() 必填**：`field_id` 缺失 / 非 16 bytes → `ProtoDecodeException`（新負面案例
   `field_id missing or not 16 bytes`）。
5. **MessagePublisherV2.send()**：簽章前把 `field_id` 餵進 canonical（目前 `protocolVersion: 2`
   硬寫在兩處，line 120 + 137 → 改 3 並加 `fieldId` 參數）。
6. **dispatcher 場域 scope 檢查**：`EnvelopeDispatcherV2` 加一道 —— 若 `envelope.field_id` 不在本機
   已加入的場域集合 → drop，新 `drop_reason = field-scope-mismatch`。GATT service-data 預過濾為
   附加最佳化（不取代）。

### 1.3 控制平面的場域豁免（要 GPT 拍板）

`PROTOCOL_HELLO`/`PROTOCOL_NOTICE`/`HEARTBEAT`/`TRACE_*`（100–129）是**傳輸協商**，發生在場域 scope
之前/之外。提案：控制框 `field_id = 16 個 0x00`（wildcard），且 dispatcher 對 control range
**豁免 field-scope drop**（它們是 link 協商，不是場域事件）。否則 HELLO 自己就會被 field-scope 擋掉、
永遠握不上手。

> ⚠️ **要 GPT 拍板的第 2 件事**：① `field_id` 用 16-byte 定長 opaque（vs 變長字串）？
> ② canonical 插在 envelope_id 之後（vs append 末端）？③ control range 用 zero-field_id 豁免？
> ④ HMAC vs 純 Ed25519 簽章綁定（白皮書 §13.3 場域金鑰；MCU 功耗 — REBUILD_PLAN Q2 仍 open）。

---

## 2. 新 EventType 怎麼落地（additive，不動既有編號）

純加常數 + matrix 條目，不碰既有值（additive、低風險）：

| 新值 | 名稱 | range | payload | priority（matrix） | max_hops |
|---|---|---|---|---|---|
| 3 | `PRESENCE` | status 1–19 | `PresenceData`（§3.2） | NORMAL（可被 §6 matrix downgrade） | 4–6（待定） |
| 4 | `CHECKPOINT` | status 1–19 | `CheckpointData`（§3.2） | NORMAL/STATUS | 4–6 |
| 82 | `ADMIN_BROADCAST` | official 80–99 | `AdminBroadcastData`（§3.2） | ALERT/STATUS | 8–12 |

落地點（全部 additive）：
- `EventTypeV2`：加 3 個常數 + `maxHopsDefault()` switch 條目 + `isKnown()` 條目。
- `PriorityMatrixV2`：加 (event_type × priority) 允許/降級條目。
- `EventTypeV2.maxHopsDefault`：PRESENCE/CHECKPOINT 較短 hop（足跡是近場）、ADMIN 較長。

> CHECKPOINT 與 PRESENCE 語意接近（都是「某人在某 anchor 出現」）。**選項 A**：分開（CHECKPOINT 帶
> 明確點名語意 checkpoint_id）；**選項 B**：CHECKPOINT = PRESENCE + `checkpoint_id` 欄位，省一個
> type。本文先列 A，待 GPT。SENSOR 延後到 Phase 3。

---

## 3. payload schema（手寫 ProtoWriter/Reader，與既有 v2 payload 同風格）

新 payload 一律比照 `StatusUpdateData`/`ShelterStatusData` 的手寫 `encode()/decode()`（不靠 protoc；
MCU 端 nanopb 共用同一份欄位定義）。欄位號一旦定就凍結（reserved 註記，禁止跨 wave 重用）。

### 3.1 `LocationEvidence`（核心 — 上 wire 的「位置證據」，§3.6）

★ 分層原則（REBUILD_PLAN §3.6）：**只有 `LocationEvidence`（單筆觀測）上 wire**；`PositionEstimate`
（多筆融合、confidence/uncertainty）是 **UI 本地推導，不上 wire**（融合演算法不凍進契約；confidence
依 evidence 年齡即時算）。

```
message LocationEvidence {
  1  source        enum   // 0 UNKNOWN 1 GPS 2 FIELD_NODE 3 BLE_RSSI 4 PDR 5 MANUAL
  2  frame         enum   // 0 UNSPEC 1 SUBJECT(自報,GPS) 2 OBSERVER(被節點看到,RSSI)  ★refinement#2
  3  lat           sint64 // 1e7 fixed-point（避免 double 跨平台 parity 漂移；MCU 友善）
  4  lng           sint64 // 1e7 fixed-point
  5  accuracy_m    uint32
  6  observed_at   HlcTimestampV2(msg)
  7  anchor_node_id string // optional（FIELD_NODE/BLE_RSSI 才有）
  8  distance_from_anchor_m uint32 // optional
  9  bearing_deg   uint32 // optional 0..359
  // 10..15 reserved
}
```
> ⚠️ lat/lng 用 **sint64 1e7 fixed-point**（非 double）以保 Dart↔Kotlin↔Swift↔MCU bit-parity；
> 這是 conformance 能跨平台對齊的關鍵。待 GPT 確認精度（1e7 ≈ 1.1cm，足夠）。

### 3.2 事件 payload

```
message PresenceData {          // EVENT_TYPE_PRESENCE = 3
  1 anon_user_id   bytes(16)    // 匿名身分（非 author_key；可輪換）
  2 location       LocationEvidence
  3 battery_hint   uint32       // 0..100 optional
  // 4..15 reserved
}

message CheckpointData {        // EVENT_TYPE_CHECKPOINT = 4
  1 anon_user_id   bytes(16)
  2 checkpoint_id  string       // 點名點 / Field Node anchor id
  3 location       LocationEvidence  // optional
  // 4..15 reserved
}

message HazardMarkerData {      // EVENT_TYPE_HAZARD_MARKER = 50（取代現行 JSON shim）
  1 hazard_id      string
  2 hazard_type    enum/string  // FIRE/FLOOD/LANDSLIDE/...
  3 severity       uint32
  4 location       LocationEvidence
  5 description     string(<=N)  // 長度上限
  6 is_confirmation bool
  // 7..15 reserved
}

message AdminBroadcastData {    // EVENT_TYPE_ADMIN_BROADCAST = 82
  1 scope          enum/string  // FIELD/ALL
  2 message        string(<=N)
  3 expires_at     HlcTimestampV2
  // 4..15 reserved
}
```

### 3.3 SOS 位置（要 GPT 拍板）

現行 `StatusUpdateData{safetyState, needs[]}` **不帶位置**（`_projectStatus` 註解明寫
"carries no location"）。白皮書 SOS 要「最後可信位置」。**選項 A**：在 `StatusUpdateData` 加
`3 location LocationEvidence`（additive proto3；改 payload hash → 需重簽，新網路可接受）。**選項 B**：
SOS 不帶位置，靠最近一筆 PRESENCE 配對。本文傾向 **A**（SOS 自帶 evidence，不依賴配對時序），待 GPT。

---

## 4. PRESENCE / SOS / HAZARD 最小 wire path

| 事件 | 送出（sender） | 收進（receiver → read-model） | debug UI |
|---|---|---|---|
| **PRESENCE** | 新 `EventPublisherV2Facade.publishPresence(PresenceData)` → `MessagePublisherV2.send(eventType=PRESENCE, priority=NORMAL, field_id)` | `V2InboundProjector` 加 `case PRESENCE → _projectPresence` → `Event_Logs` read-model（給 EventStream/Debug shell） | 「發 PRESENCE」按鈕接線（目前是 placeholder `_todoWire`） |
| **SOS** | **沿用** `publishStatusUpdate(safetyState=TRAPPED/INJURED)`（已實作）；可選帶 location（§3.3） | **已實作** `_projectStatus → requestBroadcast`（urgency≥2 → `EventStream.sosAlerts`） | 「發 SOS」按鈕 → `publishStatusUpdate` |
| **HAZARD** | `publishHazardMarker(HazardMarkerData)`（把現行 raw JSON shim 換成 typed payload） | **已實作** `_projectHazard`（把 JSON shim 改成解 typed `HazardMarkerData`） | （Phase 1 才有 hazard UI；先單元測試覆蓋） |

read-model 投影沿用既有 `MeshEventHandler.ingestVerifiedEvent`（v2→v1 投影出口；PRESENCE 需決定投到
哪個 v1 read-model 欄位，或新增一條 read-model 投影 — 不破壞 `Event_Logs` 核心）。
**Exit（Phase 0b #4 軟體核心）**：兩台 Android — A 發 SOS → B `sosAlerts` 收到顯示；A/B 互發 PRESENCE
→ 對方 read-model 看到「最後足跡 + anchor/距離方位/可信度」；殺進程重啟事件不重複（envelope_id dedup）。

---

## 5. 哪些 conformance test 要先改（精確到檔案）

Conformance 工具鏈（已定位）：
- **產生器**：`tool/generate_wire_conformance_v1.dart` → 產出 `docs/specs/wire_conformance_v1.json`。
- **corpus 內容**：`envelope_samples`×104（每筆含 `protocol_version`、`expected_canonical_sig_input_hex`
  =124 bytes、`expected_signature_hex`、`payload_sha256_hex`、test 私鑰）、`chunking_samples`×20、
  `iblt_samples`×52、`bloom_samples`×30、`negative_cases`×11。
- **Dart 守門**：`test/conformance/wire_conformance_corpus_test.dart`。
- **Kotlin parity（on-device，CI gate）**：`android/.../WireConformanceInstrumentationTest.kt`
  （讀 androidTest assets 裡的 corpus）。
- **Swift parity（R3：保持編譯不退化）**：`ios/RunnerTests/WireConformanceTests.swift`。
- **scenarios**：`test/wire_conformance/scenarios/*.yaml`（如 `sos_red_minimal.yaml`）。

**衝擊與順序**：
1. 改 `CanonicalEncoderV2`（layout 124→141、加 field_id）+ `EventEnvelopeV2`（欄位 14 + 必填 +
   pv→3）+ `MessagePublisherV2`（簽章帶 field_id、pv=3）。
2. **重跑 `generate_wire_conformance_v1.dart`** → 104 筆 `expected_canonical_sig_input_*`（124→141）
   + 全部 `expected_signature_hex` **整批重生**；`corpus_revision`/`spec_*` bump；`envelope_struct`
   加 `field_id_hex`。新增 `negative_cases`：`field_id missing/len`、`field-scope-mismatch`、
   `unknown-protocol-version`(pv≠3)。
3. `wire_conformance_corpus_test.dart`（Dart 自洽）先綠。
4. `WireConformanceInstrumentationTest.kt`（Kotlin）+ `WireConformanceTests.swift`（Swift）對齊新 corpus
   （Kotlin 是 CI gate；Swift 至少編譯不退化 — R3）。
5. PRESENCE/HAZARD 的新 payload 各加 envelope_samples（additive）。

> conformance corpus 是**跨平台契約**：Dart 改完→重生 corpus→Kotlin/Swift 比對。**先 Dart 自洽綠，
> 再推 Kotlin parity**（避免一次動三端難定位）。

---

## 6. Commit 切法（每刀綠、不一次砍爆；wire 改動隔離成可獨立 review 的刀）

| # | commit | 內容 | gate |
|---|---|---|---|
| **4-1** | payload structs（**不動信封/canonical**） | 加 `LocationEvidence` + `PresenceData` + `CheckpointData` + `HazardMarkerData` + `AdminBroadcastData` 手寫 encode/decode + 單元測試。**零 wire 信封變更 → 零 conformance 衝擊**。 | analyze/test 綠 |
| **4-2** | EventType additive | 加 `PRESENCE`/`CHECKPOINT`/`ADMIN_BROADCAST` 常數 + `maxHopsDefault`/`isKnown` + priority matrix 條目。純加值。 | test 綠 |
| **4-3** | **field_id + canonical + pv→3（核心 breaking 刀）** | `EventEnvelopeV2` 欄位 14 + 必填；`CanonicalEncoderV2` 124→141；`MessagePublisherV2` 簽章帶 field_id + pv=3；dispatcher `==3` + `field-scope-mismatch` + control-range 豁免；**重生 conformance corpus** + Dart corpus test + 負面案例；更新 `envelope_v2_spec`。 | **全 conformance（Dart）綠** |
| **4-3b** | Kotlin/Swift parity | `WireConformanceInstrumentationTest.kt` + `WireConformanceTests.swift` 對齊新 corpus。 | Kotlin on-device 綠 / Swift 編譯 |
| **4-4** | publish/receive PRESENCE | `EventPublisherV2Facade.publishPresence` + `V2InboundProjector` PRESENCE 投影 + read-model + debug shell「發 PRESENCE」接線。 | test +（雙機）|
| **4-5** | HAZARD typed payload | facade `_dualWriteHazardMarker` 與 `_projectHazard` 從 JSON shim 換 typed `HazardMarkerData`。 | test 綠 |
| **4-6** | SOS location（若 GPT 選 §3.3 A） | `StatusUpdateData` 加 `location` + 送收接線。 | test + conformance（statusUpdate 樣本重生）|
| **4-7** | field session/scope plumbing（最小） | `FieldSession` 模型 + 取得本機 field_id（debug shell 先 hardcode 一個場域；真 join QR/代碼留 Phase 1）。 | test 綠 |

每刀跑 `pub get / check_layers --strict / analyze / test --exclude-tags golden`；wire 刀（4-3/4-3b/4-6）
另加 conformance parity。**4-3 是唯一 breaking wire 刀，刻意隔離**；4-1/4-2 先把 payload/enum 鋪好（零
conformance 衝擊），讓 4-3 聚焦在 canonical/簽章/版本。

---

## 7. 待 GPT 拍板清單（彙整）

1. **EventType 策略**：接受「沿用並擴充 `EventTypeV2`」、把 REBUILD_PLAN §3.2 標 superseded？
2. **field_id 形態**：16-byte 定長 opaque？canonical 插在 envelope_id 之後？control range zero-field_id
   豁免 field-scope？
3. **場域金鑰綁定**：HMAC vs 純 Ed25519（白皮書 §13.3 / Q2，MCU 功耗實測待補）。
4. **CHECKPOINT**：獨立 type（選項 A）vs PRESENCE+checkpoint_id（選項 B）？
5. **SOS 位置**：`StatusUpdateData` 加 `location`（A）vs PRESENCE 配對（B）？
6. **LocationEvidence 精度**：lat/lng 用 sint64 1e7 fixed-point（跨平台 parity）OK？
7. **protocol_version**：直接切 v3、不做 v2/v3 並存（全新獨立網路）OK？
8. **ADMIN_BROADCAST**：新增 type 82（A）vs 複用 `OFFICIAL_ALERT_SUMMARY`（B）？

> 本輪 **docs-only**，未改任何 wire code / conformance corpus / spec。批准後才進 4-1。
