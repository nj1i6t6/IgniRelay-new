# LORA-WIRE v1 — Node↔Node↔Gateway LoRa link frame (normative)

> **任務**：MASTER_EXECUTION_PLAN §6 **B1**（契約包 v1：LORA-WIRE + provisioning 凍結，前置 A12）。
> **狀態**：FROZEN 候選 — 本檔一經 Owner 簽核即進入凍結契約集（附錄 B / G6）；此後修改唯一合法路徑＝
> Owner 明確核准 → 版本 bump → 以 `tool/generate_lora_wire_vectors.dart` 重生向量 → 排程各端 parity。
> **規範性**：所有 MUST / MUST NOT / 位元組表為 normative。**無未定項**；尚未凍結者明確標
> `RESERVED-未用` 或「附章 draft（Phase D 場試前凍結）」（電波參數，§13）——訊框格式與電波參數是兩件事，
> 前者本檔凍結、後者不是。
>
> 相依：`envelope_v2_spec_2026-05-13.md`（§21 v3 信封 / field auth / 控制框）、`app_node_gatt_v1.md`
> （App↔Node 第一跳 / NODE_RECEIPT=105，**LoRa 段不同**）、`field_auth_v2.dart`
> （`deriveLoraMacKey` / `deriveFieldMacKey`）。向量單一來源＝`tool/generate_lora_wire_vectors.dart`
> → `docs/specs/lora_wire_v1_vectors.json`。

---

## 1. 範圍與信任模型

- 本契約規範 **Node↔Node↔Gateway 之間的 LoRa 物理鏈路訊框**（store-and-forward 多跳）。
  **不**規範 App↔Node 第一跳（那是 `app_node_gatt_v1.md` 的 BLE GATT + NODE_RECEIPT），也**不**規範
  Gateway↔瀏覽器（C1）或雲端（E1）。
- **OD-3**：Node↔Gateway 與 Node↔Node 用**同一個 LORA-WIRE v1**——Gateway 就是「一個會存檔的節點」。
- **OD-2 信任模型（normative，MUST 原文遵守）**：作者的 Ed25519 簽章**不過 LoRa**（單幀 ≤128B 物理上裝不下
  64B 簽章 + payload）。Node 在 **BLE ingest 階段**已完成 `signature_status`（Ed25519）+ `field_mac`
  （HMAC，§21）驗證；通過後才把事件**翻譯**成本契約的緊湊幀進 LoRa。因此 LoRa 段的真實性 =
  **場域 HMAC（`mac8`）＋來源節點身分（`src_node`）＋ CRC 完整性**。Gateway 信的是「**持有場域 secret 的
  成員節點背書**這筆事件」，而非端到端作者證明。對應地：
  - 任何 LoRa 接收端 **MUST NOT** 宣稱已驗作者身分（那在 BLE 段，不在這）。
  - 場域 secret 外洩 ⇒ 可偽造該場域 LoRa 幀；爆炸半徑＝單場域，緩解＝場域 re-key（`node_provisioning_v1.md`）。

## 2. 常數總表（single source；向量 generator 與本表必須一致）

| 名稱 | 值 | 出處 |
|---|---|---|
| wire version | `0x1`（`ver_ptype` 高 4 位） | §3 |
| ptype EVENT | `0x1` | §4 |
| ptype ACK | `0x2` | §4 |
| header 長度 | 11 B | §3 |
| mac8 長度 | 8 B（HMAC-SHA256 截前 8） | §6 |
| crc16 長度 | 2 B（LE） | §6 |
| payload 上限 | 64 B（理想線；§9） | §5 |
| event_id 長度 | 16 B | §3 |
| ACK 全幀 | 32 B（固定） | §3 |
| HLC 重放窗 | 48 h = `172800000` ms | §7 |
| dedupe 環 | ≥ 512 槽 | §7 |
| HKDF info（LoRa MAC） | `"ignirelay/lora-mac/v1"` | §6 |
| CRC-16/CCITT-FALSE | poly `0x1021` / init `0xFFFF` / refin=false / refout=false / xorout `0x0000` | §6 |
| CRC 標準驗證值 | `"123456789"` → `0x29B1` | §6 |

**位元組序鐵則**：所有多位元組整數一律 **little-endian**（與 §3 header 既定 `src_node`/`packet_seq`/`hlc`
一致）。`mac8` 為位元組串（無位元組序）。`crc16` 以 LE 兩位元組序列化（低位在前）。

## 3. 訊框格式（位元組精確）

```
frame = hdr(11) ‖ body ‖ mac8(8) ‖ crc16(2)
```

### 3.0 Header（11 B，所有 ptype 共用）

| off | 欄位 | 型別 | 語意 |
|---|---|---|---|
| 0 | `ver_ptype` | u8 | 高 4 位 = wire version（MUST `0x1`）；低 4 位 = ptype（§4） |
| 1 | `flags` | u8 | 位元旗標（§3.1） |
| 2..5 | `field_tag` | 4 B | `field_id[0..3]`（場域預過濾，**非**安全機制；§21 的 `field_id` 前 4 位元組） |
| 6..7 | `src_node` | u16 LE | 來源節點 id（場域內唯一；`node_provisioning_v1.md`） |
| 8..9 | `packet_seq` | u16 LE | 來源節點遞增封包序（每節點自有；溢位回繞） |
| 10 | `ttl` | u8 | 剩餘跳數預算 |

- `field_tag` 只用來在驗 MAC 之前快速丟棄「明顯非本場域」的幀；**MUST NOT** 當作真實性依據（真實性靠
  `mac8`）。完整 `field_id`（16B）不過 LoRa。

### 3.1 `flags` 位元定義

| bit | 名稱 | 語意 |
|---|---|---|
| 0 | `hlc_synced` | 來源宣稱其 HLC 已對時；接收端對此幀套用 §7 重放窗檢查 |
| 1 | `retransmission` | 本幀為重送（診斷/抑制用，不影響去重結果） |
| 2 | `mule_origin` | 本幀經資料騾（手機 Data Mule）注入 LoRa 段 |
| 3..7 | RESERVED-未用 | 發送端 MUST 置 0；接收端 MUST 忽略（不得因非 0 而拒收） |

### 3.2 EVENT body（ptype `0x1`）

| off（自幀首） | 欄位 | 型別 | 語意 |
|---|---|---|---|
| 11..26 | `event_id` | 16 B | 事件唯一鍵（= 信封 `envelope_id`，UUIDv7；§20.3） |
| 27 | `event_type` | u8 | `EventTypeV2` 值（§5 翻譯表） |
| 28 | `priority` | u8 | `PriorityV2` 值 |
| 29..34 | `hlc_ms` | u48 LE | HLC 毫秒，截 48 位元：`ms & 0xFFFF_FFFF_FFFF`（溢位年 ~10889） |
| 35..36 | `hlc_ctr` | u16 LE | HLC counter，取低 16 位元 |
| 37 | `payload_len` | u8 | 緊湊 payload 長度（0..64） |
| 38..38+payload_len-1 | `payload` | 變長 | §5 緊湊 payload |

- EVENT 最小幀（payload_len=0）= 11 + 27 + 8 + 2 = **48 B**。完整幀 = `48 + payload_len`。
- `payload_len > 64` → 接收端 drop `payload-too-long`（§8）。

### 3.3 ACK body（ptype `0x2`，全幀固定 32 B）

| off | 欄位 | 型別 | 語意 |
|---|---|---|---|
| 11..12 | `ack_seq` | u16 LE | 被確認的來源 `packet_seq` |
| 13..20 | `event_id_prefix` | 8 B | 被確認事件 `event_id` 前 8 位元組 |
| 21 | `status` | u8 | `0 = ACCEPTED`、`1 = DUPLICATE`、`2 = REJECTED`；其餘 RESERVED |

- ACK = **三段收據模型的「段 2 `HOP_ACKED`」**（PHASE3 §7.2 / `app_node_gatt_v1.md` §6）。它**MUST NOT**
  被冒充為段 1（手機→Node 收據 = NODE_RECEIPT 105，BLE 段）或段 3（雲端確認）。`status` 數值與 NODE_RECEIPT
  巧合對齊純為易記，**語意上是不同段**。
- ACK body 無 `event_id`（全 16B）、無 HLC ⇒ §7 重放窗與去重環**不適用**於 ACK。

## 4. ptype

| ptype | 名稱 | body |
|---|---|---|
| `0x1` | EVENT | §3.2 |
| `0x2` | ACK | §3.3 |
| `0x0`、`0x3..0xF` | RESERVED-未用 | 接收端 drop `unknown-ptype` |

## 5. 緊湊 payload 翻譯表（envelope → LoRa；附錄 C 逐欄位元寬照抄）

Node 在 BLE ingest 驗章/MAC 後，把信封 typed payload（`event_envelope_v2.dart`）**翻譯**成下列緊湊格式。
所有多位元組 LE；`lat`/`lng` 為 **signed i32**（兩補數）degrees×1e7；列舉值沿用信封既有 enum（不另立）。

共用子結構 **`loc13`（13 B）**：

| off | 欄位 | 型別 | 來源 |
|---|---|---|---|
| 0 | `src` | u8 | `LocationSource`（0 unknown/1 gps/2 field_node/3 ble_rssi/4 pdr/5 manual） |
| 1..4 | `lat_e7` | i32 LE | `LocationEvidence.latE7` |
| 5..8 | `lng_e7` | i32 LE | `LocationEvidence.lngE7` |
| 9..10 | `acc_m` | u16 LE | `LocationEvidence.accuracyM`（0 = 未知；> 65535 飽和為 65535） |
| 11..12 | `age_s` | u16 LE | 觀測距發送的秒數（`now − observedAt`，飽和 65535 ≈ 18.2h） |

| event_type | EventTypeV2 | 緊湊 payload | 大小 |
|---|---|---|---|
| PRESENCE | 3 | `anon8(8)` ‖ `battery u8` ‖ `evid_src u8`(LocationSource) | 10 B |
| SOS（STATUS_UPDATE）| 1 | `anon8(8)` ‖ `safety u8`(SafetyState) ‖ `loc13(13)` | 22 B |
| CHECKPOINT | 4 | `anon8(8)` ‖ `checkpoint_node u16 LE` | 10 B |
| HEARTBEAT | 102 | `battery u8` ‖ `solar u8` ‖ `uptime_h u16 LE` ‖ `queue u8` ‖ `storage_pct u8` ‖ `fw u16 LE` | 8 B |
| HAZARD（HAZARD_MARKER）| 50 | `type u8`(HazardType) ‖ `sev u8` ‖ `loc13(13)` ‖ `desc_len u8` ‖ `desc(≤24, UTF-8)` | ≤ 40 B |

- `anon8` = `anon_user_id` 前 8 位元組（§OD-7；非作者公鑰）。`safety`：0 unspecified/1 safe/2 unsafe/3 injured/4 trapped。
  `HazardType`：0 unspecified/1 fire/2 flood/3 landslide/4 collapse/5 chemical/6 blocked_route/7 other。
- HAZARD `desc` **MUST ≤ 24 位元組**（UTF-8 截斷以完整 code point 為界，不得切半個字元）；超出在翻譯端截斷。
- HEARTBEAT 無 `anon8`（節點自我遙測，非人）。

## 6. 金鑰、MAC、CRC

- **LoRa MAC 金鑰（domain-separated）**：
  ```
  lora_mac_key = HKDF-SHA256(ikm=field_join_secret, salt=∅, info="ignirelay/lora-mac/v1", L=32)
  ```
  空 salt → RFC 5869 以 32 個零位元組代入。**MUST** 與 §21.3 的
  `field_mac_key = HKDF(…, info="ignirelay/field-mac/v3")` **不同**（不同 `info` ⇒ 不同金鑰；
  `field_auth_v2.dart` 的 `deriveLoraMacKey` / `deriveFieldMacKey`；向量測試硬性斷言兩把 key 不相等）。
- **`mac8`**：`mac8 = HMAC-SHA256(lora_mac_key, hdr‖body)[0..7]`（前 8 位元組）。涵蓋 header 與 body，
  **不**涵蓋 `crc16`（crc 反過來涵蓋 mac8，見下）。
- **`crc16`**：`crc16 = CRC-16/CCITT-FALSE(hdr‖body‖mac8)`，參數 poly `0x1021` / init `0xFFFF` /
  refin=false / refout=false / xorout `0x0000`；以 LE 兩位元組序列化。標準驗證值
  `CRC("123456789") = 0x29B1`（本檔與向量、各端實作都 MUST 收錄此驗證）。外加兩個自選向量見 `…_vectors.json`。

## 7. 重放、過期、TTL

- **去重**：接收端維護 `event_id` 去重環（**≥ 512 槽**，LRU）。EVENT 的 `event_id` 已在環內 → drop
  `replay-duplicate`；否則納入並接受。ACK 不入去重環。
- **HLC 重放窗**：`flags.bit0 hlc_synced` 置位的 EVENT，若接收端自身已對時，比較 `hlc_ms` 與本地 HLC 估計，
  `|hlc_ms − local_est| > 48h`（172800000 ms）→ drop `replay-window`。未置位（對時前 bootstrap）則**不**套用窗檢查
  （HLC 照單全收，靠去重環防重放）。
- **TTL**：每次轉送前 relay **MUST** 將 `ttl` 減 1 再重送。收到 `ttl == 0` 的幀 → drop `ttl-expired`
  且**不再轉送**（已抵預算上限）。`ttl` 不影響本地接受與否之外的處理——它是轉送預算，不是過期時鐘。

## 8. 接收管線順序（normative，固定，逐步對應向量 generator/consumer）

接收端 **MUST** 依下列固定順序檢查，第一個失敗即為 drop_reason（每個負向向量只觸發其中一條）：

1. `len < 11` → `truncated`（連 header 都讀不到）。
2. version（`ver_ptype` 高 4 位）≠ `0x1` → `unknown-version`。
3. ptype（低 4 位）∉ {`0x1`,`0x2`} → `unknown-ptype`。
4. 長度判定：
   - ACK：`len < 32` → `truncated`；`len ≠ 32` → `length-mismatch`。
   - EVENT：`len < 48` → `truncated`；讀 `payload_len`，`> 64` → `payload-too-long`；
     `expected = 48 + payload_len`，`len < expected` → `truncated`，`len > expected` → `length-mismatch`。
5. CRC：`crc16` over `frame[0 : len-2]` ≠ 末 2 位元組(LE) → `crc-mismatch`。
6. MAC：`HMAC(lora_mac_key, frame[0 : len-10])[0..7]` ≠ mac8 欄位（`frame[len-10 : len-2]`）→ `mac-mismatch`
   （**MUST** 常數時間比較）。
7. `ttl == 0` → `ttl-expired`。
8. （EVENT 且 `hlc_synced` 且本地已對時）§7 窗外 → `replay-window`。
9. （EVENT）`event_id` 已在去重環 → `replay-duplicate`；否則納入 → **ACCEPT**。

> 順序理由：先結構（truncated/version/ptype/length）→ 再完整性（**CRC 先於 MAC**：CRC 抓隨機位元翻轉，
> 不必動到 HMAC；偽造者若重算 CRC 後仍過不了 MAC）→ 再政策（ttl/hlc/replay）。

### 8.1 drop_reason 詞彙（封閉集；各端字面一致）

`truncated`、`unknown-version`、`unknown-ptype`、`length-mismatch`、`payload-too-long`、
`crc-mismatch`、`mac-mismatch`、`ttl-expired`、`replay-window`、`replay-duplicate`。

## 9. 尺寸預算（附錄 C 對照；偏差聲明原文收錄）

| 幀 | payload | 全幀 |
|---|---|---|
| PRESENCE | 10 B | 58 B |
| CHECKPOINT | 10 B | 58 B |
| HEARTBEAT | 8 B | 56 B |
| SOS | 22 B | **70 B** |
| HAZARD | ≤ 40 B | ≤ 88 B |
| ACK | —（固定）| 32 B |

- **偏差聲明（原文收錄）**：SOS 全幀 70 B **大於 64 B 理想線**，但在 **128 B 審查線**內。訊框格式與電波參數
  分離（§13）；70 B 在實際 SF/BW 下的 airtime 留待 **D5 場試實測**，本契約不因此調整訊框。
- `payload` 欄位上限 64 B（理想線）以 `payload_len u8` 與 §8 步驟 4 強制；HAZARD `desc` 上限 24 B 以 §5 強制。

## 10. 向量（conformance）

- 單一來源 generator：`tool/generate_lora_wire_vectors.dart`（G7：禁止手寫 JSON；generator 改動視同契約改動，走 G6）。
- 輸出：`docs/specs/lora_wire_v1_vectors.json`。內建 self-check（`--check` 與寫入皆執行）：
  每正樣本 **encode → decode → re-encode 位元組一致**、`mac8`/`crc16` 重算相符；每負樣本以 §8.1 對應
  reason 拒絕；CRC 標準值 `0x29B1`。
- 樣本量：正樣本 **≥ 40**（每事件型別 × flags 組合 × ttl 階梯 + 各 status 的 ACK）；負樣本 **≥ 10**
  （§8.1 詞彙全覆蓋）。測試金鑰**沿用** corpus 既有 TEST-ONLY `field_join_secret`
  （`wire_conformance_v1.json#test_field`），讓信封與 LoRa 向量同鑰可交叉驗。
- Dart consumer：`test/conformance/lora_wire_vectors_test.dart`。B2 起 Python（lab/gateway）、B6 起 C（field-node）
  各自吃同一份 JSON，**MUST NOT** 自行重生。

## 11. 凍結與相容性

- 一經 Owner 簽核：本檔 + `lora_wire_v1_vectors.json` + generator + `node_provisioning_v1.md` 進入凍結集（附錄 B）。
- **additive 規則**：未來新增 `flags` 位元、`ptype`、緊湊 payload 欄位，一律走 G6（版本 bump + 重生向量 + 三端 parity）。
  舊接收端對 RESERVED `flags` 位元 MUST 忽略（§3.1）、對未知 `ptype` drop（不崩）。
- **禁止**：縮短 mac8/key、跳過任一 §8 檢查、把 MAC 比對改 `startsWith`、在本檔留「待定」訊框欄位、
  把作者 Ed25519 簽章塞進 LoRa（違 OD-2 與 §9 預算）。

## 12. 與既有契約的界線（不重複、不衝突）

- **App↔Node 第一跳**（BLE GATT、`EventEnvelopeV2` v3、NODE_RECEIPT=105）＝ `app_node_gatt_v1.md`；
  本檔**不**改動其任何位元組。LoRa ACK（§3.3）與 NODE_RECEIPT 是**不同段、不同 wire**。
- **canonical / 簽章 / field_mac / chunking**＝ `envelope_v2_spec` §21 / `native_transport_v1`；本檔**不**改動，
  僅在 §6 引用其 HKDF 構造（不同 `info`）。
- 若日後發現本檔與 A12 凍結契約衝突 → G8 BLOCKED 回報 Owner，**不得**自行改任一契約。

## 13. Radio profile（附章 draft — Phase D 場試前凍結，**非本檔凍結項**）

- 台灣 **AS923**（923 MHz）；BW / SF / CR / 前導長度 / 發射功率 / duty-cycle / airtime 依法規與場試實測，
  於 **D5 場試前**寫定並凍結（PHASE3 §3.3 gate）。本章為設計佔位，**與 §3–§9 的訊框格式無耦合**：
  訊框（位元組層）本檔即凍結，電波參數另案。此分離是刻意的，不得以「電波未定」為由把訊框留白。

## 14. 修訂紀錄

- **v1（B1，rev `lora-wire-v1-1`）**：首版凍結候選。Header 11B / EVENT・ACK body / flags / ptype 位元組精確；
  §5 緊湊 payload 翻譯表（PRESENCE 10 / SOS 22 / CHECKPOINT 10 / HEARTBEAT 8 / HAZARD ≤40，loc13 共用）；
  §6 `lora_mac_key`（HKDF info `ignirelay/lora-mac/v1`，domain-separated）+ `mac8`(HMAC-SHA256[0..7]) +
  CRC-16/CCITT-FALSE（`0x29B1`）；§7 去重環/HLC 48h 窗/TTL；§8 固定接收順序 + drop_reason 詞彙；§9 尺寸預算
  （SOS 70B>64B 偏差聲明、128B 審查線）；OD-2 信任模型原文。向量 generator + Dart consumer 同刀落地。待 Owner 簽核。
