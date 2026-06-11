# IgniRelay App repo — 施工狀態紀錄（append-only）

> 格式依 `docs/MASTER_EXECUTION_PLAN.md` §10.1。每任務開工/收工都要記。
> DONE 必附 commit hash 與 gate 證據；沒有證據 = 未完成（G1）。

---

## [2026-06-10] A0 DONE

- repo/commit: IgniRelay @ （見本 commit）
- 執行者: Claude（主理 AI，Owner 授權 session）
- 根因分析:
  - **紅燈 #1** `envelope_pipeline_v2_test.dart` "unknown-protocol-version"：
    fork 版測試以 `protocolVersion: 3` 作為「未知版本」竄改值（當時 accepted=2）。
    4-3（f8d4b96）把 `_acceptedProtocolVersion` 升為 3，但未同步調整此測試字面值，
    導致測試變成「對被接受的版本斷言 drop」→ 紅。**dispatcher 本身行為正確**
    （pv≠3 確實 drop），屬 G3a「測試本身錯誤」情形。修法：竄改值改為迴圈
    `[2, 4]`（legacy 與 future 各一），覆蓋強度提升、未弱化。
  - **紅燈 #2** `v2_inbound_projector_test.dart`：f8d4b96 以有損編碼重存了
    5 個測試檔，非 ASCII 字元（`受困`、`—`、`→`、`§`）被打成 `?`。其中
    `expect(sos.description, '受困')` 的字面值變 `'?'` → 紅。產品輸出
    （`v2_inbound_projector.dart:240` `_noteForSafetyState(TRAPPED)='受困'`）正確。
  - **損毀全面清查**：以 fork(30eed86) 與 f8d4b96 的逐檔非 ASCII byte 計數比對，
    受損 5 檔：envelope_pipeline_v2_test(27→0)、canonical_encoder_v2_test(9→0)、
    ble_v2_bridge_test(12→0)、protocol_hello_test(493→323)、
    v2_inbound_projector_test(30→15)。以 `tool/repair_f8d4b96_mojibake.py`
    （ASCII 殘文比對、只還原「僅非 ASCII 受損」的行）還原 21 行；
    `canonical_encoder_v2_test` 經人工核對為 4-3 合法 ASCII 改寫（"section 21.4"
    等），非損毀，維持現狀。
- DoD: D1 ✅（根因如上，dispatcher 無需修；覆蓋保留於同名測試）/ D2 ✅ / D3 ✅
- gates:
  - `flutter test --exclude-tags golden` → exit 0，`00:12 +469 ~3: All tests passed!`
    （基線原為 +467 -2）
  - `dart run tool/check_layers.dart --strict` → exit 0，`ok — no boundary violations`
  - `flutter analyze --no-fatal-infos --no-fatal-warnings` → exit 0，0 errors
    （2 個既有 info：battery_optimization_guide use_build_context_synchronously）
  - `flutter test test/conformance/wire_conformance_corpus_test.dart` → exit 0，+21 全綠
- deviations: none
- next: A1（Kotlin/Swift v3 parity）

---

## [2026-06-10] A1 PARTIAL（D3 遞延 A11，依計畫允許）

- repo/commit: IgniRelay @ （見本 commit）
- 執行者: Claude（主理 AI）
- 變更:
  - `IgniRelayConstants.kt` / `IgniRelayConstants.swift`：`PROTOCOL_VERSION_V2 = 2`
    → `PROTOCOL_VERSION_V3 = 3`（原生程式碼無其他引用點，純宣告改名）。
  - `tool/check_constants_parity.dart`：移除 4-3b 遞延註解，加回
    `PROTOCOL_VERSION_V3` 條目（13 個常數）。
  - `WireConformanceInstrumentationTest.kt` / `WireConformanceTests.swift`：
    corpus_revision 斷言 `v0.3-stage0c-wave3d-1` → `v0.3-phase0b-4-3-1`
    （= 現行 `wire_conformance_v1.json` 實值；數量門檻不變：
    envelope 104≥100 / chunking 20 / iblt 52≥50 / bloom 30 / negative 11≥10）。
- DoD: D1 ✅ / D2 ✅ / D3 ❌（無實體裝置：`adb devices` 空清單；依 A1 DoD 規定
  記 PARTIAL，D3 併入 A11 USER-GATE 執行）/ D4 ✅（Swift source parity 完成；
  Windows 無法編譯 iOS — R3 既知限制，已註記）
- gates:
  - `dart run tool/check_constants_parity.dart` → exit 0，
    `check_constants_parity: OK (13 constants in sync)`
  - `gradlew.bat :app:assembleDebugAndroidTest` → exit 0，`BUILD SUCCESSFUL in 2m 42s`
  - `flutter analyze` → exit 0（Dart 端僅 parity 工具變更）
- deviations: D3 遞延（計畫 A1 DoD 明文允許之 PARTIAL 路徑）
- next: 設計語言規範 + Web 範本（DL 任務），再 A4/A5/A12/B1 細化

---

## [2026-06-11] DL DONE（設計語言規範 + Web 範本）

- repo/commit: IgniRelay @（見本 commit）＋ ignirelay-gateway @ 347ae52（webapp 範本）
- 執行者: Claude（主理 AI）
- 交付:
  - 本 repo `docs/DESIGN_LANGUAGE.md`：normative 凍結規範。§1 立場（ops-console）、
    §2 tokens（hex 取自 App `IgniPalette` dark 實值）、§3 Web 規則（必須沿用範本、
    tokens.css 唯一色彩來源）、§4 App 規則（IgniPalette/IgniTokens/ui-widgets 強制、
    screens 禁 `Colors.*`）、§5 禁用清單、§6 enforcement gates（grep/python 指令）、
    §7 範本檔案清單 + data-sample 移除 gate。
  - gateway repo `webapp/`：`tokens.css`（CSS vars）、`app.css`（元件樣式，僅 var()）、
    `index.html`（殼 + SOS 看板完成例，假資料節點全標 `data-sample`）、`app.js`
    （tabs/clock/relTime/setConn；`apiGet()` 刻意 throw 防假接線）、
    `DESIGN_README.md`（接手 AGENT 第一頁，6 條硬規則）。
- gates（DESIGN_LANGUAGE §6 自查，於範本交付時執行）:
  - 漸層掃描（`gradient`）→ 0 件；CDN/外部 URL 掃描 → 0 件（僅相對路徑）
  - `app.css`/`index.html`/`app.js` 色彩字面值掃描 → 0 件（hex 僅存在 tokens.css）
  - emoji 掃描（Python codepoint 檢查）→ 0 件
- deviations: none
- next: MASTER_EXECUTION_PLAN v1.1（分工表 + A4/A5/A12/B1 施工筆記 + C3/G7/附錄 B 增補）

---

## [2026-06-11] PLAN-v1.1 DONE（計畫修訂，G11 Owner 授權路徑）

- repo/commit: IgniRelay @（見本 commit）
- 執行者: Claude（主理 AI，Owner 本 session 明示授權修訂）
- 變更（v1.0 → v1.1，詳文末 Changelog）:
  1. §0.4 分工表：主理 AI（A0/A1/DL/A4/A5/A12/B1/階段稽核）vs 施工 AI（其餘）。
  2. A4 / A5 / A12 / B1 各補「施工筆記」：實檔錨點（如 `ble_v2_bridge.dart:285`
     zeroFieldId、DB version 12→13、`StatusUpdateData` field 3 空位、
     NODE_RECEIPT=105、HKDF info 字串、CRC 驗證值 0x29B1）、整合點、D5 同刀提醒。
  3. A2 排程註記：A5 先行則略過 debug-secret 墊片。
  4. §5 A7–A10 設計 DoD：`Colors.*` grep gate。
  5. C3 改寫：起點 = 已凍結 webapp 範本；新增 D4（data-sample=0）、
     D5（DESIGN_LANGUAGE §6 gates）；禁止重做殼/繞 apiGet()/假回傳。
  6. G7 同刀規則：corpus_revision 變更必須同刀更新三端硬編斷言（4-3 教訓）。
  7. 附錄 B 增列 `DESIGN_LANGUAGE.md` 與 webapp 範本為凍結項。
- DoD: 計畫版號 bump ✅ / Changelog 條目 ✅ / 凍結清單同步 ✅
- deviations: none
- next: 主理 AI 待 A2/A3（施工 AI）落地後接 A4/A5；A12/B1 可先行（無 A2/A3 依賴）

---

## [2026-06-11] PLAN-v1.2 DONE（計畫修訂，G11 Owner 授權路徑；Owner 拍板之產品範圍擴充）

- repo/commit: IgniRelay @（見本 commit）
- 執行者: Claude（主理 AI，Owner 本 session 口頭拍板逐項確認後執行）
- Owner 決策（2026-06-11，本次修訂依據）:
  1. 總順序改 A→B→C→**E**→D；Stage D 與 Stage E 可整段並行（D 入場條件 B10 不變）。
  2. 新增「雲端場域服務」（Owner VPS + 網域）：多場域 SaaS——場域主/工作人員/
     一般成員三角色、可見性政策（SOS 永不遮蔽）、手機與現場閘道雙路上雲；
     v1 無自助註冊無金流（CLI 手動開通）。
  3. 雷達相對位置視圖與場域自訂地圖由「選配」升格為**正式任務**（A10b、E7）。
  4. 節點不加 NB-IoT（OD-10 封存為閘道 future）。
- 變更（v1.1 → v1.2，詳文件 Changelog v1.2 條目）:
  - §0.3/§0.4/§1（一句話/資料流/信任邊界/FINAL DoD）/§4 依賴圖 全面同步。
  - 新增 Stage E 整章（§7 與 §8 之間）：E 不變量 6 條（wire 零變更、同一驗證管線、
    角色不進 wire、SOS 底線、隱私紅線、密鑰紅線）+ E1–E7 任務（各含 DoD/禁止）
    + §E.8 Exit（含 ≤5s 自動化 e2e 與 Owner 外網驗收 USER-GATE）。
  - 新增 A10b（雷達；純顯示層、北朝上、零新依賴）+ A11 步驟 9 + §5.13 同步。
  - A7 QR 凍結格式修訂為五段式（段3=https 雲端 URL、段4=staff token、
    未知尾段忽略鐵則）；A5 施工筆記 7 預留 `cloud_base_url` 欄。
  - C1 加雲端孿生前向相容註記（`/api/v1/fields/{fid}` 前綴擴充法）。
  - OD-9～OD-12 入表；風險表 +3；附錄 B +3 凍結項（cloud_api_v1、
    map_calibration_v1+vectors+generator、QR 五段式）；附錄 F +`http`/+`Pillow`。
- DoD: 版號 bump ✅ / Changelog ✅ / 凍結清單同步 ✅ / wire 契約檔 diff=0 ✅
  （本次修訂純文件，未觸碼）
- deviations: none
- next: 主理 AI 可先行 A12/B1；E1 排在 C1 凍結後。施工 AI 維持 A2 起跑（A2 開工前
  重檢 ActiveFieldController 是否已存在，見 A2 步驟 4 排程注意）

---

## [2026-06-11] A2 DONE（4-4：PRESENCE 發佈/接收/顯示接線）

- repo/commit: IgniRelay @ acf7172
- 執行者: 施工 AI
- 變更:
  - `lib/app/services/anon_identity.dart`（新）：16B 隨機 `anon_user_id`，
    存 `flutter_secure_storage`（key `anon_user_id_v1`），`getOrCreate()` 幂等。
    不使用 Ed25519 pubkey（OD-7 隱私分離）。A5 會補 rotate API。
  - `lib/app/services/location_evidence_builder.dart`（新）：包 `LocationService`，
    GPS 可用→`LocationEvidence(source:GPS, frame:SUBJECT, 1e7 round-to-nearest,
    observed_at=HLC.now())`；不可用→null。`forTest()` 注入自訂 provider。
  - `lib/app/services/event_publisher_v2_facade.dart`：+`publishPresence(anonUserId,
    latDegrees?, lngDegrees?, accuracyM, batteryHint)` → `PresenceData.encode()`，
    `EventTypeV2.presence`，`PriorityV2.normal`，TTL=4h（spec §11.2），maxHops=4。
    UI 層不需 import proto（facade 收 plain double）。
  - `lib/app/services/v2_inbound_projector.dart`：+`case EventTypeV2.presence` →
    `_projectPresence()`：解 `PresenceData`，寫 `Event_Logs`（event_type=19，
    read-model only, never on wire），content 存 JSON snapshot（anon8/src/lat/lng/
    acc/battery/observed_ms）。
  - `lib/app/mesh/event_types.dart`：+`static const int presence = 19`（read-model
    only, never on wire）。
  - `lib/app/controllers/event_stream.dart`：+`PresenceUpdate` wrapper 型別、
    `presenceUpdates` typed stream、`EventType.presence` dispatch case（JSON decode
    snapshot）。
  - `lib/ui/shell/debug_shell.dart`：PRESENCE 按鈕 → `_publishPresence()` 真實呼叫
    `facade.publishPresence()`；位置卡改為渲染最新 `PresenceUpdate` evidence
    （anon8/座標/accuracy/battery/時間），取代 `_todoWire` 占位。
  - `ActiveFieldController`/`FieldSessionStore` 不存在 → 未引入
    `kDebugFieldJoinSecretHex`（field ID 由 bridge `zeroFieldId()` 處理，
    dispatcher field-scope 仍 OFF；A5 收回）。
- DoD:
  - D1 ✅ `publishPresence` 全鏈 facade→publisher v3 簽章+field_mac→bridge 單元測試綠
  - D2 ✅ inbound PRESENCE → `Event_Logs` 投影 + `presenceUpdates` 流測試綠
    （含重複投影僅一筆 dedup）
  - D3 ✅ debug shell PRESENCE 按鈕為真實作（widget test 斷言非 snackbar 占位文案）
  - D4 ✅ 通用 gate 全綠
- gates:
  - `dart run tool/check_layers.dart --strict` → exit 0，
    `ok — no boundary violations`
  - `flutter analyze --no-fatal-infos --no-fatal-warnings` → exit 0，0 errors
    （2 個既有 info：battery_optimization_guide use_build_context_synchronously）
  - `flutter test --exclude-tags golden` → exit 0，
    `00:12 +477 ~3: All tests passed!`（+8 新測試）
  - `flutter test test/conformance/wire_conformance_corpus_test.dart` → exit 0，
    +21 全綠
- deviations: none（field secret 過渡步驟因 ActiveFieldController 不存在而跳過，
  依 A2 步驟 4 排程注意允許）
- next: A3（HAZARD typed payload）/ A4（SOS location）/ A5（FieldSession + field-scope）
