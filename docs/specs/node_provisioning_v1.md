# Node provisioning v1 — Field Node 佈建契約（normative）

> **任務**：MASTER_EXECUTION_PLAN §6 **B1**（契約包 v1，與 `lora_wire_v1.md` 同刀凍結，前置 A12）。
> **狀態**：FROZEN 候選 — Owner 簽核後進入凍結契約集（附錄 B / G6）。**無未定項**；流程上「後續 Phase 才實作」
> 的部分以 normative 文字**先行聲明**（不留占位）。
> **規範性**：所有 MUST / MUST NOT / JSON schema 為 normative。
>
> 相依：`lora_wire_v1.md`（`src_node` ← `node_id`；`field_join_secret` → `lora_mac_key`）、
> `envelope_v2_spec` §21（`field_id` / `field_mac_key` 派生）、`app_node_gatt_v1.md`（node HELLO 欄位 10–13、
> NODE_RECEIPT=105 由 node 簽發）。安全紅線：G14。

---

## 1. 範圍

定義一個 Field Node 在進入場域前**必須**被寫入的最小身分與金鑰物，以及寫入流程（lab 模擬 / 實機 USB）。
**不**規範韌體實作細節（Stage B B6+）、不規範電波參數（`lora_wire_v1.md` §13）。一個 Node 佈建完成
= 持有 §2 全部欄位且能據此（a）產生合法 LoRa `mac8`（b）以 node profile 回送 HELLO 與 NODE_RECEIPT。

## 2. 佈建物（一個 Node 必須持有的全部欄位）

| 欄位 | 型別 | 必填 | 語意 / 約束 |
|---|---|---|---|
| `node_id` | u16（1..65535） | 是 | **場域內唯一**的節點識別碼。`0` 為 RESERVED-未用（不得指派）。即 LoRa header 的 `src_node`（`lora_wire_v1.md` §3）。 |
| `field_join_secret` | 32 B | 是 | 場域共享秘密。Node 由它派生 `field_id`、`field_mac_key`（§21.3）與 `lora_mac_key`（`lora_wire_v1.md` §6）。**MUST NOT** 出現在 log / 匯出 / 版控（G14）。 |
| `node_ed25519_seed` | 32 B | 是 | Node 自有 Ed25519 私鑰種子，供簽 **NODE_RECEIPT(105)** 與 **PROTOCOL_HELLO**（`app_node_gatt_v1.md`）。與 `field_join_secret` **獨立**（金鑰分離）；**MUST NOT** 由 `field_join_secret` 派生。 |
| `mode` | enum `lab \| dev \| field` | 是 | 佈建環境標記。`lab`/`dev` 允許使用 TEST-ONLY secret；`field` **MUST** 為真實場域 secret 且 **MUST NOT** 與任何 TEST-ONLY 值相等。 |
| `node_label` | string（≤32 B UTF-8） | 否 | 人類可讀部署名（如「南口閘」）。非密鑰、可進 log。對應 HELLO `node_id` string 欄位（field 10）以外的展示用途。 |
| `install_lat_e7` / `install_lng_e7` | sint32 ×1e7 | 否 | Node **安裝點**座標（部署登記），對應 HELLO 欄位 11/12。未知＝省略。**MUST NOT** 被手機當成使用者位置（`app_node_gatt_v1.md` §3）。 |
| `install_accuracy_m` | u32 | 否 | 安裝座標水平誤差（公尺），HELLO 欄位 13。 |

- **`node_id` 唯一性**由佈建者（lab 編排 / Owner CLI）保證；同場域兩 Node 同 `node_id` 為佈建錯誤
  （後果：LoRa `src_node` 碰撞、ACK 對應錯亂）。本契約不在 wire 層偵測碰撞——由佈建流程把關。
- **金鑰分離鐵則**：`field_join_secret`（場域成員證明）與 `node_ed25519_seed`（節點作者身分）是兩把不同用途的
  金鑰，**MUST** 各自獨立隨機產生；任一外洩不得推導另一把。

## 3. 佈建記錄格式（USB serial 一次性 JSON 行；normative schema）

實機佈建 = 透過 USB serial 對 Node 送**單行 JSON**（換行結尾）。Node 收下後寫入安全儲存、回 ACK 行、即生效。

```json
{"schema":"ignirelay/node-provisioning/v1","node_id":7,"field_join_secret_b64":"<base64 of 32B>","node_ed25519_seed_b64":"<base64 of 32B, optional>","mode":"field","node_label":"south-gate","install_lat_e7":250339805,"install_lng_e7":1215654177,"install_accuracy_m":8}
```

- `schema` **MUST** == `"ignirelay/node-provisioning/v1"`；不符即拒絕整行。
- 32 B 欄位以 **base64**（標準字母表、含 padding）攜帶；解碼後長度 **MUST** == 32，否則拒絕。
- `node_ed25519_seed_b64` **可省略**：省略時 Node **MUST** 於首次佈建自行產生一把隨機 Ed25519 種子並持久化
  （之後佈建不覆寫，除非顯式重置）；提供時以提供值為準（lab 可注入固定種子求可重現）。
- 未知鍵：Node **MUST** 忽略（向前相容；新增鍵走 G6 版本 bump）。
- **冪等**：以相同 `node_id` + 相同 secret 重送 = no-op（回 ACK `unchanged`）；secret 變更 = 重佈建
  （回 ACK `rekeyed`）。
- Node 回應行：`{"schema":"ignirelay/node-provisioning/v1/ack","node_id":7,"status":"provisioned|unchanged|rekeyed|rejected","reason":"<僅 rejected 時>"}`。
- **G14**：Node **MUST NOT** 在任何 log / 序列輸出回印 `field_join_secret` 或 `node_ed25519_seed`（連 ACK 行也不得回帶）。

## 4. lab / dev 佈建（模擬，無實體 serial）

- lab（`ignirelay-lab`）以**測試 fixture** 直接建構佈建物，**MUST** 使用 corpus 既有 TEST-ONLY
  `field_join_secret`（`wire_conformance_v1.json#test_field` / `lora_wire_v1_vectors.json#test_field`），
  使模擬 Node 產生的 LoRa `mac8` 與向量可交叉驗。
- `node_ed25519_seed`：lab 以固定 TEST-ONLY 種子注入（可重現）；**MUST** 在 fixture 標 `TEST-ONLY`。
- lab/dev 佈建物 **MUST NOT** 標 `mode:"field"`。

## 5. 與 LORA-WIRE / 信封契約的對應（不重複定義，僅鏈結）

| 佈建欄位 | 派生 / 使用 | 出處 |
|---|---|---|
| `field_join_secret` | `field_id = SHA-256(secret)[0..15]` | `envelope_v2_spec` §21.3 |
| `field_join_secret` | `field_mac_key = HKDF(secret, info="ignirelay/field-mac/v3")` | §21.3 |
| `field_join_secret` | `lora_mac_key = HKDF(secret, info="ignirelay/lora-mac/v1")` | `lora_wire_v1.md` §6 |
| `field_id[0..3]` | LoRa header `field_tag` | `lora_wire_v1.md` §3 |
| `node_id` | LoRa header `src_node` | `lora_wire_v1.md` §3 |
| `node_ed25519_seed` | NODE_RECEIPT(105) / HELLO 簽章 | `app_node_gatt_v1.md` §3/§5 |
| `install_lat/lng/accuracy` | HELLO 欄位 11/12/13 | `app_node_gatt_v1.md` §3 |

- 本契約**不**重新定義上述派生公式，只規定佈建物須足以餵入它們。任一公式以其出處為唯一權威。

## 6. 節點遺失 / 退役處置（normative 聲明；完整流程 Phase 後續）

- 一個 Node 遺失（被竊 / 故障 / 退役）即視同其持有的 `field_join_secret` **可能外洩**。處置 = **場域 re-key**：
  Owner 產生新 `field_join_secret` → 重新佈建場域內**所有** Node（§3）→ 重發場域加入物給成員手機（A7 QR 流程）。
- re-key 後舊 secret 派生的 `field_id` / `lora_mac_key` 全部失效；以舊 secret 偽造的 LoRa 幀在新場域 `mac-mismatch`
  被拒（`lora_wire_v1.md` §8）。**爆炸半徑＝單一場域**（與 OD-9 雲端模型一致）。
- 自動化 re-key 編排（批次重佈、成員端輪換 UX）為**後續 Phase** 工作；本契約先把「遺失即 re-key、爆炸半徑單場域」
  定為 normative 處置原則，使 Stage B 之後的實作有所本。**不**留待定欄位於 wire / 佈建物。

## 7. 安全紅線（G14，逐條 MUST）

- `field_join_secret` 與 `node_ed25519_seed` **MUST NOT** 寫入版控、log、匯出、ACK 回應。
- `field` 模式 secret **MUST NOT** 等於任何 TEST-ONLY 值；佈建工具 **MUST** 在偵測到此情形時 reject。
- 兩把金鑰 **MUST** 各自獨立隨機；**MUST NOT** 互相派生。
- TEST-ONLY 金鑰**MUST** 明確標示，且只出現在 lab/dev 佈建與向量檔。

## 8. 凍結與相容性

- 一經 Owner 簽核：本檔進入凍結集（附錄 B）。schema 欄位增修走 G6（版本 bump → schema 字串 `…/v2` → 排程各端）。
- 舊 Node 對佈建記錄未知鍵 MUST 忽略（§3）；新欄位以 additive 方式加入，不得改既有鍵語意。

## 9. 修訂紀錄

- **v1（B1）**：首版凍結候選。佈建物七欄（node_id / field_join_secret / node_ed25519_seed / mode /
  node_label / install_lat·lng·accuracy）；USB 一次性 JSON schema `ignirelay/node-provisioning/v1` + 冪等 ACK；
  lab/dev fixture 沿用 corpus TEST-ONLY secret；§5 與 LORA-WIRE/信封派生對應表；§6 遺失即場域 re-key（單場域爆炸半徑）；
  §7 G14 紅線。與 `lora_wire_v1.md` 同刀。待 Owner 簽核。
