# 烽傳 IgniRelay — 總施工計畫 MASTER EXECUTION PLAN

> **版本 v1.5 · 2026-06-16 · Owner: simon（本文件中稱「Owner」）**
> 範圍：從本日現況，一路到「手機 App + 實體 Field Node + Gateway + 管理者 Web 後台
> + **雲端場域服務（Owner VPS，Stage E）**」整套產品跑通為止的完整施工路線。
> **本文件是給施工 AI（以下稱 AGENT）逐字遵守的施工規格**，
> 不是參考建議。所有任務的完成定義（DoD）、驗證指令、證據要求、禁止事項都是硬規則。

---

## §0 文件性質與使用規則（AGENT 必讀，違反即任務作廢）

### 0.1 這份文件是什麼

- 本文件 = **唯一的跨 repo 施工總綱**。它把四個 repo 的工作拆成有編號的任務
  （A0–A12 / UI-F / UI-G / B1–B10 / C1–C7 / E1–E7＋EC-1～EC-4 / D1–D5），每個任務有：前置條件、實作步驟、
  **DoD（Definition of Done）**、**驗證指令（逐字執行）**、**證據要求**、**禁止事項**。
- 涉及的 repo（皆已存在於 Owner 機器上）：

| Repo | 路徑 | 角色 |
|---|---|---|
| App（本 repo） | `C:\Users\radio\Downloads\IDE\IgniRelay` | 手機 App + **所有 wire/GATT/金鑰契約的唯一 owner** |
| Field Node | `C:\Users\radio\Downloads\IDE\ignirelay-field-node` | Zephyr 韌體（nRF54L15 + SX1262 LoRa），先模擬器後實機 |
| Gateway | `C:\Users\radio\Downloads\IDE\ignirelay-gateway` | LoRa 彙整 + SQLite + HTTP API + Web 管理後台（Python）；**v1.2 起同一 codebase 兼任 Stage E 雲端場域服務（`cloud` 部署形態，跑在 Owner VPS）** |
| Lab | `C:\Users\radio\Downloads\IDE\ignirelay-lab` | 多節點模擬編排、FakeLoRaChannel、chaos 測試（Python） |

### 0.2 文件優先序（衝突時誰說了算）

1. `ignirelay_app/docs/specs/envelope_v2_spec_2026-05-13.md`（含 §21）與
   `native_transport_v1_2026-05-13.md` — **已凍結 wire 契約，位元組層級最高權威**。
2. 本文件（MASTER_EXECUTION_PLAN）。
3. `docs/APP_UI_IA_REWORK_PLAN.md`、`docs/REBUILD_PLAN.md`、`docs/PHASE0B4_WIRE_DESIGN.md`、`docs/PHASE3_MODE_B_FIELD_NODE_PLAN.md`
   — 背景與設計依據；與本文件牴觸時以本文件為準（本文件已吸收其結論）。
4. 各 repo README / STATUS — 現況描述，不是規格。

### 0.3 Owner 指定的總順序（v1.2 改版，Owner 2026-06-11 拍板；不得擅自重排）

1. **Stage A：先把 App 做完**（含基線修復、PRESENCE/SOS/HAZARD 接線、場域加入、SOS UX、
   mapless 卡片＋雷達視圖、正式 AppShell/UI-IA 重整、motion-aware 定位節流、引導模式、雙機驗證、契約凍結）。
2. **Stage B：用模擬器把 Field Node 與 Gateway 跑起來**（先不買任何硬體；全部在 PC 上以模擬方式讓 AGENT 開發與測試）。
3. **Stage C：Web 管理端（現場 LAN 形態）**——跑在 PC 上、與 Gateway 同一個區域網路，使用者用瀏覽器觀看。
4. **Stage E：雲端場域服務**——部署在 Owner 的 VPS（網域＋HTTPS）。多場域 SaaS：
   場域主開場域、成員掃 QR 加入、有網路的手機直接上雲、現場閘道有回程網路時同步上雲、
   雲端後台（含場域自訂地圖）。詳本文件「Stage E」章（位於 §7 與 §8 之間）；
   v1.3 起含 **EC 系列**（E-CARE 跨專案串接，Owner 2026-06-12 拍板）。
5. **Stage D：實體硬體**——模擬器全綠、採購 gate（B10）通過之後，Owner 才買開發板
   （nRF54L15 DK + SX1262）與配件，進入實機 bring-up。**Stage D 可與 Stage E 整段並行**
   （軟體工作不依賴硬體、硬體工作不依賴雲端；D 的入場條件不變）。

> 標注「**可並行**」的任務允許在不違反前置條件下提前做；沒有標注的一律照編號順序。
> 文件中章節的物理順序（§5 A → §6 B → §7 C → Stage E → §8 D）即執行順序。

### 0.4 任務分工（Owner 2026-06-10 拍板；不得擅自越界）

| 執行者 | 任務 | 理由 |
|---|---|---|
| **主理 AI（Claude，Owner 授權 session）** | A0、A1、**DL（設計語言）**、A4、A5、A12、B1、**E1（雲端契約＋地圖校準規格/vectors）**、各 Stage 稽核（§10.2） | 動凍結 wire / 密碼學 / 契約圖紙 / corpus·vectors 重生 / 視覺定調——錯誤會污染全下游 |
| **施工 AI（其他 AGENT）** | A2、A3、A6、A7–A10、**A10b**、**UI-F、UI-G**、A11 腳本撰寫、B2–B9、C1–C7、**E2（文件＋腳本；執行=USER-GATE）、E3–E7、EC-1／EC-2／EC-4、EC-3（文件；執行=USER-GATE）**、其餘 | 有 corpus/vectors/grep gate 自動抓偷工，爆炸半徑受控 |

- 施工 AI **不得**執行分工表中主理 AI 的任務；遇到依賴時走 G8 BLOCKED。
- DL 任務（設計語言規範 + Web 範本）已由主理 AI 交付：規範 =
  `docs/DESIGN_LANGUAGE.md`（G6 凍結）；範本 = `ignirelay-gateway/webapp/`
  （`tokens.css`/`app.css`/`index.html`/`app.js`/`DESIGN_README.md`）。
  **任何 UI 任務（A7–A10、C3）開工前必須先讀 `DESIGN_LANGUAGE.md` 全文**，
  其 §6 enforcement gates 視同該任務 DoD 的必要項。

---

## §1 產品全貌（最終成品定義）

### 1.1 一句話

**讓每個帶手機的人「被看見、能求救、留下最後足跡」。有網路的場域（營區、賽事、
工地、校外活動）：手機直接走網際網路上 Owner 的雲端服務，場域主在任何地方用瀏覽器
看全場。完全沒有行動網路、沒有網際網路的場域（登山步道、礦場、災區、巡檢路線）：
靠手機 BLE mesh 與實體節點接力，管理者在現場的本地網頁後台即時看到全場狀態、匯出紀錄。
兩種形態＝同一個 App、同一個 QR 加入流程、同一種事件信封、同一套後台設計語言（v1.2）。
「場域」本身就是可販售的服務單位；硬體是場域的離線增強包。**

### 1.2 系統組件與資料流

```
[手機 App] --BLE GATT (EventEnvelope v3, Ed25519+field_mac)--> [Field Node ×N]
     |  ^                                                          |   ^
     |  └-- BLE 廣播 / 同步 / 手機↔手機 mesh（fallback、Data Mule）  |   |
     |                                              LoRa (LORA-WIRE v1, |
     |                                               HMAC+CRC, 64–128B) |
     v                                                          v   |
[手機 App（其他人）]                                      [Gateway (PC→Pi)]
                                                              |
                                              SQLite (events/routes/packets)
                                                              |
                                                HTTP API (token, LAN only)
                                                              |
                                              [管理者瀏覽器：Web 後台]
```

```
（v1.2 新增）網際網路路徑——與上圖並行存在，事件同一格式（信封原樣位元組）：

[手機 App] ----HTTPS POST /api/v1/ingest（信封 b64 批次，TLS）----> [VPS 雲端場域服務]
[Gateway]  ----HTTPS 批次同步（現場有回程網路時，僅上行）---------^        |
                                                  SQLite（多場域）+ 角色/可見性政策
                                                                         |
                                  [場域主/工作人員瀏覽器：雲端後台（網域 + HTTPS）]

（v1.3 新增）EC 跨專案串接——黏合層全在本專案側，E-CARE 程式碼零改動：

[手機 App] --SOS 後援 AI 對話（HTTPS＋金鑰）--> [VPS /ecare/ 代理] --tunnel--> [E-CARE 後端（學校資源：FastAPI+LLM）]
[VPS 雲端場域服務] --SOS 通報轉發（EC-2 adapter）------^
```

- **手機 App**（Flutter/Android 優先；iOS source-parity 保留、延後驗證）：
  發 PRESENCE / SOS / HAZARD / CHECKPOINT，收 ADMIN_BROADCAST，mapless 顯示
  「最後可信位置」。手機↔手機 BLE mesh 保留作為軟體驗證與後備接力。
- **Field Node**（nRF54L15 + SX1262；Stage B 先用 Zephyr 模擬器）：BLE 收手機事件、
  驗章驗 MAC、去重、優先佇列、LoRa store-and-forward 轉送到 Gateway。
- **Gateway**（Stage B/C 跑在 PC 的 Python；Stage D 移到 Raspberry Pi）：收 LoRa 封包、
  驗 MAC/CRC/replay、every event_id 存一筆 canonical、HTTP API + Web 後台 + CSV/JSON 匯出。
- **Web 後台**：與 Gateway 同主機（或同 LAN 的 PC）提供；純本地、零外網依賴；
  token 驗證；事件總表、SOS 看板、人員最後足跡、節點健康、匯出。
- **雲端場域服務（v1.2，Stage E，跑在 Owner VPS）**：多場域（一台伺服器服務多個
  場域主的多個場域）；場域主帳號＋工作人員（staff QR）＋一般成員（member QR）三種
  角色；與現場閘道**同一套信封驗證管線**；可見性政策（member 之間是否互見足跡，
  SOS 永不受政策遮蔽）；場域自訂地圖（場域主上傳圖＋對位點配準）；
  角色與政策只存在服務層，**不進 wire**。v1 無自助註冊、無金流——Owner 以 CLI
  手動開通場域即商業流程。
- **E-CARE 跨專案串接（v1.3，Stage E「EC 系列」）**：SOS 後援 AI 對話（App 直連、
  經 VPS 代理）＋SOS 案件自動通報入 E-CARE 儀表板＋本後台「E-CARE 通報」分頁。
  E-CARE 跑在學校資源、其程式碼零改動；SOS 本體對 E-CARE 零依賴（OD-13）。

### 1.3 三段信任邊界（安全模型，AGENT 不得弱化）

| 邊界 | 機制 | 規格 |
|---|---|---|
| 手機 ↔ 手機 / 手機 ↔ Node（BLE） | EventEnvelope **v3**：Ed25519 作者簽章 + `field_id`（簽進 canonical）+ `field_mac`（HMAC-SHA256 場域成員證明，截 16B），141-byte canonical | `envelope_v2_spec` §21（已凍結） |
| Node ↔ Node ↔ Gateway（LoRa） | **LORA-WIRE v1** 緊湊框架：`field_tag` 預過濾 + `mac8`（HMAC-SHA256 截 8B，金鑰 HKDF 自 `field_join_secret` 域分隔派生）+ CRC16 + event_id 去重 + HLC 窗口防重放。**作者 Ed25519 簽章不過 LoRa**（見 OD-2 信任模型） | 本文件附錄 C（B1 凍結） |
| Gateway ↔ 瀏覽器（LAN HTTP） | Bearer token（本地設定檔）、僅綁 LAN、零外網資源 | 本文件附錄 D（C1 凍結） |
| 手機 / Gateway ↔ 雲端（網際網路，v1.2） | TLS（網域憑證）＋**信封自證**：雲端以與現場閘道**同一驗證管線**重驗 Ed25519＋field_mac＋去重＋HLC 重放窗（每場域 secret 由 Owner 佈建，OD-9）＋rate limit。後台登入=owner/staff 帳密＋session。角色/可見性=服務層資料，不進 wire（OD-11） | 本文件 Stage E（E1 凍結） |
| 手機 / 雲端 ↔ E-CARE（跨專案，v1.3） | 一律經 Owner VPS 反向代理＋per-field 金鑰（學校機器不開公網）；只送事件欄位、禁 PII（`/users` 與 `user_context` 禁用）；送出資料視同離開本系統信任邊界、場域條款須揭露（OD-13）；E-CARE 不可用＝正常態（App 無聲降級）；SOS 本體對 E-CARE 零依賴 | 本文件 Stage E「EC 系列」 |

### 1.4 最終完成定義（FINAL DoD — 整個專案算「完成」的條件）

全部滿足才算完成；缺一即未完成：

1. Stage A Exit（§5.13）全項通過：App 在兩台 Android 實機上完成場域加入、
   PRESENCE/SOS/HAZARD/CHECKPOINT 收發、mapless 位置呈現（A10 卡片＋A10b 雷達），
   所有自動化 gate 綠。
2. Stage B Exit（§6.11）全項通過：模擬 Field Node（Zephyr bsim/native 雙目標）+
   模擬 LoRa 通道 + Gateway，以**真實契約位元組**（非 JSON 占位）跑通
   FakePhone→NodeA→LoRa→NodeB→Gateway→SQLite/匯出，chaos 不變量全綠，
   實機編譯目標 build 過、RAM 報告達標，硬體採購 gate 報告產出。
3. Stage C Exit（§7.8）全項通過：瀏覽器在同 LAN 另一台（或同一台）PC 上，
   於 lab 情境執行中 ≤5 秒看到新 SOS 出現在 Web 看板；token 未帶 → 401；
   匯出可下載；全程零外網請求。
4. Stage E Exit（§E.8）全項通過：雲端場域服務於 Owner VPS 上線（網域＋HTTPS）、
   多場域/角色/可見性政策生效、手機與現場閘道雙路上行、場域自訂地圖於 App 與
   後台疊加顯示、Owner 自外網瀏覽器完成驗收回填。
5. Stage D Exit（§8）全項通過：實體 2+ 節點 bench 對傳、真手機→真 Node→LoRa→Gateway
   →Web 全鏈路 demo、戶外場試報告產出。
6. 所有「凍結契約」檔案（附錄 B）版本一致、conformance/vectors 各端（Dart/Kotlin/C/Python）對齊。

---

## §2 現況盤點（2026-06-10 基線稽核，以實際指令輸出為證）

### 2.1 App repo（`IgniRelay/ignirelay_app`）

**已完成（git 已落地）**：Phase 0a fork；Phase 0b teardown #1–#3B-4（舊產品 UI/地圖/媒合/聊天/DB 表全清）；
#4-1/#4-1r（`LocationEvidence`/`PresenceData`/`CheckpointData`/`HazardMarkerData`/`AdminBroadcastData`
手寫 payload structs，位於 `lib/app/proto/event_envelope_v2.dart:1039` 起）；#4-2（`EventTypeV2` 加
`PRESENCE=3`/`CHECKPOINT=4`/`ADMIN_BROADCAST=82`，LWW/priority/maxHops 條目）；#4-3（**field-auth
protocol v3 已落地 Dart 側**：信封欄位 14 `field_id` + 15 `field_mac`、canonical 124→141、pv=3、
`FieldAuthV2`/`FieldKeyStore` 新檔、HELLO 同步升 v3、corpus 整批重生為 `v0.3-phase0b-4-3-1`、
DB purge migration）。

**基線驗證輸出（2026-06-10 實測）**：

```
dart run tool/check_layers.dart --strict   → [check_layers] ok — no boundary violations
flutter analyze --no-fatal-infos --no-fatal-warnings → 0 errors（2 個 info，battery_optimization_guide）
flutter test --exclude-tags golden         → 467 passed / ~3 skipped / **2 FAILED** ← 基線非全綠！
python -m unittest（ignirelay-lab）        → 13 OK
python -m unittest（ignirelay-gateway）    → 3 OK
```

**兩個紅燈（A0 的工作對象）**：

1. `test/controllers/envelope_pipeline_v2_test.dart:299`
   `strict drop reasons unknown-protocol-version emits DispatchDropped + trace`
   — 期望 `DispatchDropped` 實得 `DispatchAccepted`。**疑似 4-3 落地時 dispatcher
   版本檢查路徑的真實回歸**（這是 wire 安全門），必須查根因，不得只改測試。
2. `test/services/v2_inbound_projector_test.dart:165`
   `SOS-class status update projects to a v1 SOS alert`
   — 期望 `'?'` 實得 `'受困'`。**測試檔本身編碼損毀**（中文字面值與 `→` 箭頭被寫壞成
   `?`/`??`），產品行為正確；修復方向是還原測試檔 UTF-8 字面值。

**未完成（精確清單）**：

| # | 缺口 | 證據 |
|---|---|---|
| 1 | **4-3b Kotlin/Swift parity 未做**：`IgniRelayConstants.kt:37` 仍 `PROTOCOL_VERSION_V2 = 2`；`IgniRelayConstants.swift:35` 同；`WireConformanceInstrumentationTest.kt` 仍斷言舊 corpus 版號 `v0.3-stage0c-wave3d-1`（現為 `v0.3-phase0b-4-3-1`，一跑就紅）；`tool/check_constants_parity.dart` 註解明寫 PROTOCOL_VERSION parity「DEFERRED to 4-3b」 |
| 2 | **4-4 PRESENCE 未接線**：facade 無 `publishPresence`；`V2InboundProjector` 無 PRESENCE case；`debug_shell.dart` 的「發 PRESENCE / 發 SOS」按鈕是 `_todoWire` 占位 |
| 3 | **4-5 HAZARD 仍是 JSON shim**：`publishHazardMarker` 收 raw bytes，projector 解 JSON shim，未用 4-1 的 typed `HazardMarkerData` |
| 4 | **4-6 SOS 位置未定未做**：`StatusUpdateData` 無 location 欄位（本文件 OD-1 定案：採選項 A） |
| 5 | **4-7 場域 plumbing 未做**：production `FieldKeyStore.empty()`、dispatcher `enableFieldScopeCheck` 預設 OFF 且 `main.dart:163` 未傳 `fieldKeys`；無 join 流程、無場域持久化 |
| 6 | **舊產品殘留**：facade 仍有 `publishChatMessage`（chat UI 已刪）；`main.dart` 仍 `MeshRuntimeController.instance`（R4 既知，第二刀清） |
| 7 | dispatcher 三個 spec-strict 開關（clockExpiry/maxHopsOvercommit/fieldScope）**測試端預設 OFF**，「flip defaults globally」的 QA 收尾未做 |
| 8 | 雙機實機行為驗證（Phase 0b exit gate）未執行 |

### 2.2 三個 sibling repo（皆為 2026-06-10 初始 commit 的 spike 骨架）

| Repo | 已有 | 關鍵缺口（其 STATUS.md 自承） |
|---|---|---|
| field-node | Zephyr app 骨架（bsim+dk 兩 target 的 build 指令）、core C 模組（event/queue/dedupe/retry 介面）、`fake_lora_transport.c`/`sx1262_lora_transport.c` stub、結構化 log、ztest 骨架 | `west`/NCS **本機未安裝**（任何 build/ztest 都沒真正跑過）；全部契約是 `TODO_CONTRACT_PLACEHOLDER`；無 MAC/checksum 實作 |
| gateway | Python CLI + SQLite（`events`/`event_routes`/`packet_logs`）、event_id 去重、CSV/JSON 匯出、3 個測試 | 封包是 **fake JSON 占位**（`security_placeholder` 欄位）；無真驗證（MAC/CRC/replay/expiry 都是 checkpoint 欄位）；**無 Web/API** |
| lab | FakePhone/SimNode A/B/FakeLoRaChannel/FakeGatewaySink + GatewayCliSink、9 個情境（normal/loss_20/busy_sos/reboot×2/duplicate_storm/replay/expired）、chaos profile、JSONL log、13 測試 | payload 是「刻意極小的 fake JSON dict」，**不代表任何真實 wire**；無 Bloom/IBLT 模型；replay/expired 是占位檢查 |

> 三個 sibling 的共同 blocker 都是「契約未凍結」。本計畫在 Stage A 末（A12）與 Stage B 初（B1）
> 把契約釘死，之後 sibling 才從占位升級成真位元組。

---

## §3 全域施工規則（G1–G18）— 每一條都是硬規則

> **這些規則的目的：讓「宣稱完成」與「實際完成」之間沒有任何縫隙。**
> 任何一條被違反，該任務視同 FAIL，Owner 稽核時會回退（revert）該任務的全部 commit。

- **G1（證據優先）**：「完成」的唯一定義 = 該任務 DoD 每一項都有對應證據。證據 = 驗證指令的
  **原樣指令文字 + exit code + 輸出末 20 行以上**，貼在 commit body 或該 repo `STATUS.md` 的任務條目。
  沒有證據 = 未完成。「我已確認」「應該沒問題」「理論上會過」等文字**不是證據**。
- **G2（Gate 不可動）**：禁止修改任何驗證指令、測試門檻、斷言強度、CI workflow、
  `tool/check_layers.dart`、`tool/check_constants_parity.dart`、corpus 數量門檻，來讓紅燈變綠。
  若懷疑 gate 本身有錯：停下 → 走 G8 BLOCKED 流程 → Owner 書面核准後才能改，且 gate 修改必須是
  **獨立 commit**，訊息開頭 `GATE-CHANGE:`，附理由與核准出處。
- **G3（測試不可繞）**：禁止新增 `skip`/`tags`/`--exclude` 來繞過既有測試；禁止刪除測試；
  禁止把會失敗的斷言改弱（例外見 G3a）。每個新功能任務必須新增測試，且測試必須真的測到該功能
  的行為（不是只測「函式可以被呼叫」）。
  - **G3a（測試修正的唯一合法情形）**：當查明**測試本身是錯的**（如 A0 的編碼損毀、或斷言寫錯規格），
    可以修測試，但 commit body 必須含：(a) 根因分析（為什麼測試錯）；(b) 規格出處（證明新斷言才符合
    spec）；(c) 修改前後斷言對照。缺任一項視同違反 G3。
- **G4（不可假實作）**：禁止 hardcode 預期輸出、禁止用常數回傳值騙過驗證、禁止 stub/mock 取代
  **受測物本身**、禁止 `try/catch` 吞錯讓流程「看起來成功」。mock/fake 只允許用在單元測試裡替代
  「受測物以外的依賴」。凡 spec 規定的位元組、雜湊、簽章、MAC，**必須真算**——以 corpus/vectors
  比對為準。佔位字串（`TODO_CONTRACT_PLACEHOLDER` 等）在指定任務（B3/B4/B6）完成後必須為 0
  （以 grep gate 驗證）。
- **G5（範圍紀律）**：一任務一刀。diff 中出現任務範圍外的檔案（重構順手改、格式化整檔、無關 rename）
  → 該任務 FAIL。需要的前置重構自成一個任務向 Owner 提出。
- **G6（契約凍結）**：附錄 B 清單中的檔案 = 凍結。修改唯一合法路徑：Owner 明確核准 → 版本 bump →
  以 generator 重生 corpus/vectors → 排程三端 parity 任務。AGENT 不得以任何理由（「更優雅」「更省
  位元組」）自行改契約。
- **G7（corpus 單一來源）**：`docs/specs/wire_conformance_v1.json` 與一切 vector 檔**只能由
  generator 重生**（`tool/generate_wire_conformance_v1.dart` 等），禁止手編 JSON。generator 本身的
  修改視同契約修改（走 G6）。**同刀規則（v1.1 增補）**：任何 `corpus_revision` / vectors meta
  版本字串變更，必須在**同一個任務的同一刀**內，同步更新所有硬編該字串的三端測試
  （Kotlin `WireConformanceInstrumentationTest.kt`、Swift `WireConformanceTests.swift`、
  Dart conformance 測試）並各自跑綠後才算完成；漏任一端 = 該任務 FAIL。
  （教訓來源：4-3 bump corpus 後漏改 Kotlin/Swift 斷言，跨端不一致由 A1 補修。）
- **G8（BLOCKED 程序）**：遇到（a）環境缺工具、（b）需要 Owner 決策、（c）gate 與 spec 衝突、
  （d）發現本計畫錯誤——一律：在該 repo `STATUS.md` 寫 `BLOCKED` 條目（§10 模板），說明已嘗試什麼，
  **然後停止該任務**。禁止繞道、禁止自行代替 Owner 做契約級決策、禁止假完成。
- **G9（STATUS 即時性）**：每個任務開工時與結束時都必須更新該 repo 的 `STATUS.md`（§10 模板）。
  DONE 條目必須含 commit hash；沒有 hash 的 DONE 無效。
- **G10（commit 紀律）**：commit message 格式 `[<TaskID>] <一行摘要>`；body 含 DoD 勾選清單與
  G1 證據。一個任務可拆多個 commit，但**禁止一個 commit 混多個任務**。禁止 force-push 改寫已記錄
  在 STATUS.md 的歷史。
- **G11（本計畫唯讀）**：AGENT **不得編輯本文件**（包括打勾、改措辭、「順手修正」）。進度只記在
  各 repo `STATUS.md`。本計畫的修訂只能由 Owner（或 Owner 明示授權的 session）執行，需 bump 版號
  並在文末 changelog 記錄。
- **G12（USER-GATE / ENV-GATE）**：標 `USER-GATE` 的步驟（實機雙機測試、買硬體、跨機 LAN 瀏覽器
  驗收）AGENT 不得宣稱通過——只能準備好腳本、checklist 與證據表格，由 Owner 執行並回填。
  標 `ENV-GATE` 的步驟（安裝 NCS/west、Android emulator 等大型環境）需先在 STATUS.md 列出
  將安裝什麼、占用多少空間，取得 Owner 同意後才動手。
- **G13（依賴白名單）**：各 repo 允許新增的第三方依賴**只限附錄 F 清單**（含版本 pin）。
  清單外的依賴一律走 G8 問 Owner。理由欄不可空白。
- **G14（安全紅線）**：禁止弱化任何密碼學（縮短金鑰、跳過 verify、註解掉簽章檢查、把 MAC 比對改
  `startsWith`）；禁止在 log/匯出印出 `field_join_secret` 或私鑰；禁止把任何真實 secret 寫進版控。
  測試金鑰必須與 corpus 既有測試金鑰一致或明確標示 `TEST-ONLY`。
- **G15（完成宣告語言）**：STATUS.md 只有三種狀態：`DONE`（DoD 全項有證據）、`PARTIAL`（列出
  已完成項與缺項）、`BLOCKED`。禁止使用「基本完成」「大致可用」「應該可以」等模糊宣告。
- **G16（跨 repo 邊界）**：sibling repo 永遠不得發明契約。一切 wire/GATT/金鑰/封包格式以 App repo
  `docs/specs/` 為準。發現 spec 不足以實作 → G8 BLOCKED 提需求，不得自行補洞。
- **G17（驗證指令逐字執行）**：DoD 的驗證指令必須**原樣**執行（同參數、同目錄）。換指令、加參數、
  只跑子集然後宣稱等效——視同未驗證。指令在該環境確實無法執行時走 G8。
- **G18（紅燈即停）**：任何 gate 紅燈時，禁止繼續往下一個任務疊代碼。先修紅燈（或 BLOCKED），
  再前進。「先做完再一起修」不被允許。

### 3.1 任務完成定義（DoD）結構說明

每個任務的 DoD 區塊格式固定如下，AGENT 回報時必須逐項對應：

```
DoD：
  D1 …（可客觀驗證的敘述）
  D2 …
驗證（G17：逐字執行，全部 exit 0）：
  V1: <指令>            期望：<明確輸出特徵>
  V2: …
證據：commit body / STATUS.md 條目，含 V1..Vn 輸出
禁止：<該任務特定的禁止清單>
```

### 3.2 通用驗證指令組（後文以代號引用）

| 代號 | 指令（於 `IgniRelay/ignirelay_app/` 執行） | 通過標準 |
|---|---|---|
| **GATE-LAYERS** | `dart run tool/check_layers.dart --strict` | 輸出 `ok — no boundary violations`，exit 0 |
| **GATE-ANALYZE** | `flutter analyze --no-fatal-infos --no-fatal-warnings` | 0 個 `error`，exit 0 |
| **GATE-TEST** | `flutter test --exclude-tags golden` | 末行 `All tests passed!`，exit 0；**禁止以管線截斷 exit code**（不得接 `\| tail` 後拿管線 exit 0 當證據；要截尾請先存檔再截） |
| **GATE-PARITY** | `dart run tool/check_constants_parity.dart` | exit 0 |
| **GATE-CONF-DART** | `flutter test test/conformance/wire_conformance_corpus_test.dart` | 全綠 |
| **GATE-KOTLIN-BUILD** | `cd android; .\gradlew.bat :app:assembleDebugAndroidTest` | BUILD SUCCESSFUL |
| **GATE-KOTLIN-RUN** *(ENV-GATE：需 Android 裝置或 emulator)* | `cd android; .\gradlew.bat :app:connectedDebugAndroidTest` | 全綠 |
| **GATE-LAB** | （於 lab repo）`python -m unittest discover -s tests` | `OK` |
| **GATE-GW** | （於 gateway repo）`python -m unittest discover -s tests` | `OK` |
| **GATE-SCEN** | （於 lab repo）`python -m ignirelay_lab.cli --all` | 全情境 PASS、exit 0 |

---

## §4 里程碑總覽與依賴

```
Stage A（App 完成）
 A0 基線修復(2紅燈) ──► A1 4-3b Kotlin/Swift parity
 A0 ──► A2 PRESENCE 接線(4-4) ──► A3 HAZARD typed(4-5) ──► A4 SOS location(4-6)
 A2..A4 ──► A5 FieldSession + field-scope 開啟(4-7) ──► A6 殘留清理
 A5 ──► A7 場域加入 UX(QR/代碼) ──► A8 SOS UX ──► A9 PRESENCE beacon/CHECKPOINT/ADMIN UI
 A2..A9 ──► A10 mapless 位置呈現 ──► A10b 雷達視圖 ──► UI-F 正式AppShell+motion-aware定位
 UI-F ──► UI-G 先看功能/引導模式 ──► A11 雙機驗證(USER-GATE) ──► A12 App↔Node 契約凍結
Stage B（模擬器：Node + Gateway）
 B1 契約包凍結(需A12) ──► B2 Python 參考實作(可並行於A5後) ──► B3 lab 真位元組化
 B3 ──► B4 gateway 真驗證化
 B5 Zephyr 環境(ENV-GATE,可並行) ──► B6 field-node 真實作 ──► B7 模擬 E2E
 B7 ──► B8 chaos 全綠 ──► B9 實機目標 build+RAM ──► B10 採購 gate 報告
Stage C（Web 管理端，LAN 形態）
 C1 API 規格凍結(需B4) ──► C2 API server ──► C3 Web UI ──► C4 E2E 即時看板
 C4 ──► C5 LAN 部署(USER-GATE) ──► C6 匯出強化 ──► C7 安全基線
Stage E（雲端場域服務；前置：Stage C Exit）
 E1 雲端契約+地圖校準凍結(需C1) ──► E3 雲端伺服器(多場域) ──► E4 App 雲端整合 ──► E6 雲端後台 ──► E7 場域自訂地圖(另需A10)
 E2 VPS/網域/TLS 佈建(USER-GATE；可在 E1 進行中先做) ──► E3 的部署驗收
 E3 ──► E5 閘道↔雲端同步
 （v1.3）E4 ──► EC-1 App SOS 後援對話；E3 ──► EC-2 雲端→E-CARE 通報轉發 ──► EC-4 後台 E-CARE 分頁(另需E6)
 （v1.3）E2 ──► EC-3 E-CARE 代理佈建(USER-GATE) ──► EC 實連驗收(§E.8 第 5 項)
Stage D（實體硬體；需 B10 + Owner 採購；全程可與 Stage E 並行）
 D1 採購與開箱 ──► D2 bench bring-up ──► D3 真手機↔真Node ──► D4 Node→LoRa→GW→Web ──► D5 場試
```

允許的並行：A1 與 A2 可並行（不同端）；B2 可在 A5 之後先行（v3 信封規格已凍結）；
B5 環境安裝可隨時先做（經 Owner 同意）；C1–C3 可在 B4 後與 B6–B9 並行；
**Stage D 與 Stage E 互不依賴，可整段並行**；E2 不依賴 E1 的契約內容，可先做；
EC-1／EC-2／EC-4 以 mock 開發、可與 E5–E7 並行（實連驗收需 EC-3 完成）。

---

## §5 Stage A — 把 App 做完

> Stage A 全程在 App repo。每個任務收尾必跑：GATE-LAYERS、GATE-ANALYZE、GATE-TEST、
> GATE-PARITY（動到常數時）、GATE-CONF-DART（動到 wire 時）。以下不再重複列，
> **視為每個 A 任務 DoD 的隱含必要項**。
>
> **A7–A10、A10b 共同追加 DoD（設計，v1.1；v1.2 將 A10b 納入）**：畫面實作必須遵守
> `docs/DESIGN_LANGUAGE.md` §4（IgniPalette/IgniTokens/既有 `ui/widgets/` 元件、
> showcase 同步、急難可及性、§3.6 位置文案鐵則）與 §5 禁用清單；
> 結案驗證追加 `grep -rn "Colors\." lib/ui/screens/ | grep -v debug_shell.dart`
> 輸出為 0（debug_shell 為既存豁免，A7+ 汰換時一併清除豁免）。

### A0 — 基線修復：把 2 個紅燈修成綠（最高優先，其他任務一律排後）

**背景**：§2.1 兩個紅燈。4-3 commit 宣稱全綠但實測 2 紅——這正是本計畫要杜絕的行為。

**步驟**：
1. **紅燈 #1（envelope_pipeline_v2_test.dart:299）**：先讀
   `lib/app/controllers/envelope_dispatcher_v2.dart` 的 protocol_version 檢查路徑與
   4-3 diff（`git show f8d4b96 -- ignirelay_app/lib/app/controllers/envelope_dispatcher_v2.dart`），
   判定是（a）dispatcher 真回歸——pv≠3 的信封被接受（**安全問題**，修 dispatcher）；或
   （b）4-3 改變了檢查時序（如 decode 階段先拒），測試構造方式已不再觸發該路徑——此時依 G3a
   修測試，使其重新覆蓋「pv≠3 → `unknown-protocol-version` drop + trace」這條 spec 行為
   （spec §21.2/§21.8），不得刪除或弱化此覆蓋。
2. **紅燈 #2（v2_inbound_projector_test.dart）**：確認檔案編碼損毀範圍（`'?'`、`??`），
   還原為正確 UTF-8 字面值（期望值應為產品實際輸出 `'受困'` 一類的本地化字串——以
   `lib/` 內對應常數為準，不得反過來改產品字串遷就壞測試）。檢查同檔其他被損毀的字面值一併還原。
3. 排查還有沒有其他「測試檔被編碼損毀」的檔案：`grep -rn "??" test/ --include=*.dart` 人工過濾
   測試名中可疑的 `??`（原為 `→`），一併修復並在 commit body 列出清單。

**DoD**：
- D1 紅燈 #1 根因寫明（dispatcher 回歸或測試時序），對應修復落地；`unknown-protocol-version`
  行為仍被測試覆蓋（指出測試名）。
- D2 紅燈 #2 修復，期望值與產品實際本地化輸出一致。
- D3 GATE-TEST 全綠（`All tests passed!`）。

**驗證**：GATE-TEST、GATE-CONF-DART、GATE-LAYERS、GATE-ANALYZE。
**證據**：commit body 貼 GATE-TEST 末 20 行 + 紅燈 #1 根因分析。
**禁止**：刪除任一測試；把 `expect(...DispatchDropped...)` 改成接受 Accepted；
用 `--plain-name` 只跑兩個測試就宣稱全綠（G17）。

---

### A1 — 4-3b：Kotlin / Swift v3 parity（可與 A2 並行）

**步驟**：
1. `android/.../IgniRelayConstants.kt`：`PROTOCOL_VERSION_V2 = 2` → 新增
   `PROTOCOL_VERSION_V3 = 3` 並移除/棄用 V2 常數（與 Dart `kProtocolVersionV3` 對齊；
   Amendment §8.1 建議常數名與值一致，不留「名 V2 值 3」的誤導）。
2. `ios/Runner/IgniRelayConstants.swift` 同步（source parity；iOS 不是本階段 gate—R3 立場）。
3. `tool/check_constants_parity.dart`：依檔內註解把 `PROTOCOL_VERSION_V3` 條目加回
   `_specs`（dartName: `kProtocolVersionV3`）。
4. `WireConformanceInstrumentationTest.kt`：corpus 斷言更新——`corpus_revision` →
   `"v0.3-phase0b-4-3-1"`（以 `docs/specs/wire_conformance_v1.json` 現值為準，不得 hardcode 舊值）；
   檢查 `negative_cases`/`envelope_samples` 門檻仍滿足（新 corpus 數量只增不減）。
5. `ios/RunnerTests/WireConformanceTests.swift` 的 metadata 斷言同步。
6. 確認 Kotlin/Swift 的 IBLT/Bloom/chunking parity 測試對新 corpus 仍綠
   （這三個 slice 在 4-3 未變層，理論上不受影響——仍須實證）。

**DoD**：
- D1 三端常數一致，GATE-PARITY 綠（含 PROTOCOL_VERSION_V3 條目）。
- D2 GATE-KOTLIN-BUILD 綠（instrumentation APK 可編譯）。
- D3 *(ENV-GATE)* GATE-KOTLIN-RUN 於 Android 裝置/emulator 全綠；無裝置時：STATUS.md 記
  `PARTIAL`+缺 D3，**不得宣稱 DONE**，並把 D3 移交 A11 雙機驗證時一併執行。
- D4 Swift 檔案修改完成（source parity）；macOS 不可用 → 在 STATUS 註記「Swift 未編譯驗證
  （R3 既知）」。

**驗證**：GATE-PARITY、GATE-KOTLIN-BUILD、（有環境則）GATE-KOTLIN-RUN、GATE-TEST。
**禁止**：調低 instrumentation 測試的數量門檻；為過編譯而註解掉測試方法。

---

### A2 — 4-4：PRESENCE 發佈/接收/顯示接線

**設計輸入**：`PHASE0B4_WIRE_DESIGN.md` §4 表、`PresenceData`（`event_envelope_v2.dart:1200`）、
`LocationEvidence`（同檔 :1039）。

**步驟**：
1. **匿名身分（OD-7）**：新 service `lib/app/services/anon_identity.dart` —— 首次啟動產 16B
   隨機 `anon_user_id` 存 `flutter_secure_storage`（key `anon_user_id_v1`）；提供
   `Future<Uint8List> getOrCreate()`。輪換 API 留介面、Phase 2 實作。**不得**拿 Ed25519
   pubkey 當 anon id（隱私分離）。
2. **位置證據**：`lib/app/services/location_evidence_builder.dart` —— 包 `location_service`：
   GPS 可用→`LocationEvidence(source: GPS, frame: SUBJECT, lat/lng 1e7 round-to-nearest,
   accuracy, observed_at=HLC.now)`；GPS 不可用→回 `null`（anchor/PDR 留 A10/Phase 1）。
   單元測試覆蓋 1e7 round（含 `25.0339805` 這個已知 IEEE-754 陷阱值，見 PHASE0B4 §3.1 注）。
3. **發佈面**：`EventPublisherV2Facade.publishPresence({required Uint8List anonUserId,
   LocationEvidence? location, int? batteryHint})` → `_broadcast(eventType:
   EventTypeV2.presence, priority: PriorityV2.normal, payload: PresenceData(...).encode(),
   ttlOffset: <spec §11.2 PRESENCE 預設；spec 未列則用 6h 並同步補進 spec §11.2 表（走 G6 流程，
   屬 4-2 已核准事件的 TTL 補遺）>, maxHops: EventTypeV2.maxHopsDefault(presence)=4)`。
4. **field_id 過渡（4-4 暫行，A5 收回）**：`MessagePublisherV2.send` 已要求 `fieldId`。
   本任務允許引入 `kDebugFieldJoinSecretHex`（**TEST-ONLY 註記 + `@visibleForTesting`**，
   值任選 32B），由它派生 field_id/mac_key 餵 publisher 與一個 `FieldKeyStore.fromSecrets`
   實例（dispatcher 端 check 此時仍 OFF）。**A5 的 DoD 含「此常數從 production 程式碼徹底移除」
  （grep gate）**。
   > **排程注意（v1.1）**：A5 由主理 AI 負責且可能先於 A2 落地。若開工時
   > `ActiveFieldController`/`FieldSessionStore` 已存在（A5 已 DONE），**跳過本步驟**，
   > 直接從 ActiveFieldController 取 fieldId/macKey，禁止再引入 debug 常數。
5. **接收投影**：`V2InboundProjector` 加 `case EventTypeV2.presence → _projectPresence`：
   解 `PresenceData`，寫入 `Event_Logs` read-model（id=`v2-<hex>` 前綴沿用；read-model 的
   event_type 用既有 v1 enum 無對應 → 依 projector 現行模式擴一個 read-model 專用值，
   **明確註記「local read-model only, never on wire」**）。內容欄存 JSON snapshot：
   `{anon8: <hex8>, src, lat?, lng?, acc?, battery?, observed_ms}` 供 UI 渲染。
6. **EventStream**：加 typed stream `presenceUpdates`（沿用既有 typed-stream 模式），
   debug shell 訂閱刷新。
7. **Debug shell 接線**：`_todoWire('PRESENCE')` → 真呼叫
   `context.read<EventPublisherV2Facade>().publishPresence(...)`，顯示 `BroadcastOutcome`
   （sent/queued/peer 數）。位置卡片從占位改為渲染「最近 PRESENCE evidence 清單
   （anon8 / 來源 / 時間 / 經緯或 anchor）」。
8. **測試**：facade publish 單元測試（payload bytes 解回對齊）、projector PRESENCE 投影測試
   （含 dedup：同 envelope 投影兩次→一筆）、debug shell smoke 更新（按鈕不再是占位）。

**DoD**：
- D1 `publishPresence` 全鏈（facade→publisher v3 簽章+field_mac→bridge）單元測試綠。
- D2 inbound PRESENCE → `Event_Logs` 投影 + `presenceUpdates` 流測試綠（含重複投影僅一筆）。
- D3 debug shell PRESENCE 按鈕為真實作（widget test 斷言非 snackbar 占位文案）。
- D4 通用 gate 全綠（含 GATE-CONF-DART——若本任務需補 PRESENCE envelope 樣本，依 G7 用
  generator 重生並讓 GATE-KOTLIN-BUILD 維持綠）。

**驗證**：GATE-TEST、GATE-CONF-DART、GATE-LAYERS、GATE-ANALYZE。
**禁止**：把 anon_user_id 設成 author pubkey；在 UI 直接 import `lib/app/proto/**`
（層規則 #4——payload 結構由 facade/decoder 轉成 plain Dart 再給 UI）。

---

### A3 — 4-5：HAZARD 換 typed payload

**步驟**：
1. facade `publishHazardMarker` 簽名改為收結構化參數（hazardType/severity/location/description/
   isConfirmation），內部以 `HazardMarkerData.encode()` 產 payload；保留 raw-bytes 入口僅供測試
   （`@visibleForTesting`）或直接移除舊入口並修正呼叫端。
2. `V2InboundProjector._projectHazard`：JSON shim 解析 → `HazardMarkerData.decode()`；
   投影到既有 Hazards read-model 路徑維持不變。
3. 移除 shim 相關常數/註解（`hazard_marker_v0_3_json_shim`），grep 確認無殘留。
4. description 長度上限依 payload budget（spec §9 HAZARD/ALERT 800B 內）在 encode 端強制，
   超限丟 `ArgumentError`，測試覆蓋。
5. conformance：HAZARD envelope 樣本以 generator 增補 typed payload 版本（G7）。

**DoD**：D1 shim 全移除（`grep -rn "json_shim" lib/ test/` 為 0）；D2 typed 編解碼 roundtrip +
投影測試綠；D3 超長 description 拒發測試綠；D4 通用 gate + GATE-CONF-DART 綠。
**禁止**：同時保留 shim 與 typed 兩條接收路徑（會變成永久殘留）。

---

### A4 — 4-6：SOS 自帶位置（OD-1 定案 = PHASE0B4 §3.3 選項 A）

**決策（OD-1，Owner 可否決）**：`StatusUpdateData` 新增欄位 `3 location LocationEvidence`
（additive proto3，0/absent = 無位置）。理由：SOS 自含證據，不依賴「最近一筆 PRESENCE」的
配對時序；對 MCU/Gateway 的 SOS 顯示鏈最短。

**步驟**：
1. `StatusUpdateData` 加 optional `location`（欄位號 3；原 reserved 區依檔內註記調整，
   **欄位號一旦提交即凍結**）。encode/decode + roundtrip 測試。
2. facade `publishStatusUpdate`/`publishSosStatus` 接 `LocationEvidence?`（由
   `location_evidence_builder` 提供當下最佳 evidence；無 GPS → null，照發）。
3. projector `_projectStatus`：解出 location 一併寫進 read-model snapshot（SOS 列表要能
   顯示「最後可信位置」）。
4. conformance：statusUpdate 相關 envelope 樣本 payload 變 → **generator 重生**（G7），
   Dart corpus 綠 → GATE-KOTLIN-BUILD/（可行則）RUN 對齊。
5. spec 同步：`envelope_v2_spec` §5.1 proto fragment 加欄位 3 註記（G6：本文件 OD-1 即
   Owner 核准書面依據，commit message 引用 `MASTER_EXECUTION_PLAN OD-1`）。

**DoD**：D1 roundtrip + 帶位置 SOS 端到端（facade→dispatcher→projector）測試綠；
D2 無位置 SOS 不退化（向後相容測試）；D3 corpus 重生且 GATE-CONF-DART 綠；D4 通用 gate 綠；
D5（v1.1）corpus_revision bump 後，`WireConformanceInstrumentationTest.kt` 與
`WireConformanceTests.swift` 的 metadata 斷言**在同一刀內**同步更新並重過
GATE-KOTLIN-BUILD。
**禁止**：把 location 塞進 needs[] 或 note 字串等旁門位置；手改 corpus JSON。

> **施工筆記（v1.1，主理 AI 用；逐點核對後才動手）**
> 1. 欄位號實證：`StatusUpdateData.encode/decode`（`event_envelope_v2.dart:605-634`）
>    目前僅用 field 1（safetyState enum）與 2（needs repeated message）→ **field 3 可用**，
>    decode 加 `case 3:` message → `LocationEvidence.decode`；absent → Dart 端 `null`。
> 2. **payload hash 變 → 既有 statusUpdate envelope 樣本簽章全部失效**：必須跑
>    `tool/generate_wire_conformance_v1.dart` 整批重生；`corpus_revision` bump 為
>    `v0.3-phase0b-4-6-1`；generator 內**新增**帶 location 的 statusUpdate 樣本
>    （含 bearing absent 與 bearing=正北 0 兩型，覆蓋 4-1r 的 +1 編碼）。
> 3. SOS 預算：`SOS_ENVELOPE_BUDGET_BYTES = 240`（三端常數）。LocationEvidence
>    全欄位約 +38B——新增測試斷言「TRAPPED + 2 needs + 完整 location」編出的信封
>    ≤240B，超出即 fail（不是調預算，是砍欄位）。
> 4. `v2_inbound_projector.dart` `_projectStatus` 現有註解明寫 "carries no
>    location"——同刀更新註解與投影（location 進 read-model snapshot JSON）。
> 5. `test/wire_conformance/scenarios/sos_red_minimal.yaml` 等情境檔含 payload
>    期望值——以情境工具重生，不得手改 hex。
> 6. `impliedPriorityFloor()` 不受 location 影響（明確不改，加回歸測試釘住）。

---

### A5 — 4-7：FieldSession 最小落地 + field-scope 檢查開啟

**目標**：場域從「測試 shim」變成「產品事實」：本機可加入 ≥1 場域、金鑰持久化、
publisher 用真場域、**dispatcher 的 field-scope + field-mac 檢查在 production 打開**。

**步驟**：
1. `lib/app/services/field_session_store.dart`：`FieldSession{fieldIdHex, displayName,
   joinedAtMs}`；`field_join_secret` 存 `flutter_secure_storage`（key
   `field_secret_<fieldIdHex>`），session 中繼資料存 SQLite 新表 `Field_Sessions`
   （migration 走 `database_helper` 版本 bump；onUpgrade 測試比照 4-3 的 purge 測試模式）。
2. 啟動時載入全部 sessions → `FieldKeyStore.fromSecrets` → 注入
   `EnvelopeDispatcherV2(fieldKeys: ..., enableFieldScopeCheck: true)`（`main.dart:163` 處）。
3. `MessagePublisherV2` 的 fieldId/fieldMacKey 來源改為「目前作用中場域」
   （`ActiveFieldController`，單一作用場域；多場域切換 UI 留 A7）。**未加入任何場域時**：
   facade 對非 control 事件回 `BroadcastOutcome` 失敗（新欄位 `noField: true`），UI 顯示
   「尚未加入場域」。control（HELLO 等）不受影響（zero field_id 豁免，spec §21.7）。
4. Debug shell 加「場域」卡片：顯示目前場域 idHex 前 8 碼/名稱；提供「以代碼加入」對話框
   （輸入 64 hex chars 的 `field_join_secret`，僅 debug 用；QR 流程在 A7）＋「產生新場域」
   按鈕（隨機 32B secret，顯示 hex 供另一台手機輸入）。
5. **移除 A2 的 `kDebugFieldJoinSecretHex`**（production 程式碼 0 引用）。
6. 測試：join→publish→另一個 dispatcher（不同 FieldKeyStore）`field-scope-mismatch` drop；
   同場域收方 `field_mac` 驗過→accept；篡改 field_id→`signature-invalid`；
   非成員偽造 field_id→`field-mac-invalid`（複用 4-3 的 `field_auth_v2_test` 模式做整合層）。

**DoD**：
- D1 production dispatcher `enableFieldScopeCheck: true` 且注入真 FieldKeyStore（指出
  main.dart diff）。
- D2 `grep -rn "kDebugFieldJoinSecretHex" lib/` 輸出為 0。
- D3 跨場域隔離整合測試綠（mismatch/mac-invalid/accept 三態都有斷言 drop_reason）。
- D4 `Field_Sessions` migration 的 onUpgrade 單元測試綠。
- D5 通用 gate 全綠。
**禁止**：為了測試方便把 `enableFieldScopeCheck` 在 production 留 OFF；把 secret 存
SharedPreferences/SQLite 明文（必須 secure storage）。

> **施工筆記（v1.1，主理 AI 用）**
> 1. **fieldId 真正的接點是 `ble_v2_bridge.dart:285`**：`sendEnvelope()` 目前硬寫
>    `fieldId: FieldAuthV2.zeroFieldId()`（檔內註解明說等 join flow）。A5 把
>    `BleV2Bridge.sendEnvelope` 增加 `fieldId`/`fieldMacKey` 參數（或建構時注入
>    ActiveFieldController），由 facade 傳入；**`protocol_hello_service.dart:109`
>    的 zeroFieldId 是 control 框，正確，不得改**（§21.7）。
> 2. DB：`database_helper.dart` 現為 `version: 12` → `Field_Sessions` 表 bump 13；
>    onUpgrade 測試比照 4-3 的「建舊 schema→塞列→升級→斷言」模式（CI 唯一會走
>    onUpgrade 的路）。
> 3. **Outbox_V2 與場域的綁定**：信封簽章發生在 drain 時（envelope_id 先配、
>    簽章後到），若 drain 時用「當下作用場域」，切換場域會把舊佇列事件簽到新場域。
>    定案：`Outbox_V2` 加 `field_id BLOB(16)` 欄（同次 migration），enqueue 時寫入、
>    drain 時取該列場域之 macKey；該場域已離開 → 刪列並 trace。
> 4. 啟動順序：secure storage 載 secrets → `FieldKeyStore.fromSecrets`（async）→
>    才建 dispatcher（`enableFieldScopeCheck: true, fieldKeys: store`）→ bridge.start。
>    `_startV2Bridge()` 本來就 async，把 FieldKeyStore 載入插在 keypair 載入旁。
> 5. 守 production 開關的測試：新增 main-wiring 測試斷言 dispatcher 以
>    `enableFieldScopeCheck: true` 建構（防止日後被「順手」關掉）。
> 6. 多場域：v1 僅一個「作用中場域」用於發送；接收端 FieldKeyStore 可持多場域
>    （isJoined 全部成立）。切換 UI 在 A7；A5 先給 setActive API + debug 卡片。
> 7. （v1.2）`Field_Sessions` 表同刀加 `cloud_base_url TEXT NULL` 欄、
>    `FieldSession` 加對應 nullable 欄位。值由 A7 解析 QR 第 4 段時寫入；
>    Stage E（E4）之前任何程式不讀取它。無此值的離線場域行為完全不變。

---

### A6 — 舊產品殘留清理（OD-6）

**步驟**：
1. 移除 facade `publishChatMessage` 與 projector 的 `CHAT_MESSAGE` case、`EventStream` 中
   chat 相關 typed 流（若仍存在）。`EventTypeV2.chatMessage = 30` **保留為 reserved**
   （spec 編號永不重用；只是 App 不再發/收）。
2. 移除無人引用的舊產品檔案（先 `flutter analyze` + `grep` 證明 0 引用再刪）：候選
   `app/data/supply_category_data.dart`、`app/mesh/hazard_manager.dart`（若 projector 已不經
   它）、`app/services/room_display_name_resolver.dart` 等——**以引用證據為準，逐檔列清單**。
3. v1 `event_types.dart` 僅保留 read-model 還在用的值；其餘標 `@Deprecated('v1 wire legacy')`
   不刪（v1 解碼相容期仍需）。
4. spec §4.1 注記 CHAT_MESSAGE → reserved（引用本任務）。

**DoD**：D1 chat 發佈/投影路徑 0 殘留（grep `publishChatMessage|chatMessage` 在 lib/ 僅剩
enum 定義與 reserved 註記）；D2 刪檔清單逐檔附 0 引用證據；D3 通用 gate 全綠。
**禁止**：刪 `EventTypeV2` 的 enum 值或重排編號；「順手」清理本任務清單外的檔案（G5）。

---

### A7 — 場域加入 UX（QR / 代碼）

**步驟**：
1. 依附錄 F 白名單加依賴：`qr_flutter`（顯示）、`mobile_scanner`（掃描）。
2. **QR 內容格式（凍結；v1.2 修訂為五段式）**——以 `:` 分段：
   `IGNI1:<base64url(field_join_secret 32B)>:<urlencode(displayName)>[:<urlencode(cloud_base_url)>[:<urlencode(staff_invite_token)>]]`
   - 段 0 `IGNI1` 版本前綴必驗，未知前綴拒收並提示；段 1、段 2 必填。
   - 段 3（選填）＝雲端服務 base URL，**只接受 `https://` 開頭**（其餘拒收），
     寫入 `FieldSession.cloudBaseUrl`（A5 施工筆記 7 的欄位）；Stage E 前不使用。
   - 段 4（選填）＝staff 邀請 token（僅 staff QR 含此段；語意見 Stage E E1）；
     **段 4 存在而段 3 缺/空 → 整碼拒收**。
   - **前向相容鐵則**：parser 對第 5 段（含）以後的未知尾段一律忽略、不報錯
     （未來擴充不破舊版 App）；三段式舊碼（無段 3/4）完全相容。
3. UI：場域頁（建立場域→顯示 QR；掃碼加入；代碼輸入 fallback=A5 的 hex 對話框升級）；
   多場域清單 + 切換作用場域 + 離開場域（刪 secret + session row；**離開不可逆**需二次確認）。
4. 測試：QR 字串編解碼 roundtrip（三段/四段/五段三型）、壞前綴/壞長度拒收、
   段 3 非 `https://` 拒收、「有段 4 無段 3」拒收、含未知第 6 段仍正常解析、
   多場域切換後 publisher fieldId 跟著換。

**DoD**：D1 兩台裝置可憑 QR 完成同場域加入（自動化部分：QR 字串層測試綠；實機掃碼歸 A11
USER-GATE 腳本）；D2 未知前綴/壞 payload 不 crash 且有使用者提示；D3 通用 gate 綠。
**禁止**：把 secret 放進剪貼簿 log；QR 裡帶明文場域名以外的個資；
段 3 接受 `http://`（明文）URL。

### A8 — SOS UX（白皮書 §13.4）

**步驟**：
1. SOS 主畫面（debug shell 升級或新 screen，仍守 UI 層規則）：**長按 1.5s** 觸發 →
   safetyState 選擇（TRAPPED=RED / INJURED=YELLOW）→ **5 秒倒數可取消** → 發送（帶 A4 位置）。
2. 發送後狀態列：queued/sent/peers 數（吃 `BroadcastOutcome`）。
3. **取消/誤報（OD-8 定案）**：不新增 wire 事件型別；「我安全了」= 後送
   `publishStatusUpdate(safetyState: SAFE)`，LWW（spec §10.2 STATUS_UPDATE by author）讓全網
   收斂到最新狀態；UI 對同 author 顯示最新 safetyState 並把舊 SOS 標「已解除」。
4. 收方：`sosAlerts` 流驅動全螢幕/highlight 告警卡（含位置、相對時間）。
5. 測試：長按+倒數狀態機 widget test；SAFE 後 read-model 顯示解除；RED 優先級 = SOS_RED
   （§5.3 floor 已有，整合斷言）。

**DoD**：D1 狀態機測試綠（觸發/倒數/取消/送出四態）；D2 解除流測試綠；D3 通用 gate 綠。
**禁止**：跳過倒數直接發（誤觸防護是白皮書硬需求）；自行新增 `SOS_CANCELLED` wire 型別（OD-8）。

### A9 — PRESENCE 週期信標 + CHECKPOINT + ADMIN_BROADCAST 顯示

**步驟**：
1. **PRESENCE beacon**：`PresenceBeaconController`（app 層、DI 注入 facade）：mesh running 且
   已加入場域時每 **120s** 自動 `publishPresence`（電量 <20% 時 300s；參數常數化）。
   UI 開關（預設開）。測試用 fake clock。**v1.4 註記**：此為 A9 既有基線；UI-F 會以
   motion-aware policy 取代 production cadence（moving 30s、stationary 180s、low battery 降頻），
   A11 以 UI-F 的新策略驗收。
2. **CHECKPOINT**：debug 階段 = 手動按鈕 + checkpoint_id 輸入（真實流程綁 Node QR/接觸，
   Stage D）；`publishCheckpoint(CheckpointData)` + projector case + read-model 列表。
3. **ADMIN_BROADCAST 接收**：projector case `adminBroadcast` → read-model + `adminBroadcasts`
   typed 流 + UI 置頂橫幅（依 expires_at 自動下架）。發佈端：**僅 debug flag 後門**
   （`kDebugMode` 才显示「發測試公告」），正式發佈權在 Gateway/Web（Stage C/D）。
4. 測試：beacon 週期/低電降頻（fake clock）、checkpoint roundtrip、admin 過期下架。

**DoD**：D1 beacon 控制器測試綠；D2 CHECKPOINT/ADMIN 投影+UI 測試綠；D3 通用 gate 綠。
**禁止**：beacon 在未加入場域時發送；ADMIN 發佈入口出現在 release UI。

### A10 — mapless 位置呈現（PositionEstimate 本地融合）

**步驟**：
1. `lib/app/services/position_estimator.dart`（**不上 wire**，REBUILD §3.6 分層鐵則）：
   輸入某 anon8 的 evidence 集 → 輸出 `PositionEstimate{latLng?, anchorNodeId?,
   distanceM?, bearingDeg?, confidence(HIGH/MEDIUM/LOW), uncertaintyM, ageS}`。
   規則：confidence 依 evidence 年齡即時算（≤2min HIGH、≤10min MEDIUM、其後 LOW；
   uncertainty 隨時間線性增、參數常數化並寫註解出處 §3.6 原則 4）。
2. UI 卡片：每人一列「最後可信位置：<座標或 anchor> · <n 分鐘前> · 可信度 <H/M/L> ·
   誤差 ~<m>」；**文案禁止寫「目前位置」**（§3.6 原則 5）。
3. 純函式單元測試（年齡→confidence 邊界值全覆蓋）。

**DoD**：D1 estimator 純函式測試綠（邊界 2min/10min 兩側都測）；D2 UI 渲染 smoke 綠；
D3 通用 gate 綠。
**禁止**：把 confidence/uncertainty 寫進任何 wire payload 或 DB 事件列（只能即時推導）。

### A10b — 雷達相對位置視圖（v1.2 納入正式範圍；前置：A10）

**目標**：把 A10 同一份 `PositionEstimate` 資料畫成「以我為圓心」的相對位置雷達
（同心距離環＋方位點），與卡片列表雙視圖切換。**純顯示層任務：零 wire 變更、
零 DB 變更、零新依賴。**

**步驟**：
1. `lib/app/services/relative_position.dart` 純函式：輸入「本機最新 `PositionEstimate`
   ＋他人 estimates 清單」→ 輸出每人 `{distanceM, bearingDeg(0=正北、順時針 0–360),
   confidence, uncertaintyM, ageS}`。距離/方位採局部等距投影（常數與 E1 地圖校準
   規格同一組：1° lat = 110574.0 m、1° lng = 111320.0 × cos(lat₀)；lat₀=本機緯度）
   ＋ `atan2`。本機無可用位置 → 回 `null`，UI 顯示「需要本機位置才能顯示相對方位」
   並自動退回列表視圖。
2. UI：`CustomPaint` 雷達面。固定**北朝上**（v1 明確不接指南針/磁力計旋轉，列
   future——避免 sensor 權限與校準負擔）。距離環自動選檔（100/250/500 m、
   500/1000/2000 m…取能涵蓋最遠成員的最小檔，環值標在環上）。點色=狀態語意
   （SOS=sos、正常=ok、stale=灰；confidence LOW 加虛線不確定圈，半徑 =
   uncertaintyM 依當前比例尺換算）；節點/錨點畫三角形。超出最外環者釘在環緣並
   標「>環值」。點按任一點 → 開啟該人的 A10 卡片。
3. 列表 / 雷達切換（同一頁籤內 toggle，預設列表；切換狀態不持久化也可）。
4. 測試：純函式 fixtures——北/東/南/西四象限各一、跨 ±180° 經度、距離 0（同點）、
   bearing 環繞（359.x°→0°）、cos(lat₀) 在高緯度的縮放；widget smoke
   （n=0 / 1 / 8 人渲染不 crash；含 SOS 時斷言 sos 色點存在）。

**DoD**：
- D1 `relative_position` 純函式測試綠（上列 fixtures 全覆蓋；數值斷言相對誤差 ≤0.5%）。
- D2 雷達 widget smoke 綠＋列表/雷達切換測試綠。
- D3 「本機無位置」退化路徑有 widget 測試（顯示提示文案、不 crash）。
- D4 通用 gate 全綠＋A7–A10b 設計 DoD（含 `Colors.*` grep gate）。
**禁止**：引入地圖 SDK/圖磚/GIS 套件（G13 白名單外一律 G8）；把 distance/bearing
等推導值寫進任何 wire payload 或 DB（同 A10 鐵則）；使用指南針/磁力計（v1 明確不做）；
文案出現「目前位置」（§3.6 原則 5 同樣適用——雷達點是「最後可信位置」的投影）。

### UI-F — 正式 AppShell / UI-IA 重整 + motion-aware 定位節流（前置：A10b）

**依據**：`docs/APP_UI_IA_REWORK_PLAN.md` §0–§4。此任務是 Stage A 產品殼校正：
保留 BLE/event/v3 envelope/SOS/PRESENCE/位置估計等底層，將 `DebugShell` 降級為開發者診斷，
新增正式 `AppShell`。**不含「先看功能」引導模式（UI-G）**。

**v1.5 拆刀規則**：UI-F 必須分成 UI-F0～UI-F5 小任務施工（preflight、AppShell entry、module
placement、field membership、CommunicationState、motion cadence）。每一刀都要維持 gate 綠並更新
`STATUS.md`；不得用一個 commit 混完整個 UI-F。

**步驟**：
1. **正式入口 / 首次啟動**：production home 不再進 `DebugShell`。無 active field 時顯示 field entry：
   `加入場域`（掃 QR / 輸入密鑰）、`建立場域`、`先看功能`。權限策略沿用現況的一次性引導，
   並加入相機權限（QR）；相機拒絕或無相機時仍可輸入密鑰。
2. **五分頁 AppShell**：固定 tab label = `安全 | 位置 | 事件 | 協助 | 我的`。`地圖` 不作 tab 名；
   自訂地圖/配準圖層僅是 future/Stage E layer。全域層包含 active field status、communication status、
   admin/emergency overlay、global SOS action。
3. **模組搬遷**：將既有 `FieldScreen`、`SosScreen`/`SosController`、`LastSeenScreen`/`RelativeRadar`、
   `AdminBroadcastBanner`、`CheckpointCard`、`HazardCard`、`PresenceBeaconController` 移入對應分頁。
   `DebugShell` 僅可在 debug/developer diagnostics route 進入。
4. **基本角色/能力**：補最小 `FieldMembership` / `FieldCapabilityResolver`（命名可依現有程式碼調整）。
   Stage A offline 模型只支援 creator=`owner`、joiner=`participant`；**不得用第二組
   `field_join_secret` 假裝 staff**，因為它會導出不同 `field_id`。`staff` 保留為 Stage E cloud
   staff-token 或另開 QR 契約任務。角色在「我的」與 active field status 顯示，且 owner 可建立/分享
   場域 QR，participant 不可。
5. **CommunicationState**：聚合 BLE/mesh running、nearby peers/nodes（若可得）、pending outbox、
   last presence sent、current best path。UI 不得只顯示 online/offline。
6. **motion-aware 定位與 PRESENCE**：取代 A9 的固定 120s production cadence。用窄版 Android
   `SensorManager` native bridge 或注入式 platform source 取得低頻 motion state；**不得使用 step
   counter / Activity Recognition**，不得要求 `ACTIVITY_RECOGNITION`；不得新增第三方 sensor 依賴
   （除非 Owner 另准並修 G13）。必須有 hysteresis，避免單一雜訊 sample 讓 moving/stationary 來回跳。
   政策常數：
   moving 30s、moving fresh-fix age 30s、stationary 180s、stationary fresh-fix age 15min、
   low battery moving 60s、low battery stationary 300s、low battery threshold 20%。manual
   SOS/HAZARD/CHECKPOINT/SAFE 可嘗試一次 fresh GPS（timeout）再 fallback last known fix。
7. **A11 可觀測性**：UI 或 debug diagnostics 必須顯示 moving/stationary、current interval、
   last GPS fix age、last presence sent、policy reason，供 A11 實機驗收。

**DoD**：
- D1 first-run / no-field entry 可測，production launch 不落 `DebugShell`。
- D2 五分頁存在且 label 精確為 `安全 | 位置 | 事件 | 協助 | 我的`；無 `地圖` tab。
- D3 global SOS 從每個 tab 可觸發，且不藏在單一 tab 深層。
- D4 現有功能模組移入對應 tab；debug diagnostics 僅 debug 可見。
- D5 owner/participant 最小角色模型存在，角色顯示並有明確 UI 差異：owner 可建立/分享場域 QR；
  participant 不可。staff 不可用第二組 field secret 假裝完成。
- D6 motion-aware cadence 單元/widget 測試覆蓋 moving、stationary、transition、low battery；
  測試證明 stationary 不熱跑高精度 GPS、moving 會縮短 presence/GPS refresh。
- D7 debug diagnostics 不是 production home，且只在 debug/developer mode 可進入。
- D8 HAZARD 有正式事件入口，不只存在 debug card。
- D9 grep/assert 證明 Android manifest 無 `ACTIVITY_RECOGNITION`，`pubspec.yaml` 無 `sensors_plus`
  （除非 Owner 另准並修 G13）。
- D10 通用 gate + GATE-CONF-DART + GATE-KOTLIN-BUILD 全綠；wire/proto/GATT/crypto 零變更。

**禁止**：重寫 BLE/event/v3 envelope/SOS/PRESENCE 底層；把 `DebugShell` 當正式首頁；
新增地圖 SDK/圖磚/GIS 套件；使用 `ACTIVITY_RECOGNITION`；把 motion-derived state 寫進 wire。

### UI-G — 「先看功能」/ 引導模式完善（前置：UI-F）

**依據**：`docs/APP_UI_IA_REWORK_PLAN.md` §5。UI-G 是 no-field 狀態下的產品理解入口，
不是真場域、不送事件、不啟動 mesh。E-CARE、完整管理者畫面、Web 後台串接不在本任務範圍。

**步驟**：
1. no-field entry 的 `先看功能` 進入 bounded preview/tutorial mode。
2. 使用 fixture/demo data：demo field、demo member footprints、demo SOS、demo hazard、
   demo broadcast/checkpoint。不得寫入 real membership，不得產生真 field secret。
3. preview 內容以操作心智為主：加入場域、被看見、SOS、位置/雷達、事件、協助、離線降級。
   不做 marketing landing page。
4. preview 的結束路徑：加入場域、建立場域、返回 no-field。
5. preview 不得因未授權 GPS/BLE/camera 而壞掉；若權限已拒絕，顯示說明但不得阻止觀看。

**DoD**：
- D1 `先看功能` 可從 no-field entry 開啟。
- D2 fixture mode 不啟動 mesh、不 publish wire event、不讀真 secrets。
- D3 覆蓋五分頁核心概念，且可導向加入/建立場域。
- D4 tests 覆蓋 preview entry、fixture rendering、no real publish calls。
- D5 通用 gate 全綠；wire/proto/GATT/crypto 零變更。

**禁止**：把 preview 資料混入真 `EventStore` / outbox；preview 內觸發真 SOS；為 preview 強迫請求權限。

### A11 — 雙機實機驗證（USER-GATE）

AGENT 工作 = 產出/更新 `docs/ACCEPTANCE_A11_TWO_PHONE_SCRIPT.md`，內容必須含逐步操作腳本與
證據表格；Owner 實機執行回填。**v1.5 起 A11 驗正式 `AppShell` 與 UI-F/UI-G 結果，
不得再以 `DebugShell` 當主要驗收路徑。**腳本至少涵蓋：

| # | 步驟 | 預期 | 證據欄 |
|---|---|---|---|
| 1 | fresh install/clear data 後首次啟動 | 權限引導出現；no-field entry 顯示「加入場域 / 建立場域 / 先看功能」 | 截圖+權限狀態 |
| 2 | 檢查正式 AppShell | 加入/建立場域後出現五分頁 `安全/位置/事件/協助/我的`，無 `地圖` tab；global SOS 每 tab 可見 | 截圖×5 |
| 3 | 手機 A 建立場域並出示 participant QR/密鑰；手機 B 加入 | 同 fieldId 前 8 碼；A 顯示 owner，B 顯示 participant；staff join 標為 Stage E deferred | 截圖×2 |
| 4 | A/B 啟動 mesh，互相發 PRESENCE；motion-aware diagnostics 開啟 | 對方位置卡/位置頁出現本機 anon8 + 時間；診斷顯示 current interval / last presence | 截圖+log |
| 5 | motion-aware GPS/presence：靜置→移動 | 靜置使用 stationary cadence，不熱跑 GPS；移動後 ≤30s 更新 presence/GPS policy reason；無 `ACTIVITY_RECOGNITION` 權限 | 截圖+log+秒數+權限查核 |
| 6 | A 從非安全 tab 觸發 SOS(RED)（倒數中取消一次，再真發） | global SOS 可用；B 端 sosAlerts 告警卡 ≤10s | 截圖+秒數 |
| 7 | A 發「我安全了」 | B 端該 SOS 標記解除 | 截圖 |
| 8 | B 發 HAZARD（typed） | A 端事件/危害列表出現 | 截圖 |
| 9 | 殺掉 B app 進程重啟 | 事件不重複（envelope_id dedup）、Outbox 補送 | 截圖+log |
| 10 | 手機 C（或改 B 的場域）發事件 | A **收不到**（field-scope）；trace 顯示 mismatch | trace 截圖 |
| 11 | （有環境）GATE-KOTLIN-RUN 於其中一機 | 全綠 | 輸出貼上 |
| 12 | A/B 相距 ≥20m 開「位置」分頁雷達視圖 | 對方點的方位與實際方向一致（目視粗略即可）、距離量級正確、SOS 點為 sos 色 | 截圖×2 |

**DoD**：D1 腳本文件存在且含上表全部步驟+證據欄；D2 Owner 回填全項通過（USER-GATE——
AGENT 不得代填）。Stage A 在 D2 完成前不得宣告 Exit。

### A12 — App↔Node 契約凍結（交付 Stage B 的鑰匙）

**步驟**：
1. 產出 `docs/specs/app_node_gatt_v1.md`，**normative** 內容（依附錄 E 草案逐項落定）：
   - Node 角色 = GATT **peripheral**，沿用既有 `SERVICE_UUID a4d11949-49d0-5230-96bb-43dd95d2cb2e`
     與 EVENT/BLOOM/HANDSHAKE 三 characteristic（`IgniRelayConstants` 現值，逐字收錄）。
   - HELLO：node 用既有 capability profile 目錄中的 node 型 profile（`capability_profile.dart`
     現有定義收錄；node 端 `ProtocolHelloData` 附加 additive 欄位 `node_id`、`node_lat_1e7`、
     `node_lng_1e7`、`install_accuracy_m`——手機端 decode 容忍未知欄位，舊手機不破）。
   - **NODE_RECEIPT**：新 control EventType **105**（100–129 區、additive）：payload
     `{1 ref_envelope_id bytes16, 2 status u8(0=ACCEPTED_STORED,1=DUPLICATE,2=REJECTED),
     3 queue_depth u32}`；node 收到手機事件、完成驗章+去重+落佇列後以 notify 回送；
     control range → zero field_id、無 field_mac（§21.7）。手機端：收到 → UI 狀態
     「已送達節點」（與 LoRa/Gateway 確認分離——PHASE3 §7.2 三段收據模型）。
   - chunking/MTU/重組規則 = `native_transport_v1` §4 原樣引用（節點 MCU 必須實作一致）。
2. App 端落地 NODE_RECEIPT 的解碼+顯示（發送端為 Node/模擬器，App 只收）。
3. `EventTypeV2` 加 105 常數 + `isKnown` + priority/maxHops 條目（control 同 HELLO 模式）；
   corpus 以 generator 增補 NODE_RECEIPT 樣本（G7）。
4. spec `envelope_v2_spec` §4 control 區註記 105（commit 引用本任務）。

**DoD**：D1 `app_node_gatt_v1.md` 完整（UUID/HELLO 欄位/RECEIPT/chunking 全 normative，
無 TBD 字樣）；D2 EventType 105 + corpus + 解碼測試綠；D3 通用 gate + GATE-CONF-DART 綠；
D4 Owner 簽核（STATUS 記 `A12 contract sign-off: <日期>`）；
D5（v1.1）corpus_revision bump 與 Kotlin/Swift metadata 斷言同刀更新（同 A4-D5）。
**禁止**：發明新 GATT UUID（必須沿用現值——兩端既有韌體/手機已綁定）；
在 spec 留「待定」欄位（要嘛定案，要嘛明確標 `RESERVED-未用`）。

> **施工筆記（v1.1，主理 AI 用）**
> 1. NODE_RECEIPT=105 的 matrix 條目比照 PROTOCOL_HELLO 模式：priority 僅
>    NORMAL（其餘 drop）、`maxHopsDefault = 0`（link-local，不轉送）、LWW = null、
>    control range → zero field_id / 無 field_mac / dispatcher 豁免（§21.7 自動涵蓋
>    100–129，驗證測試要含 105）。
> 2. payload 手寫 struct 比照 `CheckpointData` 風格：`1 ref_envelope_id bytes(16)`
>    `2 status u8` `3 queue_depth u32`；decode 對未知欄位 skip（與既有 reader 一致）。
> 3. App 收端：`V2InboundProjector` **不**投影 receipt 到 Event_Logs（非場域事件）；
>    改走新 `EventStream.nodeReceipts` typed 流 → debug shell 在對應送出列顯示
>    「已送達節點」。對應鍵 = ref_envelope_id ↔ facade 預配的 envelope_id。
> 4. `ProtocolHelloData` 附加欄位（node_id/node_lat_1e7/node_lng_1e7/
>    install_accuracy_m）：先確認現 decode 對未知 tag 是 skip（是——手寫 reader
>    模式），舊手機相容即成立；欄位號接在現有欄位之後，文件記 reserved 區。
> 5. GATT 文件中 UUID 逐字取自 `IgniRelayConstants.kt:14-18`（SERVICE
>    `a4d11949-…`、EVENT `a932d89d-…`、BLOOM `9b60940f-…`、HANDSHAKE
>    `24b532d3-…`、CCCD 標準值）；chunk framing 引 `native_transport_v1` §4
>    原文，不另寫一份（避免雙源漂移）。
> 6. 「三段收據」語意表（PHASE3 §7.2）原文收進 spec：PHONE_TO_NODE_ACCEPTED ≠
>    HOP_ACKED ≠ GATEWAY_CONFIRMED；NODE_RECEIPT 只承諾第一段。

### §5.13 Stage A Exit（「App 完成」的定義）

全部滿足，Owner 在 App repo STATUS.md 記 `STAGE-A-EXIT: PASS`：

1. A0–A10、A10b、UI-F、UI-G、A12 全 DONE（含證據）；A11 Owner 回填全過。
2. GATE-LAYERS / GATE-ANALYZE / GATE-TEST / GATE-PARITY / GATE-CONF-DART /
   GATE-KOTLIN-BUILD 一次性連跑全綠（同一個 commit 上，輸出存證）。
3. `grep -rn "_todoWire\|TODO_CONTRACT\|kDebugFieldJoinSecretHex" lib/` 輸出 0 行。
4. 凍結契約（附錄 B）全部就位且版本一致。

---

## §6 Stage B — 模擬器把 Field Node + Gateway 跑起來

> 原則（PHASE3 doc 全文沿用，此處只列增量）：simulator-first；**所有 chaos/協定測試以
> 「真實契約位元組」跑**，不再用 JSON 占位。模擬器綠 ≠ 場域可用（不得宣稱 field-proven）。

### B1 — 契約包 v1：LORA-WIRE + provisioning 凍結（前置：A12）

**步驟**：
1. 產出 `docs/specs/lora_wire_v1.md`（附錄 C 草案逐位元組落定為 normative）。要點：
   - 訊框：`hdr(11B)=ver_ptype(1)+flags(1)+field_tag(4=field_id[0..3])+src_node(2)+
     packet_seq(2)+ttl(1)` ‖ `body` ‖ `mac8(8)+crc16(2)`。
   - ptype：`0x1 EVENT`、`0x2 ACK`；其餘 reserved。
   - EVENT body：`event_id(16)+event_type(1)+priority(1)+hlc(8=u48 ms‖u16 ctr)+
     payload_len(1)+payload(≤64)`；ACK body：`ack_seq(2)+event_id_prefix(8)+status(1)`（全幀 32B）。
   - 緊湊 payload 對照表（envelope→LoRa 轉譯）：PRESENCE 10B、SOS 22B、CHECKPOINT 10B、
     HEARTBEAT 8B、HAZARD ≤40B（附錄 C 表逐欄位元組寬度照抄）。
   - 金鑰：`lora_mac_key = HKDF-SHA256(ikm=field_join_secret, salt=empty,
     info="ignirelay/lora-mac/v1", L=32)`；`mac8 = HMAC-SHA256(lora_mac_key,
     hdr‖body)[0..7]`；`crc16 = CRC-16/CCITT-FALSE(hdr‖body‖mac8)`。
   - 重放/過期：event_id 去重環（≥512 槽）；`flags.bit0 = hlc_synced`，synced 幀
     `|hlc_ms−local_est| > 48h` 即丟 `replay-window`；TTL 遞減、0 即丟。
   - **信任模型（OD-2 定案）**：Node 在 BLE ingest 驗 Ed25519+field_mac 後，LoRa 段
     **不攜帶** 作者簽章（64B 裝不下）；LoRa 真實性 = 場域 HMAC + src_node 出處。
     spec 內必須原文寫入此安全界線聲明（Gateway 信的是「場域成員節點背書」）。
2. 產出 `docs/specs/node_provisioning_v1.md`：node_id（u16，場域內唯一）、
   `field_join_secret` 安裝（lab=測試 fixture；實機=USB serial 一次性 JSON 行
   `{"node_id":7,"field_join_secret_b64":"...","mode":"lab|dev|field"}`）、node Ed25519
   keypair（供 NODE_RECEIPT/HELLO 簽章）、遺失節點處置=場域 re-key（流程 Phase 後續，先聲明）。
3. **向量生成**：`ignirelay_app/tool/generate_lora_wire_vectors.dart` →
   `docs/specs/lora_wire_v1_vectors.json`：≥40 正樣本（每 ptype/每事件型別/邊界長度）+
   ≥10 負樣本（bad mac、bad crc、ttl=0、replay 同 event_id、hlc 窗外、truncated、未知 ptype、
   未知 ver）。**金鑰沿用 corpus 既有 TEST-ONLY field_join_secret**，向量內標明。
4. Owner 簽核 → 兩份 spec + vectors 進附錄 B 凍結清單。

**DoD**：D1 兩 spec 無 TBD；D2 vectors 由 generator 產出且 Dart 自測綠
（generator 內建 self-check：encode→decode→re-encode bit 一致）；D3 Owner 簽核記錄。
**禁止**：手寫 vectors JSON；spec 與 generator 數字不一致（單一來源=spec，generator 註明
spec 章節）。

> **施工筆記（v1.1，主理 AI 用）**
> 1. 金鑰派生掛在既有 `FieldAuthV2`（`lib/app/crypto/field_auth_v2.dart`）：新增
>    `deriveLoraMacKey(secret)`，HKDF 參數與 `deriveFieldMacKey` 相同惟
>    `info = "ignirelay/lora-mac/v1"`；單元測試含「兩把 key 必不相等」
>    （domain separation 實證）。
> 2. CRC-16/CCITT-FALSE 釘死參數：poly 0x1021、init 0xFFFF、不反轉、xorout 0；
>    spec 與測試都收標準驗證值 `"123456789" → 0x29B1`，外加兩個自選向量。
> 3. hlc 48-bit 截斷規則寫死：`ms & 0xFFFF_FFFF_FFFF`（LE 序），溢位年 ~10889，
>    spec 註明；counter 取低 16 bit。
> 4. vectors JSON schema（generator 輸出，檔名 `lora_wire_v1_vectors.json`）：
>    `{meta:{spec_rev, generated_by, test_field_join_secret_b64(TEST-ONLY)},
>    frames:[{name, ptype, fields…, frame_hex, mac8_hex, crc16_hex}],
>    negative:[{name, frame_hex, expect_reason}]}`；正樣本 ≥40（每事件型別 ×
>    邊界長度 × flags 組合）、負樣本 ≥10（§6 B1 步驟 3 清單全覆蓋）。
> 5. 測試金鑰**沿用 corpus 既有 TEST-ONLY `field_join_secret`**（讓 envelope 與
>    LoRa 向量同鑰可交叉驗），generator 從 corpus JSON 讀取而非另設常數。
> 6. spec 內 radio profile（AS923/BW/SF/功率）標明「**附章 draft、Phase D 場試前
>    凍結**」——訊框格式與電波參數是兩件事，前者本刀凍結、後者不是；
>    不得因此把訊框留 TBD。
> 7. 緊湊 payload 對照表（附錄 C）逐欄位元寬照抄進 spec；SOS 70B > 64B 理想線
>    的偏差聲明也要原文收錄（128B 審查線內）。

### B2 — Python 參考實作（lab repo；可在 A5 後並行先做 envelope 部分）

**步驟**：
1. lab repo 新增 `ignirelay_lab/wire/`：
   - `envelope_v3.py`：decode `EventEnvelopeV2`（proto3 手寫 reader 對齊 Dart）、
     `canonical_sig_input_v3`（141B）、Ed25519 verify（依附錄 F 用 `cryptography`）、
     `field_mac` HMAC 驗證、payload structs（PresenceData/StatusUpdateData/…）decode。
   - `lora_v1.py`：B1 spec 的 encode/decode/mac/crc/replay 檢查。
   - `keys.py`：HKDF 派生（field_mac_key / lora_mac_key），與 spec §21.3 字串常數一致。
2. **對 corpus 驗證**：新測試 `tests/test_envelope_v3_conformance.py` 讀
   `..\IgniRelay\docs\specs\wire_conformance_v1.json`（路徑可用環境變數
   `IGNIRELAY_APP_DIR` 覆寫）：全部 `envelope_samples` 的 canonical hex、signature 驗證、
   `field_mac` 重算必須逐筆相等；全部 `negative_cases` 必須以對應錯誤拒絕。
3. `tests/test_lora_v1_vectors.py` 同法吃 `lora_wire_v1_vectors.json` 全過。

**DoD**：D1 corpus envelope 樣本 **100% 逐筆通過**（測試輸出列 sample 數，須 ≥104）；
D2 lora vectors 100% 通過（≥50 筆）；D3 GATE-LAB 綠；D4 新依賴僅 `cryptography`（pin 於
`requirements.txt`，附錄 F）。
**禁止**：跳過任何 sample（「抽測前 10 筆」不算過）；自己生測資取代 corpus。

### B3 — lab 升級：FakePhone/SimNode 改跑真位元組

**步驟**：
1. `FakePhone`：用 corpus TEST-ONLY 金鑰**真簽** v3 envelope（PRESENCE/SOS/CHECKPOINT），
   經「假 BLE」介面交給 SimNode（保持函式注入，BLE 真模擬在 field-node bsim 段）。
2. `SimNode`：ingest = `envelope_v3.py` 全驗（簽章/field_mac/dedupe/expiry）→ 轉譯
   LORA EVENT（B1 對照表）→ 佇列（P0 插隊維持）→ `FakeLoRaChannel`（**改載真 bytes**；
   corrupt= 隨機翻位元組，由 CRC/MAC 擋）→ 對端 SimNode 驗 mac/crc/ttl/replay → Gateway sink。
   發 NODE_RECEIPT 回 FakePhone（接受/重複/拒絕三態）。
3. 結構化 log 的 `drop_reason` 改用 spec 真代碼（`field-mac-invalid`/`crc-fail`/
   `replay-window`/`ttl_expired`…），log schema 文件同步。
4. 既有 9 情境全部改跑真 bytes；`security_placeholder` 等占位欄位/字串**全數移除**。
5. 不變量測試升級：P0 preempt、P4 先丟、bounded retry+jitter、ACK 冪等、10 節點風暴
   無重複（沿用 PHASE3 §6.1 清單，逐條變成 assert）。

**DoD**：D1 `grep -rn "TODO_CONTRACT\|security_placeholder\|PLACEHOLDER" ignirelay_lab/`
輸出 0；D2 GATE-LAB、GATE-SCEN 全綠（情境數 ≥9 不減）；D3 §6.1 不變量逐條有對應測試
（測試名對照表貼 STATUS）；D4 壞通道 20% loss 情境：SOS 送達率 100%、無使用者可見重複。
**禁止**：為過 chaos 把 channel 參數調軟（profile 檔數值不得改）；移除既有情境。

### B4 — Gateway 升級：真驗證 + 真封包

**步驟**：
1. `ignirelay_gateway/wire.py`：移植/共用 B2 的 lora_v1 解碼（兩 repo 各自 vendoring 或
   gateway 依賴 lab 套件——**選 vendoring 複製檔案 + 檔頭註明來源與版本**，避免跨 repo
   import 脆弱；兩份以 vectors 測試鎖一致）。
2. ingest 改收「LoRa 幀 hex/JSONL」：每幀過 mac/crc/ttl/replay/expiry → `packet_logs.
   security_check_status` 寫真實結果（`mac_ok|mac_fail|crc_fail|expired|replayed|ok`）；
   只有全過的幀才能 upsert `events` canonical 列。
3. `events` 表加欄位：`anon8`、`safety_state`、`lat_1e7/lng_1e7/acc_m`（自緊湊 payload 解出，
   供 C 階段 API 直接查）；migration 腳本 + 測試。
4. 設定檔 `gateway_config.json`（gitignore；`cli.py config-init` 產生）：
   `{field_secrets_b64:[...], admin_token, db_path}`。
5. fake_packets fixtures 重做成真幀（由 vectors 衍生）；負樣本 fixtures（mac_fail 等）
   斷言被拒且 log 正確。

**DoD**：D1 placeholder grep = 0（同 B3 模式）；D2 GATE-GW 綠且測試數 ≥10（含 ≥4 負樣本）；
D3 lab `gateway_cli` 情境端到端綠（真幀進、canonical 一筆、routes 多筆）；
D4 vectors 全過（與 B2 同口徑）。
**禁止**：把驗證失敗的幀也 upsert 進 `events`；token/secret 寫死在程式碼。

### B5 — Zephyr/NCS 環境建置（ENV-GATE；可隨時先做）

**步驟**：徵得 Owner 同意後安裝 Nordic Connect SDK（建議 nRF Connect for Desktop →
Toolchain Manager，NCS v2.7+ 與對應 Zephyr SDK；磁碟需求 ~15GB，安裝路徑寫入 STATUS）。
驗證三件事：
```
west build -b nrf54l15bsim/nrf54l15/cpuapp .      （於 field-node repo）
west build -b nrf54l15dk/nrf54l15/cpuapp .
west build -b nrf54l15bsim/nrf54l15/cpuapp tests/core && 執行產出之 ztest 可執行檔
```
**DoD**：D1 三指令 exit 0，輸出貼 STATUS；D2 ztest 骨架執行結果記錄（紅燈允許——骨架
本來沒跑過，紅燈轉入 B6 工作清單，不得隱瞞）。
**禁止**：把 SDK 裝進任何 repo 目錄內（SETUP.md 已禁）。

### B6 — field-node 真實作（前置：B1、B5）

**步驟**：
1. `src/wire/`：LORA-WIRE v1 codec（C）；HMAC-SHA256/HKDF 用 Zephyr **PSA Crypto API**
   （mbedTLS backend）；CRC16 查表實作。向量測試：lab 提供
   `tools/gen_c_vectors.py` 把 `lora_wire_v1_vectors.json` 轉 `tests/wire/vectors.inc`
   （生成器進 lab repo，產物進 field-node 並標「GENERATED — 重生勿手改」）。
2. core 補真：dedupe 環（固定 512 槽、O(1)）、優先佇列（P0>P1>P3>P4，滿時先丟 P4，
   行為=PHASE3 §6.1）、retry ≤3 + 指數退避 + jitter、TTL。全部 ztest 化。
3. envelope v3 **最小接收子集**（BLE ingest 用）：decode + canonical 141B + Ed25519 verify
   （PSA）+ field_mac 驗證 + 轉譯 LoRa 緊湊 payload；以 corpus envelope 樣本子集（由
   gen_c_vectors 抽全部 PRESENCE/STATUS/CHECKPOINT/HAZARD 樣本）做 ztest。
4. `fake_lora_transport.c` 改為 **UDP hub 模式**：`--lora-hub 127.0.0.1:9300 --node-id N`
   （bsim/native 可用 host socket；若該 board 禁 socket → **契約允許的備援**：改用
   `native_sim/nrf54l15` 等 POSIX target 跑協定 E2E，bsim 僅跑 BLE 對位——此備援啟用須記
   STATUS 並引用本句）。
5. NODE_RECEIPT 發送（BLE 端先以函式注入測試；真 GATT server 到 D 階段）。
6. 結構化 log 全事件決策（PHASE3 §3.6 欄位）。

**DoD**：D1 wire 向量 ztest 100% 過（樣本數列印）；D2 corpus envelope 子集 ztest 100% 過；
D3 core 不變量 ztest 全綠（佇列/去重/retry/TTL 各至少 3 案例）；D4 兩 build target 仍 exit 0；
D5 `grep -rn "TODO_CONTRACT" src/` = 0。
**禁止**：用簡化 MAC（如 CRC 當 MAC）；向量檔手改；malloc 於核心路徑（固定配置，PHASE3 §3.1）。

### B7 — 模擬端到端：FakePhone → SimNodeA → FakeLoRa → SimNodeB → Gateway

**步驟**：lab 新情境 `e2e_real_stack`：lab 以子行程啟動 **2 個 field-node 模擬執行檔**
（B6 產物）+ Python FakeLoRaChannel 作 UDP hub + GatewayCliSink；FakePhone 簽真 envelope
經 stdin/控制 socket 注入 NodeA（BLE 真模擬留 D）；斷言：PRESENCE、SOS(RED) 到 Gateway
SQLite 各恰一筆 canonical；SOS 先於同窗 P3 事件到達；NodeA log 有 NODE_RECEIPT 發出記錄；
殺 NodeB 進程重啟 → 無重複 canonical。
**DoD**：D1 `python -m ignirelay_lab.cli --scenario e2e_real_stack` PASS；D2 上述 5 斷言
都在測試碼中（指出檔名行號）；D3 GATE-SCEN 全綠。
**禁止**：在 lab 內重新實作 node 邏輯來「模擬」C 程式（必須跑 B6 真執行檔）。

### B8 — chaos 全綠（真位元組版）

PHASE3 §6 全部旋鈕 × §6.1 全部不變量，對 `e2e_real_stack` 拓撲執行；新增
`loss_50`、`partition_heal`、`asymmetric_link` 三個 profile。隨機種子固定並記錄於
log（重現性）。**DoD**：全情境 PASS 報告（`logs/<scenario>/report.json` 含 seed、
封包統計、不變量結果）；20% loss 下 SOS 送達 100%；50% loss 下 SOS 最終送達且
無重複。**禁止**：調 profile 數值、提高 retry 上限超過 spec（≤3）。

### B9 — 實機目標 build + 資源報告

`west build -b nrf54l15dk/nrf54l15/cpuapp .` + memory report：static RAM **< 160KB**、
保留 ≥64KB（PHASE3 §3.1 硬門檻）。超標→寫書面例外（量測值+緩解）交 Owner，
**不得自行放行**。**DoD**：build exit 0；`ROM/RAM report` 原文貼 STATUS；達標或例外簽核。

### B10 — 硬體採購 gate 報告（Stage B Exit）

產出 `docs/HARDWARE_PURCHASE_GATE_REPORT.md`：PHASE3 §9 檢核表**逐項**填
PASS/FAIL + 證據連結（log/commit/報告路徑）。全 PASS（或 Owner 簽核之例外）→
Owner 決定採購（清單照 PHASE3 §9：2–3× nRF54L15 DK、2–3× SX1262 模組+天線、
Pi 4/5、SPI Flash/FRAM、PPK2 選配）。

### §6.11 Stage B Exit

B1–B10 全 DONE；`STAGE-B-EXIT: PASS` 記於 lab repo STATUS（彙整三 sibling 證據連結）。
**明文限制**：此時只能宣稱「core protocol and firmware logic are green」，
不得宣稱任何實場效能（PHASE3 §5 原則）。

---

## §7 Stage C — Web 管理端（PC 上、與 Gateway 同 LAN）

> 部署形態（Owner 指定）：Gateway 程式 + Web 服務跑在一台 PC（之後移 Pi）；
> 使用者用**同一網段另一台（或同一台）電腦的瀏覽器**開管理頁。**全程零網際網路依賴**：
> 不得引用任何 CDN/外部字型/外部 JS——所有資產隨 repo 提供。

### C1 — HTTP API 規格凍結（前置：B4）

產出 `docs/API_V1.md`（gateway repo；附錄 D 草案落定）。要點（normative）：
- Base：`http://<gateway-host>:8088`；靜態 Web 在 `/`，API 在 `/api/*`。
- 驗證：`Authorization: Bearer <admin_token>`（token 來自 `gateway_config.json`）；
  缺/錯 → `401 {"error":"unauthorized"}`。`/api/health` 免 token（僅回 `{status:"ok"}`）。
- 端點（v1 全部唯讀，POST 僅 ack）：

| Method/Path | 參數 | 回應要點 |
|---|---|---|
| GET `/api/health` | – | `{status, version, now_ms}` |
| GET `/api/events` | `since_ms`(增量輪詢)、`type`、`priority`、`limit≤500`、`offset` | `{events:[{event_id,event_type,priority,first_seen_ms,last_seen_ms,source_node,last_hop,anon8?,payload}],total}` |
| GET `/api/events/{id}` | – | 事件 + `routes[]` + `packets[]`（轉送軌跡） |
| GET `/api/sos/active` | – | 依 anon8 LWW：safety∈{TRAPPED,INJURED} 且其後無 SAFE；含最後位置與經過秒數 |
| POST `/api/sos/{id}/ack` | body `{note}` | 寫本地 `sos_acks` 表（稽核留痕，不上 wire） |
| GET `/api/presence` | – | 每 anon8：last_seen_ms、last_node、battery |
| GET `/api/nodes` | – | 每 node：last_heartbeat_ms、battery、queue_depth、`stale`(>3×心跳間隔) |
| GET `/api/export.csv` / `.json` | 同 events 篩選 | 檔案下載 |

**DoD**：文件無 TBD；錯誤格式/分頁/時間單位（一律 epoch ms）全定義；Owner 簽核。

> **（v1.2）雲端孿生前向相容**：撰寫本規格時必須預期 Stage E 雲端版的重用：
> 回應 schema 與錯誤格式為兩形態共用；雲端多場域版以
> `/api/v1/fields/{field_id_hex}/...` 前綴擴充（LAN 單場域版不帶前綴，語意=
> 「本閘道唯一場域」）。雲端新增端點屬 E1 範圍、不在 C1 內，但 **C1 不得做出
> 與上述擴充方式衝突的設計**（例如把 field 語意藏進 query 參數）。

### C2 — API server 實作

FastAPI + uvicorn（附錄 F pin）；`ignirelay_gateway/api.py`；讀既有 SQLite（B4 schema）。
測試：FastAPI TestClient——每端點至少：200 正常、401 無 token、參數邊界（limit>500→400）；
SOS active 的 LWW 衍生邏輯單元測試（TRAPPED→SAFE 後不再 active）。
**DoD**：GATE-GW 綠且 API 測試 ≥15 案例；`uvicorn ignirelay_gateway.api:app --host 0.0.0.0
--port 8088` 可啟動（輸出貼證）。**禁止**：在 API 層重算/繞過 B4 的安全驗證結果欄位。

### C3 — Web UI（vanilla，零外部資源）

> **起點不是空白畫布（v1.1）**：殼與設計系統已由 DL 任務交付並凍結於
> `ignirelay-gateway/webapp/`（`tokens.css`、`app.css`、`index.html` 殼＋SOS 看板完成例、
> `app.js`、`DESIGN_README.md`）。C3 = **在此範本上接線**，不是重寫。開工第一步：
> 讀完 `webapp/DESIGN_README.md` 與本 repo `docs/DESIGN_LANGUAGE.md` §3/§5/§6，
> STATUS.md 開工條目須註明「已讀」二者，否則任務無效。

`webapp/`：`index.html` 單頁 + `app.js` + `tokens.css`/`app.css`（手寫，無框架、無 build
步驟；檔案結構以已交付範本為準，不得增刪改名——新增 JS 模組除外，須經 `app.js` 掛載）。
頁籤與驗收標準（殼之 KPI 列與五頁籤已存在，逐一接真資料）：
1. **KPI 列（常駐）**：活躍 SOS / 24h 事件 / 在場人員 / 節點在線；3 秒輪詢
   `since_ms` 增量。
2. **SOS 看板**：紅卡列表（anon8、狀態、位置、已過時間、最後節點）、`ack` 按鈕、
   已解除區（SAFE 後灰卡）。範本內已有紅/黃/已解除三張完成例卡——資料接上後
   **整段 data-sample 節點刪除**，新卡照其密度、類名、文案風格產生。
3. **事件表**：篩選 type/priority、分頁、點開看 routes/packets。
4. **人員足跡**：presence 表（anon8/最後節點/時間/電量），>10min 標黃、>30min 標紅。
5. **節點健康**：heartbeat 表，stale 紅標。
6. **匯出**：CSV/JSON 下載按鈕。
7. 登入：首次輸入 token 存 `localStorage`；401 時清除並要求重輸。
8. **資料路徑單一**：一切請求經 `app.js` 的 `apiGet()`（token/Bearer/401/`setConn()`
   集中於此實作）；不得另開第二條 fetch 路徑。`apiGet()` 現為刻意 `throw`，
   接線即移除 throw——禁止改成假回傳混過測試。
**DoD**：D1 `grep -rn "http://\|https://" webapp/` 僅允許出現相對路徑與註解（零外部 URL）；
D2 以 Python 端對端測試（TestClient 抓 `/` 與靜態檔 200）+ AGENT 以 headless 工具或
curl 驗證 API 流；D3 視覺驗收 = USER-GATE（C5 一併）；
D4 `grep -n "data-sample" webapp/index.html` 輸出 **0 行**（假資料節點全數移除）；
D5 `DESIGN_LANGUAGE.md` §6 全部 enforcement gates 逐字執行且通過
（漸層/CDN/外部 URL/色彩字面值/emoji 掃描，指令與輸出貼進 STATUS.md）。
**禁止**：引入 npm/webpack/CDN；token 寫進原始碼；重做殼（appbar/kpis/tabs/panel 結構）；
在 `tokens.css` 之外出現任何 hex/rgb 色彩定義；繞過 `apiGet()` 直接 fetch；
保留任何 data-sample 節點「當佔位」。

### C4 — 即時看板 E2E（lab → gateway → web）

1. gateway `cli.py` 加 `ingest --follow <file.jsonl>`（tail 模式，模擬 serial 流）。
2. lab `e2e_real_stack` 加 `--live-out <file>`：邊跑邊 append 幀。
3. 自動化驗收腳本 `tests/test_live_pipeline.py`：啟 API server + follow ingest + 跑情境，
   輪詢 `/api/sos/active`，斷言 **SOS 從幀寫入到 API 可見 ≤5 秒**（時間戳相減），
   presence/nodes 端點同步出現資料。
**DoD**：該測試綠（latency 數值列印）；GATE-GW、GATE-SCEN 全綠。
**禁止**：把 5 秒門檻調大；用直接寫 DB 取代 follow-ingest 路徑。

### C5 — LAN 部署 + 瀏覽器驗收（USER-GATE）

AGENT 產出 `docs/DEPLOY_LAN.md`：Windows 防火牆開 8088、`config-init` 產 token、啟動指令、
第二台電腦瀏覽器開 `http://<gateway-ip>:8088`、輸 token、跑 lab live 情境看 SOS 浮現。
Owner 回填證據表（截圖：401 畫面、登入後看板、SOS 卡出現、匯出檔開啟）。
**DoD**：文件存在 + Owner 全項回填。

### C6 — 匯出強化（選配，可後移）：篩選參數齊 C1；PDF 留 future（明確標註不在 v1）。
### C7 — 安全基線檢查

checklist 落 `docs/SECURITY_BASELINE_C7.md` 並逐項證據：token 必填、`/api/*`（除 health）
無 token 全 401（自動測試）、bind 與防火牆說明、零外網請求（C3 grep + 瀏覽器 devtools
截圖 USER 回填）、secrets 不在版控（`git log -p` 抽查 + `.gitignore` 覆蓋 config/db）、
log 不含 secret。

### §7.8 Stage C Exit

C1–C5、C7 全 DONE（C6 可延）；`STAGE-C-EXIT: PASS` 記 gateway repo STATUS。
下一步：本文件「Stage E」章（Stage D 可同時並行起跑）。

---

## Stage E — 雲端場域服務（v1.2 新增；前置：Stage C Exit；可與 Stage D 整段並行）

> **產品定位（Owner 2026-06-11 拍板）**：「場域」本身就是產品。
> **純軟體形態**＝場域主在雲端開場域、成員掃 QR 加入、有網路的手機直接上雲、
> 場域主在任何地方用瀏覽器看全場（可作為軟體服務販售；v1 由 Owner 手動開通，
> 無自助註冊、無金流系統）。**軟硬整合形態**＝同一個場域加上節點/閘道覆蓋無網區。
> 同一個 App、同一個 QR、同一種信封、同一套後台設計語言。
>
> **Stage E 不變量（每個 E 任務的隱含 DoD，違反=任務 FAIL）**：
> 1. **wire 契約零變更**：附錄 B 既凍結檔案 `git diff` = 0；信封不加任何角色/雲端欄位。
> 2. 雲端對信封的驗證**必須重用** B4/C2 的同一驗證管線（Ed25519＋field_mac＋去重＋
>    HLC 重放窗）。「外層有 TLS 所以不用驗信封」＝G4 假實作同級違規。
> 3. 角色（owner/staff/member）與可見性政策只存在於雲端 DB 與後台/讀 API——
>    **不進 wire**（OD-11）。**SOS 永遠對全場域成員可見，任何政策不得遮蔽。**
> 4. 離線 mesh 形態下，成員間可見性＝App 端遵守政策（場域內事件本就全員接力）；
>    一切對外文件必須如實描述此差異，禁止宣稱離線也有伺服器級強制。
> 5. 隱私底線：雲端只存 anon8 / pubkey / 事件內容 / 場域主自填備註；v1 禁止新增
>    實名、電話等 PII 欄位。`field_join_secret`、owner 密碼雜湊只存伺服器設定檔/DB，
>    **永不入版控、永不出現在 log**（G14 延伸）。
> 6. 部署密鑰紅線：TLS 私鑰、token、場域 secret 只存在 VPS 檔案系統（權限 600）；
>    repo 內只允許 `*.example` 樣板。
>
> **程式碼落點（凍結決策）**：雲端伺服器＝gateway repo **同一 codebase** 的 `cloud`
> 部署形態（多場域）；雲端後台＝**同一份 `webapp/`**（依伺服器回報的 capabilities
> 顯示/隱藏管理功能）。禁止 fork 第二份 server 或第二份 webapp（單源原則，G7 精神）。

### E1 — 雲端契約凍結：cloud_api_v1 + 地圖校準規格/vectors（主理 AI；前置：C1）

產出三件，Owner 簽核後依附錄 B 凍結：

1. `ignirelay-gateway/docs/specs/cloud_api_v1.md`（normative）：
   - **場域生命週期**：`created → active → closed → archived`；場域由 Owner 以 CLI
     `field-add` 佈建（v1 的商業開通流程＝手動執行此指令）。
   - **角色模型**：`owner / staff / member`。staff 經 staff QR（A7 段 4 invite token，
     後台可輪換/作廢）或後台升格取得；member＝掃 member QR 後 App 自動
     `POST /api/v1/fields/{fid}/join`（提交 anon8＋pubkey，伺服器記 roster，
     回 `member_token` 供 app-bundle 下行使用——member 無後台登入權）。
   - **可見性政策**：`peer_visibility ∈ {"all","staff_only"}`（member 是否可見其他
     member 的非 SOS 足跡）；**SOS 不受政策影響**（OD-11）；政策變更即時生效於
     讀 API 與 app-bundle。
   - **Ingest**：`POST /api/v1/ingest`，body `{"envelopes":["<b64>", ...]}`（≤100/次），
     回每封 `{status: accepted|duplicate|rejected, reason?}`；以 event_id 冪等；
     **無帳號驗證**——信封自證＋rate limit（OD-9）；400/413/429 行為全定義。
     上傳者身分不影響驗收結果（data-mule 代傳他人事件天然成立）。
   - **讀 API**：C1 表逐端點加 `/api/v1/fields/{fid}` 前綴；角色矩陣＝owner/staff
     全量、member 無讀 API（member 的資訊面在 App 本地 mesh 資料＋app-bundle）。
   - **認證**：owner/staff 後台＝帳號＋密碼（`hashlib.pbkdf2_hmac` SHA-256、
     iterations ≥600000、每帳號隨機 salt）＋session cookie（HttpOnly、Secure）；
     登入錯誤節流。閘道同步＝每場域 `gateway_sync_token`（Bearer）。
   - **地圖檔案**：`PUT/GET /api/v1/fields/{fid}/map`（image/png|jpeg、上傳 ≤8MB，
     伺服器重編碼長邊 ≤4096px、以 sha256 定址、GET 帶 ETag）。
   - **App 下行**：`GET /api/v1/fields/{fid}/app-bundle`（帶 member_token）＝
     政策＋地圖 meta＋ADMIN_BROADCAST 信封清單（**信封原樣 bytes 的 b64**——
     App 端必須走既有 decode＋驗證，見 E4）。
   - **（v1.3）場域選用整合設定**：場域表加 `ecare_base_url`／`ecare_api_key`
     （皆 nullable；owner 後台設定，供 EC 系列）；隨 app-bundle 下行。空值＝App
     隱藏 AI 對話入口（EC-1）。金鑰由 VPS 代理層驗證（EC-3），雲端服務本身不驗此 key。
2. `ignirelay_app/docs/specs/map_calibration_v1.md`（normative）：
   - **投影**：局部等距投影，原點＝第 1 對位點；
     `x_m = (lng − lng₀) × 111320.0 × cos(lat₀)`、`y_m = (lat − lat₀) × 110574.0`
     （兩常數凍結；與 A10b 的 relative_position 同一組）。
   - **擬合**：2D 相似變換（4 參數 Helmert：均勻縮放＋旋轉＋平移）最小平方閉式解；
     **禁止鏡射**（行列式 > 0，違反即校準無效並回報）；對位點數 2–10；
     必須輸出 RMS 殘差（公尺），後台必須對場域主顯示。
   - **單一來源＝對位點集**（`{px,py,lat,lng}`×N）：兩端（Dart 與 Python/JS）**各自
     從點集重算變換**，禁止傳遞擬合係數（防漂移）。不確定圈換算
     `radius_px = uncertainty_m × scale`。像素座標系＝左上原點、y 向下。
   - 數值容差：vectors 斷言 `|Δpx| ≤ 0.01`。
3. `ignirelay_app/tool/generate_map_calibration_v1.dart` →
   `ignirelay_app/docs/specs/map_calibration_v1_vectors.json`（generator-only，G7）：
   正樣本 ≥12（2/3/5/10 點、旋轉 0°/90°/任意角、經度跨符號、含殘差非零組）、
   負樣本 ≥4（兩點重合、鏡射陷阱、點數 <2、>10）；generator 內建
   「生成 → 擬合 → 投影 → 反算」self-check。

**DoD**：D1 兩 spec 無 TBD 字樣；D2 vectors 由 generator 產出且 Dart 自測綠；
D3 Owner 簽核記 STATUS（`E1 contract sign-off: <日期>`）。
**禁止**：在信封/wire 加任何欄位；手寫 vectors JSON；改動 C1 已凍結語意
（只允許加前綴擴充）。

### E2 — VPS / 網域 / TLS 佈建（施工 AI 寫文件＋腳本；執行＝USER-GATE）

產出 `ignirelay-gateway/docs/DEPLOY_CLOUD.md` ＋ `deploy/` 腳本（可重複執行 idempotent），
必含小節：DNS A 記錄 → 防火牆（僅 22/80/443）→ 反向代理＋Let's Encrypt 自動續期 →
systemd 非 root 服務 → `cloud_config.json`（權限 600；repo 只放 `.example` 樣板）→
SQLite 每日備份排程＋還原演練步驟 → 換鑰程序（場域 secret / staff token / owner 密碼）。
Owner 回填證據：`curl -sSI https://<域名>/api/health` 為 200、`openssl s_client` 憑證鏈
輸出、`systemctl status` 截圖、備份檔存在清單。
**DoD**：D1 文件含上列全部小節且指令可逐字複製執行；D2 Owner 全項回填。
**禁止**：自簽憑證交差；以 root 跑服務；把任何真實密鑰/網域 API token 寫進 repo。

### E3 — 雲端伺服器實作（施工 AI；前置：E1、C2）

gateway repo 加 `cloud` 部署形態（單 codebase，設定檔/旗標切換）：
1. 多場域 schema migration：`fields`（fid/狀態/政策/地圖 meta）、場域 secret 載入
   （設定檔，不入 DB 亦可——擇一並寫明）、`rosters`、`staff_tokens`、
   `owner_accounts`、`sos_acks` 加 fid 維度。
2. CLI：`field-add` / `owner-add` / `staff-token-rotate`（佈建即商業開通）。
3. ingest 端點（E1 語意）。**驗證必須 import B4 既有管線函式**——以測試釘死：
   對同一壞 MAC 信封，LAN 形態與 cloud 形態回**同一個 reason 字串**（同 code path 證明）。
4. 角色過濾讀 API；owner/staff 登入＋session；登入錯誤節流（同帳號 5 次 / 15 分鐘）。
5. rate limit：per-IP 與 per-field token bucket（stdlib 實作即可），超限回 429。
6. 測試 ≥25 案例：accepted/duplicate/壞簽章/壞 MAC/未知場域/超量 413/限流 429/
   無 session 401/角色 403 矩陣/政策過濾/join 註冊/staff token 作廢後 403。
**DoD**：D1 GATE-GW 綠（含新測試，總數列於 STATUS）；D2 cloud 形態本機可啟動
（啟動指令＋輸出貼證）；D3 「同一驗證 code path」斷言測試綠；D4 既有 LAN 形態
測試零退化（C2/C4 測試原樣全綠）。
**禁止**：重寫第二份信封驗證；明文或弱雜湊存密碼；自創 E1 之外的端點；
為 cloud 形態削弱 LAN 形態的任何行為。

### E4 — App 雲端整合（施工 AI；前置：E1、E3、A7）

1. `lib/app/services/cloud_uplink.dart`：作用場域有 `cloudBaseUrl` 且網路可用 →
   批次上傳事件信封（**原樣 bytes 的 b64**、≤100/批、指數退避；伺服器冪等故重送
   安全）；上傳狀態（成功/退避/離線）進 debug shell。
2. join 註冊（掃 QR 後自動）與 app-bundle 輪詢：**僅前景**輪詢、間隔 ≥60 秒（省電）。
3. **下行信封必須走既有 decode＋dispatcher 驗證**（與 BLE ingest 同一路徑）；
   「雲端來的就可信」捷徑＝G4 違規。整合測試：壞 MAC 的雲端信封必須被 drop 並 trace。
4. 政策套用：`peer_visibility = staff_only` 時，member 視角的足跡列表與雷達隱去
   其他 member（**SOS 不隱**）；政策值來自 app-bundle，離線沿用最後快取值。
5. 地圖下載快取（sha256 驗證後落盤，供 E7 用）。
6. 依附錄 F 白名單處理 HTTP client 依賴。
**DoD**：D1 上傳批次/退避/政策過濾單元測試＋下行驗證整合測試綠；D2 通用 gate 全綠；
D3 離線零退化（無 cloudBaseUrl 場域的全部既有測試原樣綠）。
**禁止**：繞過 facade 另開發佈路徑；輪詢間隔 <60s；把未經驗證的雲端資料注入
read-model；雷達/列表對 SOS 套用任何隱藏。

### E5 — 現場閘道 ↔ 雲端同步（施工 AI；前置：E3）

gateway LAN 形態加 `cloud-sync` 子命令/背景執行緒：以 `gateway_sync_token` 向雲端
ingest 批次上行本地新事件（游標持久化、斷線指數退避、event_id 冪等）。
**v1 僅上行**；雲端→現場下行明確標 future（涉及 LoRa 下行排程，Stage D 後另案）。
測試：TestClient 假雲端收批、游標斷點續傳、token 錯 → 401 退避不得死循環。
**DoD**：D1 測試綠＋GATE-GW 綠；D2 同步指標（批次大小/延遲）寫 log 並於測試斷言存在。
**禁止**：直接寫對方 DB；繞過 ingest 端點；把游標存記憶體（重啟即重傳全量）。

### E6 — 雲端場域主後台（施工 AI；前置：E3；設計受 DESIGN_LANGUAGE 全約束）

同一份 `webapp/` 依 capabilities 擴充：owner/staff 登入頁、場域切換器、場域管理
（建立流程顯示 CLI 產出之邀請資料、member/staff QR 海報列印視圖、staff token 輪換、
政策切換、**anon8 備註欄**＝場域主自填別名，僅該場域後台可見、不上 wire、
（v1.3）E-CARE 連線設定＝URL／金鑰僅 owner 可編輯、顯示一律遮蔽尾碼）、
C3 同款看板（per-field）、地圖頁籤（E7 掛入）。QR 在**伺服器端產 SVG**（零外部資源）。
**DoD**：D1 角色行為自動測試（member 無後台、staff 看板有/管理無、owner 全有——
API 層測試＋UI smoke）；D2 `grep -rn "data-sample" webapp/` 維持 0 行；
D3 DESIGN_LANGUAGE §6 enforcement gates 全過（指令與輸出貼 STATUS）；D4 GATE-GW 綠。
**禁止**：fork 第二份 webapp；引入 CDN/外部資源（雲端形態同樣零外源）；
後台任何頁面出現 secret/token 全文（顯示一律遮蔽尾碼）。

### E7 — 場域自訂地圖（georeferencing；施工 AI；前置：E1、E6、A10）

1. 後台校準 UI：上傳圖 → 圖上放 2–10 個釘（可拖曳）→ 每釘填 lat/lng（手動輸入；
   座標可由 App 的 A10 位置卡複製）→ **即時顯示 RMS 殘差（公尺）** → 存檔
   （只存點集——E1 規格的單一來源原則）。
2. 後台疊加視圖：人員/節點/SOS 畫在圖上（顏色語意=tokens.css；不確定圈、stale
   降級沿用 A10 規則；SOS 點永遠繪於最上層）。
3. App 疊加視圖：用 E4 快取圖＋同一變換畫點；場域無地圖 → 此視圖自動隱藏。
4. **跨端一致性（本任務的靈魂）**：Dart 與 Python（伺服器端重算）各自實作變換，
   **同一份 `map_calibration_v1_vectors.json` 兩端測試全過**——App repo 新測試檔
   跑在 GATE-TEST 下；gateway repo 新測試檔跑在 GATE-GW 下，以 sibling 相對路徑
   `../IgniRelay/ignirelay_app/docs/specs/map_calibration_v1_vectors.json` 讀取
   （允許環境變數覆寫路徑）。**禁止複製 vectors 檔到第二處**（單一來源）。
5. 測試：雙端 vectors 全過、校準「存檔→重載→重算」冪等、壞圖（超大/非影像/
   超點數）拒收且有使用者提示。
**DoD**：D1 Dart vectors 測試綠；D2 Python vectors 測試綠；D3 校準冪等測試綠；
D4 App/後台疊加 smoke＋設計 gates 過；D5 通用 gate 全綠。
**禁止**：兩端各自發明投影/擬合公式而不過同一份 vectors；引入 GIS/地圖函式庫；
傳遞擬合係數（必須由點集重算）；把推導出的像素/距離寫進 DB 或 wire。

### EC 系列 — E-CARE 跨專案串接（v1.3 新增；Owner 2026-06-12 拍板）

> **背景**：Owner 與校內另一團隊的專案 **E-CARE**（`github.com/rungyu0721/Ecare`；
> FastAPI 緊急事件輔助後端——事件分類／風險評估／LLM 安撫對話／案件通報 CRUD；
> 跑在**學校 GPU 資源**上，不在 Owner VPS）合作。烽傳取用其三個能力：
> ① SOS 後的 AI 安撫對話（`POST /chat`）；② SOS 案件通報進其儀表板
> （`POST /reports`、`POST /reports/{id}/status`）；③ 急救圖卡內容（離線快照）。
> 主理 AI 已於 2026-06-12 審閱 E-CARE repo（commit `4e4543d`）確認對接基礎：
> `/chat` 無伺服器端 session（對話歷史由 client 全量攜帶，天然可斷線重試）；
> `/reports` 含 `latitude`/`longitude` 欄位；API 目前**完全無認證**（其 roadmap
> P3 自承待補）——故一切存取必須經 EC-3 代理層，學校機器不得直接面對公網。
>
> **EC 不變量（疊加在 Stage E 六條不變量之上；違反＝任務 FAIL）**：
> 1. **SOS 零延遲**：一切 EC 功能（彈窗／對話／通報轉發）只發生在 SOS 本體
>    **已完成發送之後**；EC 任何失敗不得阻擋、延遲、改變 SOS 的 mesh 廣播與
>    雲端上行。實作鐵則：SOS 發佈路徑**禁止 import 任何 EC 程式碼**（grep gate 釘死）。
> 2. **E-CARE 程式碼零改動**：所有黏合層位於本專案 repo（App／gateway cloud／
>    VPS 設定）。任何「需要對方改 X 才能接」的做法＝設計錯誤，走 G8 回報 Owner。
> 3. **隱私紅線**：禁止呼叫 E-CARE `/users`（該表含實名／電話／地址 PII）；
>    `/chat` 禁止攜帶 `user_context`；`POST /reports` 只送事件欄位（category／
>    location 文字／lat/lng／risk／description；description 內容限 anon8、安全
>    狀態、時間，禁任何 PII）。送往 E-CARE 之資料視同離開本系統信任邊界（OD-13）。
> 4. **可用性降級**：E-CARE 不可用（timeout／5xx／斷網／合作中止）＝**正常狀態**。
>    App 逾時後無聲降級回本地圖卡；禁止無限轉圈、禁止 crash；重試上限與退避
>    依各任務明定。
> 5. **AI 輸出只進顯示層**：E-CARE 的回覆／風險判斷一律不回寫 wire、DB、SOS 狀態
>    （同 A10b「顯示層」紀律）。
> 6. **wire 契約零變更**（承襲 E 不變量 1）。v1 範圍**不含**「AI 對話經 mesh 中繼」
>    ——該構想屬 wire 契約修訂，明確標 future、Owner 另案核可，AGENT 不得擅自實作。

### EC-1 — App：SOS 後援對話（本地圖卡＋E-CARE AI）（施工 AI；前置：E4）

UX 流程（Owner 2026-06-12 拍板）：SOS 送出成功**之後** → 非阻擋式 bottom sheet
「需要進一步協助嗎？」→ 同意 → 對話畫面：無網路或場域未設 E-CARE → 輸入文字觸發
關鍵字→本地急救圖卡；有網路且場域已設 E-CARE → AI 對話。拒絕／忽略彈窗＝零影響。

1. `lib/app/services/ecare_client.dart`：constructor 注入 HTTP client（MultiProvider
   接線，禁 `.instance`）；方法 `chat()`／`createReport()`／`updateReportStatus()`；
   全部回傳 Result 型別（不向外拋例外）；timeout 10s、重試 ≤1 次（指數退避）；
   端點與欄位以附錄 B「EC 對接面」基準為準。
2. 設定來源：E1 之 `ecare_base_url`／`ecare_api_key` 隨 app-bundle 下行（E4 既有
   輪詢）；記憶體持有＋`SharedPreferences` 快取（key `ecare_cfg_<field_id_hex>`）；
   **不新增 DB schema**。空值＝AI 對話入口隱藏（圖卡模式仍可用）。debug build 允許
   TEST-ONLY 手動覆寫欄位（沿 A2 debug-secret 模式；release 不可見，widget test 釘死）。
3. SOS 後彈窗：訂閱既有 SOS 發佈完成訊號（實作時以實際 API 為準、錨點記 STATUS）；
   bottom sheet 顯示路徑不得 await 任何網路呼叫。
4. 對話畫面（`ui/screens/`；facade 規則＋500 行上限＋Controller/View 拆分）：
   - 本地模式：`assets/first_aid_cards_v1.json`（內容取自 E-CARE
     `backend/data/first_aid_guides.json` 快照；檔頭標注來源 repo／commit／日期）；
     關鍵字比對＝純函式 `first_aid_matcher.dart`（可單測）。
   - 連線模式：messages 全量帶上 `POST /chat`；顯示 `reply`＋`next_question`；
     `risk_level` 僅顯示（EC 不變量 5）；失敗→無聲切回本地模式＋單行非阻擋提示。
5. SOS 通報 hook：SOS 送出後網路可用→fire-and-forget `createReport()`
   （title=`烽傳 SOS <anon8>`、category=`災防求救`、座標取 SOS 自帶位置、
   description 開頭含 `[IGNI:<event_id 前 8 hex>]` 供對帳）；成功記 report_id
   （同上 SharedPreferences key 空間）；後續**本人** SOS 安全狀態變更→
   `updateReportStatus()`。映射表**必須窮舉本專案 safety state enum 全部值**
   （switch 禁 default 漏接；單測逐值斷言）：語意吻合者用 E-CARE 終態詞
   （如 SAFE→「我已安全」），無對應者 status=`現場更新`、狀態原文入 note。
6. 測試：client 成功/timeout/5xx/降級；「彈窗路徑拋例外，SOS pipeline 照常完成」
   widget test；關鍵字→圖卡；映射窮舉；release 無覆寫欄位。

**DoD**：D1 GATE-TEST 綠（新測試檔名列 STATUS）；D2 GATE-LAYERS／GATE-ANALYZE 綠；
D3 grep gate＝SOS 發佈路徑零 EC 引用：`grep -rni "ecare" lib/app/controllers/ lib/app/mesh/`
→ **0 行**（指令＋輸出貼 STATUS）；D4 E-CARE 不可用情境之降級證據（測試輸出）。
**禁止**：在 SOS 發佈路徑 await EC 呼叫或 import EC 程式碼；AI 輸出回寫 wire/DB/
SOS 狀態；呼叫 `/users` 或攜帶 `user_context`；UI 自建 HTTP client（必須注入）；
新增 DB 欄位；release 出現 URL 覆寫欄位。

### EC-2 — 雲端→E-CARE 通報轉發 adapter（施工 AI；前置：E3）

**只跑在 cloud 形態**（單一轉發點；現場 LAN 閘道不轉發——避免雙重通報與金鑰外散）。

1. 設定：per-field `ecare_base_url`／`ecare_api_key`（cloud_config，權限 600；
   repo 只放 `*.example`）；未設定的場域＝完全跳過（零行為、零 log noise）。
2. 訂閱**已通過驗證管線**的 SOS 事件（post-pipeline hook；非 SOS 一律不轉發）；
   非同步佇列處理——E-CARE 失敗不得回壓 ingest 路徑。
3. 映射：同 EC-1 步驟 5 的欄位規則（title／category／座標／`[IGNI:]` 標記／無 PII）。
   E-CARE `POST /reports` **非冪等**→本地持久化 `event_id → report_id` 映射
   （成功後寫入；重啟以映射防重複 create；崩潰窗口可能殘留單次重複，以 `[IGNI:]`
   可對帳——此已知限制必須寫進 EC-3 部署文件）。
4. 本人 SOS 之 STATUS_UPDATE（SAFE 等）→`POST /reports/{id}/status`（同映射表）。
5. 重試：指數退避、上限 5 次，之後進 dead-letter log（檔案）；log 禁含金鑰全文。
6. 測試（mock E-CARE server）：轉發一次性／5xx 重試／dead-letter／非 SOS 不轉發／
   **無 PII 斷言**（對送出 JSON 全文掃 name/phone 類欄位）／重啟不重複 create／
   未設定場域零呼叫。

**DoD**：D1 GATE-GW 綠（新測試數列 STATUS）；D2 mock 收到之 JSON 樣本貼 STATUS；
D3 grep gate：repo 內無真實 URL／金鑰（只允許 example／測試值；指令＋輸出貼 STATUS）；
D4 LAN 形態零退化（C2/C4 測試原樣全綠）。
**禁止**：在 LAN 形態啟用；直寫 E-CARE DB；轉發非 SOS 事件；同步阻塞 ingest；
呼叫 `/users`；金鑰入 repo 或 log。

### EC-3 — E-CARE 代理與金鑰佈建（施工 AI 寫文件；執行＝USER-GATE；前置：E2）

產出 `ignirelay-gateway/docs/DEPLOY_ECARE_PROXY.md`，必含小節：

1. **Owner 協調清單**（執行前 Owner 親自向 E-CARE 團隊取得並記 STATUS）：
   base URL／服務常駐時段／同意經 Owner VPS 代理對外。三項齊才得執行後續。
2. 學校機器→VPS 反向通道（主推方案擇一寫死步驟；學校機器**不開任何公網 port**）。
3. VPS 反向代理 `location /ecare/`：對外要求 header `X-Igni-Ecare-Key`
   （per-field 金鑰，與 E1 下行給 App 者一致）、無效→401；per-key rate limit；
   TLS 沿用 E2 憑證；金鑰檔權限 600、repo 只放 `*.example`。
4. 驗收指令（Owner 逐字執行回填）：無 key→401/403；有 key `GET /ecare/reports`→200；
   App 對話 round-trip 一次成功。
5. 金鑰輪換＋「合作中止」處置程序（拆代理＝EC 全功能自動降級，App 不需改版）。

**DoD**：D1 文件全小節齊且指令可逐字執行；D2 Owner 回填全項證據。
**禁止**：學校機器直開公網；任何真實 URL／金鑰／tunnel token 入 repo；
要求 E-CARE 端改碼。

### EC-4 — 雲端後台「E-CARE 通報」分頁（施工 AI；前置：EC-2、E6）

1. cloud server 加讀代理：`GET /api/v1/fields/{fid}/ecare/reports`（與
   `…/ecare/reports/{rid}/status`）——伺服器端以場域金鑰經代理取 E-CARE 資料後
   原欄位轉發（**金鑰永不到瀏覽器**）；owner/staff session 保護；E-CARE 逾時→
   504＋webapp 顯示「E-CARE 暫不可用」空狀態（不是錯誤畫面）。
2. webapp 加「E-CARE 通報」分頁（同一份 webapp、依 capabilities 顯示；
   DESIGN_LANGUAGE 全約束）：案件列表（risk chips 用 tokens 色）、`[IGNI:]` 案件
   標注「來自烽傳」、狀態歷程展開。**v1 唯讀**（建立／改狀態由 EC-1/EC-2 自動流負責）。
3. 測試：代理端點角色矩陣（member 401/403）／E-CARE down→504 路徑／
   `data-sample`=0／DESIGN_LANGUAGE §6 gates。

**DoD**：D1 GATE-GW 綠；D2 設計 gates＋data-sample=0 證據；D3 金鑰不出現於任何
回應 body／前端原始碼（grep 證據）。
**禁止**：瀏覽器直連 E-CARE；金鑰進前端；fork webapp；在本分頁提供寫操作。

### §E.8 Stage E Exit

全部滿足，`STAGE-E-EXIT: PASS` 記 gateway repo STATUS.md：

1. E1–E7 全 DONE（證據齊）；附錄 B 既凍結 wire 檔案 `git diff` = 0 的稽核紀錄。
2. 自動化 e2e（比照 C4 模式）：TestClient 模擬手機 ingest SOS → 後台
   `/api/v1/fields/{fid}/sos/active` **≤5 秒**可見（latency 數值列印於測試輸出）。
3. USER-GATE（Owner 回填）：外網瀏覽器開 `https://<域名>` 登入 → SOS 看板、
   地圖疊加、QR 海報列印視圖各一張截圖；手機行動網路下發 SOS → 後台 **≤30 秒**
   浮現（截圖＋秒數）。
4. E2 的備份還原演練至少實際執行一次（Owner 回填）。
5. **（v1.3）EC 附加驗收（條件項）**：OD-13 合作生效中＝必要項。實連情境
   （Owner 回填）：手機發 SOS → E-CARE `GET /reports` 出現對應 `[IGNI:]` 案件
   （≤60 秒）；後台「E-CARE 通報」分頁顯示同案件（截圖）；App AI 對話 round-trip
   一次成功（截圖）。若 Owner 於 STATUS 書面記錄合作中止 → EC-1～EC-4 標
   SUSPENDED 並自本項移除——**此判定只有 Owner 能做**，AGENT 不得以
   「連不上／沒回應」自行豁免或跳過。

---

## §8 Stage D — 實體硬體（前置：B10 全過 + Owner 完成採購；全程可與 Stage E 並行）

> 全程多數為 USER-GATE（AGENT 寫腳本/韌體，Owner 操作硬體回填）。細節以
> `PHASE3_MODE_B_FIELD_NODE_PLAN.md` §9–§10 為準，此處定任務殼與 DoD 錨點。

| 任務 | 內容 | Exit（全 USER-GATE 回填） |
|---|---|---|
| D1 採購/開箱 | 依 B10 清單；序號/照片記錄 | 板卡點亮、UART log 出字 |
| D2 bench bring-up | SX1262 devicetree/SPI、`sx1262_lora_transport.c` 真驅動（Zephyr LoRa API）、雙板對傳 | NodeA→NodeB 真 LoRa 幀過 mac/crc；RSSI/SNR 記錄 |
| D3 真手機↔真 Node | Node GATT server（A12 契約）、手機連線發 PRESENCE/SOS、NODE_RECEIPT 顯示「已送達節點」 | A11 腳本對 Node 重跑全過 |
| D4 全鏈路 | 手機→Node→LoRa→Gateway(Pi 或 PC+LoRa 收發)→Web 看板 | SOS 端到端 ≤30s 出現於瀏覽器；軌跡 routes 完整 |
| D5 場試 | 戶外距離/遮蔽/功耗/失效案例報告 `docs/FIELD_TRIAL_REPORT.md` | 報告產出 + Owner 驗收 |

LoRa 區域參數：台灣 AS923（923MHz）頻段；功率/duty 依法規；場試前 radio profile
（BW/SF/CR/前導/功率/airtime）必須先寫進 `lora_wire_v1.md` 附章（PHASE3 §3.3 gate）。

---

## §9 已代決事項（OD）與風險

### 9.1 OD 決策表（Owner 任何時點可否決；否決即開修訂任務）

| # | 決策 | 內容 | 依據 |
|---|---|---|---|
| OD-1 | SOS 帶位置 = 選項 A | `StatusUpdateData` 加 `3 location` | PHASE0B4 §3.3 傾向 A；自含證據 |
| OD-2 | LoRa 信任模型 = 節點轉譯背書 | 作者 Ed25519 不過 LoRa；HMAC+出處 | 64B 預算物理上限；白皮書 §8.1 |
| OD-3 | Node↔Gateway = 同一 LORA-WIRE v1 | Gateway 即「會存檔的節點」 | 簡化雙格式維護 |
| OD-4 | App↔Node GATT = 沿用手機 GATT 契約 + NODE_RECEIPT=105 | 手機端零改動成本 | A12 |
| OD-5 | Web 技術 = FastAPI + vanilla JS、零 CDN | 離線場域、Pi 可跑、無 build 鏈 | §7 |
| OD-6 | CHAT 從 App 移除、enum 30 保留 reserved | 白皮書無聊天 | A6 |
| OD-7 | anon_user_id = 16B 隨機、secure storage、與簽章金鑰分離 | 隱私分層 | A2 |
| OD-8 | SOS 取消 = 後送 SAFE STATUS_UPDATE（LWW），不加新 wire 型別 | 零 wire 變更 | A8 |
| OD-9 | 雲端信任模型 = VPS 持每場域 secret 的「雲端閘道」 | 與現場閘道同一驗證管線（Ed25519+field_mac+去重+重放窗）；secret 由 Owner 逐場域佈建於設定檔（web root 外、權限 600）；爆炸半徑=單場域、可換鑰；ingest 無帳號、信封自證+rate limit | `field_join_secret` 本就全場手機共持，單一加固伺服器不實質改變威脅模型；零新驗證邏輯（Owner 2026-06-11 核） |
| OD-10 | 節點**不加** NB-IoT | 蜂巢回程若日後需要，正確位置=閘道（單 SIM/單數據機）；封存為 future，D5 場試見到實際覆蓋缺口再評估 | 與離線前提衝突（同基地台依賴）、每節點 SIM 營運負擔、Stage E 已覆蓋「任一端有網路即上雲」多數需求（Owner 2026-06-11 核） |
| OD-11 | 角色/可見性 = 服務層概念，不進 wire | `owner/staff/member` 與 `peer_visibility∈{all,staff_only}` 存雲端 DB；**SOS 永遠對全場域成員可見，政策不可遮蔽**；離線 mesh 下可見性=App 端遵守（文件如實標註） | wire 契約零變更；信封簡單性與凍結狀態不受商業功能污染（Owner 2026-06-11 核） |
| OD-12 | 場域地圖 = 場域主上傳圖像＋對位點配準（不採線上圖磚） | 2–10 對位點、局部等距投影＋2D 相似變換最小平方；App 與後台兩端過同一份 vectors；只存點集 | 零外網、零圖資授權、自製圖比官方圖磚更貼場域；演算法純函式可測（Owner 2026-06-11 核） |
| OD-13 | E-CARE 跨專案合作＝零改動掛接（v1.3） | 資料層用 E-CARE 後端（`/chat`、`/reports`、status log）；管理畫面＝本專案雲端後台自建分頁讀其 API（EC-4）；存取一律經 Owner VPS 代理＋per-field 金鑰（學校機器不開公網）；禁 `/users` 與 `user_context`（PII）；SOS 零延遲不變量；E-CARE 不可用＝正常態（App 無聲降級）；「AI 對話經 mesh」標 future | E-CARE API 無認證且跑在學校資源（可用性不可控）——代理＋金鑰把安全與停用開關收在 Owner 手上；零改動＝不產生跨團隊維護 fork（Owner 2026-06-12 核） |

### 9.2 風險表

| 風險 | 影響 | 緩解（已排進任務） |
|---|---|---|
| 4-3 型「宣稱綠實際紅」再發生 | 基線腐蝕 | G1/G17/G18 + A0 即時抓 + §10 稽核抽跑 |
| bsim 目標不支援 host socket | B7 E2E 受阻 | B6 步驟 4 已寫 native_sim 備援與啟用條件 |
| LoRa 64B 預算 vs SOS 22B payload+48B 框架=70B | 超 64B 理想線 | spec 已定 ≤128B 審查線；場試實測 airtime（D5） |
| corpus 重生把三端打散 | 跨端不一致 | G7 單一 generator + B2/B6 以同一 corpus 鎖 |
| Windows 上 NCS/west 路徑問題 | B5 卡關 | 用官方 Toolchain Manager；BLOCKED 流程上報 |
| 手機廠商 BLE 怪癖（背景/Doze） | D3 不穩 | 既有 native_transport §8–§10 恢復策略；場試清單 |
| 單人 Owner 簽核瓶頸 | 進度阻塞 | 簽核點集中在 A12/B1/C1/E1/B9 例外/各 Stage Exit |
| VPS 被入侵 → 該場域 MAC 金鑰外洩（v1.2） | 可偽造該場域事件 | OD-9 單場域爆炸半徑＋E2 換鑰程序＋hardening checklist＋E3 rate limit |
| 雲端 ingest 被濫用（垃圾上傳/灌爆）（v1.2） | 資料污染、資源耗盡 | 信封自證（無效即棄不入庫）＋E3 per-IP/per-field 限流＋429 測試 |
| 場域地圖校準不準 → 疊加誤導搜救（v1.2） | 安全風險 | E1 規格強制顯示 RMS 殘差；E7 疊加沿用 A10 可信度/年齡降級；文案鐵則「最後可信位置」 |
| E-CARE 不可用（學校機器關機/學期空窗/合作中止）（v1.3） | AI 對話與通報轉發失效 | EC 不變量 4 降級設計＋EC-3 中止處置（拆代理即全降級）＋SOS 本體零依賴＋§E.8 第 5 項 SUSPEND=Owner-only |
| E-CARE API 無認證遭濫用（v1.3） | 學校資源被盜用、資料污染 | EC-3：學校機器不開公網、只經 VPS 代理＋per-field 金鑰＋限流＋可輪換 |
| 通報重複/遺失（E-CARE `POST /reports` 非冪等）（v1.3） | 儀表板出現重複/缺漏案件 | EC-2 `event_id→report_id` 持久映射＋`[IGNI:]` 對帳標記＋dead-letter log |

---

## §10 進度回報與稽核（反偷懶的執行機制）

### 10.1 STATUS.md 條目模板（每 repo 通用，append-only）

```markdown
## [YYYY-MM-DD] <TaskID> <DONE|PARTIAL|BLOCKED>
- repo/commit: <repo> @ <hash>（DONE 必填）
- DoD: D1 ✅ / D2 ✅ / D3 ❌(缺因…)
- gates:
  - <指令原文> → exit 0
    ```
    <輸出末 20 行>
    ```
- deviations: none｜<偏差與依據（G 條款/OD 編號）>
- next: <下一任務或 BLOCKED 解除條件>
```

### 10.2 Owner 稽核程序（每個 Stage Exit 前執行）

1. 隨機抽 ≥2 個 DONE 任務，**親自重跑**其 DoD 驗證指令——輸出與 STATUS 證據不符 → 該任務
   退回 PARTIAL，且該 AGENT 後續任務全部加抽。
2. `git log --stat` 對照 G5/G10（範圍、一任務一刀）。
3. grep gates 重跑（`_todoWire`/`TODO_CONTRACT`/`PLACEHOLDER`/secret 字樣）。
4. 凍結檔案 diff 檢查（附錄 B 清單自上次稽核以來的變更必有 GATE-CHANGE/G6 記錄）。

### 10.3 AGENT 開工程序（每個 session 開頭照做）

1. 讀本文件 §0/§3 + 目標任務全文 + 該任務引用的 spec 章節。
2. 讀該 repo `STATUS.md` 最新 10 條，確認前置任務皆 DONE（缺 → 停，回報）。
3. 開工先寫 STATUS「開工」行（任務、預計動到的檔案清單）。
4. 收工依 §10.1 模板回報。

---

## 附錄 A — 指令速查

```powershell
# App repo（C:\Users\radio\Downloads\IDE\IgniRelay\ignirelay_app）
flutter pub get
dart run tool/check_layers.dart --strict
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test --exclude-tags golden
dart run tool/check_constants_parity.dart
flutter test test/conformance/wire_conformance_corpus_test.dart
cd android; .\gradlew.bat :app:assembleDebugAndroidTest      # 編譯 instrumentation
cd android; .\gradlew.bat :app:connectedDebugAndroidTest     # 需裝置/emulator

# lab（C:\Users\radio\Downloads\IDE\ignirelay-lab）
python -m unittest discover -s tests
python -m ignirelay_lab.cli --all
python -m ignirelay_lab.cli --scenario e2e_real_stack        # B7 之後

# gateway（C:\Users\radio\Downloads\IDE\ignirelay-gateway）
python -m unittest discover -s tests
python -m ignirelay_gateway.cli config-init                  # B4 之後
uvicorn ignirelay_gateway.api:app --host 0.0.0.0 --port 8088 # C2 之後

# field-node（C:\Users\radio\Downloads\IDE\ignirelay-field-node；需 NCS shell）
west build -b nrf54l15bsim/nrf54l15/cpuapp .
west build -b nrf54l15dk/nrf54l15/cpuapp .
west build -b nrf54l15bsim/nrf54l15/cpuapp tests/core        # ztest
```

## 附錄 B — 凍結契約清單（G6 管制；版本一致性 = Stage Exit 必查）

| 檔案（App repo） | 狀態 |
|---|---|
| `docs/specs/envelope_v2_spec_2026-05-13.md`（含 §21 v3） | 已凍結 |
| `docs/specs/native_transport_v1_2026-05-13.md` | 已凍結 |
| `docs/specs/wire_conformance_v1.json`（rev `v0.3-phase0b-4-3-1` 起） | generator-only |
| `tool/generate_wire_conformance_v1.dart` | G6 管制 |
| `docs/specs/app_node_gatt_v1.md` | A12 產出後凍結 |
| `docs/specs/lora_wire_v1.md` + `lora_wire_v1_vectors.json` + generator | B1 產出後凍結 |
| `docs/specs/node_provisioning_v1.md` | B1 產出後凍結 |
| `docs/API_V1.md`（gateway repo） | C1 產出後凍結 |
| GATT UUID（`IgniRelayConstants.kt/.swift/mesh_constants.dart` 內三組 UUID） | 永久鎖定 |
| `docs/DESIGN_LANGUAGE.md`（repo 根 docs/） | 已凍結（DL 任務交付；v1.1 起） |
| `ignirelay-gateway/webapp/` 範本（`tokens.css`/`app.css`/`index.html` 殼/`app.js`/`DESIGN_README.md`） | 已凍結（殼與 tokens 不得重做；C3 僅准接線與依完成例鋪 panel） |
| `ignirelay-gateway/docs/specs/cloud_api_v1.md` | E1 產出後凍結 |
| `docs/specs/map_calibration_v1.md` + `map_calibration_v1_vectors.json` + `tool/generate_map_calibration_v1.dart` | E1 產出後凍結；vectors generator-only（G7） |
| QR 內容格式 `IGNI1` 五段式（§5 A7 步驟 2） | A7 落地後凍結；「未知尾段必須忽略」鐵則永久有效 |
| EC 對接面：E-CARE `/chat`／`/reports`／`/reports/{id}/status` 之請求/回應欄位（基準＝E-CARE repo commit `4e4543d` 之 `API_SPEC.md`＋`backend/models.py`） | v1.3 起管制：EC 任務開工前必須 diff 上游同三介面，有變更→G8 報 Owner 重核；禁止靜默適配 |

## 附錄 C — LORA-WIRE v1 草案（B1 落定為 normative 前的唯一基準）

```
幀 = hdr(11) ‖ body ‖ mac8(8) ‖ crc16(2)
hdr: ver_ptype u8（高 4 位版本=0x1；低 4 位 ptype）｜flags u8（bit0 hlc_synced,
     bit1 retransmission, bit2 mule_origin, 其餘 0）｜field_tag 4B = field_id[0..3]
     ｜src_node u16 LE｜packet_seq u16 LE｜ttl u8
EVENT(ptype 0x1) body: event_id 16B｜event_type u8（=EventTypeV2 值）｜priority u8
     ｜hlc 8B（u48 ms LE ‖ u16 ctr LE）｜payload_len u8｜payload ≤64B
ACK(ptype 0x2) body: ack_seq u16｜event_id_prefix 8B｜status u8 → 全幀固定 32B
mac8 = HMAC-SHA256(lora_mac_key, hdr‖body)[0..7]
crc16 = CRC-16/CCITT-FALSE(hdr‖body‖mac8)，poly 0x1021 init 0xFFFF
緊湊 payload（B1 凍結表）：
  PRESENCE  10B: anon8(8) battery u8 evid_src u8
  SOS       22B: anon8(8) safety u8 loc{src u8, lat i32 1e7, lng i32 1e7, acc u16, age_s u16}
  CHECKPOINT 10B: anon8(8) checkpoint_node u16
  HEARTBEAT  8B: battery u8 solar u8 uptime_h u16 queue u8 storage_pct u8 fw u16
  HAZARD ≤40B: type u8 sev u8 loc(13) desc_len u8 desc ≤24B
總長：PRESENCE 58B｜CHECKPOINT 58B｜HEARTBEAT 56B｜SOS 70B｜HAZARD ≤88B（審查線 128B）
```

## 附錄 D — Gateway API v1 草案：見 §7 C1 表（C1 落定 normative）。雲端多場域擴充見 Stage E E1（`cloud_api_v1.md`）。

## 附錄 E — App↔Node GATT 草案：見 §5 A12 步驟 1（A12 落定 normative）。

## 附錄 F — 依賴白名單（G13）

| Repo | 允許新增 | 版本 | 理由 |
|---|---|---|---|
| App | `qr_flutter` | ^4.1.0 | A7 QR 顯示 |
| App | `mobile_scanner` | ^5.1.1 | A7 掃碼 |
| lab/gateway | `cryptography` | ==43.x pin | Ed25519/HKDF/HMAC（stdlib 無 Ed25519） |
| gateway | `fastapi` | ==0.111.x pin | C2 API |
| gateway | `uvicorn[standard]` | ==0.30.x pin | C2 server |
| gateway(dev) | `httpx` | ==0.27.x pin | TestClient |
| field-node | （無第三方；只用 Zephyr/PSA 內建） | – | – |
| App | `http` | ^1.2.0 | E4 雲端上傳/下行（**先查 repo 既有等效 HTTP client，有則沿用、不新增**） |
| gateway(cloud) | `Pillow` | ==10.x pin | E3 地圖重編碼（僅 cloud 形態 import；LAN 形態不得依賴） |

> gateway 雲端形態其餘一律 stdlib：密碼雜湊 `hashlib.pbkdf2_hmac`、限流 token bucket
> 自寫、session 自管。TLS 由 E2 的反向代理承擔（系統層佈建，非 Python 依賴）。

其餘一律 G8 問 Owner。

---

## Changelog

- v1.0（2026-06-10）：初版。基線稽核（含 2 紅燈）、Stage A–D 全任務、G1–G18、OD-1–8、
  附錄 A–F。作者：Claude（Owner 委託）。
- v1.1（2026-06-11）：①新增 §0.4 分工表（主理 AI vs 施工 AI）；②A4 / A5 / A12 / B1
  各補「施工筆記」（實檔錨點、整合點、D5 同刀提醒）；③A2 加排程註記（A5 先行則略過
  debug-secret 墊片步驟）；④§5 補 A7–A10 設計 DoD（`Colors.*` grep gate）；⑤C3 改寫為
  「接線既有 `webapp/` 範本」並新增 D4 data-sample=0、D5 DESIGN_LANGUAGE §6 gates；
  ⑥G7 增補同刀規則；⑦附錄 B 增列 `DESIGN_LANGUAGE.md` 與 webapp 範本為凍結項。
  基線狀態：A0 DONE（f2026a3）、A1 PARTIAL—D3 連線測試移 A11（c39070f）、
  DL DONE（gateway repo 347ae52）。作者：Claude（Owner 委託）。
- v1.2（2026-06-11，Owner 拍板的產品範圍擴充）：
  ①**總順序改為 A→B→C→E→D**（§0.3；Stage D 與 Stage E 可整段並行；D 入場條件不變）。
  ②**新增 Stage E「雲端場域服務」整章**（§7 與 §8 之間）：多場域 SaaS（場域主/staff/
  member 三角色、可見性政策、SOS 永不遮蔽）、VPS=雲端閘道（OD-9）、E1–E7 任務與
  §E.8 Exit；產品一句話/資料流/信任邊界/FINAL DoD（§1）同步擴充。
  ③**A10b 雷達相對位置視圖**納入正式範圍（Stage A；A11 腳本加步驟 9；§5.13 同步）。
  ④**E7 場域自訂地圖**（georeferencing，OD-12）納入正式範圍：上傳圖＋2–10 對位點
  ＋相似變換；App 與後台過同一份 vectors（E1 凍結規格）。
  ⑤A7 QR 格式修訂為五段式（段 3 雲端 URL、段 4 staff token、未知尾段忽略鐵則）；
  A5 施工筆記 7 加 `cloud_base_url` 欄位預留；C1 加雲端孿生前向相容註記。
  ⑥OD-9～OD-12 入表（雲端信任模型、節點不加 NB-IoT、角色/可見性=服務層、
  地圖=配準不採圖磚）；風險表加 3 列；附錄 B 凍結清單加 cloud_api/map_calibration/
  QR 格式；附錄 F 加 `http`（App）與 `Pillow`（gateway cloud）。
  ⑦wire 契約（信封/LORA-WIRE/GATT）**零變更**——Stage E 全部掛在服務層。
  作者：Claude（Owner 委託）。
- v1.3（2026-06-12，Owner 拍板的跨專案合作）：
  ①新增 **EC 系列（Stage E 附掛）：E-CARE 跨專案串接**——背景＋6 條 EC 不變量；
  EC-1 App SOS 後援對話（SOS 後彈窗→本地關鍵字圖卡／E-CARE AI 對話＋SOS 通報
  hook）；EC-2 雲端→E-CARE 通報轉發 adapter（只跑 cloud 形態、event_id 映射防
  重複）；EC-3 代理／金鑰佈建（USER-GATE；學校機器不開公網）；EC-4 後台
  「E-CARE 通報」唯讀分頁。§E.8 加第 5 項條件性實連驗收（SUSPEND 判定=Owner-only）。
  ②E1 契約加場域選用設定 `ecare_base_url`/`ecare_api_key`（nullable，隨 app-bundle
  下行）；E6 場域管理加 E-CARE 連線設定欄位。
  ③OD-13 入表；風險表加 3 列；附錄 B 加「EC 對接面」管制列（基準＝E-CARE repo
  `4e4543d`）；§0.1（補列 E 系列任務編號）/§0.3/§0.4/§1.2/§1.3/§4 同步。
  ④紅線：SOS 零延遲（SOS 發佈路徑禁 import EC，grep gate）；E-CARE 程式碼零改動；
  禁 `/users` 與 `user_context`（PII）；AI 輸出只進顯示層；wire 契約零變更
  （「AI 對話經 mesh」明確標 future）。零新增第三方依賴（App 沿用 `http`、
  gateway 走 stdlib）。
  ⑤A0–A12／B／C／D 各任務內容零變更（既有排程不受影響）。
  作者：Claude（Owner 委託）。
- v1.4（2026-06-16，Owner 拍板的 App UI/IA 校正）：
  ①新增 `docs/APP_UI_IA_REWORK_PLAN.md` 作為 App 產品殼重整依據；Stage A 在 A10b 後插入
  **UI-F 正式 AppShell / UI-IA 重整 + motion-aware 定位節流**與 **UI-G「先看功能」/引導模式**
  兩任務，再回 A11/A12。②五分頁定案為 `安全 | 位置 | 事件 | 協助 | 我的`，`地圖` 不作 tab 名；
  `DebugShell` 降級為 debug diagnostics。③首次啟動定案：權限引導後 no-field entry 顯示加入場域
  （QR/密鑰）、建立場域、先看功能；同場域 participant/staff 兩條 join secret，owner 建立者。
  ④A9 固定 120s beacon 僅為既有基線；UI-F production policy 改 motion-aware（moving 30s、
  stationary 180s、low battery 降頻），使用低頻 motion sensor，不用 step counter/Activity Recognition、
  不新增 sensor 依賴。⑤A11 雙機腳本改驗正式 AppShell、角色 QR、global SOS、motion-aware 診斷與
  `位置` 雷達；wire/GATT/crypto 契約零變更。作者：Codex（Owner 明示授權）。
- v1.5（2026-06-16，Claude review #1 後的施工收斂）：
  ①修正 v1.4 的角色/QR 語意：Stage A offline 同場域只用一條 `field_join_secret`，creator=`owner`、
  joiner=`participant`；`staff` QR/會員資格延後到 Stage E cloud staff-token 或另開 QR 契約任務，
  不得用第二條 field secret 造成不同 `field_id`。②UI-F 拆成 UI-F0～UI-F5 小任務，避免一刀混
  AppShell、模組搬遷、角色模型、CommunicationState、motion cadence。③motion source 改明確要求窄版
  Android `SensorManager`/注入式 source、hysteresis、無 `ACTIVITY_RECOGNITION`、無 `sensors_plus`。
  ④A11 改驗 owner+participant，補 motion 權限查核；visibility policy 只釘「SOS 永不被角色/可見性隱藏」，
  完整 `peer_visibility=staff_only` 留 Stage E。作者：Codex（Owner 要求審查後完善）。
