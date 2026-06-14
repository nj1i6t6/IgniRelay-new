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

## [2026-06-12] CORRECTION — 歷史條目 commit hash 回填（append-only 補正）

- 依 G9「DONE 必附 commit hash」字面要求，回填先前以「（見本 commit）」記載之條目
  （施工 AI 於 A2 開工檢視時指出，判定有效）：
  - A0 DONE = `f2026a3`
  - A1 PARTIAL = `c39070f`
  - DL DONE（App repo 部分）= `c73b248`（gateway repo `347ae52` 原已記載）
  - PLAN-v1.1 DONE = `c136591`
  - PLAN-v1.2 DONE = `0c9fe71`
- 根因：條目與變更同 commit 寫入，寫入當下無法預知自身 hash。
- 自本日起改採兩段式：先 commit 變更本體，再以後續 commit 記 STATUS 條目（含字面 hash）。

---

## [2026-06-12] PLAN-v1.3 DONE（計畫修訂，G11 Owner 授權路徑；E-CARE 跨專案串接）

- repo/commit: IgniRelay @ `172e15e`（計畫本體；本條目為後續 commit）
- 執行者: Claude（主理 AI，Owner 2026-06-12 口頭逐項拍板後執行）
- Owner 決策（本次修訂依據）:
  1. 與校內 E-CARE 專案（`github.com/rungyu0721/Ecare`，FastAPI 緊急事件輔助後端，
     跑學校 GPU 資源）合作；合作模式＝零改動掛接（OD-13）。
  2. UX：SOS 送出後彈窗詢問→同意進對話框；無網路＝關鍵字觸發本地圖卡、
     有網路＝E-CARE AI 對話。SOS 本體零延遲、零依賴。
  3. 管理端：本專案雲端後台（E6）為完整主控台；「E-CARE 通報」為其中一個
     唯讀分頁（EC-4），資料層用 E-CARE 後端。
  4. Demo 無時程壓力 → EC 全數排 Stage E 窗口，A→B→C 既有排程不動。
- 變更（v1.2 → v1.3，詳文件 Changelog v1.3 條目）:
  - 新增 EC 系列（Stage E 附掛）：背景＋EC 六不變量＋EC-1（App SOS 後援對話）
    ＋EC-2（雲端→E-CARE 通報轉發 adapter，僅 cloud 形態）＋EC-3（VPS 代理／金鑰，
    USER-GATE）＋EC-4（後台唯讀分頁）；§E.8 加第 5 項條件性實連驗收
    （SUSPEND 判定=Owner-only）。
  - E1 契約加 `ecare_base_url`/`ecare_api_key`（nullable，隨 app-bundle 下行）；
    E6 加 E-CARE 連線設定。
  - OD-13 入表；風險表 +3；附錄 B 加「EC 對接面」管制列
    （基準＝E-CARE repo commit `4e4543d` 之 API_SPEC.md＋backend/models.py）；
    §0.1/§0.3/§0.4/§1.2/§1.3/§4 同步。
- DoD: 版號 bump ✅ / Changelog ✅ / A–D 任務內容零變更 ✅ / wire 契約檔 diff=0 ✅
  （純文件修訂，未觸碼；工作區中施工 AI 的 A2 進行中檔案未被本次 commit 觸及）
- deviations: none
- next: 施工 AI 續 A2；EC-1～EC-4 待 Stage E 窗口（EC-1 前置 E4、EC-2 前置 E3、
  EC-3 前置 E2、EC-4 前置 EC-2+E6）；E1 動工時記得納入 ecare 設定欄位

---

## [2026-06-12] DOC-WP DONE（對外白皮書 + README 重寫，Owner 委託）

- repo/commit: IgniRelay @ `6aa2495`（文件本體；本條目為後續 commit）
- 執行者: Claude（主理 AI，Owner 委託——比賽/合作文件之基礎藍圖）
- 交付:
  - `docs/WHITEPAPER.md` 對外版 v1.0：問題/方案/降級階梯/信封架構/
    **E-CARE 整章（§4，成果具名歸屬其團隊）**/誠實定位與自訂地圖/安全模型/
    場域即服務商業模式/五階段路線圖（✅🔧📋💡 四態誠實標注）/規格速查/名詞表。
    開頭聲明與內部《技術白皮書 v2.0》之區隔（工程文件引用「白皮書 §x」指後者）。
  - `README.zh-Hant.md`（主）/`README.md`（英）重寫：fork 基線之舊產品描述
    （物資媒合/聊天室/醫療卡/離線圖磚）汰換為重建方向；保留仍有效之
    quick start/品質檢查/OSM attribution。
- 紀律: 所有「已完成」陳述皆有測試/commit 依據；規劃中項目一律標 📋/💡，
  不以現況語氣陳述（比賽答辯防穿幫）。E-CARE 能力描述以其 repo @ 4e4543d
  實際程式碼為準（微調 LLM/PFA/情緒辨識/雙層風險引擎/本地 TTS/77+36+52 測試）。
- 待 Owner 回填: 白皮書 §9 與 README 之〔待填〕——正式姓名/系所、E-CARE 團隊
  成員名單、指導教授；授權確認（fork 基線標示 AGPL-3.0 但 repo 無 LICENSE 檔，
  對外發布前須補齊）。
- deviations: none
- next: Owner 校閱兩份文件；比賽文件自 WHITEPAPER 裁切

---

## [2026-06-14] A2 DONE（4-4 PRESENCE 發佈/接收/顯示接線）

- repo/commit: IgniRelay @ `e0b4eff`（變更本體；本條目為後續 commit）
- 執行者: 施工 AI（Claude，Owner 授權 session）
- 開工前置檢查（A2 步驟 4 排程注意）:
  - `rg -n "ActiveFieldController|FieldSessionStore" ignirelay_app/lib ignirelay_app/test`
    → 無結果（A5 未落地）→ 依步驟 4 允許引入 `kDebugFieldJoinSecretHex`
      （TEST-ONLY + `@visibleForTesting`，定義於 facade，僅 facade 內使用），A5 以
      grep gate 移除。**未引入 debug secret 以外的任何 field 捷徑。**
- 變更（皆在 `e0b4eff`）:
  - 新檔 `lib/app/services/anon_identity.dart`：`AnonIdentityService.getOrCreate()`
    產 16B CSPRNG `anon_user_id`，存 `flutter_secure_storage`（key `anon_user_id_v1`，
    hex）；`rotate()` 留介面（Phase 2）；**不以 Ed25519 pubkey 當 id**；`SecureKvStore`
    抽象供測試注入。
  - 新檔 `lib/app/services/location_evidence_builder.dart`：包 `LocationService`，
    GPS 可用→`LocationEvidence(GPS/SUBJECT, 1e7 round-to-nearest, observed_at=HLC.now)`，
    不可用→`null`。
  - 新檔 `lib/app/controllers/presence_controller.dart`：app 層編排（anon + location
    evidence → `facade.publishPresence`），讓 UI 不 import `app/proto`。
  - `EventPublisherV2Facade.publishPresence({anonUserId, location?, batteryHint?})`：
    `PresenceData` / `EventTypeV2.presence` / `PriorityV2.normal` / TTL 4h（spec §11.2）/
    maxHops 4；A2 debug field 派生 field_id/mac_key 餵 publisher（dispatcher
    field-scope check 仍 OFF）。field 上下文穿過 `_broadcast`/`_PendingPublish`/
    `_sendToPeers`/`_drainQueue`（in-memory；**Outbox_V2 schema 不動，留 A5**）。
  - `ble_v2_bridge.sendEnvelope` 增 optional `fieldId`/`fieldMacKey`（null→沿用
    `zeroFieldId` 既有行為，其餘 publish 路徑不變）。
  - `event_types.dart`：`LocalReadModelType.presence = 9001`（local read-model only,
    never on wire）。
  - `v2_inbound_projector`：PRESENCE case → `Event_Logs`（event_type=9001，
    payload=JSON snapshot `{anon8,src,lat?,lng?,acc?,battery?,observed_ms}`）；
    dedup 沿用 `event_id`（`v2-<hex>`）。
  - `event_stream`：`presenceUpdates` typed stream + `PresenceUpdate`（純 Dart）。
  - `debug_shell`：「發 PRESENCE」改真 publish（顯示 `BroadcastOutcome`）；位置卡改
    渲染最近 PRESENCE evidence 清單（anon8/來源/座標/時間）。
  - `main.dart`：`PresenceController` provider。
- 測試（新增/更新，皆綠）:
  - `anon_identity_test`（5）：16B / persist / CSPRNG 非 pubkey / 壞值重生 / rotate 未實作。
  - `location_evidence_builder_test`（5）：null when no GPS / GPS evidence /
    1e7 round（含 `25.0339805` → `250339805`）。
  - `event_publisher_v2_facade_test`：`publishPresence` wire spec（NORMAL/4h/maxHops4）
    + payload roundtrip + 非零 field_id（= 由 debug secret 派生之 deriveFieldId）。
  - `v2_inbound_projector_test`：PRESENCE 投影 + presenceUpdates 流；同 envelope
    投影兩次→一筆（以可控 outcomes stream 餵兩次 DispatchAccepted）。
  - `debug_shell_smoke_test`：PRESENCE 按鈕真 publish（非占位 `尚未接線`），佇列深度 +1。
  - `provider_wiring_smoke_test`：補 `PresenceController`。
- DoD: D1 ✅ / D2 ✅ / D3 ✅ / D4 ✅（GATE-CONF-DART 綠；未動 corpus——PRESENCE wire
  格式自 4-1 起未變，無需 generator 重生）
- gates（G17 逐字執行，皆 exit 0）:
  - `dart run tool/check_layers.dart --strict`
    → exit 0，`[check_layers] ok — no boundary violations`
  - `flutter analyze --no-fatal-infos --no-fatal-warnings`
    → exit 0，`2 issues found`（2 個既有 info：battery_optimization_guide
      use_build_context_synchronously），**0 errors**
  - `flutter test --exclude-tags golden`
    → exit 0，`00:15 +483 ~3: All tests passed!`（基線 A0 為 +469；本刀 +14）
  - `flutter test test/conformance/wire_conformance_corpus_test.dart`
    → exit 0，`00:00 +21: All tests passed!`
  - （附帶，非 A2 必跑）`dart run tool/check_constants_parity.dart` → exit 0
- deviations: 無偏離 A2 範圍。A2 過渡 `kDebugFieldJoinSecretHex` 將於 A5 移除（grep gate）。
- next: A3（4-5 HAZARD typed payload，施工 AI）；主理 AI 可接 A4/A5。

### A2 ADDENDUM（review 回應，commit `f2ea83e`）

- review #1（測試證據可更硬）→ **已處理**：新增 hardening 測試
  `event_publisher_v2_facade_test`「A2 hardening — PRESENCE final wire envelope
  carries a real, receiver-verifiable field_mac」：經真實 `BleV2Bridge.sendEnvelope`
  產 `PublishedEnvelope` → `EventEnvelopeV2.decode(wireBytes)` 斷言 field_id 非零、
  field_mac 16B；再以 `enableFieldScopeCheck:true` + `FieldKeyStore.fromSecrets`
  證同場域成員 ACCEPT、外場域 `field-scope-mismatch` DROP。
  GATE-TEST → `+484 ~3 All tests passed!`（exit 0）；其餘三門維持綠。
- review #2（Outbox 重啟不保留 field context）→ **已知技術債，A2 程式碼註解標明，A5
  補 schema 收回**（非 A3 blocker）。
- review #3（live GPS accuracy 無來源，LocationService 僅存 LatLng）→ **已知，
  builder 支援 accuracyM 但 production 路徑無來源；補 LocationService 屬另刀範圍**
  （非 A3 blocker）。
