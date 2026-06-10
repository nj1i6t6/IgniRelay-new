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

| 新值 | 名稱 | range | payload | priority（matrix） | max_hops | LWW? |
|---|---|---|---|---|---|---|
| 3 | `PRESENCE` | status 1–19 | `PresenceData`（§3.2） | NORMAL（其餘 downgrade→NORMAL） | **4** | **yes（by anon_user_id）** |
| 4 | `CHECKPOINT` | status 1–19 | `CheckpointData`（§3.2） | STATUS/NORMAL（其餘→STATUS） | **6** | no（每次穿越都是 event） |
| 82 | `ADMIN_BROADCAST` | official 80–99 | `AdminBroadcastData`（§3.2） | ALERT/STATUS（SOS→DROP、低→STATUS） | **12** | no（多則指令並存，靠 expires） |

落地點（全部 additive，**已於 4-2 落地 commit**）：
- `EventTypeV2`：加 3 個常數 + `maxHopsDefault()` switch 條目（4/6/12）+ `isKnown()` 條目。
- `PriorityMatrixV2`：加 (event_type × priority) 允許/降級條目（ADMIN 對 SOS 走 DROP 防偽裝）。
- `EnvelopeStoreV2._lwwKeyComponentFor`：PRESENCE → LWW by `anon_user_id`（bytes key，空/壞 → author_key
  fallback）；CHECKPOINT/ADMIN 非 LWW（return null）。store 層即可,**不動 dispatcher**。
- spec `envelope_v2_spec` §4.1/§4.2/§6.1/§10.2/§11.2 同步更新,spec 與 code 一致。

> **已拍板（4-2）**：CHECKPOINT 採**選項 A**（獨立 type，帶 checkpoint_id 點名語意；不併入 PRESENCE）。
> ADMIN_BROADCAST 採新 type 82（非複用 OFFICIAL_ALERT_SUMMARY）。SENSOR 仍延後到 Phase 3。
> **未接線**（留 4-4+）：publisher/dispatcher/projector/debug UI 都還沒發/收這些事件；本刀只讓系統
> 「認得」新類型 + store 層 LWW 預備。

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
  8  distance_from_anchor_m uint32 // optional, 0 == absent
  9  bearing_deg_plus_one uint32 // optional: 0/omitted == absent, 1..360 == 0..359°（見下注 4-1r）
  // 10..15 reserved
}
```
> ⚠️ **lat/lng（已落地 4-1）**：`sint64`、degrees × 1e7 fixed-point（非 double）以保
> Dart↔Kotlin↔Swift↔MCU bit-parity。轉換規則 **round-to-nearest**（量化誤差 ≤0.55cm；
> 各平台必須一致 round，否則整數 wire 值不對齊）。例：25.0339805° → 250339805
> （注意 `25.0339805*1e7` 在 IEEE-754 是 …804.9999，**必須 round 不能 truncate**，4-1 已踩過此雷）。
>
> ⚠️ **bearing 存在性歧義（4-1r 修正）**：原 `bearing_deg uint32` 用「0 == absent」會與「0° 正北」
> 混淆。改用 **`bearing_deg_plus_one`**：wire 上 0/omitted = 沒有方位、1..360 = 0..359°（單一純量、
> 維持 proto3 default-omit、MCU/nanopb 友善）。Dart API 暴露為 `int? bearingDeg`（`null` = absent，
> `0..359` = 真實角度含正北 0）。`distance_from_anchor_m` 維持「0 == absent」(0 距離=就在 anchor 上，
> 退化情形,可接受)；只有 bearing 需要此修正。

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
| **4-3** | **field_id + canonical + pv→3（核心 breaking 刀）** | `EventEnvelopeV2` 欄位 14 + 必填；`CanonicalEncoderV2` 124→141；`MessagePublisherV2` 簽章帶 field_id + pv=3；dispatcher `==3` + `field-scope-mismatch` + control-range 豁免；**重生 conformance corpus** + Dart corpus test + 負面案例；更新 `envelope_v2_spec`。**＋ HELLO negotiation 同步升 v3（完整 version-literal 落點見 §8.1）＋ purge 舊 pv=2 local wire state（見 §8.3）。前置決策：場域金鑰綁定須先拍板（§8.2）。** | **全 conformance（Dart）綠＋ HELLO 握手測試綠** |
| **4-3b** | Kotlin/Swift parity | `WireConformanceInstrumentationTest.kt` + `WireConformanceTests.swift` 對齊新 corpus。 | Kotlin on-device 綠 / Swift 編譯 |
| **4-4** | publish/receive PRESENCE | `EventPublisherV2Facade.publishPresence` + `V2InboundProjector` PRESENCE 投影 + read-model + debug shell「發 PRESENCE」接線。 | test +（雙機）|
| **4-5** | HAZARD typed payload | facade `_dualWriteHazardMarker` 與 `_projectHazard` 從 JSON shim 換 typed `HazardMarkerData`。 | test 綠 |
| **4-6** | SOS location（若 GPT 選 §3.3 A） | `StatusUpdateData` 加 `location` + 送收接線。 | test + conformance（statusUpdate 樣本重生）|
| **4-7** | field session/scope plumbing（最小） | `FieldSession` 模型 + 取得本機 field_id（debug shell 先 hardcode 一個場域；真 join QR/代碼留 Phase 1）。 | test 綠 |

每刀跑 `pub get / check_layers --strict / analyze / test --exclude-tags golden`；wire 刀（4-3/4-3b/4-6）
另加 conformance parity。**4-3 是唯一 breaking wire 刀，刻意隔離**；4-1/4-2 先把 payload/enum 鋪好（零
conformance 衝擊），讓 4-3 聚焦在 canonical/簽章/版本。

> ⚠️ **4-3 的真實邊界比信封大**：升 envelope `protocol_version` 會連動「HELLO 協商版本」與「本機已存的
> pv=2 wire state」。這兩條若不在同一刀處理，會出現「envelope 已 v3、但握手仍 v2 / DB 仍餵 v2」的半升級
> 死角。完整落點與策略見 §8（Amendment A，pre-code 補強）。

---

## 7. 待 GPT 拍板清單（彙整）

1. **EventType 策略**：~~接受「沿用並擴充 `EventTypeV2`」、把 REBUILD_PLAN §3.2 標 superseded？~~ ✅ **已拍板（GPT review #2）並於 4-2 落地：沿用並擴充，§3.2 已標 superseded。**
2. **field_id 形態**：16-byte 定長 opaque？canonical 插在 envelope_id 之後？control range zero-field_id
   豁免 field-scope？
3. **場域金鑰綁定**：HMAC vs 純 Ed25519（白皮書 §13.3 / Q2，MCU 功耗實測待補）。
4. **CHECKPOINT**：~~獨立 type（選項 A）vs PRESENCE+checkpoint_id（選項 B）？~~ ✅ **4-2 拍板：選項 A（獨立 type=4，非 LWW）。**
5. **SOS 位置**：`StatusUpdateData` 加 `location`（A）vs PRESENCE 配對（B）？
6. **LocationEvidence 精度**：lat/lng 用 sint64 1e7 fixed-point（跨平台 parity）OK？
7. **protocol_version**：直接切 v3、不做 v2/v3 並存（全新獨立網路）OK？
8. **ADMIN_BROADCAST**：~~新增 type 82（A）vs 複用 `OFFICIAL_ALERT_SUMMARY`（B）？~~ ✅ **4-2 拍板：新增 type 82（A，非 LWW，SOS→DROP 防偽裝）。**
9. **HELLO 協商版本**（Amendment §8.1）：envelope 升 v3 時，HELLO `protocolVersion` 是否一併升 v3
   （讓不相容 peer 在握手就被擋，而非下游默默 drop）？
10. **場域金鑰綁定時程**（Amendment §8.2）：HMAC / field-scoped key / membership proof 的選型是否
    **必須在 4-3 前**定案（`field_id` 只是 signed scope label，不是完整成員驗證）？
11. **舊 wire state 處理**（Amendment §8.3）：Envelopes_V2 / Outbox_V2 既有 `protocol_version=2` records
    用 purge migration（A）/ dev DB reset（B）/ 兩者都做（C）？

> 本輪 **docs-only**，未改任何 wire code / conformance corpus / spec。批准後才進 4-1。
> 本次新增 **§8 Amendment A**（pre-code 補強 3 點：HELLO 連動、field_id 非成員驗證、舊 wire state 清理），
> 同樣 docs-only。

---

## 8. Amendment A — pre-code 補強（GPT review #2 之前）

> 觸發原因：第一版設計把「升 `protocol_version` 2→3」只當成 `EventEnvelopeV2` / dispatcher /
> `MessagePublisherV2` 的事。重讀實際程式碼後，發現 **3 個缺口**會讓 4-3 變成「半升級死角」或留下安全
> 誤解。以下全部對齊實際程式碼（行號為現況），仍 **docs-only**，不改 code。

### 8.1 `protocol_version` v3 會連動 HELLO 協商，不只信封

實際程式碼裡有 **兩個獨立的版本命名空間**，第一版設計只談到信封那個：

- **信封版本**：`EventEnvelopeV2.protocolVersion`（決定 canonical 布局、簽章）。
- **HELLO 協商版本**：`ProtocolHelloData.protocolVersion`（決定兩台 peer 在握手時要不要互相接受）。
  位於 `event_envelope_v2.dart:598` 的 `ProtocolHelloData`，由 `ProtocolHelloValidator` 在
  `protocol_hello_validator.dart:77` 檢查 `hello.protocolVersion != kProtocolVersionV2` → drop
  （`hello-protocol-version-incompatible`）。

**為什麼非處理不可**：若 4-3 只升信封到 v3、HELLO 仍停在 2，兩台 v3 build 的 peer 會在握手時「都自報
HELLO=2、握手成功」，然後才在 envelope dispatcher 因 `protocol_version=3 != _acceptedProtocolVersion`
互相 drop —— 變成「握得上手、卻一個事件都收不到」的死角，且 trace reason 會誤導（落在 dispatcher 而非
握手）。正解：**HELLO 協商版本與信封版本在 4-3 同步升 v3**，讓不相容 peer 在握手階段就被乾淨擋下。

**version-literal 完整落點（4-3 一個都不能漏；漏一個就半升級）**：

| # | 檔案:行 | 現況 | 角色 | 4-3 動作 |
|---|---|---|---|---|
| 1 | `lib/app/mesh/mesh_constants.dart:78` | `kProtocolVersionV2 = 2` | HELLO 驗證用常數 | 升 3（建議同時更名/加 `kProtocolVersionV3`，避免常數名與值不符的誤導） |
| 2 | `lib/app/services/protocol_hello_validator.dart:77,81` | `hello.protocolVersion != kProtocolVersionV2` | HELLO 握手 drop | 隨常數走；drop detail 字串同步 |
| 3 | `lib/app/proto/event_envelope_v2.dart:610` | `ProtocolHelloData.protocolVersion = 2` 預設 | HELLO 送出端預設版本 | 升 3 |
| 4 | `lib/app/proto/event_envelope_v2.dart:235` | `EventEnvelopeV2.protocolVersion = 2` 預設 | 信封建構預設 | 升 3 |
| 5 | `lib/app/proto/event_envelope_v2.dart:377` | `decode()` 拒 `protocolVersion == 0` | 信封 decode 防呆 | 維持拒 0；註解 `==2` 改 `==3` |
| 6 | `lib/app/controllers/envelope_dispatcher_v2.dart:118,185` | `_acceptedProtocolVersion = 2` | 信封 dispatcher 接受版本 | 升 3 |
| 7 | `lib/app/controllers/message_publisher_v2.dart:120,137` | 硬寫 `protocolVersion: 2`（兩處） | 送出端寫入信封 | 升 3（已在 §1.2.5 記） |
| 8 | `lib/app/services/protocol_hello_service.dart:167` | `ProtocolHelloData(...)` 建構（用預設版本） | HELLO 送出 | 確認吃到新預設（或顯式帶 3） |
| 9 | `test/services/protocol_hello_test.dart:97-100` | `protocolVersion: 1` 當不相容案例 | HELLO 測試 | 重寫：`2` 變成被拒、`3` 變成接受 |
| 10 | `test/services/ble_v2_bridge_test.dart` | 端到端 v2 握手＋傳輸 | bridge 整合測試 | 對齊 v3（握手＋至少一筆 v3 envelope 過關） |
| 11 | conformance corpus `protocol_version` 欄 | 全部 = 2 | 跨平台契約 | 隨 §5 corpus 重生為 3 |

> ⚠️ 第 6 點（`_acceptedProtocolVersion`）與第 1 點（`kProtocolVersionV2`）是**兩個分開的常數**，分別守
> 信封與 HELLO；不要以為改一個就好。建議 4-3 把兩條版本軸一起推到 3，並在 commit message 明列上表 11 點
> 已逐一處理。

### 8.2 `field_id` 是「已簽章的 scope 標籤」，不是「成員身分驗證」

把 `field_id` 綁進 Ed25519 簽章（§1.2）能防「中途竄改 field_id」—— 這是對的、必要的。但要寫明它的
**安全邊界**，避免日後誤以為「有 field_id 就等於通過場域授權」：

- `field_id` 會出現在 wire 上（明文 16 bytes），**任何人都看得到、抄得到**。簽章只證明「這個 author_key
  簽的這筆事件聲稱屬於這個 field」，**不證明** author 真的是該場域的合法成員。
- 一個惡意節點完全可以用自己的合法 `author_key`，填上一個它**偷看到**的 `field_id`，簽出一筆「看起來
  屬於該場域」的事件注入進來。簽章會過、`field-scope-mismatch` 也不會擋（因為 field_id 對得上）。

**結論（要寫進 spec）**：`field_id` = **signed scope label**（防竄改、可路由過濾），**≠ membership
authentication**（防偽冒成員）。真正的場域授權還需要下列之一，且**必須在 4-3 拍板前選定**（因為它可能改變
canonical 簽章輸入的形態 —— 例如 HMAC 會引入 field key 參與 MAC，等於動到簽章層，不能拖到 4-3 之後再補）：

1. **field key + HMAC**：場域共享密鑰，事件附 `HMAC(field_key, canonical)`；MCU 友善但金鑰散佈/輪換要管。
   （白皮書 §13.3 場域金鑰；REBUILD_PLAN Q2 的 MCU 功耗實測仍 open。）
2. **field-scoped author key**：加入場域時派發/簽發一把該場域專用 author key（憑證鏈）；驗證端認簽發者。
3. **join token / membership proof**：加入時取得短憑證，事件帶可驗證的成員證明。

> ⚠️ 這題不能拖到 4-3 之後。若選 HMAC（方案 1），canonical / 簽章輸入要在 **4-3 當刀**就把 field-key
> MAC 一起設計進去，否則 4-3 的 corpus 重生白做一次。Q3（§7）升級為 **4-3 前置硬決策**。

### 8.3 直接 v2→v3、不做 coexist：要寫明舊 wire state 的清理策略

「全新獨立網路、直接切 v3、不做 v2/v3 並存」可以接受。但**本機 dev DB 可能已存有 `protocol_version=2`
的舊 wire records**，升級後若不處理會出問題。實際程式碼（`database_helper.dart`）：

- `Envelopes_V2`（line 267 起）：**durable** 信封存儲，欄位 `protocol_version INTEGER NOT NULL`（line 269）。
  舊列是 pv=2，且其 `signature` 是蓋在**舊 124-byte canonical** 上的 —— 在 v3 dispatcher 下，這些列若被
  重新拿去 relay，會以 `unknown-protocol-version` 被丟（甚至更糟：被當 v3 重算 canonical → 簽章驗不過）。
  **無法就地升級**（canonical 變了、沒有私鑰重簽他人事件）。
- `Outbox_V2`（line 403 起）：依契約是 **ephemeral bounded queue**（line 236 註解），但升級瞬間若仍有
  pending pv=2 待送列，會把不相容信封推上線。

**策略（要寫進 4-3 migration 註記，三選一或組合）**：

| 選項 | 做法 | 適用 |
|---|---|---|
| **A. purge migration** | 4-3 的 DB migration 內 `DELETE FROM Envelopes_V2`／`DROP/重建 Outbox_V2`（清掉所有 pv=2 列）。版本號 bump 觸發。 | 想保留同一顆 dev DB、自動清乾淨 |
| **B. dev DB reset** | 文件明寫「v3 升級需清掉舊 app data / 重裝」；不寫 migration。 | fork 初期、dev 機少、最省事 |
| **C. A+B** | migration 清 + 文件也提醒 reset（雙保險）。 | 最保守 |

> 注意：現有測試都跑 **fresh in-memory DB → 只走 `onCreate`**，**不會**碰到 `onUpgrade`。所以無論選 A/B/C，
> purge/upgrade 邏輯**在 CI 裡是測不到的**（既有風險，非本刀新增）。若選 A，建議 4-3 額外補一個**顯式建舊
> schema → 塞 pv=2 列 → 跑 upgrade → 斷言已清空**的單元測試，把這條唯一會碰 `onUpgrade` 的路徑釘住。
> 傾向 **C**（migration 清 + 文件提醒），最穩；最終由 GPT 拍板（§7 第 11 點）。

> 本節同樣 **docs-only**：未改任何 code / schema / corpus。GPT review #2 通過後，4-3 的實作範圍以
> §6 表 + §8 三節為準。
