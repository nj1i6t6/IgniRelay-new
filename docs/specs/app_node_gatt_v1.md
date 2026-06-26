# App ↔ Field Node — GATT 契約 v1（normative）

> **任務**：MASTER_EXECUTION_PLAN §5 A12（App↔Node 契約凍結，交付 Stage B 的鑰匙）。
> **狀態**：FROZEN 候選 — D1 完成。**本檔一經 Owner D4 簽核即為凍結契約（附錄 B / G6）**，
> 此後修改唯一合法路徑＝Owner 明確核准 → 版本 bump。
> **規範性**：本檔所有「MUST / MUST NOT / 逐字收錄」段落為 normative，無 TBD；未定者明確標 `RESERVED-未用`。
> **不重複原則**：chunking/MTU/重組 與 envelope/canonical 規則一律**引用**既有 spec，不另寫一份（避免雙源漂移）。
>
> 相依：`native_transport_v1_2026-05-13.md`（GATT framing / chunking §4）、`envelope_v2_spec`（v3 §21 控制區）、
> PHASE3 §7.2（三段收據模型）。實作參照：`IgniRelayConstants`（UUID）、`event_envelope_v2.dart`
> （EventTypeV2 / ProtocolHelloData / NodeReceiptData）。

---

## 1. 角色與拓撲

- **Field Node = GATT peripheral（被連端）**，沿用手機↔手機既有的 GATT 角色：手機為 **central** 主動掃描/連線，
  Node advertise 服務、被連。Node 端 MCU **MUST** 實作與手機 peripheral 端**位元組一致**的 GATT 行為。
- App **MUST NOT** 為了 Node 另開新 service/characteristic/UUID（兩端既有韌體/手機已綁定現值）。
- 本契約只規範 **App↔Node 第一跳（link-local）**。Node→LoRa/Gateway 的後續轉送不在本契約（見 §6 三段收據）。

## 2. GATT Service 與 Characteristics（逐字收錄，MUST 一致）

UUID 逐字取自 `IgniRelayConstants`（UUIDv5：`NAMESPACE_DNS` + `"ignirelay.com"`）；**MUST NOT** 變更：

| 名稱 | UUID | 用途 | 屬性 |
|---|---|---|---|
| SERVICE | `a4d11949-49d0-5230-96bb-43dd95d2cb2e` | 主服務 | — |
| EVENT_CHAR | `a932d89d-c24c-5d11-8320-55374c7feb74` | 事件 envelope 收送（含 NODE_RECEIPT notify） | Write / Notify |
| BLOOM_CHAR | `9b60940f-ca37-5c28-8620-42a89e7fdca7` | Bloom/IBLT 同步摘要 | Write / Notify |
| HANDSHAKE_CHAR | `24b532d3-243f-5b61-92b0-50af4cf0bd1a` | PROTOCOL_HELLO 能力交換 | Write / Notify |
| CCCD | `00002902-0000-1000-8000-00805f9b34fb` | 標準 notify 描述子 | — |

- Node **MUST** 在 EVENT_CHAR 上以 notify 回送 NODE_RECEIPT（§5）。
- chunk framing / MTU 協商 / 重組規則 = `native_transport_v1 §4` **原文引用**，Node MCU **MUST** 實作一致
  （單一 envelope 超過協商 MTU 時的分片標頭、序號、重組與逾時，全依該節，不在此另定）。

## 3. HELLO 能力交換（PROTOCOL_HELLO = EventType 100）

Node 在 HANDSHAKE_CHAR 上送 `PROTOCOL_HELLO`，payload = `ProtocolHelloData`（`event_envelope_v2.dart` 現有定義
逐字收錄）。Node **MUST** 使用既有 capability profile 目錄中的 **node 型 profile**（`peerKind = PeerKind.bleNodeV1 = 2`）。

**現有欄位（1–9，不變）**：`1 protocol_version`、`2 peer_kind`、`3 max_rx_envelope_bytes`、`4 supports_iblt`、
`5 supports_bloom_v2`、`6 supports_chunking`、`7 min_negotiated_mtu`、`8 capabilities (repeated string)`、`9 bg_state`。

**Node additive 欄位（10–13，本契約新增；additive，手機端 decode 容忍未知 → 舊手機不破）**：

| field | 名稱 | 型別 | 語意 |
|---|---|---|---|
| 10 | `node_id` | string | Node 安裝識別碼（部署登記用；非密鑰） |
| 11 | `node_lat_1e7` | sint32 | Node 安裝點緯度 × 1e7（zigzag varint）；未知＝省略 |
| 12 | `node_lng_1e7` | sint32 | Node 安裝點經度 × 1e7（zigzag varint）；未知＝省略 |
| 13 | `install_accuracy_m` | uint32 | 安裝座標水平誤差（公尺）；未知＝省略 |

- 手機端 `ProtocolHelloData.decode` 對未知 tag 一律 `skipValue`（**現碼已如此**），故舊手機收到帶 10–13 的
  node HELLO **MUST** 正常解析既有欄位、安全略過新欄位。
- 欄位號 14+ 為 **RESERVED-未用**。
- node_lat/lng 為 Node **自身安裝點**（部署時登記），非任何 peer 位置；手機**MUST NOT** 把它當成使用者位置投影。

## 4. 事件收送（手機 → Node）

- 手機在 EVENT_CHAR 寫入既有 `EventEnvelopeV2`（v3 §21 canonical bytes，逐字依 `envelope_v2_spec`）。
- Node **MUST** 對收到的事件執行：驗章（Ed25519，依 `signature_status` 規則）→ 去重（envelope_id）→ 落佇列，
  然後以 §5 NODE_RECEIPT 回送結果。
- field-scope（field_id / field_mac）規則沿用 §21；Node 屬該場域節點時方接受非控制事件。

## 5. NODE_RECEIPT — EventType 105（control，本契約新增）

### 5.1 型別與矩陣

- `EventType.NODE_RECEIPT = 105`（control range 100–129，additive，接於 `TRACE_ACK = 104` 之後）。
- **matrix（比照 PROTOCOL_HELLO 模式）**：
  - `maxHopsDefault(105) = 0` — **link-local，MUST NOT 轉送**（§11.4 同 HELLO）。
  - 允許 priority **僅 `NORMAL`**；其餘 priority **MUST drop**（drop_reason 比照控制型逾權）。
  - LWW = null（非 LWW，不參與場域 read-model 收斂）。
  - `isKnown(105) = true`。
- **控制框規則（§21.7）**：control range 100–129 → `field_id` 全零 16 bytes、**無 `field_mac`**、dispatcher 對
  field-scope 驗證**豁免**。NODE_RECEIPT MUST 遵循（zero field_id、no field_mac）。驗證測試 MUST 涵蓋 105。

### 5.2 payload — `NodeReceiptData`（手寫 struct，仿 `CheckpointData`）

| field | 名稱 | 型別 | 語意 |
|---|---|---|---|
| 1 | `ref_envelope_id` | bytes(16) | 被回執的手機事件之 envelope_id（對應鍵） |
| 2 | `status` | uint32(u8 範圍) | `0 = ACCEPTED_STORED`、`1 = DUPLICATE`、`2 = REJECTED` |
| 3 | `queue_depth` | uint32 | Node 當前待轉佇列深度（手機端 UI 提示用） |

- field 4+ 為 **RESERVED-未用**。decode 對未知 tag `skipValue`（與既有 reader 一致）。
- `status` 列舉以外的值：手機端**MUST** 視為「未知狀態」保守顯示，不得當成 ACCEPTED。

### 5.3 方向與手機端行為（App 只收不送）

- **送方 = Node / 模擬器**；App **只接收** NODE_RECEIPT（A12 範圍不含手機端產生 receipt）。
- 手機端 `V2InboundProjector` 收到 event_type=105 **MUST NOT** 投影到 `Event_Logs`（非場域事件）；改解
  `NodeReceiptData` 後推 `EventStream.nodeReceipts` typed 流。
- 對應鍵：`ref_envelope_id` ↔ 送出端 facade **預配的 envelope_id**。debug shell 在對應「送出列」顯示
  **「已送達節點」**（`status=0`）/「重複」（1）/「遭拒」（2）+ queue_depth。
- 收到 NODE_RECEIPT **不**改變場域 read-model（PRESENCE/SOS/HAZARD…），純屬傳輸層收據。

## 6. 三段收據模型（PHASE3 §7.2，收錄）

NODE_RECEIPT 只承諾**第一段**，三段語意 MUST 分離、**MUST NOT** 互相冒充：

| 段 | 意義 | 來源 |
|---|---|---|
| `PHONE_TO_NODE_ACCEPTED` | 手機事件已被**本跳 Node** 驗章+去重+落佇列 | **本契約 NODE_RECEIPT (105)** |
| `HOP_ACKED` | 事件已被**下一跳**（LoRa/mule）接收 | 後續 Stage（不在本契約） |
| `GATEWAY_CONFIRMED` | 事件已達**雲端 Gateway** | 後續 Stage（不在本契約） |

手機 UI **MUST NOT** 以「已送達節點」(段1) 宣稱已達雲端/已被救援端看到（段3）。

## 7. 凍結與相容性

- 一經 D4 簽核：本契約檔 + `EventType 105` + `NodeReceiptData` + HELLO 欄位 10–13 + corpus NODE_RECEIPT 樣本
  進入**凍結**集（附錄 B）。
- **additive 相容**：未實作 Node 的舊手機收到 HELLO 10–13 / 不會收到 105（Node 才發），行為不變；
  收到 105 的新手機若 Node profile 未知亦不破（control 豁免 + 未知欄位 skip）。
- **禁止**：發明新 GATT UUID；在本檔留「待定」欄位。

## 8. 修訂紀錄

- **v1（A12，2026-06-23）**：首版凍結候選。GATT service/char UUID 逐字收錄；HELLO node additive 10–13；
  NODE_RECEIPT=105 + NodeReceiptData（ref_envelope_id/status/queue_depth）；控制框 §21.7 豁免；chunking 引
  native_transport_v1 §4；三段收據模型收錄。待 Owner D4 簽核。
