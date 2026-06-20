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

---

## [2026-06-14] A3 DONE（4-5 HAZARD 換 typed payload）

- repo/commit: IgniRelay @ `8c91657`（變更本體；本條目為後續 commit）
- 執行者: 施工 AI（Claude，Owner 授權 session）
- 開工前置: 讀 MASTER v1.3 §A3（v1.3 changelog：A–D 任務內容零變更，A3 與 v1.2 同）
  + 本 STATUS 之 A2 DONE/ADDENDUM。僅做 A3，未碰 A4/A5/FieldSession，未改 MASTER。
- 變更（皆在 `8c91657`）:
  - `EventPublisherV2Facade.publishHazardMarker`：raw `payload` → 結構化參數
    `(hazardType, severity, location?, description, isConfirmation, priority)`，內部
    `HazardMarkerData.encode()`。description 超 `kDescriptionMaxLen`(280) → **同步拋
    `ArgumentError`**（spec §9 HAZARD/ALERT ≤800B 之發佈端防護；publisher 既有
    `PayloadBudgetV2` 仍為 wire 硬上限，defense-in-depth）。
  - 新檔 `lib/app/services/hazard_type_codec.dart`：`HazardType` enum ↔ v1 read-model
    字串（FIRE/FLOOD/…/ROADBLOCK/OTHER/UNKNOWN）單一來源，避免 sender/projector 漂移；
    `fromV1String` 大小寫不敏感 + 別名，未知→`other`（不丟）。
  - `event_publisher._dualWriteHazardMarker`：JSON shim → typed 呼叫（字串 `type` 經
    codec → `HazardType`；lat/lng → `LocationEvidence(GPS/OBSERVER)`；移除 `dart:convert`）。
  - `v2_inbound_projector._projectHazard`：`jsonDecode` shim → `HazardMarkerData.decode()`，
    `HazardType` → v1 字串經 codec；投影 `Hazards_State` read-model 路徑不變。
    **typed payload 無 radius 欄（reserved）→ read-model 用預設 200m；radius 僅留 v1 path。**
  - 移除 `hazard_marker_v0_3_json_shim` 全部殘留（lib + test）。
- 測試（新增/更新，皆綠）:
  - `hazard_type_codec_test`（4）：enum↔字串 roundtrip、canonical 形、大小寫/別名、未知 fallback。
  - `event_publisher_v2_facade_test`：`publishHazardMarker` typed payload roundtrip
    （eventType=HAZARD/priority=ALERT/maxHops10、HazardMarkerData decode 對齊）+
    超長 description `throwsArgumentError`（cap 邊界放行）。
  - `event_publisher_dual_write_test`：spy 改收結構化參數，斷言 `HazardType.fire`/
    severity/location（不再有 json shim 斷言）。
  - `v2_inbound_projector_test`：hazard 測試改送 typed `HazardMarkerData` payload，
    斷言 read-model `type='FLOOD'`/severity/lat + `hazardEvents` 流。
  - `event_envelope_v2_test` 之 `HazardMarkerData` roundtrip 既有綠（未動 proto）。
- DoD: D1 ✅（`grep -rn "json_shim" lib/ test/` → 0）/ D2 ✅ / D3 ✅ / D4 ✅
- step 5（corpus 增補 typed hazard 樣本）: **依 §0.4 分工屬主理 AI（corpus·vectors
  重生 + G7 同刀三端 parity），本刀不動 corpus。** wire envelope 格式未變、payload 對
  corpus 不透明（`generate_wire_conformance_v1.dart` 零 hazard 參照；corpus 之
  `event_type=50` 樣本 payload 為任意位元組，非 shim/typed），故 GATE-CONF-DART 不受
  影響、D4 獨立滿足。建議主理 AI 後續以 generator 增補 typed HAZARD 樣本鎖跨端契約。
- gates（G17 逐字執行，皆 exit 0）:
  - `dart run tool/check_layers.dart --strict` → `[check_layers] ok — no boundary violations`
  - `flutter analyze --no-fatal-infos --no-fatal-warnings` → `2 issues found`（2 既有
    info：battery_optimization_guide），**0 errors**
  - `flutter test --exclude-tags golden` → `00:13 +490 ~3: All tests passed!`（A2 後 +484 → +490）
  - `flutter test test/conformance/wire_conformance_corpus_test.dart` → `+21 All tests passed!`
- deviations: 無偏離 A3 範圍。step 5 corpus 增補移交主理 AI（理由如上）。
- next: A4（4-6 SOS 自帶位置，OD-1）或 A6（殘留清理）；A4/A5 為主理 AI 任務。

### A3 step-5 CLOSURE（角色變更：本 session 經 Owner 指派接任主理 AI）

- Owner 2026-06-14 指派本 session 接任 IgniRelay 主理 AI（原主理 AI 不可用）。
  A3 step 5（typed HAZARD conformance 樣本）原因角色分工 deferred，現由本 session
  以主理 AI 身分於 A4 corpus 重生一併補上（Owner 授權「A4 corpus 更新一併補」）。
  **已於 A4 commit `f49889e` 完成**：generator Group F 新增 typed HazardMarkerData
  樣本（`hazard_typed_flood`），經 generator 重生（非手改 corpus）。此債清除。

---

## [2026-06-14] A4 DONE（4-6 SOS 自帶位置；OD-1）

- repo/commit: IgniRelay @ `f49889e`（變更本體；本條目為後續 commit）
- 執行者: 主理 AI（Claude，Owner 2026-06-14 指派接任）
- 依據: MASTER_EXECUTION_PLAN OD-1（Owner 書面核准，additive proto3 欄位 3）。
- 變更（皆在 `f49889e`）:
  - `StatusUpdateData`：加 nullable `location`（field 3，null=absent）；encode 僅在
    `location!=null` 時發 field 3（**無位置 SOS 與 4-6 前 byte-identical**）；decode 加
    `case 3`。欄位號 3 凍結。`impliedPriorityFloor` 不受 location 影響。
  - facade `publishStatusUpdate`/`publishSosStatus`：接 `LocationEvidence?`（無 GPS=null 照發）。
  - projector `_projectStatus`：location present → 投影 lat/lng 進 read-model
    （`received_lat/lng`）；absent → null（back-compat）。更新「carries no location」舊註解。
  - spec `envelope_v2_spec_2026-05-13.md §5.1`：proto fragment 加
    `LocationEvidence location = 3`，`reserved 3..15` → `4..15`（G6：OD-1 書面依據）。
  - generator：新增 typed-payload emitter（`explicitPayload`，always `payload_hex`）+
    Group F 三樣本（StatusUpdateData TRAPPED+2needs+full location bearing-absent、
    TRAPPED+location bearing=0 正北、typed HazardMarkerData FLOOD）。
    `corpus_revision` bump `v0.3-phase0b-4-3-1` → `v0.3-phase0b-4-6-1`，
    **generator 重生（非手改）**；corpus diff = +97/−1（1 行 revision + 3 樣本，
    既有 104 樣本 byte-identical）。envelope_samples 104 → 107。
  - 三端 `corpus_revision` 同刀對齊（G7）：Dart conformance test / Kotlin
    `WireConformanceInstrumentationTest.kt` / Swift `WireConformanceTests.swift`
    （數量門檻皆 `>=`，新增樣本不破門檻）。
- 測試（新增/更新，皆綠）:
  - `event_envelope_v2_test`：location roundtrip（bearing absent + bearing 0 ≠ absent）
    + no-location byte-identical + decode null + `impliedPriorityFloor` 不變回歸（施工筆記 #6）。
  - `event_publisher_v2_facade_test`：`publishSosStatus` location passthrough
    （payload decode 對齊；no-location 照發）。
  - `v2_inbound_projector_test`：e2e SOS+location → read-model `received_lat/lng`；
    no-location → null；**budget：TRAPPED+2needs+full location 信封 ≤240B**（施工筆記 #3）。
  - `event_publisher_dual_write_test`：spy `publishStatusUpdate` override 補 location 參數。
- DoD: D1 ✅ / D2 ✅ / D3 ✅ / D4 ✅ / D5 ✅（三端同刀 + GATE-KOTLIN-BUILD 綠）
- gates（G17 逐字執行，皆 exit 0）:
  - `dart run tool/check_layers.dart --strict` → `[check_layers] ok — no boundary violations`
  - `flutter analyze --no-fatal-infos --no-fatal-warnings` → `2 issues found`（2 既有
    info：battery_optimization_guide），**0 errors**
  - `flutter test --exclude-tags golden` → `00:14 +498 ~3: All tests passed!`（A3 後 +490 → +498）
  - `flutter test test/conformance/wire_conformance_corpus_test.dart` → `+21 All tests passed!`
    （另：`dart run tool/generate_wire_conformance_v1.dart --check` → 確定性 OK）
  - `cd android; .\gradlew.bat :app:assembleDebugAndroidTest` → `BUILD SUCCESSFUL in 39s`
- ENV-GATE 註記: GATE-KOTLIN-RUN（on-device instrumentation，驗 corpus_revision/樣本）
  無實機，遞延 A11 USER-GATE（比照 A1 D3）。Swift 因 Windows 無法編譯（R3 既知）。
- deviations: 無偏離 A4 範圍。A4/A5 未混刀（未碰 FieldSession/ActiveFieldController）。
- next: A5（4-7 FieldSession + field-scope 開啟）；其前置 A2/A3/A4 已備。A5 須一併移除
  A2 過渡 `kDebugFieldJoinSecretHex`（grep gate）並補 Outbox_V2 `field_id` 欄持久化。

---

## [2026-06-14] A3-fix DONE（GPT review：HAZARD description 預算改 UTF-8 byte）

- repo/commit: IgniRelay @ `51db9aa`
- 執行者: Claude（主理 AI，Owner 2026-06-14 接任）
- 根因: `publishHazardMarker` 原以 `description.length`（Dart code units）擋預算，但
  wire 以 UTF-8 字串攜帶 description、spec §9 HAZARD/ALERT 為 **byte** 預算。280 字
  中日韓描述約 840B，舊 guard 會誤放行。
- 變更: facade 改計 `utf8.encode(description).length`；`HazardMarkerData.kDescriptionMaxLen`
  語意改為「UTF-8 bytes」（doc 同步）。既有 ASCII 測試不受影響；新增中文 94 字
  （282B > 280）拒發測試釘住。
- gates: 屬 A5 大刀前置小修，gate 證據併入下方 A5 DONE 全綠。

---

## [2026-06-14] A5 DONE（4-7 FieldSession 最小落地 + field-scope 在 production 開啟）

- repo/commit: IgniRelay @ `93c4556`（程式碼）；前置小修 A3-fix @ `51db9aa`
- 執行者: Claude（主理 AI，Owner 2026-06-14 接任；覆蓋計畫 §0.4）
- 目標達成: 場域由「測試 shim」變產品事實——本機可加入場域、金鑰持久化、publisher
  用真場域、dispatcher 的 field-scope + field-mac 檢查在 production 打開。
- 新增檔案:
  - `app/services/field_session_store.dart`：`FieldSession{fieldIdHex,displayName,
    joinedAtMs,cloudBaseUrl?}`；secret 進 `flutter_secure_storage`（key
    `field_secret_<hex>`），中繼資料進 SQLite `Field_Sessions`。**secret 絕不入
    SQLite 明文**（A5 禁止事項）；HKDF mac key 亦不持久化（載入時重生）。
  - `app/controllers/active_field_controller.dart`（ChangeNotifier）：`initialize`
    由 secrets 重生 (field_id, mac_key)、`joinBySecret`/`leave`/`setActive`、單一
    作用場域供發送、`macKeyForFieldId` 供 drain 重綁；持有與 dispatcher **共享的
    可變 `FieldKeyStore`**（runtime join/leave 立即反映到收方，免重建 dispatcher）。
  - `app/controllers/v2_pipeline_factory.dart`：`createProductionDispatcherV2` 單一
    接點，釘住三 production flag（clock-expiry / max-hops / **field-scope ON**）。
- 改動:
  - DB version 12→13：`Field_Sessions` 表（onCreate + onUpgrade）；`Outbox_V2` 加
    `field_id BLOB` 欄（drop+rebuild，沿用 v11/v12 ephemeral 模式）。
  - facade：**移除 A2 `kDebugFieldJoinSecretHex` 與 `_debugFieldContext`**；`_broadcast`
    改由 `ActiveFieldController` 解析作用場域，未加入場域→`BroadcastOutcome.noField`
    （不入佇列、不發送，控制框豁免）；`Outbox_V2` 持久化 `field_id`；drain 依
    `entry.fieldId` 由 controller 重綁 mac_key，場域已離開→刪列並 trace（施工筆記 3）。
  - `FieldKeyStore` 改可變（`addDerived`/`removeByHex`）；`EnvelopeDispatcherV2` 加三個
    `@visibleForTesting` flag getter（守門用）。
  - `main.dart`：`_startV2Bridge` 先 `await controller.initialize()`（secure storage→
    重生→填共享 keyStore）→經 factory 建 dispatcher（field-scope ON + 共享 keyStore）→
    `attachActiveField`（施工筆記 4 啟動順序）；`ListenableProvider` 接
    `ActiveFieldController`。
  - debug shell：場域卡片（顯示作用場域 idHex8/名稱、以代碼加入 64-hex、產生新場域
    隨機 32B、>1 場域時切換作用場域）；PRESENCE 處理 `noField`。
- 測試（新增/更新，皆綠）:
  - `field_session_store_test`（5）：secret→secure storage / 中繼資料→SQLite（無
    secret 欄）、secretFor roundtrip、loadAll 排序、leave 雙刪、join 冪等。
  - `active_field_controller_test`（5）：initialize 空 / join 設作用+填 keyStore /
    setActive 切換 / leave 退場+fallback / **restart 重生持久場域**。
  - `database_migration_v13_test`（D4，2）：v12→v13 onUpgrade 建 Field_Sessions +
    Outbox_V2.field_id（drop+rebuild 空）；fresh install onCreate 同樣有。
  - `field_scope_integration_test`（D3，4）：同場域 accept / 異場域
    `field-scope-mismatch` / 偽造 mac `field-mac-invalid` / 竄改 field_id
    `signature-invalid`，**四態皆斷言 drop_reason**。
  - `v2_pipeline_factory_test`（施工筆記 5）：守門斷言 production dispatcher
    field-scope/clock-expiry/max-hops flag 皆 ON。
  - `event_publisher_v2_facade_test`：presence 改吃真作用場域、`noField`、Outbox
    `field_id` 持久化；移除 debug-secret 引用。
  - `provider_wiring_smoke_test` / `debug_shell_smoke_test`：補 `ActiveFieldController`
    provider + 場域卡片渲染斷言。
- DoD: D1 ✅（factory 釘 field-scope ON + 真 FieldKeyStore，守門測試驗證）/ D2 ✅
  （`grep -rn "kDebugFieldJoinSecretHex" lib/` = 0）/ D3 ✅（跨場域隔離四態）/
  D4 ✅（Field_Sessions migration onUpgrade）/ D5 ✅（通用 gate 全綠）
- gates（G17 逐字執行，皆 exit 0）:
  - `dart run tool/check_layers.dart --strict` → `[check_layers] ok — no boundary violations`
  - `flutter analyze` → `2 issues found`（2 既有 info：battery_optimization_guide），
    **0 errors**
  - `flutter test` → `00:15 +526 ~3: All tests passed!`（A4 後 +498 → +526）
  - `flutter test test/conformance/wire_conformance_corpus_test.dart`（含於上）+
    `dart run tool/generate_wire_conformance_v1.dart --check` → 確定性 OK
    （A5 未碰 wire/corpus，rev 維持 `v0.3-phase0b-4-6-1`）
  - `grep -rn "kDebugFieldJoinSecretHex" lib/` → 0（D2）
  - `cd android; ./gradlew :app:assembleDebugAndroidTest` → `BUILD SUCCESSFUL`
    （corpus 未變，增量；exit 0）
- ENV-GATE 註記: GATE-KOTLIN-RUN（on-device，驗 corpus）無實機，遞延 A11（比照 A1 D3）。
  Swift 因 Windows 無法編譯（R3 既知）。
- 行為轉變（刻意，安全姿態）: field-scope ON 後，未加入場域時非控制事件（PRESENCE/
  STATUS/HAZARD）發送回 `noField`、收方對未知場域 envelope 回 `field-scope-mismatch`；
  HELLO 等控制框（100–129，zero field_id）不受影響（§21.7）。新使用者須先於場域卡片
  加入/產生場域，事件才會流動。
- 觀察（非 A5 範圍，記錄備查）: 全模組 `./gradlew assembleDebugAndroidTest`（無
  `:app:` 前綴）會因 `flutter_secure_storage` androidTest 透傳
  `androidx.exifinterface:1.4.1`（要求 minSdk 21）與 androidTest minSdk 19 衝突而
  manifest-merger 失敗；與本刀無關（純 plugin 傳遞依賴 + minSdk 設定）。**正式 gate
  用 `:app:assembleDebugAndroidTest`（綠）**，conformance Kotlin 測試所在模組不受影響。
- deviations: 無偏離 A5 範圍。A4/A5 未混刀。未碰 corpus/generator（A5 不動 wire）。
- next: A6（舊產品殘留清理，OD-6）。

---

## [2026-06-14] A5-docfix DONE（ble_v2_bridge 過時註解）

- repo/commit: IgniRelay @ `96e037f`
- 執行者: Claude（主理 AI）
- 變更: `ble_v2_bridge.dart` `sendEnvelope` 兩段註解仍寫「dispatcher field-scope
  check stays OFF until A5」「A2 debug field seam」，A5 完成後失效會誤導。改述為
  fieldId/macKey 由 facade 經 ActiveFieldController 解析自作用場域；A5 起 production
  dispatcher 於收方強制 field-scope + field-mac（§21.6）。**純註解，0 code 變更**。
- gates: `flutter analyze lib/app/services/ble_v2_bridge.dart` → No issues。
- next: A6。

---

## [2026-06-14] A6 DONE（舊產品殘留清理，OD-6）

- repo/commit: IgniRelay @ `a7b0b0f`
- 執行者: Claude（主理 AI；Owner 收窄為 8 點範圍）
- 變更（移除 CHAT_MESSAGE 發佈/投影路徑 + 刪死檔）:
  - `EventPublisherV2Facade.publishChatMessage` 移除（無 production 呼叫端；3 個
    facade 測試借用它作泛用 raw-payload publish → 改 `publishPresence`，以
    anon_user_id[0] 區分佇列項驗 FIFO）。header migration 註解同步移除 CHAT 條目。
  - `V2InboundProjector` 移除 `case EventTypeV2.chatMessage` 與 `_projectChat`
    （收到 type-30 落 default no-op，不再投影）。§17 TRANSLATION 註解同步更新。
  - `EventStream` chat typed stream：早於 #3B-4 已移除（僅留註解，無殘留可移）。
  - `EventTypeV2.chatMessage = 30` **保留並凍結**（編號永不重用），加 reserved 註解；
    `maxHopsDefault`/`isKnown` 的 `case chatMessage` 為 reserved 型別 spec metadata，保留。
  - spec **§4.1** `EVENT_TYPE_CHAT_MESSAGE = 30` 注記 RETIRED/RESERVED（引用 A6/OD-6；
    編號凍結不重用；非 wire 變更）。
- 刪檔（D2，逐檔 rg 證 0 引用）:
  - `lib/app/data/supply_category_data.dart`（`SupplyCategory`/`supplyCategories`/
    `findCategory`/`SupplyCategoryLocalizer` 全自引用，外部 0；−1181 行）。
  - `lib/app/services/room_display_name_resolver.dart`（lib 0 引用，僅其測試）
    ＋ `test/room_display_name_resolver_test.dart`。
  - `lib/app/mesh/hazard_manager.dart` 仍被 `event_manager.dart` 引用 → **保留**
    （計畫條件「若 projector 已不經它」不成立）。
- 範疇界定（Owner 收窄 8 點 + G5，逐項註明未動）:
  - 未動 `priority_matrix_v2.dart` / `tombstone_sweeper.dart` 的 `EventTypeV2.chatMessage`
    （reserved 型別之 §6 matrix / tombstone TTL metadata，非發佈/投影路徑，不在 Owner
    具名清單）。
  - 未動 v1 `EventType.chatMessage = 13`（v1 解碼相容期保留）。
  - **plan step 3（v1 enum 標 `@Deprecated`）遞延**：不在 Owner 收窄範圍，且需先界定
    「read-model 仍用的 v1 值」清單，留待後續專責清理。
  - 未碰 corpus/wire/FieldSession/A7 QR。
- DoD: D1 ✅（chat 發佈/投影路徑 0 殘留：`grep publishChatMessage lib/` 僅剩註解；
  `EventTypeV2.chatMessage` 僅剩 enum 定義＋reserved 註解＋reserved 型別 metadata）
  / D2 ✅（刪檔逐檔 0 引用證據如上）/ D3 ✅（通用 gate 全綠）
- gates（G17 逐字，皆 exit 0）:
  - `dart run tool/check_layers.dart --strict` → `ok — no boundary violations`
  - `flutter analyze` → `2 issues found`（2 既有 info），**0 errors**
  - `flutter test` → `00:15 +510 ~3: All tests passed!`（A5 +526 → +510：刪
    `room_display_name_resolver_test` 之 16 測試；facade 測試遷移非刪）
  - `dart run tool/generate_wire_conformance_v1.dart --check` → 確定性 OK（未碰 corpus）
  - `cd android; ./gradlew :app:assembleDebugAndroidTest` → `BUILD SUCCESSFUL`
- deviations: 無偏離 Owner 收窄範圍；plan step 3 遞延（已於 A6-polish 補完，見下）。
- next: A7（場域加入 UX：QR / 代碼；依附錄 F 加 `qr_flutter`/`mobile_scanner`）。

---

## [2026-06-14] A6-polish DONE（過時 chat 註解 + plan A6 step 3）

- repo/commit: IgniRelay @ `fa100ef`
- 執行者: Claude（主理 AI）
- 緣由: GPT review 指出 A6 留兩條小尾巴——(a) 仍有把 CHAT_MESSAGE 當 active/core
  route 的過時註解；(b) plan A6 step 3（v1 enum @Deprecated）被遞延。本刀補完。
- 變更:
  - 過時註解修正：`event_publisher_v2_facade.dart`（0d core types / wave 3F-r3 非
    LWW 清單兩處）、`main.dart`（facade provider 0d-eligible 清單）、`ble_manager.dart`
    兩處排除註解「v2-only」→「聊天產品已下線（A6/OD-6）」。`event_manager.dart:21`
    為「#3B-2 已移除方法」之正確歷史記錄（非誤導），刻意保留。
  - **plan A6 step 3 完成**：`event_types.dart` 對非 read-model 的 v1 wire-legacy
    常數標 `@Deprecated('v1 wire legacy')`（resourceRegister / match 全系列 + aliases /
    station / locationUpdate / quarantineVote / fireAlarmRf / physicalHandshake /
    handshakeComplete / chatMessage(13) / matchInquiry·Available·Gone）。**值與編號
    不刪、不改、不重排**（v1 解碼相容仍需）。read-model 仍在用的 `requestBroadcast`(1)/
    `hazardMarker`(4) 不標。sanctioned 消費端 `mesh_event_handler`/`ble_manager` +
    `event_types` alias 自引用以 file-level `ignore_for_file:
    deprecated_member_use_from_same_package` 抑制 hint（無新 analyzer info）。
  - `EventTypeV2.chatMessage = 30` reserved 不動；未碰 A7/QR/corpus/FieldSession。
- gates（exit 0）: `flutter analyze` → **0 errors**（2 既有 info，無新 deprecation
  hint）；`dart run tool/check_layers.dart --strict` → ok；`flutter test` →
  `+510 ~3 All tests passed!`（與 A6 同——純註解/標註，無 runtime 影響）。
  GATE-KOTLIN-BUILD / GATE-CONF-DART 未重跑（Dart 註解/標註，未動 wire/corpus/Kotlin；
  A6 已證綠）。
- deviations: 無。
- next: A7（場域加入 UX：QR / 代碼）。

---

## [2026-06-15] A7 DONE（場域加入 UX：QR / 代碼）

- repo/commit: IgniRelay @ `bdb09a1`
- 執行者: Claude（主理 AI）
- 範圍: MASTER_EXECUTION_PLAN A7 步驟 1–4（UI 任務；開工前讀 DESIGN_LANGUAGE.md）。
- 變更:
  - **QR 編解碼器**（純 Dart；A7 DoD D1 可自動化核心）`lib/app/services/field_qr_codec.dart`：
    IGNI1 五段式 join code（凍結格式）`IGNI1:<base64url(secret32B)>:<urlencode(name)>
    [:<urlencode(https-cloud-url)>[:<urlencode(staff_token)>]]`。段0 前綴必驗；段1→恰 32B；
    段3 僅收 `https://`（其餘 badCloudUrl 拒）；有段4 無/空段3→staffWithoutCloud 拒；
    **未知第 5+ 段一律忽略不報錯（前向相容鐵則）**；三段舊碼相容。`tryDecode` 不 throw，
    回傳 typed `FieldQrError`（D2 不 crash）。urlencode 確保段內無裸 `:`。
  - **場域頁** `lib/ui/screens/field/field_screen.dart`（447 行，≤500 UI 規則）：作用場域
    摘要 / 空狀態、多場域清單 + 切換作用場域、離開（二次確認 destructive）、建立新場域→
    顯 QR、掃碼加入、輸入代碼（**A5 hex 對話框升級**——吃 IGNI1 代碼或 64-hex）。
  - **QR 顯示 sheet** `field_qr_sheet.dart`（拆出以守行數規則）：dark-on-light 以 token
    維持可掃；raw code（含 secret）僅 `kDebugMode` 顯示，永不入剪貼簿 / log。
  - **掃碼頁** `field_scan_screen.dart`：mobile_scanner，掃到首個合法 IGNI1 即 pop(raw)；
    非法 / 非本 app 的碼只提示續掃不 crash；相機不可用→errorBuilder 提示改用代碼。
  - **debug shell** 場域卡片精簡為狀態 + 「場域管理」入口推 FieldScreen；移除被取代的
    A5 內嵌 hex 對話框 / 產生鈕 / hex helpers（升級而非新增——符 plan step 3 語意）。
  - **app 層**：`active_field_controller.dart` +`createField`（產生隨機 32B secret→join→
    回傳 transient secret 供顯 QR）、+`exportSecretForQr`（自安全儲存重讀供重顯 QR）。
  - **依賴（附錄 F G13 白名單）**：`qr_flutter ^4.1.0`（解析 4.1.0）/ `mobile_scanner ^5.1.1`
    （解析 5.2.3，transitive `qr 3.0.2`）。AndroidManifest +CAMERA（uses-feature camera
    required=false——無相機仍可用輸入代碼）；iOS Info.plist +NSCameraUsageDescription。
- 測試（+21）:
  - `test/services/field_qr_codec_test.dart`（15）：三/四/五段 roundtrip、空輸入 / 壞前綴 /
    太少段 / 壞長度 / 非 base64url / seg3 非 https / 有 seg4 無 seg3 拒收、未知第 6 段仍解析、
    名稱含 `:` 經 urlencode 存活、encode guards（非 32B / staff 無 cloud throw）。
  - `test/ui/screens/field_screen_test.dart`（5）：空狀態、作用場域摘要 + 清單、代碼加入、
    壞碼提示不 crash 不加入、QR sheet 顯示 QrImageView。
  - `event_publisher_v2_facade_test.dart` +1：多場域切換→published field_id 跟著作用場域換。
  - `debug_shell_smoke_test.dart`：場域卡片斷言改「場域管理」入口（FilledButton 計數改 specific）。
- DoD: D1 ✅（QR 字串層 15 測試綠；**實機兩機掃碼 join 同場域歸 A11 USER-GATE 腳本**）/
  D2 ✅（未知前綴 / 壞 payload 不 crash 且有使用者提示）/ D3 ✅（通用 gate 全綠）。
- 禁止事項（逐項守）: secret 不入剪貼簿 / log（新碼 grep `Clipboard|debugPrint|print(` = 0）；
  QR 僅帶明文場域名（無其他個資）；seg3 不收 `http://`（badCloudUrl 拒，有測試）。
- gates（G17 逐字，皆 exit 0）:
  - `dart run tool/check_layers.dart --strict` → `ok — no boundary violations`
  - `flutter analyze` → `2 issues found`（2 既有 info），**0 errors / 0 新 issue**
  - `flutter test` → `00:16 +531 ~3: All tests passed!`（A6-polish +510 → +531：A7 +21）
  - `dart run tool/generate_wire_conformance_v1.dart --check` → 確定性 OK（未碰 corpus/wire）
  - `cd android; ./gradlew :app:assembleDebugAndroidTest` → `BUILD SUCCESSFUL`
    （mobile_scanner/CameraX 原生整合於 androidTest 變體乾淨組裝，minSdk 26 ≥ 21）
  - DESIGN_LANGUAGE §6 App gate：新場域 screens `grep Colors. lib/ui/screens/field/` = 0。
- 觀察（備查，非 A7 範圍）: `grep Colors. lib/ui/screens/` 於 `design_showcase_screen.dart`
  仍有 4 處既有 `Colors.white`/`Colors.transparent`（debug-only 元件對照頁，kDebugMode 路由）。
  §4.1 豁免名單僅列 debug_shell；此屬既有債，G5 禁順手清理，留待 Owner 決定是否另開清理刀。
- deviations: 無偏離。`field_screen.dart` 初稿 531 行→拆 `field_qr_sheet.dart` 後 447 行符規則。
- next: A8（SOS UX，白皮書 §13.4：長按 1.5s→safetyState→5s 倒數可取消→帶 A4 位置發送）。

---

## [2026-06-15] A7-polish DONE（encode 對稱拒收非 https cloudBaseUrl）

- repo/commit: IgniRelay @ `04f7905`
- 執行者: Claude（主理 AI）
- 緣由: GPT review A7 尾巴——`FieldQrCodec.encode()` 先前可吐含 `http://` cloudBaseUrl
  的碼，`tryDecode()` 卻以 `badCloudUrl` 拒收（encoder/decoder 不對稱；UI 目前無 cloud
  輸入故不會立即炸，但建構端應同步禁止）。
- 變更:
  - `field_qr_codec.dart` `encode()`：`cloudBaseUrl` 非空且非 `https://` → `ArgumentError`
    （鏡像 decode 的 `badCloudUrl`；A7 禁止事項「seg3 不收 http://」於建構端同樣成立）。
    encode doc 同步列出三條 guard（32B / https / staff 需 cloud）。
  - 測試：encode guards +「非 https cloud url throwsArgumentError、https 接受」；既有
    decode 端 http:// 拒收測試改為手工拼碼（encode 已不再吐 http:// 碼）。
- 純 Dart：未改 UI、未碰 A8 / corpus / wire / Kotlin。
- gates（exit 0）: `flutter test test/services/field_qr_codec_test.dart` → `+16 All passed`；
  `dart run tool/check_layers.dart --strict` → ok；`flutter analyze`（codec+test）→ No issues。
  GATE-KOTLIN-BUILD / GATE-CONF-DART 未重跑（純 Dart 邏輯，未動 wire/corpus/Kotlin；A7 已證綠）。
- deviations: 無。
- next: A8（SOS UX，白皮書 §13.4）。

---

## [2026-06-15] A8 DONE（SOS UX：長按→倒數→帶位置發送 + 我安全了解除）

- repo/commit: IgniRelay @ `d7f2921`
- 執行者: Claude（主理 AI）
- 範圍: MASTER_EXECUTION_PLAN A8 步驟 1–5（白皮書 §13.4；UI 任務）。
- 變更:
  - **發送端狀態機** `lib/app/controllers/sos_controller.dart`（SosController/ChangeNotifier）：
    `idle ─arm(severity)→ countdown(5s 可取消) ─elapsed→ sending → sent`；
    `cancelCountdown` 於送出前中止（誤觸防護）。送出走
    `publishStatusUpdate(safetyState, location)`，§5.3 floor 由 facade 套用
    （TRAPPED→SOS_RED / INJURED→SOS_YELLOW）。UI 面 `enum SosSeverity`
    （trapped/injured）映射 wire `SafetyState`——**使 UI 不 import app/proto**
    （GATE-LAYERS 攔到首版 sos_screen 直接 import event_envelope_v2，已改 enum 修正）。
    `markSafe()`=「我安全了」後送 `STATUS_UPDATE(SAFE)`（**OD-8：不新增 SOS_CANCELLED
    wire 型別**；LWW spec §10.2 收斂）。
  - **UI**（守 DESIGN_LANGUAGE §4：`context.igni`＋Igni 元件，screen 內 0 `Colors.*`）
    `lib/ui/screens/sos/`：`sos_screen.dart`（368 行≤500；長按 1.5s 觸發→狀態選擇
    受困 RED/受傷 YELLOW→5s 倒數〔取消鈕 ≥64dp〕→送出後狀態列吃 `BroadcastOutcome`
    〔queued/sent/peers〕→「我安全了」；收方 `sosAlerts` 告警卡〔位置＋相對時間〕，
    收同 author 的 SAFE 即標「已解除」）＋`sos_hold_button.dart`（按住 1.5s 才觸發、
    進度環為 hold 功能性回饋、圓鈕 ≥96dp）。
  - debug shell「發 SOS」改推 `SosScreen`（移除 `_todoWire` 占位）。
  - **收方解除**：`event_types.dart` +`LocalReadModelType.sosResolved=9002`（本地
    read-model 標記，**非 wire 型別**）；`v2_inbound_projector` 收 STATUS_UPDATE
    safetyState=SAFE → 投影 `sosResolved` row（author=sender_pub_key），UNSAFE 仍不投影；
    `event_stream` +`SosResolved`＋`sosResolutions` typed stream（以 author hex 標記）。
  - `main.dart` +`ChangeNotifierProvider<SosController>`。
- 測試（+10）:
  - `test/controllers/sos_controller_test.dart`（5）：arm→countdown 不發、cancel 中止、
    countdown→送出＋TRAPPED floor=SOS_RED、INJURED floor=SOS_YELLOW、markSafe 後送
    SAFE(STATUS)＋清作用 SOS。**讀 Outbox_V2 的 priority+payload 斷言 §5.3 floor，免架
    recording BLE bridge**（real facade＋joined field＋無 peer → 佇列持久化）。
  - `test/ui/screens/sos_screen_test.dart`（3）：trigger＋空收方、長按→選擇→倒數→取消、
    倒數→送出橫幅＋我安全了（送出態因真實 DB I/O 用 `tester.runAsync` 放行）。
  - `v2_inbound_projector_test`：+SAFE→sosResolved＋sosResolutions；既有「SAFE 不投影」
    測試改測 UNSAFE 仍不投影（A8 改 SAFE 為投影解除 row）。
- DoD: D1 ✅（觸發/倒數/取消/送出四態測試綠）/ D2 ✅（解除流：markSafe SAFE＋收方
  sosResolved read-model＋sosResolutions stream）/ D3 ✅（通用 gate 全綠）。
- 禁止事項（逐項守）: 未跳過倒數（arm 一律進倒數、`_send` 僅倒數結束後觸發；無 direct-publish
  路徑）；未新增 `SOS_CANCELLED` wire 型別（`sosResolved` 為本地 read-model）。
- gates（G17 逐字，皆 exit 0）:
  - `dart run tool/check_layers.dart --strict` → `ok — no boundary violations`
  - `flutter analyze` → `2 issues found`（2 既有 info），**0 errors / 0 新 issue**
  - `flutter test` → `00:18 +541 ~3: All tests passed!`（A7 +531 → +541：A8 +10）
  - `dart run tool/generate_wire_conformance_v1.dart --check` → 確定性 OK（未碰 corpus/wire）
  - `cd android; ./gradlew :app:assembleDebugAndroidTest` → `BUILD SUCCESSFUL in 22s`
  - DESIGN_LANGUAGE §6 App gate：`grep Colors. lib/ui/screens/sos/` = 0。
- 觀察（同 A7，非 A8 範圍）: `design_showcase_screen.dart` 4 處既有 `Colors.*`（debug-only
  對照頁）仍在，G5 禁順手清。
- deviations: 無偏離。首版 sos_screen import app/proto 取 `SafetyState` 被 GATE-LAYERS 攔，
  已改為 controller 暴露 UI 安全 `SosSeverity` enum 修正。
- next: A9（PRESENCE 週期信標 + CHECKPOINT + ADMIN_BROADCAST 顯示）。

## [2026-06-15] A9-1 DONE（PRESENCE 週期信標：mesh+場域雙閘 120s/低電300s）

A9 拆三刀之一（GPT review 建議）：`[A9-1]` PRESENCE beacon only。code commit `f7627de`。
- 新 `lib/app/controllers/presence_beacon_controller.dart`（ChangeNotifier）：自動 PRESENCE
  足跡信標，走 A2 `PresenceController.publishPresence` 同一發佈路徑（不另開 wire/路徑）。
  - **週期常數化**：normal 120s；電量 <20%（`lowBatteryThreshold`）降頻 300s。每次 re-arm
    前重讀電量 → cadence 逐輪自適應，**含首個間隔**（低電時第一拍即 300s）。
  - **雙閘**：`isMeshRunning` ∧ `hasJoinedField` 才發；否則 tick 為 NO-OP（**禁止事項
    「beacon 在未加入場域時發送」**：零場域 PRESENCE 會被 A5 §21.6 拒/peer 丟，故不嘗試）。
    閘未過仍 re-arm，條件成立即恢復，毋須使用者手動切換。
  - 一次性 `Timer` 每輪重排（**非 `Timer.periodic`**，故 cadence 可逐輪改）；clock/電量/
    閘/publish 皆 callback 注入 → fake clock 全覆蓋。UI 開關預設 ON。
- `main.dart`：`ChangeNotifierProvider<PresenceBeaconController>`；電量自既有
  `DeviceInfoController.batteryLevel()`（守護 try/catch，headless/無 plugin 回 null →
  維持 normal cadence）。**未新增依賴**（G13）。
- `debug shell`：actions 卡片加「自動 PRESENCE 信標」`SwitchListTile` + 狀態列
  （cadence / 已發次數 / 低電降頻標記）。
- 測試（+6）：`test/controllers/presence_beacon_controller_test.dart`（fake_async）：
  120s 週期累進、低電 300s 降頻（含首間隔）、無場域不發（閘）、mesh 停不發（閘）、
  開關停/復、建構即關不武裝。smoke test 補 beacon provider + 開關渲染斷言。
- DoD：D1 ✅（beacon controller fake-clock 測試綠）。D2/D3 屬 A9-2/A9-3。
- 禁止事項（逐項守）：未加入場域時不 beacon（雙閘 + 專測）。
- gates（本刀跑 3 項，皆 exit 0）:
  - `dart run tool/check_layers.dart --strict` → `ok — no boundary violations`
  - `flutter analyze lib test` → `2 issues found`（2 既有 baseline info），**0 errors / 0 新 issue**
    （fake_async 為 plan 指定 fake clock，已在 flutter_test transitive 依賴樹；以 inline
    `ignore: depend_on_referenced_packages` 抑制而**不動依賴清單**，G13）
  - `flutter test` → `00:17 +547 ~3: All tests passed!`（A8 +541 → +547：A9-1 +6）
  - GATE-CONF-DART / GATE-KOTLIN-BUILD：本刀未碰 wire/corpus/native/deps，與 A8 同態，
    於 A9 收尾統一確認（見 A9-3）。
- deviations: 無偏離。
- next: A9-2（CHECKPOINT：手動按鈕 + checkpoint_id + publish/projector/read-model 列表）。

## [2026-06-15] A9-2 DONE（CHECKPOINT：手動點名通過 publish + 投影 + read-model 列表）

A9 拆三刀之二：`[A9-2]` CHECKPOINT。code commit `226e1d2`。**wire 早於 Phase 0b #4-1
已就位（CheckpointData / EventTypeV2.checkpoint=4 / 矩陣），本刀純收發接線、不碰 wire。**
- facade `publishCheckpoint(anonUserId, checkpointId, location?)`：priority **STATUS**、
  **TTL 12h**、**max_hops 6**（spec §6 matrix / §11.2 CHECKPOINT）。**非 LWW**（§10.2，
  每次通過為獨立事件）。同非控制發佈走作用場域（A5），無場域→`noField`。
- 新 `lib/app/controllers/checkpoint_controller.dart`（app 層，鏡像 PresenceController）：
  組 anon_user_id ＋ GPS evidence 後呼叫 facade，**使 UI 不 import app/proto**。
- `v2_inbound_projector` +`case checkpoint`→`_projectCheckpoint`：寫
  `LocalReadModelType.checkpoint=9003` read-model row（純 JSON snapshot：checkpoint_id/
  anon8/src/observed/經緯；**非 protobuf、非 wire**）。
- `event_stream` +`CheckpointCrossing`＋`checkpointCrossings` typed stream＋`case checkpoint`
  （JSON snapshot 還原）＋dispose close。
- `main.dart` +`Provider<CheckpointController>`。
- UI：新 `lib/ui/shell/checkpoint_card.dart`（自帶 provider 讀取＋訂閱 → 使 `debug_shell.dart`
  維持 <500 行 facade 上限；lib/ui/shell/ 不在 §6 Colors gate 掃描路徑內）。**手動 CHECKPOINT
  按鈕僅 `kDebugMode`**（真實流程綁 Field Node QR/接觸→Stage D）＋ checkpoint_id 輸入對話框
  ＋收到的點名通過清單（非 LWW，逐筆保留、以 eventId 去重重送）。`debug_shell` ListView
  插入 `const CheckpointCard()`。
- 測試（+4）:
  - `event_publisher_v2_facade_test`：publishCheckpoint priority=STATUS / TTL 12h /
    max_hops 6 / payload roundtrip。
  - `v2_inbound_projector_test`：CHECKPOINT envelope → Event_Logs(event_type=checkpoint=9003)
    ＋`checkpointCrossings` stream（checkpoint_id / anon8 / 經緯）。
  - `test/ui/shell/checkpoint_card_test.dart`（2）：空狀態＋手動按鈕→對話框→queued。
  - smoke test 補 `CheckpointController` provider；surface 加高（2400→3200）容 6 卡。
- DoD：D2（CHECKPOINT 半）✅（projection + UI 測試綠）。
- 禁止事項（逐項守）：手動 CHECKPOINT 入口 `kDebugMode` 包夾（release 無；ADMIN 發佈入口
  屬 A9-3）。
- gates（本刀跑 3 項，皆 exit 0）:
  - `dart run tool/check_layers.dart --strict` → `ok — no boundary violations`
  - `flutter analyze lib test` → `2 issues found`（2 既有 baseline info），**0 errors / 0 新 issue**
  - `flutter test` → `00:17 +551 ~3: All tests passed!`（A9-1 +547 → +551：A9-2 +4）
  - GATE-CONF-DART / GATE-KOTLIN-BUILD：本刀未碰 wire/corpus/native/deps，於 A9-3 收尾統一確認。
- deviations: 無偏離。
- next: A9-3（ADMIN_BROADCAST 接收：projector + typed stream + 置頂橫幅 expires_at 下架；
  發佈端僅 kDebugMode 後門）+ A9 收尾 gate（CONF-DART/KOTLIN）。

## [2026-06-15] A9-3 DONE（ADMIN_BROADCAST 接收：置頂橫幅 expires_at 下架 + kDebugMode 發佈後門）

A9 拆三刀之三（收尾）：`[A9-3]` ADMIN_BROADCAST 接收顯示。code commit `d4a37ee`。
**wire 早於 Phase 0b #4-1 已就位（AdminBroadcastData / EventTypeV2.adminBroadcast=82 / 矩陣），
本刀純收發接線、不碰 wire。**
- `event_types.dart` +`LocalReadModelType.adminBroadcast=9004`（本地 read-model 標記，**非 wire**）。
- `v2_inbound_projector` +`case adminBroadcast`→`_projectAdminBroadcast`：寫 9004 read-model
  row（純 JSON snapshot：scope/message/expires_ms；**非 protobuf**）。多筆並存（§10.2 非 LWW）。
- `event_stream` +`AdminBroadcast`〔含 `isExpired(now)` 純函式〕＋`adminBroadcasts` typed stream
  ＋`case adminBroadcast`（JSON snapshot 還原）＋dispose close。
- facade `publishAdminBroadcast({message, toAllNodes=true, ttl=6h})`＝**debug 後門發佈面**：
  priority **ALERT**、**max_hops 12**、**TTL 6h**（spec §6 / §11.2），payload 帶 `expires_at`
  供收方下架；UTF-8 byte 預算守護（§9，`AdminBroadcastData.kMessageMaxLen=480`）。`toAllNodes`
  bool→`AdminScope`，**使 UI 不 import app/proto**。
- UI：新 `lib/ui/shell/admin_broadcast_banner.dart`（自帶 provider／注入 source+clock 測試 seam；
  lib/ui/shell/ **不在 §6 Colors gate 掃描路徑**內）：置頂橫幅，依 `expires_at` prune（prune
  timer 僅在有到期項時武裝、清空即取消 → 閒置無 pending timer）。**「發測試 ADMIN 廣播」按鈕僅
  `kDebugMode`**（`DebugShell` 為 release home → 發佈入口必 kDebugMode 包夾＝**禁止事項
  「ADMIN 發佈入口出現在 release UI」**）；facade 讀取惰性（僅按鈕 handler），收方路徑免 facade
  provider。`debug_shell` ListView 置頂插入 `const AdminBroadcastBanner()`。
- 測試（+6）:
  - `event_publisher_v2_facade_test`：publishAdminBroadcast priority=ALERT / max_hops 12 /
    TTL 6h / payload(scope=ALL/message/expires_at) roundtrip；over-budget message throwsArgumentError。
  - `v2_inbound_projector_test`：ADMIN envelope → Event_Logs(event_type=adminBroadcast=9004)
    ＋`adminBroadcasts` stream（message/scope/expiresAt）＋isExpired 邊界。
  - `test/ui/shell/admin_broadcast_banner_test.dart`（3）：isExpired 單元；有效公告顯示；
    過 expires_at 周期 prune 自動下架（注入 source + fake clock + pruneInterval）。
- DoD：D2 ✅（CHECKPOINT+ADMIN projection+UI 測試綠）/ D3 ✅（通用 gate 全綠）。**A9 全數完成**
  （A9-1 beacon / A9-2 CHECKPOINT / A9-3 ADMIN）。
- 禁止事項（逐項守）：ADMIN 發佈入口 `kDebugMode` 包夾（release 無）；beacon 雙閘（A9-1）。
- gates（A9 收尾，5 項全跑，皆 exit 0）:
  - `dart run tool/check_layers.dart --strict` → `ok — no boundary violations`
  - `flutter analyze lib test` → `2 issues found`（2 既有 baseline info），**0 errors / 0 新 issue**
  - `flutter test` → `00:17 +557 ~3: All tests passed!`（A8 +541 → +557：A9 共 +16〔beacon 6 /
    checkpoint 4 / admin 6〕）
  - `dart run tool/generate_wire_conformance_v1.dart --check` → `--check OK (deterministic + up to date)`
    （未碰 wire/corpus，rev 維持 `v0.3-phase0b-4-6-1`）
  - `android> .\gradlew.bat :app:assembleDebugAndroidTest` → `BUILD SUCCESSFUL`（未碰 native/deps）
  - DESIGN_LANGUAGE §6 App gate：`grep Colors. lib/ui/screens/` 僅既有 `design_showcase_screen.dart`
    （A7 既有 debug-only debt，G5 禁順手清）；A9 新 UI 在 `lib/ui/shell/`，不在掃描範圍。
- deviations: 無偏離。A9 全程未動 wire/corpus/native/deps。`fake_async`（A9-1 beacon fake clock）
  為 flutter_test transitive，以 inline ignore 抑制 `depend_on_referenced_packages`，不動依賴清單（G13）。
- next: A9 完成，待 GPT review。計畫下一棒見 master plan（A10+）。

## [2026-06-15] A10 DONE（mapless 位置呈現：PositionEstimate 本地融合 + 最後可信位置卡片）

GPT review 放行 A9（含一小灰區：A9 shell 卡片用原生 Card/Colors——判定 skip A9-polish：
那兩個元件在 `lib/ui/shell/`、刻意與 `debug_shell.dart` 的原生 Material 風格一致；設計系統
token 範疇是 `lib/ui/screens/` 產品畫面，只改那兩個反而與所在 shell 不一致；debug shell 全面
汰換時再一併套——GPT 同意非 blocker）。續做 A10。code commit `a7a2357`。
- 新 `lib/app/services/position_estimator.dart`（**純函式、零 I/O、不上 wire**；REBUILD §3.6
  分層鐵則：wire 只搬 LocationEvidence〔觀測〕，PositionEstimate〔融合〕純 UI 本地推導）：
  - `PositionObservation`（plain Dart，UI 餵入）/ `PositionEstimate{lat?,lng?,anchorNodeId?,
    distanceM?,bearingDeg?,confidence,uncertaintyM,ageSeconds}` / `enum PositionConfidence`。
  - `confidenceForAge`：≤2min HIGH、≤10min MEDIUM、其後 LOW（§3.6 原則 4；常數註解出處）。
  - `uncertaintyForAge`：base + 0.5 m/s × age 線性（base=觀測 accuracy 或 GPS-class 15m）。
  - `estimate`：v1 融合＝freshest-fix wins；confidence/uncertainty 依年齡**即時算、絕不持久化**
    （存事件 30 分鐘後即謊言，REBUILD §3.6）；負年齡 clamp 0；空集合→null。
- 新 `lib/ui/screens/position/last_seen_screen.dart`（**產品畫面，守 DESIGN_LANGUAGE §4**：
  一律 `context.igni` + Igni 元件〔IgniCard/IgniSubPageHeader/StatusChip/MonoText〕、零
  `Colors.*`/hex）：每 anon8 一張卡「最後可信位置：<座標或錨點> · <n 分鐘前> · 可信度 H/M/L
  〔StatusChip ok/warn/neutral〕 · 誤差 ~<m>m」。**文案鐵則：「最後可信位置/推估」，禁「目前
  位置」**（§3.6 原則 5 / DESIGN §4.5）。週期 timer 重整年齡（注入 seam 可關）；訂閱
  EventStream.presenceUpdates/checkpointCrossings（注入 seam 供測試）。debug shell PRESENCE
  卡片頭加「最後可信位置」入口。
- 測試（+11）:
  - `test/services/position_estimator_test.dart`（9，純函式 DoD D1）：年齡→confidence **邊界
    120s/600s 兩側全測**（119/120/121、599/600/601）、負年齡 clamp、uncertainty 線性、
    freshest-fix 融合、anchor-only、future-dated clamp。
  - `test/ui/screens/last_seen_screen_test.dart`（2，DoD D2）：空狀態提示；PRESENCE fix 渲染卡片
    ＋可信度 chip＋座標；**斷言無「目前位置」字樣**。
- DoD：D1 ✅（estimator 純函式邊界全綠）/ D2 ✅（UI smoke 綠）/ D3 ✅（通用 gate 綠）。
- 禁止事項（逐項守）：confidence/uncertainty 未寫進任何 wire payload / DB 事件列（estimator
  零持久化、純推導）；文案無「目前位置」（widget 測試斷言）。
- gates（5 項，皆 exit 0）:
  - `dart run tool/check_layers.dart --strict` → `ok — no boundary violations`
  - `flutter analyze lib test` → `2 issues found`（2 既有 baseline info），**0 errors / 0 新 issue**
  - `flutter test` → `00:17 +568 ~3: All tests passed!`（A9-3 +557 → +568：A10 +11）
  - `dart run tool/generate_wire_conformance_v1.dart --check` → `--check OK`（未碰 wire/corpus，
    rev 維持 `v0.3-phase0b-4-6-1`）
  - GATE-KOTLIN-BUILD：A10 純 Dart UI，未碰 native/deps，自 A9-3 收尾 `:app:assembleDebugAndroidTest`
    BUILD SUCCESSFUL 後無變動。
  - DESIGN §6 App gate：`grep -rn "Colors\." lib/ui/screens/position/` = 0（新畫面全 token 化）；
    `lib/ui/screens/` 其餘僅既有 `design_showcase_screen.dart`（A7 debug-only debt，G5 禁順手清）。
- deviations: 無偏離。A9-polish 經判斷 skip（理由見上，GPT 同意非 blocker）。
- next: A10b（雷達相對位置視圖，前置 A10）——本刀未做（A10 範圍外）；待 Owner / GPT 指示。

## [2026-06-16] A10b DONE（雷達相對位置視圖：relative_position 局部等距投影 + CustomPaint 北朝上雷達 + 列表/雷達切換）

GPT review 放行 A10（純函式無 I/O、screen 全 token 化無 Colors.*、文案無「目前位置」、信心邊界有測），
按文件 §5 A10b 完成；GPT 明示 A10b 收尾務必**實跑** GATE-KOTLIN-BUILD、不得沿用 A9/A10 說法。
code commit `e848f8a`。
- 新 `lib/app/services/relative_position.dart`（**純函式、零 I/O、不上 wire**；同 A10 鐵則）：
  - `RelativePosition{distanceM, bearingDeg(0=正北/順時針 0–360), confidence, uncertaintyM, ageSeconds}`。
  - `RelativePositionProjector.relativeTo(origin, subject)`：局部等距投影——eastM = Δlng × 111320 ×
    cos(lat₀)、northM = Δlat × 110574（**常數凍結、與 E1 map_calibration_v1 同一組**），
    distance=hypot、bearing=atan2(east,north) 正規化 [0,360)；Δlng 跨 ±180° wrap；origin/subject
    任一無 latLng → null（錨點-only 留列表；本機無位置走退化）。
  - `relativeAll`：批次投影、丟不可定位者、保序。
- 新 `lib/app/services/local_position_source.dart`（**本機自有 GPS、不偷拿 peer**——A10b 首要紅線）：
  app 層包裝 legacy `LocationService` singleton → 純 Dart `PositionObservation?`/`PositionEstimate?`
  （UI 經 DI 取得、永不直接碰 singleton；CLAUDE.md）。無 fix → null（雷達退化）。main.dart 注入
  `Provider<LocalPositionSource>`（currentLocation ← LocationService）。
- 改 `lib/ui/screens/position/last_seen_screen.dart`（487 行 < 500 facade 上限）：加 **列表⇄雷達
  toggle（預設列表）**；新增 SOS 訂閱（sosAlerts 自帶 lat/lng → 紅點/卡片；pubkey 識別空間，
  **刻意不偽造與 anon8 連結**）；雷達 origin ← LocalPositionSource（注入 seam 供測試）；**本機無位置
  → 顯示「需要本機位置才能顯示相對方位」並自動退回列表**；雷達點按 → bottom sheet 開該人 A10 卡片。
- 新 `lib/ui/screens/position/relative_radar.dart`（CustomPaint 雷達面，**全 token 化零 Colors.***）：
  **北朝上固定（v1 不接指南針/磁力計）**；距離環自動選檔（100/250/500…50k/100k/200k 取涵蓋最遠成員
  最小檔、環值標環上）；點色語意（SOS=sos / 正常=ok / LOW=stale 灰）；LOW 加虛線不確定圈（半徑＝
  uncertaintyM 依比例尺）；節點/錨點三角形、他人圓點；超最外環者釘環緣標「>環值」。`RadarMarker`
  public（widget 測試斷言 sos 點）。
- 測試（+21）:
  - `test/services/relative_position_test.dart`（純函式 DoD D1，數值斷言**相對誤差 ≤0.5%**）：
    N/E/S/W 四象限、±180° antimeridian wrap、同點距離 0、bearing 環繞 359.x°（<360）、cos(lat₀)
    高緯（60° ×0.5）；latLng 缺漏 guard、relativeAll 丟錨點保序、欄位透傳。
  - `test/ui/screens/relative_radar_test.dart`（DoD D2）：n=0/1/8 渲染不 crash、**含 SOS → sos 色
    RadarMarker 存在**、LOW → neutral 點、超環 pin「>」。
  - `test/ui/screens/last_seen_screen_test.dart`（A10 2 + A10b 3）：列表⇄雷達切換（DoD D2）、
    **本機無位置退化顯示提示文案（DoD D3）**、SOS 卡片 chip；既有空狀態/PRESENCE 卡片補 sosSource seam。
- DoD：D1 ✅ / D2 ✅（雷達 smoke + 切換）/ D3 ✅（本機無位置退化 widget 測試）/ D4 ✅（通用 gate +
  A7–A10b 設計 DoD 含 Colors grep）。
- 禁止事項（逐項守）：未引入地圖 SDK/圖磚/GIS、**零新依賴**（G13，pubspec 未動）；distance/bearing/
  confidence/uncertainty 未寫進任何 wire/DB（純推導）；未用指南針/磁力計；文案無「目前位置」（測試斷言）。
- gates（5 項皆 exit 0；KOTLIN **本刀實跑**）:
  - `dart run tool/check_layers.dart --strict` → `ok — no boundary violations`
  - `flutter analyze` → `2 issues found`（2 既有 baseline info），**0 errors / 0 新 issue**
  - `flutter test` → `00:18 +589 ~3: All tests passed!`（A10 +568 → +589：A10b +21）
  - `dart run tool/generate_wire_conformance_v1.dart --check` → `--check OK`（未碰 wire/corpus，rev 維持
    `v0.3-phase0b-4-6-1`）
  - GATE-KOTLIN-BUILD：`cd android && .\gradlew.bat :app:assembleDebugAndroidTest` → **BUILD SUCCESSFUL
    in 1m 6s**（A10b 收尾實跑，未沿用 A9/A10 說法）。
  - DESIGN §6 App gate：`grep -rn "Colors\." lib/ui/screens/position/` = 0；`lib/ui/screens/` 其餘僅既有
    `design_showcase_screen.dart`（A7 debug-only debt，G5 禁順手清）。
- deviations: 無偏離。SOS 與 PRESENCE 屬不同識別空間（pubkey vs anon8），刻意不偽造連結——SOS 以自帶
  座標獨立紅點/卡片呈現（誠實不猜）。
- next: A11 雙機實機驗證（USER-GATE，AGENT 產 `docs/ACCEPTANCE_A11_TWO_PHONE_SCRIPT.md` 腳本 / Owner
  實機回填；A11 腳本步驟 9 含 A10b 雷達）；或 A12 App↔Node 契約凍結。待 Owner / GPT 指示。

## [2026-06-16] A10b-polish DONE（雷達節點三角形漏接 + 本機位置中途遺失自動退化）

GPT review A10b 大方向放行，先補一個小尾巴再進 A11/A12。code commit `75c5360`。
- **漏接修正**：`LastSeenScreen` 建 `RadarSubject` 原未傳 `isNode`，導致有座標的 CHECKPOINT /
  錨點 estimate 被畫成一般圓點（規格 A10b 明寫「節點/錨點畫三角形」）。改：`isNode =
  baseTone != sos && est.anchorNodeId != null`（可投影的錨點 estimate → 三角形；SOS 維持圓點、
  不誤標 node）。
- **防護**：原本只在「點雷達當下無 origin」設 `_radarUnavailable` flag；若**已在雷達模式才遺失
  GPS**（origin 後來變 null），畫面雖退回列表卻無提示、toggle 還停在雷達。改：移除 flag，build
  從 `origin`（雷達模式才取）即時推導——`origin == null` → 顯示「需要本機位置才能顯示相對方位」
  + 列表 + toggle 同步回「列表」；`_selectRadar` 只記意圖；**origin 復原 → 自動回雷達**。
- 測試（+2，總 +591）：CHECKPOINT 含 checkpointId+lat/lng + 本機 origin → 切雷達 → 斷言對應
  `RadarMarker.isNode == true`；雷達模式中 origin 遺失（注入 seam 後變 null + 新事件觸發 rebuild）
  → 斷言退回列表 + 提示文案、`RelativeRadar` 消失。
- gates（皆 exit 0；本刀純 Dart UI，KOTLIN 仍實跑驗證）:
  - `dart run tool/check_layers.dart --strict` → `ok`
  - `flutter analyze` → `2 issues found`（2 既有 baseline），0 新
  - `flutter test` → `00:21 +591 ~3: All tests passed!`（A10b +589 → +591）
  - `dart run tool/generate_wire_conformance_v1.dart --check` → `--check OK`（未碰 wire/corpus）
  - GATE-KOTLIN-BUILD：`:app:assembleDebugAndroidTest` → **BUILD SUCCESSFUL in 5s**（純 Dart
    變更、native 無動，仍實跑確認）。
  - DESIGN §6：`grep -rn "Colors\." lib/ui/screens/position/` = 0。
- deviations: 無。未碰 wire/DB/pubspec/specs（逐項守 GPT 補丁指令）。
- next: A11 雙機實機驗證（**USER-GATE**——AGENT 僅產 `docs/ACCEPTANCE_A11_TWO_PHONE_SCRIPT.md`
  驗收腳本與證據表格，**不得自宣稱雙機通過**，Owner 實機回填）；或 A12 App↔Node 契約凍結。

## [2026-06-16] A11-D1 DONE（雙機實機驗收 runbook 腳本；D2=USER-GATE pending Owner）

A11 是 **USER-GATE**：AGENT 只能產驗收腳本，Owner 晚上兩台 Android 實機照腳本實測回填才算 D2 通過，
**AGENT 不得代填、不得宣稱雙機通過**。本刀僅新增 `docs/ACCEPTANCE_A11_TWO_PHONE_SCRIPT.md`，
**未碰 app code / wire / DB / pubspec / specs**。code commit `675ca16`。
- 腳本性質：晚上 Owner 兩台手機 USB 偵錯接上電腦後「照著跑」的驗收 runbook（CLI/ADB 優先，
  Android Studio 非必要），不是抽象規劃。
- 覆蓋 MASTER_EXECUTION_PLAN A11 表 **1–9 全步驟**，每步：目的／操作（人工 vs ADB）／預期／證據指令／
  Owner 回填欄／pass-fail；文末結果彙總表。
- 兩層結構：
  - 自動/半自動 **ADB 區**：`adb devices -l`、`$DEVICE_A/$DEVICE_B`、`flutter build apk --debug` / `install`、
    `adb -s install -r`、`logcat -c`、`screencap -p`+`pull`、`logcat -v time flutter:V`、`am force-stop`+重啟、
    `:app:connectedDebugAndroidTest`（step 8 GATE-KOTLIN-RUN）。
  - **人工操作區**：QR 出示/掃碼、按「啟動」mesh、發 PRESENCE/SOS、我安全了、手機相距 20m、目視雷達方位。
- 證據資料夾 `tmp/a11-evidence/YYYYMMDD-HHMM/`；PowerShell helper `Shot`/`LogStart`/`LogStop`。
- 測前檢查（USB debug、RSA 授權、BLE、位置/Nearby/通知 權限、關省電、時間同步、GPS fix）＋排錯段
  （adb 看不到/unauthorized、權限未授〔含 `pm grant`〕、BLE 不通、QR 掃不到、connectedTest ambiguous〔`:app:`
  前綴 + `$env:ANDROID_SERIAL`〕、雷達需 GPS）。
- 具體識別：applicationId `network.ignirelay.field`、activity `network.ignirelay.ignirelay_app.MainActivity`。
- **誠實標註 step 5（HAZARD）BLOCKED**：目前 mapless debug shell **無 HAZARD 發送入口**——A3 只接了
  **typed 接收側**（`hazardEvents` 流 + projector 投影），`publishHazardMarker` 僅在 facade 層、無任何畫面
  呼叫，**發送 UI 隨舊地圖頁退役**。建議獨立小任務補一個 `kDebugMode`「發 HAZARD」測試鈕（不在 A11 範圍、
  本腳本不動 app code）。其餘 1–4、6–9 皆可實測。
- gates：本刀純文件（無 Dart/wire/DB/pubspec 變更），不觸發 code gate；A11-D1 DoD = 腳本存在且含表 1–9
  全步驟 + 證據欄（達成）。
- next: **A11-D2（USER-GATE）**——Owner 晚上雙機照腳本實測 + 截圖/logcat 回填（AI 可代跑 ADB 區）；A11-D2
  全項 PASS（step 5 另案）後 Owner 才在 STATUS 記結果、再開 A12（App↔Node 契約凍結）。

## [2026-06-16] A11-prep DONE（debug shell HAZARD 發送鈕 → 解開 A11 step 5）

GPT/Owner 判斷：A11-D1 腳本合格，但 step 5（B 發 typed HAZARD）因 mapless shell 無發送
入口被標 BLOCKED、A11-D2 無法全項通過。本刀補一顆 kDebugMode HAZARD 發送鈕還原發送能力。
code commit `8155e30`。

- **新 `lib/ui/shell/hazard_card.dart`**：自洽卡片（鏡像 A9-2 CheckpointCard）。訂閱
  `EventStream.hazardEvents` 顯示收到的 typed HAZARD（type/sev/座標）；kDebugMode 才出現
  「手動 HAZARD」鈕 → 對話框選類型（FIRE/FLOOD/COLLAPSE/CHEMICAL/ROADBLOCK/OTHER）+ 描述 →
  送出，接既有 `EventPublisher.publishHazard`。座標取本機 `LocalPositionSource`（**永不偷
  peer**，與 A10b 雷達 origin 同規則），無 GPS fix 用樣本座標仍送出 typed 事件；severity
  固定 2。注入 seam（hazardSource/onPublish/localEstimate）沿用 LastSeenScreen 模式，免
  provider 即可測。
- `debug_shell.dart`：CheckpointCard 後掛 `const HazardCard()`。
- `debug_shell_smoke_test.dart`：`_wrap` 補 `EventPublisher` + `LocalPositionSource`
  provider（HazardCard initState 需要；鏡像 production 注入）—— 否則 tall-surface smoke 會在
  HazardCard.initState 拋 ProviderNotFound、events-log 卡片不渲染而 FAIL。
- 測試 `test/ui/screens/hazard_card_test.dart`（+4）：空狀態 / 收到 typed HAZARD 顯示一列 /
  kDebugMode 送出走 seam（預設 FIRE、sev 2、帶本機座標）/ 無 GPS 退樣本座標（25.0339,121.5645）。
- `docs/ACCEPTANCE_A11_TWO_PHONE_SCRIPT.md`：step 5 由 ⚠BLOCKED 改可實測（操作=B 按手動
  HAZARD 選類型送出、預期=A 危害卡列表出現該事件）；彙總表 row 5、A11-D2 PASS 條件、§8
  USER-GATE 聲明皆移除「step 5 除外」例外 → 現 step 1–9 全項 PASS 才算 D2。

- gates（全 exit 0，KOTLIN 本刀實跑）：
  - `dart run tool/check_layers.dart --strict` → `ok — no boundary violations`
  - `flutter analyze` → `2 issues found`（皆既有 baseline info；0 errors / 0 新 issue）
  - `flutter test` → `00:21 +595 ~3: All tests passed!`（A10b-polish +591 → +595，HAZARD +4）
  - `dart run tool/generate_wire_conformance_v1.dart --check` → `--check OK`（未動 wire/corpus，
    rev 維持 `v0.3-phase0b-4-6-1`）
  - GATE-KOTLIN-BUILD：`:app:assembleDebugAndroidTest` → **BUILD SUCCESSFUL in 14s**（純 Dart
    UI、未碰 native；G17 本刀實跑、未沿用 A9/A10/A10b claim）
  - DESIGN §6：HazardCard 在 `lib/ui/shell/`（非 `lib/ui/screens/`，§6 grep 範圍外，與
    CheckpointCard/debug_shell 同；沿用 shell 既有 Colors.grey 風格）；`lib/ui/screens/position/`
    Colors grep 維持 0。
- 未動 wire/DB/proto/native/pubspec/specs。
- next: **A11-D2（USER-GATE）**：Owner 晚上接雙機照 runbook 實測 step 1–9（含本刀補上的 step
  5）+ 截圖/logcat 回填；AI 可代跑 ADB 區但不得代填/宣稱通過。A11-D2 全項 PASS 後 Owner 於
  STATUS 記，再開 A12（App↔Node 契約凍結）。

## [2026-06-16] PLAN-v1.4 DONE（App UI/IA 校正：UI-F/UI-G 插入 A11 前）

Owner 明示授權修訂 MASTER_EXECUTION_PLAN（G11 例外）：打開 App 後確認現況仍像 debug shell / 舊 onboarding，
產品體感不符合「場域安全工具」。本刀為 docs-only planning update，commit `d6dd61d`。

- `docs/MASTER_EXECUTION_PLAN.md` bump v1.3 → v1.4：Stage A 在 A10b 後插入 **UI-F**
  （正式 AppShell / UI-IA 重整 + motion-aware 定位節流）與 **UI-G**（先看功能/引導模式），再回 A11/A12。
- 新增 `docs/APP_UI_IA_REWORK_PLAN.md`：定義五分頁 `安全 | 位置 | 事件 | 協助 | 我的`、global SOS、
  no-field entry（加入場域 / 建立場域 / 先看功能）、participant/staff/owner 最小角色、DebugShell 降級、
  CommunicationState、motion-aware GPS/PRESENCE policy。
- motion-aware policy 定案：A9 固定 120s 僅為既有基線；UI-F production cadence 改 moving 30s、
  stationary 180s、low battery moving 60s / stationary 300s；使用低頻 motion sensor，不用 step
  counter / Activity Recognition，不新增 sensor 依賴，不要求 `ACTIVITY_RECOGNITION`。
- `docs/ACCEPTANCE_A11_TWO_PHONE_SCRIPT.md` 重寫為 v1.4：前置改 UI-F/UI-G DONE；A11 改驗正式
  AppShell、first-run/no-field、先看功能、participant/staff join、五分頁、global SOS、motion-aware
  diagnostics、PRESENCE/SOS/SAFE/HAZARD、restart/dedup、field-scope、connectedDebugAndroidTest、
  `位置` 雷達 ≥20m。
- gates：docs-only；`git diff --check` 已跑，無 whitespace error。
- deviations: MASTER 依 G11 需 Owner 明示授權；本次即 Owner 於對話中要求「寫 F/G、A11 也要改」。
- next: UI-F 開工（正式 AppShell + motion-aware 定位），UI-F DONE 後 UI-G，再執行 A11-D2。
## [2026-06-16] PLAN-v1.5 DONE — Claude review #1 後收斂 UI-F/A11 施工規格
- repo/commit: IgniRelay @ 5590495
- DoD:
  - D1 ✅ `docs/MASTER_EXECUTION_PLAN.md` bump v1.4 → v1.5；UI-F 明確拆成 UI-F0..UI-F5，禁止一刀混完整 AppShell/角色/motion。
  - D2 ✅ `docs/APP_UI_IA_REWORK_PLAN.md` bump v0.2；收斂 Claude review：QR/角色與 motion source 是真 blocker，IncidentCase/E-CARE/完整 visibility policy 延後。
  - D3 ✅ `docs/ACCEPTANCE_A11_TWO_PHONE_SCRIPT.md` bump v1.5；A11 改驗 owner+participant，不再驗 Stage A 尚不存在的 staff offline QR；補 applicationId 與 `ACTIVITY_RECOGNITION` 權限查核。
- gates:
  - `git diff --check` → exit 0
    ```
    warning: in the working copy of 'docs/ACCEPTANCE_A11_TWO_PHONE_SCRIPT.md', LF will be replaced by CRLF the next time Git touches it
    warning: in the working copy of 'docs/APP_UI_IA_REWORK_PLAN.md', LF will be replaced by CRLF the next time Git touches it
    warning: in the working copy of 'docs/MASTER_EXECUTION_PLAN.md', LF will be replaced by CRLF the next time Git touches it
    ```
- deviations: docs-only；未動 app code / wire / proto / GATT / crypto / DB / pubspec / tests。
- next: UI-F0 preflight（確認 staff offline QR deferred、motion source 走窄版 Android SensorManager/注入式 source、無 `sensors_plus`/`ACTIVITY_RECOGNITION`），再依序 UI-F1..UI-F5。

## [2026-06-17] UI-F0 DONE — preflight UI-F scope and acceptance gaps（docs-only）

- repo/commit: IgniRelay @ `11a601e`
- 執行者: Claude（Owner 授權 session；本刀經 Owner 於 UI-F0 任務明示授權編輯 MASTER，G11 例外）
- 性質: docs-only preflight。先以 rg / 讀檔對程式碼實證，再把 v1.5 剩餘 UI-F 規格縫隙釘死，未動 app code / pubspec / manifest / test。
- 實證（read-only）:
  - production home = `DebugShell`（`lib/main.dart:830`，`_StartupRouter` 在 `OnboardingScreen` 之後）。
  - 全 repo 無 `sensors_plus` / `ACTIVITY_RECOGNITION` / `SensorManager` / step counter；既有
    native bridge = `MethodChannel('network.ignirelay/native')` + `EventChannel`（`lib/platform/native_bridge.dart`）。
  - `PresenceBeaconController` 已有 `readBattery` callback（每次 (re)arm 前重讀、`_lowBatteryThreshold` 驅動節流）。
  - `FieldSession` 無 status 欄（fieldIdHex/displayName/joinedAtMs/cloudBaseUrl）；
    `ActiveFieldController` 僅 join/switchActive/leave（leave 不可逆），無 ended/archived lifecycle。
  - HAZARD 發送 UI 僅 `lib/ui/shell/hazard_card.dart`（kDebugMode），無角色 gating；
    `EventPublisher.publishHazard` → facade `publishHazardMarker`。
  - `field_qr_codec.dart`：staff token（seg4）必須伴隨 `https://` cloud URL（seg3），
    offline staff QR 為硬性 `staffWithoutCloud` 拒收 → Stage A offline 只有一條 `field_join_secret`。
- 文件決策（凍結，UI-F1..UI-F5 不得偏離）:
  - ①UI-F1 必須新增 widget smoke test：home≠DebugShell、no-field 三入口、五分頁精確 label、global SOS 每 tab 可達。
  - ②iOS motion source 延後（R3/iOS source-parity）；UI-F5 僅 Android 窄版 SensorManager / 注入式 source。
  - ③UI-F5 低電量沿用 `PresenceBeaconController.readBattery`，不新增 battery 來源。
  - ④Field.status lifecycle 延後；Stage A 只做 active/current field。
  - ⑤HAZARD Stage A：participant 與 owner 皆可發；staff deferred 不影響。
  - ⑥debug diagnostics 僅 debug/developer；release home 不落 DebugShell。
  - ⑦staff offline QR 不做回來（codec 已強制 staff token 需伴隨 https cloud URL）。
- 變更檔（3）:
  - `docs/MASTER_EXECUTION_PLAN.md` bump v1.5 → v1.5.1：UI-F 章補「UI-F0 preflight 結論」七條 + changelog v1.5.1（G11：Owner 授權、bump 版號 + changelog 記錄）。
  - `docs/APP_UI_IA_REWORK_PLAN.md` bump v0.2 → v0.2.1：新增 §4.0.1（findings + file:line 證據）。
  - `docs/ACCEPTANCE_A11_TWO_PHONE_SCRIPT.md` bump v1.5 → v1.5.1：新增 §0.1（HAZARD 角色、不驗 lifecycle、Android-only、不驗 staff offline QR、motion 權限查核）。
- gates（G17 逐字）:
  - `git diff --check` → exit 0（僅 benign LF→CRLF warning，同 PLAN-v1.5 既例）
  - rg 兩條 field secret 指令（3 docs）→ 無任一 `+` 新增行；唯一 repo 命中 MASTER:1770 為 v1.4 歷史 changelog（v1.5 已更正），非新指令
  - rg staff offline QR 驗收要求（3 docs）→ 全部為「延後 / 不驗 / 不做回來」，無任何要求驗收 staff offline QR
  - rg `sensors_plus|ACTIVITY_RECOGNITION`（pubspec + 全 AndroidManifest）→ 無命中（exit 1 = PASS；只查未改）
- deviations: 編輯 MASTER 依 G11 需 Owner 明示授權——本次即 Owner 於 UI-F0 任務的 allowed-files 清單明示授權，已 bump 版號 + 文末 changelog。
- next: **UI-F1**（AppShell entry：first-run/no-field entry、五分頁 AppShell、production home swap、DebugShell 降級為 debug-only；含 widget smoke test 如上 ①），維持 gate 綠並更新 STATUS。

## [2026-06-17] UI-F1 DONE — formal AppShell entry + no-field home

- repo/commit: IgniRelay @ `2047a13`
- 執行者: Claude（Owner 授權 session）；經 Owner 審查放行 UI-F0 後開工，Owner 指定範圍只做 UI-F1。
- 範圍: 只做 UI-F1（AppShell entry / first-run no-field entry / production home swap / DebugShell debug-only）。**不做** UI-F2 模組搬遷、UI-F3 角色模型、UI-F4 CommunicationState、UI-F5 motion、UI-G 引導模式。
- 變更檔（3）:
  - **新 `lib/ui/shell/app_shell.dart`**（正式 production 殼，DESIGN §4：全 `context.igni`/`IgniButton`/`IgniTypography`，0 個真實 `Colors.*`）：
    - `AppShell` watch `ActiveFieldController` → 無 active field 顯示 `NoFieldEntry`、有則五分頁 scaffold（join/leave 自動切換）。
    - `NoFieldEntry`：加入場域 / 建立場域（皆導向既有 A7 `FieldScreen`）+ 先看功能（佔位 snackbar，UI-G 再做）。
    - 五分頁 label = `kAppShellTabLabels`（單一真實來源）精確 `安全/位置/事件/協助/我的`，**無「地圖」tab**；分頁 body 為佔位 surface（UI-F2 移入模組）。
    - 全域 SOS 錨在 body 右下、bottom tab bar 之上（不重疊分頁點擊區）→ 既有 `SosScreen`（A8）；每個分頁可達；**未改 SOS 底層**。
    - 「我的」分頁 kDebugMode-only「開發者診斷（DebugShell）」→ debug-only 命名路由。
  - `lib/main.dart`：(1) `_StartupRouter` production home `const DebugShell()` → `const AppShell()`（onboarding/權限流程未動）；(2) 註冊 `kDeveloperDiagnosticsRoute`(`/debug-shell`) **僅 `kDebugMode||kProfileMode`**（與 `/design-showcase` 同模式）→ DebugShell 不再是 production home。
  - 新 `test/ui/shell/app_shell_test.dart`（+4 widget smoke）：no-field 三入口且非 DebugShell；五分頁精確 label + 無地圖 + 無 DebugShell；global SOS 每 tab 可達；我的分頁 debug 診斷入口（kDebugMode）。
- DoD（APP_UI_IA_REWORK_PLAN §4.3 之 UI-F1 子集）: D1 ✅（home 不落 DebugShell、no-field 三入口）/ D2 ✅（五分頁精確 label、無地圖）/ D3 ✅（global SOS 每 tab 可達）/ D7+D8 ✅（debug diagnostics 僅 debug-only、非 production home）。D5 角色/D6 motion/D9 HAZARD 正式入口 = UI-F2/F3/F5，非本刀。
- gates（G17 逐字）:
  - `dart run tool/check_layers.dart --strict` → `ok — no boundary violations`，exit 0
  - `flutter analyze --no-fatal-infos --no-fatal-warnings` → `2 issues found`（皆既有 baseline info battery_optimization_guide；**0 新**），exit 0
  - `flutter test --exclude-tags golden` → `All tests passed!` `+590 ~3`（HEAD 基線 586 + app_shell 4；以 `git stash -u` 實測基線確認 delta=+4，無掉測試），exit 0
  - `flutter test test/conformance/wire_conformance_corpus_test.dart` → `+21 All tests passed!`（未動 wire/corpus），exit 0
  - GATE-KOTLIN-BUILD `:app:assembleDebugAndroidTest` → **BUILD SUCCESSFUL in 1m 6s**（未碰 native；G17 本刀實跑），exit 0
  - DESIGN §6 `rg "Colors\." lib/ui/screens/ | rg -v debug_shell.dart` → 僅 4 處既有 `design_showcase_screen.dart`（debug-only 對照頁，A7 起既存、G5 禁順手清，非本刀 diff）；`app_shell.dart` 在 `lib/ui/shell/`（§6 範圍外）且 0 真實 `Colors.*`（唯一命中為註解字面）。
  - `rg "return const DebugShell" lib/main.dart` → 無（exit 1）；home 改 `return const AppShell()`。
- deviations: 無。未動 wire/proto/GATT/crypto/DB/pubspec/manifest；無新依賴；未引入 `sensors_plus`/`ACTIVITY_RECOGNITION`；未把 staff offline QR 做回來。
- next: **UI-F2**（模組搬遷：把既有 SOS/FieldScreen/LastSeenScreen+RelativeRadar/AdminBroadcastBanner/CheckpointCard/HazardCard/PresenceBeacon 移入對應分頁；HAZARD 升為正式事件入口〔participant+owner 皆可發，UI-F0 §4.0.1 F0-5〕），再 UI-F3..F5 → UI-G → A11-D2 → A12。

## [2026-06-17] UI-F2 DONE — move existing modules into the five AppShell tabs

- repo/commit: IgniRelay @ `b932157`
- 執行者: Claude（Owner 授權 session）；經 plan mode 提案、Owner 核准計畫並追加 6 條 copy/quality 硬邊界後開工。
- 範圍: 把既有模組搬進五分頁（UI-F2）。**不做** UI-F3 角色模型、UI-F4 CommState 聚合、UI-F5 motion、UI-G 引導；未動 wire/proto/GATT/crypto/DB/pubspec/manifest、無新依賴、未改 SOS 底層。
- 變更檔（7）:
  - 新 `lib/ui/shell/tabs/`（**全 token-clean**：`context.igni`+`ui/widgets`，0 真實 Colors.*）:
    - `safety_tab.dart`（安全）：近距離通訊狀態 + 開關（MeshRuntimeController）、「立即更新足跡」（PresenceController.publishPresence）、自動足跡信標 toggle（PresenceBeaconController）、最近足跡（EventStream.presenceUpdates）；通訊狀態彙整為產品佔位（UI-F4）。
    - `events_tab.dart`（事件）：AdminBroadcastBanner + `HazardCard(formalSend:true)` + CheckpointCard + 最近事件列表（EventStore.queryRecent）。
    - `my_tab.dart`（我的）：作用場域摘要 + 場域管理入口（→ 既有 FieldScreen）+ 身分/角色 & 權限狀態產品佔位（「即將提供」）+ kDebugMode「開發者診斷」入口（從 app_shell 移來）。
    - `assist_tab.dart`（協助）：產品佔位（離線協助 — 即將提供）。
  - `app_shell.dart`：IndexedStack 改掛 SafetyTab/LastSeenScreen/EventsTab/AssistTab/MyTab（位置直接嵌入既有 A10/A10b LastSeenScreen）；底部列/五 label/全域 SOS 不變，SOS 鈕加 `kGlobalSosButtonKey`；移除 dev 診斷入口與「UI-F2 將移入」佔位文案。
  - `hazard_card.dart`：新增 `formalSend` 旗標——true 時送出入口在 production 顯示（participant+owner，F0-5）且採正式文案（「回報危害」，無 debug/測試字樣）；DebugShell 的 `HazardCard()` 維持 kDebugMode-only 不變；**無 wire 變更**。
  - `test/ui/shell/app_shell_test.dart`（4→7）：沿用 debug_shell_smoke_test 的完整 provider graph；重驗 UI-F1 不變量（五精確 label、無地圖、global SOS 每 tab〔以 key 定位〕、home≠DebugShell），加 安全/位置〔嵌 LastSeenScreen〕/事件〔正式 HAZARD 入口非 debug gate〕/我的〔場域管理 + dev 入口〕。
- Owner 6 條硬邊界落實: ①可見文字無 UI-F2/debug/測試/將於（僅存在於程式註解）②安全頁用「立即更新足跡」「近距離通訊」非工程語 ③HazardCard formalSend 文案零 debug/測試，DebugShell 路徑不變 ④新 tab 包裝層 token-clean 0 Colors. ⑤UI-F1 smoke 不變量續綠 ⑥每分頁覆蓋測試到位。
- gates（G17 逐字）:
  - `dart run tool/check_layers.dart --strict` → `ok — no boundary violations`，exit 0
  - `flutter analyze --no-fatal-infos --no-fatal-warnings` → `2 issues`（皆既有 baseline，0 新），exit 0
  - `flutter test --exclude-tags golden` → `All tests passed!` `+593 ~3`（UI-F1 590 + app_shell 3），exit 0
  - `flutter test test/conformance/wire_conformance_corpus_test.dart` → `+21`（未動 wire），exit 0
  - GATE-KOTLIN-BUILD `:app:assembleDebugAndroidTest` → **BUILD SUCCESSFUL in 5s**（純 Dart UI、本刀實跑），exit 0
  - DESIGN §6 `rg "Colors\." lib/ui/screens/ | rg -v debug_shell.dart` → 僅 4 處既有 design_showcase（非本刀 diff）；`lib/ui/shell/tabs/` 0 真實 Colors.*
  - copy grep：tabs 可見 Text/label/SnackBar 字串無 UI-F/debug/測試/將於（exit 1）
- deviations: 無。
- next: **UI-F3**（最小 owner/participant 角色模型：由「本機建立 vs 加入」推導、不靠第二條 field secret；角色顯示於「我的」與 active field status；owner 可建立/分享場域 QR、participant 不可），再 UI-F4（CommunicationState）→ UI-F5（motion）→ UI-G → A11-D2 → A12。

## [2026-06-17] UI-F2-polish DONE — remove internal stage copy from no-field entry

- repo/commit: IgniRelay @ `f553484`
- 執行者: Claude（Owner 授權 session）；Owner 比對 UI-F2 diff 後指出唯一尾巴並下達此 polish brief。
- 背景: UI-F2 的 STATUS 宣稱「可見文字無 UI-F2/debug/測試/將於」，但 no-field 首頁（NoFieldEntry）仍有**兩處可見字串**露出建構階段名——「先看功能」預覽 SnackBar 與三入口下方說明皆寫「…將於 UI-G 提供」。此為 UI-F1 遺留（非 UI-F2 新增），但違反 UI-F0 邊界「正式產品可見面不得露施工階段名 / debug / 測試字眼」，且與 UI-F2 STATUS 的乾淨宣稱矛盾，故收尾補上。
- 變更檔（2）:
  - `lib/ui/shell/app_shell.dart`：兩處可見文案 `app_shell.dart:87`（SnackBar）、`app_shell.dart:149`（下方說明）皆改為「先看功能即將提供。」（產品語「即將提供」，無階段名）。「先看功能」仍為 stub（引導模式實作仍屬 UI-G）——僅改文案，無行為/wire/layer/依賴變更；程式註解中的 roadmap 引用（UI-G/UI-F）屬開發文件，不在「可見面」範圍，保留不動。
  - `test/ui/shell/app_shell_test.dart`：no-field 案例新增防迴歸斷言——畫面不得含「UI-G」「UI-F」「將於」。
- gates（Owner 指定三項，G17 逐字）:
  - `dart run tool/check_layers.dart --strict` → `ok — no boundary violations`，exit 0
  - `flutter test test/ui/shell/app_shell_test.dart` → `All tests passed!` `+7`，exit 0
  - `flutter analyze --no-fatal-infos --no-fatal-warnings` → `2 issues`（皆既有 baseline，0 新），exit 0
  - GATE-CONF-DART / GATE-KOTLIN-BUILD 未跑：本刀為純 copy 變更、未碰 wire/native，無觸發條件。
- deviations: 無。
- next: 同 UI-F2 → **UI-F3**（owner/participant 角色模型）。

## [2026-06-17] UI-F3 DONE — owner/participant field role model

- repo/commit: IgniRelay @ `ab617c2`
- 執行者: Claude（Owner 授權 session）；plan mode 提案 → Owner 核准並追加 2 條硬要求（migration 三路徑測試、re-join 不得降級 owner）→ 開工。
- 範圍: 最小 owner/participant 角色模型（APP_UI_IA §4.1 step 6 / §4.3 D5·D10 / RD-1 / F0-7）。角色純由「本機建立 vs 加入」推導、**不靠第二條 field secret**；單一 field_join_secret 不變。**未動 wire/proto/GATT/crypto**（D7：field_qr_codec / FieldAuthV2 / exportSecretForQr 密鑰流皆原封不動）；未動 pubspec/manifest、無新依賴。staff 維持「不存在」（保留給 Stage E 雲端 staff-token，刻意不設 enum case，不以第二 secret 偽造）。
- 變更檔（10 = 5 lib + 5 test，1 新）:
  - `lib/app/db/database_helper.dart`：version 13→14；`Field_Sessions` 加 `created_here INTEGER NOT NULL DEFAULT 0`（`_createFieldSessionsTable` 含此欄供 fresh install + <13 升級路徑）；新 `<14` 區塊以新 helper `_columnExists`（`PRAGMA table_info`）守 ALTER，避免從 <13 升級者重複加欄。DEFAULT 0 ⇒ 任何 v14 前既有場域視為 participant（保守、無分享權）。
  - `lib/app/services/field_session_store.dart`：`FieldSession.createdHere`；`_fromRow` 讀欄；`join(... createdHere)` **單調 OR 合併**——re-join 只會把旗標往上 promote，**永不把 owner 降級成 participant**，並回傳 effective 值。
  - `lib/app/controllers/active_field_controller.dart`：新 `enum FieldRole { owner, participant }`；`ActiveField.role` + `isOwner`；`createField` ⇒ owner；角色取自 store 回傳的 effective 旗標（re-join 記憶體也保 owner）；`initialize` reload 重推角色。
  - `lib/ui/screens/field/field_screen.dart`：作用中卡片 + 各場域列加角色 chip（主辦/成員）；**「顯示 QR」再分享鈕改 gate 於 `f.isOwner`**——只有建立者能再分享加入 QR（D5），participant 列不顯示。純 UI 政策，密鑰流不變。
  - `lib/ui/shell/tabs/my_tab.dart`：「身分與角色」佔位換成真實角色卡（主辦/成員 + 產品文案）；「權限狀態」維持獨立 OS 權限佔位（D10，角色與權限不混用）。
  - 測試（+9，593→602）：新 `test/db/database_migration_v14_test.dart`（fresh / v13→v14 / v12→v14：created_here 存在、default 0、無 double-add）；store + controller sticky-owner 與「角色撐過 reload」；field_screen owner-only 分享 gate；app_shell「我的」角色 chip。既有 QR-sheet 測試改用 createField（owner）以保有分享入口；store 欄位集斷言補 created_here。
- Owner 2 條追加硬要求落實: ① migration 三路徑測試齊備且綠（含 <14 guard 防 double-add 證明）②re-join 不降級 owner——store（DB）+ controller（記憶體）雙測試證明 sticky-true。
- gates（G17 逐字）:
  - `dart run tool/check_layers.dart --strict` → `ok — no boundary violations`，exit 0
  - `flutter analyze --no-fatal-infos --no-fatal-warnings` → `2 issues`（皆既有 baseline，0 新），exit 0
  - `flutter test --exclude-tags golden` → `All tests passed!` `+602 ~3`（UI-F2-polish 593 + 9），exit 0
  - `flutter test test/conformance/wire_conformance_corpus_test.dart` → `+21`（未動 wire），exit 0
  - GATE-KOTLIN-BUILD `:app:assembleDebugAndroidTest` → **BUILD SUCCESSFUL in 1m 9s**（DB 改動為純 Dart，本刀實跑），exit 0
  - DESIGN §6 `rg "Colors\." lib/ui/screens/ | rg -v debug_shell.dart` → 僅 4 處既有 design_showcase（非本刀；field_screen 0 處）
  - copy grep：my_tab / field_screen 可見字串無 UI-F/debug/測試/將於（命中皆 `//` 註解）
- deviations: 無。
- next: **UI-F4**（CommunicationState 聚合：cloud stub/off、BLE/mesh、peers/nodes、outbox、last presence、best-path copy；「安全」分頁通訊狀態彙整由佔位轉真實），再 UI-F5（motion-aware cadence）→ UI-G → A11-D2（USER-GATE）→ A12。

## [2026-06-17] UI-F4 DONE — CommunicationState aggregation into the 安全 tab

- repo/commit: IgniRelay @ `49fb561`
- 執行者: Claude（Owner 授權 session）；plan mode 提案 → Owner 核准並追加 2 條硬要求（手動足跡只在真送出/排隊才更新、5s timer 僅 UI refresh 必 dispose cancel）→ 開工。
- 範圍: 把「安全」分頁的 `通訊狀態彙整 — 即將提供` 佔位換成真實 CommunicationState 摘要（APP_UI_IA §4.0 / §4.1 step 7）。**純聚合**既有且已在 root 注入的數值——**未動 transport / wire / proto / GATT / crypto / DB、無新依賴**。cloud Stage A 維持 stub/off，文案一律不宣稱「可達/已連線」（誠實邊界，雲端串接留 Stage E）。全域通訊狀態 chip/banner（§4.1 step 2）本刀**不做**，摘要先落在「安全」分頁。
- 變更檔（6 = 3 lib + 3 test，3 新）:
  - 新 `lib/ui/shell/tabs/communication_state.dart`（**純 Dart、零 widget、零 app/ui import**，沿用 A10/A10b position_estimator/relative_position 純函式風格）：`CommunicationState` 值物件 + `.from()` 推導 `CommsPath`（noField / offline / waitingPeers / meshRelay）+ 誠實 cloud 文案；另含純判定 `presenceCountsAsSent`。
  - `lib/app/controllers/event_publisher.dart`：一行 `pendingQueueDepth` 讀通到 v2 facade outbox 深度（無 facade 回 0），讓 UI 經 EventPublisher facade 取值而非直碰 v2 facade。
  - `lib/ui/shell/tabs/safety_tab.dart`：用既讀 controller（+ EventPublisher + ActiveFieldController）建 CommunicationState 並渲染最佳路徑 / cloud / 待送 / 最後足跡；保留通訊開關與 peers/sent/received。
  - 測試（+13，602→615）：`communication_state_test`（best-path 矩陣、誠實 cloud 文案、passthrough、presenceCountsAsSent true/false 矩陣）；`event_publisher_pending_depth_test`（讀通 + 無 facade 回 0）；app_shell「安全」摘要出現 + 佔位消失 + dispose 無洩漏 timer。
- Owner 2 條追加硬要求落實: ①`_lastManualPresenceAt` 只在 `publishPresence()` 回 accepted 或 queued（`presenceCountsAsSent`）時更新；noField /「已嘗試」/ catch 失敗皆不更新——純判定函式單測涵蓋 true/false。②5s `Timer` callback 只 `if (mounted) setState((){})`、不累積/不偽造狀態，`dispose()` cancel；widget test 卸載分頁後快轉過 tick，洩漏的 periodic timer 會在 teardown 被判定 pending（綠＝已 cancel）。
- gates（G17 逐字）:
  - `dart run tool/check_layers.dart --strict` → `ok — no boundary violations`，exit 0
  - `flutter analyze --no-fatal-infos --no-fatal-warnings` → `2 issues`（皆既有 baseline，0 新），exit 0
  - `flutter test --exclude-tags golden` → `All tests passed!` `+615 ~3`（UI-F3 602 + 13），exit 0
  - `flutter test test/conformance/wire_conformance_corpus_test.dart` → `+21`（未動 wire），exit 0
  - GATE-KOTLIN-BUILD `:app:assembleDebugAndroidTest` → **BUILD SUCCESSFUL in 4s**（純 Dart，本刀實跑），exit 0
  - DESIGN §6 `rg "Colors\." lib/ui/screens/ | rg -v debug_shell.dart` → 僅 4 處既有 design_showcase（新 comms UI 在 lib/ui/shell，0 Colors）
  - copy grep：safety_tab / communication_state 可見字串無 UI-F/debug/測試/將於；cloud 文案無「已連線/可達」（命中皆 `//` 註解）
- deviations: 無。
- next: **UI-F5**（motion-aware cadence：低頻 Android 動作感測或注入式 source、moving/stationary 遲滯、低電量降頻沿用 PresenceBeaconController.readBattery、診斷狀態；不加 sensor 依賴、不要 ACTIVITY_RECOGNITION/step counter、雷達維持北朝上），再 UI-G → A11-D2（USER-GATE）→ A12。

## [2026-06-18] UI-F5a DONE — motion-aware presence cadence policy (Dart) ＝ UI-F5 PARTIAL（pending UI-F5b native source）

- repo/commit: IgniRelay @ `1b34153`
- 執行者: Claude（Owner 授權 session）；plan mode 提案 → Owner 核准並追加 **8 條硬邊界**（見下）→ 開工。
- **狀態邊界（Owner 邊界 1）: 本刀僅記 UI-F5a DONE；UI-F5 overall 仍是 PARTIAL，pending UI-F5b（原生 Android `SensorManager` source 經 NativeBridge + §4.2 GPS-fix-age 行為）。本刀不宣稱 UI-F5 DONE。**
- 範圍: APP_UI_IA §4.2/§4.3 **D6** motion-aware cadence 的**純 Dart 政策層**——動作分類器（遲滯）、2×2 cadence 矩陣、stationary→moving 觸發、診斷，全以**注入式假來源 + 假時鐘**測試覆蓋（滿足 D6）。**未動 wire / proto / GATT / crypto / DB、無新依賴、無 native code**。沒有來源時 motion 維持 `unknown`、cadence 退回現行 120s / 300s ⇒ **production cadence 零變更**，只新增「已測能力」＋一個省電修正。
- 變更檔（10 = 6 lib + 4 test，5 新）:
  - 新 `lib/app/services/motion/motion_state.dart`（**純 Dart**）：`enum MotionState { unknown, stationary, moving }` + 純 `motionPresenceInterval(...)`：moving 30s / stationary 180s / 低電 moving 60s / 低電 stationary 300s；**`unknown` → 退回 120s / 300s 固定 fallback**（＝今日行為，未接來源的 production build 不變）。
  - 新 `lib/app/services/motion/motion_classifier.dart`：windowed-RMS + 遲滯分類器（注入 `now`）；`addSample` / `state` / `stateChanges`（broadcast、只發真轉換）；**起始 `unknown`，絕不預設 stationary**；→moving 需 2 連續 active 視窗、→stationary 需 45s 連續安靜；**broadcast controller 於 `dispose()` close**。
  - 新 `lib/app/services/motion/motion_source.dart`：`abstract class MotionSource { magnitudes / start / stop }` + `NoopMotionSource`（永不發 → 維持 unknown）。**本刀無 native**；UI-F5b 才加 `NativeMotionSource`。
  - `lib/app/controllers/presence_beacon_controller.dart`：新增可選 ctor 參數 `motionStates` + 4 個 motion 間隔常數；`_arm()` 經 `motionPresenceInterval` 選間隔；**stationary→moving 立即發**（last-beacon null 或 >15s）並**走與週期 tick 同一道 gate**；`MotionState get motionState` 診斷；訂閱於 `dispose()` cancel。**未供 motion stream ⇒ 行為與今日完全相同**（main.dart 構造本刀不變、既有測試全綠）。
  - `lib/ui/shell/app_shell.dart`：IndexedStack 子頁包 `TickerMode(enabled: i == _index)`，讓非作用中分頁的計時器確實暫停。
  - `lib/ui/shell/tabs/safety_tab.dart`：足跡卡新增動作診斷行——`moving`「動作偵測：移動中」/`stationary`「動作偵測：靜止」/`unknown`「動作偵測：尚未啟用」（無來源的 production 恆顯「尚未啟用」，**絕不對 unknown 顯示「靜止」**）；5s refresh callback 加 `if (!mounted || !TickerMode.valuesOf(context).enabled) return;` 並計入 `@visibleForTesting debugRefreshTicks`；`dispose()` 仍 cancel。
  - 測試（+16，615→631）：新 `motion_state_test`（cadence 矩陣 6 案，含 unknown→120/300 fallback）；新 `motion_classifier_test`（起始 unknown／遲滯雙向／stateChanges 各轉換一次／dispose close 無 leak）；`presence_beacon_controller_test` +5（no-motion→unknown/120s；moving 30s/stationary 180s；低電 60s/300s；stale-transition 立即發；**邊界 3：disabled / no-field / mesh-off 轉換不送**）；`app_shell_test`（安全分頁顯「尚未啟用」非「靜止」；**邊界 6：AppShell/IndexedStack 情境下切到他頁後 `debugRefreshTicks` 不增**）。
- Owner 8 條硬邊界落實:
  1. ✅ 僅記 UI-F5a DONE；UI-F5 = PARTIAL pending F5b（本條）。
  2. ✅ 無來源 ⇒ `unknown`（非假 stationary）；unknown 退回 120/300；診斷顯「尚未啟用」絕不顯「靜止」。
  3. ✅ stationary→moving 立即發走既有 gate（enabled ∧ mesh ∧ field）；disabled/no-field/mesh-off 不送（3 子案測試）。
  4. ✅ classifier StreamController 於 dispose close；測試關閉並斷言 `emitsDone`、close 後 addSample 仍安全。
  5. ✅ GPS freshness / last-fix-age / stationary 不熱跑高精度 GPS **明確 deferred to F5b**，本刀不宣稱完成、未碰 LocationService/publish 路徑。
  6. ✅ 離畫面暫停 refresh 以 AppShell/IndexedStack 情境測（切分頁），非僅 isolated SafetyTab。
  7. ✅ 未碰 native bridge / SensorManager / MethodChannel；grep gate 確認 `lib/app/services/motion` 無 SensorManager/MethodChannel/sensors_plus（命中皆 `//` 註解說明 F5b 規劃）。
  8. ✅ 低電量沿用既有 `readBattery` callback，未新增電量來源。
- gates（G17 逐字）:
  - `dart run tool/check_layers.dart --strict` → `ok — no boundary violations`，exit 0
  - `flutter analyze --no-fatal-infos --no-fatal-warnings` → `2 issues`（皆既有 baseline，0 新；過程修掉 3 個新 info：motion_source const Stream、safety_tab TickerMode.valuesOf、test import 順序），exit 0
  - `flutter test --exclude-tags golden` → `All tests passed!` `+631 ~3`（UI-F4 615 + 16），exit 0
  - `flutter test test/conformance/wire_conformance_corpus_test.dart` → `+21`（未動 wire），exit 0
  - GATE-KOTLIN-BUILD `:app:assembleDebugAndroidTest` → **BUILD SUCCESSFUL in 5s**（本刀無 native 改動，仍實跑），exit 0
  - 無-native grep gate（邊界 7）：`rg "SensorManager|MethodChannel|sensors_plus" lib/app/services/motion` 僅命中 `//` 註解；`pubspec.yaml` 無 sensors_plus；Android manifests 無 ACTIVITY_RECOGNITION（皆與本刀前相同）
  - DESIGN §6 `rg "Colors\." lib/ui/screens/ | rg -v debug_shell.dart` → 僅 4 處既有 design_showcase（新 motion code 在 lib/app；新 UI 在 lib/ui/shell，0 Colors）
  - copy grep：safety_tab / motion 可見字串無 UI-F/debug/測試/將於；診斷對 unknown 顯「尚未啟用」非「靜止」（命中皆 `//` 註解）
- deviations: 無。
- next: **UI-F5b**（UI-F5 收尾：① 窄 Android `SensorManager` 加速度 motion source 經既有 `NativeBridge`〔MethodChannel('network.ignirelay/native') + EventChannel('network.ignirelay/events')〕接到 classifier→controller；② §4.2 GPS-fix-age：moving 且 fix 老於 moving_min_fix_age 30s 才於 PRESENCE 前 refresh GPS、stationary_min_fix_age 15min、stationary 不熱跑高精度 GPS。硬約束不變：無 sensors_plus、無 ACTIVITY_RECOGNITION、無 step counter、compass 不入雷達），收尾後 UI-F5 方可記 DONE；再 UI-G → A11-D2（USER-GATE）→ A12。

## [2026-06-18] UI-F5a-polish DONE — notify UI on paused motion change（Owner review 抓到的非 blocker 小尾巴）

- repo/commit: IgniRelay @ `28dfd42`
- 執行者: Claude（Owner 授權 session）；Owner 比對 UI-F5a 實際 commit 後放行、並標出一個非 blocker 診斷小尾巴，建議進 UI-F5b 前先補此 polish。
- 範圍: 修 `PresenceBeaconController._onMotion()` 在 **disabled（暫停）** 狀態下，若剛好是 `stationary → moving` 且 last-beacon stale，會落入立即發佈轉換分支——`_publishIfGated()` 與 `_arm()` 皆在 disabled 時提前 return、**不 `notifyListeners()`**——導致 `_motion` 已更新但動作診斷文字不會即時刷新。**純 app 層 controller 邏輯修正 + 1 回歸測試；未動 wire/proto/DB/native/UI 字串/deps、無新可見文案。**
- 變更檔（2 = 1 lib + 1 test，0 新）:
  - `lib/app/controllers/presence_beacon_controller.dart`：`_onMotion()` 在更新 `_motion` 後、轉換分支**之前**先處理 `!_enabled`——`notifyListeners()` 後 return，不發佈不 arm。一致涵蓋暫停下的轉換與非轉換變化；enabled 路徑完全不變（移除原 `else if (_enabled)/else` 分歧，因 disabled 已在前段攔下，剩下單純 enabled `else`→`_arm()`）。
  - `test/controllers/presence_beacon_controller_test.dart`：+1 回歸測試「disabled: a stationary→moving change still notifies the UI without publishing or arming」——先在暫停下沉澱到 stationary，掛 listener 後加 moving，斷言**恰好 1 次通知**、`motionState==moving`、`count()==0`、`isRunning==false`。修正前此轉換走 publish/arm 路徑零通知 → 測試會 FAIL（確實守住回歸）。
- gates（G17 逐字）:
  - `dart run tool/check_layers.dart --strict` → `ok — no boundary violations`，exit 0
  - `flutter analyze --no-fatal-infos --no-fatal-warnings` → `2 issues`（皆既有 baseline，0 新），exit 0
  - `flutter test --exclude-tags golden` → `All tests passed!` `+632 ~3`（UI-F5a 631 + 1），exit 0
  - `flutter test test/conformance/wire_conformance_corpus_test.dart` → `+21`（未動 wire），exit 0
  - GATE-KOTLIN-BUILD `:app:assembleDebugAndroidTest` → **BUILD SUCCESSFUL in 1m 5s**（純 Dart，本刀仍實跑），exit 0
- deviations: 無。
- 對 UI-F5 整體狀態無影響：**UI-F5 overall 仍 PARTIAL，pending UI-F5b**（原生 SensorManager source + §4.2 GPS-fix-age）。
- next: 同上——**UI-F5b**（收尾後 UI-F5 方可記 DONE）→ UI-G → A11-D2（USER-GATE）→ A12。

## [2026-06-18] UI-F5b DONE — 原生 Android 動作來源 + §4.2 GPS-fix-age 政策（**UI-F5 overall 自此 DONE**）

- repo/commit: IgniRelay @ `b10da37`
- 執行者: Claude（Owner 授權 session）；plan mode 提案 → Owner 選「一刀做完動作+GPS」、抓到 hazard_card 既有假座標 fallback、追加硬邊界（throttle≥200ms、手動 timeout 寫死、idempotent、resetForTest、誠實 GPS reason、**正式路徑禁假座標**）→ 修訂 plan → 開工。
- 範圍: 收尾 UI-F5（APP_UI_IA §4.2 / D6）。兩半：①原生 Android 加速度 motion source 經**既有 NativeBridge**接 classifier→beacon；②§4.2 GPS-fix-age 政策（fix 時戳 + 單次 refresh + 移除常駐高精度 stream + 移動且過時才發前 refresh + 手動事件單次有界 fresh fix + 診斷）。**未動 wire/proto/GATT/crypto/DB、無新依賴、無 ACTIVITY_RECOGNITION/step counter/compass、無新增 manifest 權限。**
- 變更檔（22 = 12 lib + 1 kotlin… 實為 11 lib/1 kotlin + 9 test/1 main，5 新 lib + 4 新 test）:
  - 動作來源：`android/.../MainActivity.kt` 加 `startMotionSensor/stopMotionSensor`〔SENSOR_DELAY_NORMAL + ≥200ms throttle、idempotent〔已啟動再呼叫 no-op〕、stop/onDestroy 解除註冊；經 companion `sharedEventSink` 發 `{type:"motion",magnitude}`〕；`native_bridge.dart` 加 start/stop + `motionMagnitudes` 流 + 純 `parseMotionMagnitude`；新 `motion/native_motion_source.dart`〔NativeMotionSource，`_started` 守 idempotent、注入 seam〕；新 `motion/motion_service.dart`〔source+classifier 生命週期，idempotent start/stop/pause、dispose 不漏〕；`main.dart` 模組級 `_motionService`〔Android→Native，其餘→Noop＝iOS 延後〕+ `_IgniRelayAppState` WidgetsBindingObserver 前景啟動/背景暫停 + 接 `motionStates`。
  - GPS：`location_service.dart` 加 `lastFixAt` + `refreshOnce`〔有界 timeout、in-flight dedup、失敗沿用上次 fix 永不 throw〕、**移除常駐 `getPositionStream` 熱跑**、加 Geolocator LatLng seam + `resetForTest`；新純檔 `motion/gps_refresh_policy.dart`〔`shouldRefreshBeforePresence`：moving∧fix≥30s；誠實 `GpsPolicyReason{movingRefresh/stationaryReuse/unknownReuse/manualEvent/unavailable}`，**刻意無 lowBattery**〕；新 `location_refresh_coordinator.dart`〔ensureFreshForBeacon / ensureFreshForManualEvent / lastFixAge / lastReason〕；`presence_beacon_controller.dart` 加可選 `onBeforePublish`〔在 gate 內、publish 前 await，失敗不中止 publish〕；`sos_controller.dart`/`checkpoint_controller.dart` 加 `ensureFreshLocation` 鉤〔SOS/markSafe ≤1500ms、CHECKPOINT ≤2000ms，失敗不中止送出〕；`main.dart` 接 coordinator provider + 三鉤。
  - 診斷/假座標：`safety_tab.dart` 足跡卡加「GPS 定位：N 分鐘前/尚無定位」+ 誠實「定位策略：…」〔低電量不混入〕；`hazard_card.dart` **把 `_kSampleLat/_kSampleLng` 隔離到 `formalSend==false` debug 路徑**，正式 HAZARD 先單次有界 refresh→真 fix 才發，**無真座標則不送並提示「目前沒有位置，請取得位置後再回報」**（Owner 紅線：正式路徑零假座標）。
- Owner 12 條硬邊界落實: ①正式路徑零假/樣本座標〔hazard_card 隔離 + 正式無 fix 不送，測證〕②throttle ≥200ms ③手動 timeout 寫死 SOS1500/HAZARD・CHECKPOINT2000、GPS 失敗不中止 SOS〔測證〕④moving∧≥30s 才 refresh、stationary 沿用且無熱跑 stream〔矩陣測〕⑤refreshOnce 有界/沿用/不 throw/dedup〔測證〕⑥MotionService/NativeMotionSource/Kotlin 全 idempotent〔start-twice/stop-before-start/pause-resume/dispose 測〕⑦LocationService resetForTest 隔離〔teardown 還原〕⑧GPS reason 誠實無 lowBattery〔enum 集合測〕⑨僅既有 NativeBridge、無 sensors_plus/ACTIVITY_RECOGNITION/step/compass/manifest 權限〔grep 綠〕⑩iOS 延後＝Noop⑪無 wire/proto/GATT/crypto/DB、hook 在 gate 內、F5a/polish 行為不變⑫gates 全綠含實跑 KOTLIN 後才記 DONE。
- gates（G17 逐字）:
  - `dart run tool/check_layers.dart --strict` → `ok — no boundary violations`，exit 0
  - `flutter analyze --no-fatal-infos --no-fatal-warnings` → `2 issues`（皆既有 baseline，0 新），exit 0
  - `flutter test --exclude-tags golden` → `All tests passed!` `+673 ~3`（UI-F5a-polish 632 + 41），exit 0
  - `flutter test test/conformance/wire_conformance_corpus_test.dart` → `+21`（未動 wire），exit 0
  - GATE-KOTLIN-BUILD `:app:assembleDebugAndroidTest` → **BUILD SUCCESSFUL in 20s**（MainActivity SensorManager 本刀實跑），exit 0
  - grep gates：pubspec 無 sensors_plus；android 無 ACTIVITY_RECOGNITION/step counter；`_kSampleLat/_kSampleLng` 僅 hazard_card〔正式不可達，formal-no-fix 測證〕，app/ 命中 25.0339 皆 IEEE-754 註解非 publish；DESIGN §6 `Colors\.` 僅 4 處既有 design_showcase（新 UI 在 lib/ui/shell，0 Colors）；copy grep 正式可見字串無 UI-F/debug/測試/將於、GPS 文案無「目前位置」。
- deviations: 無。
- **UI-F5 overall 自此 DONE**（motion source + §4.2 GPS-fix-age 皆完成；iOS motion 明確延後 R3，非 UI-F5 範圍）。實機加速度行為 + GPS refresh 時序留 A11 雙機 device gate（無法單測）。
- next: **UI-G**（先看功能/引導）→ A11-D2（USER-GATE，Owner 雙機實機回填 runbook 13 步）→ A12 契約凍結。

## [2026-06-18] UI-F5b-polish DONE — 全 runtime 零假座標 + LocationService stream 自癒 + GPS reason 誠實化（UI-F5 維持 DONE）

- repo/commit: IgniRelay @ `660b005`
- 執行者: Claude（Owner 授權 session）；Owner 比對 UI-F5b 實際 diff/grep 後判定無 blocker、UI-F 可進 UI-G，但點出 3 條小尾巴並將「零假座標」規則升級為更廣版（連 debug shell 都不留）。plan mode 提案 → Owner 核准並追加 2 條精修（LocationService 自動復原非僅 resetForTest；A11 註記對實際步驟不要假設 step 9）→ 開工。本刀為 UI-F5b 自身審核尾巴的 cleanup，**UI-F5 仍維持 DONE**，非重開。
- 範圍: ① runtime 全面拔除樣本座標（含 debug shell）② LocationService 單例 broadcast stream 生命週期硬化 ③ GPS 診斷 reason 誠實化。**未動 wire/proto/GATT/crypto/DB/native**；無新依賴；無 manifest 變更。`GpsPolicyReason` 仍為純 UI 診斷、**永不上 wire/DB**（A10/A10b 保持）。
- 變更檔（10 = 5 lib + 4 test + 1 doc）:
  - `lib/ui/shell/hazard_card.dart`：刪除 `_kSampleLat/_kSampleLng` 常數與其文件區塊；`_promptAndPublish` 合併為**單一 no-fix 守衛**——無真實 fix 時正式與 debug 兩條路徑皆**不送**並顯示「目前沒有位置，請取得位置後再回報」。正式路徑仍先取一次有界 fresh fix（`ensureFreshLocation`，debug 不呼叫 ⇒ DebugShell 不需 coordinator provider）。改用 `est?.lat/est?.lng` + null-promotion（移除 `hasFix` 樣本分支）；snackbar/描述文案去除「樣本座標」字樣。
  - `lib/app/services/location_service.dart`：`_locationController` 改可重建欄位；新 `_ensureLocationControllerOpen()`（已關閉就重建 broadcast controller），由 `locationStream` getter 與 `_adoptFix` **兩處**呼叫 ⇒ dispose 後取得的 fix 仍會推送、**不靜默丟棄**，dispose 後新訂閱者也拿到活 stream；`resetForTest` 亦呼叫之。production 不呼叫 dispose，行為不變。
  - `lib/app/services/motion/gps_refresh_policy.dart`：`GpsPolicyReason` 加 `movingReuseFreshFix`；`gpsReasonForBeacon` 加 `refreshed` 參數 ⇒ moving 時 `refreshed?movingRefresh:movingReuseFreshFix`，診斷不再宣稱沒發生的 refresh。
  - `lib/app/services/location_refresh_coordinator.dart`：`ensureFreshForBeacon` 將既有 `refresh` 旗標以 `refreshed:` 傳入 reason mapper。
  - `lib/ui/shell/tabs/safety_tab.dart`：`_gpsReasonLabel` 加 `movingReuseFreshFix → 移動中沿用新定位`。
  - `docs/ACCEPTANCE_A11_TWO_PHONE_SCRIPT.md`：Step 9（實際即正式 HAZARD／座標查核步驟）加零假座標註記——B 需真實 GPS/last-known fix，無 fix 拒送並提示；室內無 fix 應延後此座標型查核而非標 FAIL。
- 測試（+1，673→674）:
  - `hazard_card_test.dart`：原「DEBUG 無 fix 退回樣本座標」改為「DEBUG 無 fix 亦不送 + 顯示提示」（publishCalls==0 + 提示文案）；保留以 `localEstimate` seam 注入真座標的 with-coordinate 測試；正式三測不變；檔頭註解更新。
  - `location_service_test.dart`：新增——dispose 後經 `locationStream` 訂閱仍收到下一次 `refreshOnce` fix（自癒、事件不丟棄），且 `refreshOnce` 不 throw。
  - `gps_refresh_policy_test.dart`：refreshed true→movingRefresh、false→movingReuseFreshFix；enum 集合補 movingReuseFreshFix；仍**無 lowBattery**。
  - `location_refresh_coordinator_test.dart`：moving+stale→movingRefresh、moving+fresh→movingReuseFreshFix。
- Owner 2 條精修落實: ① LocationService 自動復原（getter + `_adoptFix` 皆呼叫 `_ensureLocationControllerOpen`，dispose 後事件不丟棄）——非僅 resetForTest；② A11 註記對實際 Step 9（讀現檔確認無另設座標步驟）。
- gates（G17 逐字）:
  - `dart run tool/check_layers.dart --strict` → `ok — no boundary violations`，exit 0
  - `flutter analyze --no-fatal-infos --no-fatal-warnings` → `2 issues`（皆既有 baseline，0 新），exit 0
  - `flutter test --exclude-tags golden` → `All tests passed!` `+674 ~3`（UI-F5b 673 + 1），exit 0
  - `flutter test test/conformance/wire_conformance_corpus_test.dart` → `+21`（未動 wire），exit 0
  - GATE-KOTLIN-BUILD `:app:assembleDebugAndroidTest` → **BUILD SUCCESSFUL in 1m 9s**（本刀未碰 Kotlin，仍實跑），exit 0
  - no-fake-coordinate gate: `rg "_kSampleLat|_kSampleLng" lib` → **0 命中**；`rg "25\.0339|121\.5645" lib` → 僅 location_evidence_builder.dart:13 / event_envelope_v2.dart:1065 兩處 IEEE-754 文件註解（非可執行座標常數）；DESIGN §6 `Colors\.` 僅 4 處既有 design_showcase。
- deviations: 無。
- **UI-F5 仍為 DONE**（本刀為審核尾巴 cleanup，非重開）。零假座標規則自此延伸至「app runtime 含 debug shell」。
- next: **UI-G**（先看功能/引導）→ A11-D2（USER-GATE，Owner 雙機回填 runbook 13 步）→ A12 契約凍結。

## [2026-06-18] UI-G DONE —「先看功能」引導預覽（純 fixture、不啟動 mesh / 不送事件）

- repo/commit: IgniRelay @ `2a72811`
- 執行者: Claude（Owner 授權 session）；plan mode 提案 → Owner 核准並追加 4 條精修（fixtures 零可解碼物、CTA→FieldScreen 測試走完整 provider harness、雷達放有界盒、fixture-only import 守衛 grep+test）→ 開工。
- 範圍: no-field「先看功能」從 SnackBar 佔位換成真正有界引導預覽（APP_UI_IA §5 / MASTER UI-G）。**結構性 fixture-only**：PreviewScreen 不持有任何 publisher/controller/location provider ⇒ 無從啟動 mesh、送 wire event、寫真 membership、索取權限、顯示真 secret。**未動 wire/proto/GATT/crypto/DB**；無新依賴；無 manifest 變更。
- 變更檔（5 = 2 新 lib + 1 lib 接線 + 1 新 test + 1 test）:
  - 新 `lib/ui/screens/preview/preview_fixtures.dart`：純 display-only demo 資料（示範場域 label =「示範場域 · DEMO-FIELD」純描述字串，**無**擬真 join secret / QR / IGNI1 / field_id hex〔Owner①〕；示範足跡 anon8+時間+PositionEstimate、示範 SOS/HAZARD/廣播/打卡；座標僅供雷達/列表呈現、永不進 publisher）。
  - 新 `lib/ui/screens/preview/preview_screen.dart`：5 頁引導 PageView tour——加入場域 / 安全〔被看見+SOS illustrated〕/ 位置〔最後可信位置 + 重用純 RelativeRadar 放固定高有界盒〕/ 事件〔危害/廣播/打卡〕/ 協助+離線降級；IgniSubPageHeader 返回 +「示範資料」badge + 頁點 + 上一步/下一步；結束路徑 加入/建立場域 → FieldScreen（pushReplacement，避免殘留 nav stack）、返回 → pop；全 token-clean 零硬編色、文案「最後可信位置」永不「目前位置」〔§3.6〕。
  - `lib/ui/shell/app_shell.dart`：NoFieldEntry `_previewStub` SnackBar 改 push `PreviewScreen`，移除「先看功能即將提供。」佔位字 + 更新 doc。
- 測試（+6，674→680）:
  - 新 `preview_screen_test.dart`：零-provider 群組——無任何 provider 即可 pump〔結構證明無從 publish〕、走完 5 頁、雷達在有界盒渲染、整樹無「目前位置」；import 守衛測試——讀 preview/*.dart import 行斷言不含 event_publisher / presence_*_controller / sos_controller / checkpoint_controller / location_* / active_field_controller / mesh / app·proto·db / platform〔Owner④〕。
  - `app_shell_test.dart`（完整 provider harness，Owner②）：no-field 點「先看功能」→ PreviewScreen〔非 SnackBar〕、加入場域 CTA → FieldScreen〔widgetWithText 鎖按鈕避開同名頁標題〕、返回 → 回 no-field。
- Owner 4 精修落實: ①fixtures 無可解碼 secret/QR/IGNI1/hex ②CTA→FieldScreen 測試走完整 harness、零-provider 測試不觸 FieldScreen ③RelativeRadar 放 SizedBox(320) 有界盒〔避免 PageView 無界高度〕④fixture-only import grep+test 雙重守衛。
- gates（G17 逐字）:
  - `dart run tool/check_layers.dart --strict` → `ok — no boundary violations`，exit 0
  - `flutter analyze --no-fatal-infos --no-fatal-warnings` → `2 issues`（皆既有 baseline，0 新），exit 0
  - `flutter test --exclude-tags golden` → `All tests passed!` `+680 ~3`（UI-F5b-polish 674 + 6），exit 0
  - `flutter test test/conformance/wire_conformance_corpus_test.dart` → `+21`（未動 wire），exit 0
  - GATE-KOTLIN-BUILD `:app:assembleDebugAndroidTest` → **BUILD SUCCESSFUL**（未碰 native，仍實跑），exit 0
  - grep gates：DESIGN §6 `Colors\.` 僅 4 處既有 design_showcase（preview token-clean）；forbidden-import `rg ... lib/ui/screens/preview` → 0；preview 可見樹無「目前位置」；fixtures 無可解碼 IGNI1/secret/hex（IGNI1/目前位置 僅出現在規則說明註解，與 relative_radar 既有作法一致）。
- deviations: 無。
- **UI-F + UI-G 皆 DONE**——Stage A 介面層（正式 AppShell / 五分頁 / motion-aware 定位 / 引導預覽）收尾完成。
- next: **A11-D2（USER-GATE，Owner 兩台 Android 實機照 runbook 13 步回填，AI 可代跑 ADB/Gradle 但不得代填/宣稱通過）→ A12 App↔Node 契約凍結**。

## [2026-06-18] A11-D2-prep READY — 雙機驗收 runbook 對齊 UI-F/UI-G（docs-only，狀態 READY-FOR-OWNER-TEST）

- repo/commit: IgniRelay @ `3459aa5`
- 執行者: Claude（Owner 授權 session）；Owner 指示：晚上接兩台 Android USB 偵錯後由 AI 直接代跑 ADB 驗收，先把 runbook 對齊目前 UI-F/UI-G 後流程。**docs-only。**
- 範圍: 更新 `docs/ACCEPTANCE_A11_TWO_PHONE_SCRIPT.md`，使其符合 UI-F（正式 AppShell + 五分頁 + motion-aware 定位）與 UI-G（先看功能/引導預覽）後的 App 流程，並改寫為 AI 代跑 ADB、Owner 手動操作的今晚實跑腳本。**未碰 app code / wire / proto / GATT / crypto / DB / native；無新依賴；無 manifest 變更。**
- 狀態紅線: **不宣稱 A11 通過、不寫 A11 DONE**——本檔狀態僅 **READY-FOR-OWNER-TEST（A11-D2-prep）**。PASS/FAIL 與「結果」欄一律由 Owner 在實機回填；AI 不得預填、不得代判、不得宣告 Stage A Exit。
- 變更（1 檔 docs，+105/−15）:
  - Header：加狀態橫幅 READY-FOR-OWNER-TEST；D2 框架改為「今晚 AI 在電腦端代跑 ADB/Gradle/logcat/截圖，Owner 在手機端做實體操作」；USER-GATE 紅線重申（AI 不可代填 PASS/FAIL、不可宣稱雙機通過、不可宣告 Stage A Exit）。
  - §0：角色表加 `dumpsys`；加註「每步皆有 `分工` 行」。
  - **每步 `分工` 行（Step 1–13）**：逐步點名 AI 代跑指令 / Owner 手動操作 / 該步證據（截圖·logcat·dumpsys）。
  - Step 2（UI-G）：強化為引導預覽——**可進可退**（下一步/上一步雙向翻 5 頁、返回回 no-field 不殘留）、**不啟動 mesh、不送事件、不建立真 field**、**不需任何權限**（位置/藍牙/相機全拒仍可瀏覽）、位置文案「最後可信位置」永不「目前位置」；加選用 logcat 佐證無 mesh/權限活動。
  - Step 3：加 raw join secret 不外洩查核（Owner 讀畫面密鑰填 `$SECRET`，AI 代跑 `Select-String` grep join logcat，預期無命中）。
  - Step 4：明列五分頁 smoke（安全/位置/事件/協助/我的）+ 無「地圖」tab。
  - 保留雙機核心：同場域加入 / PRESENCE / SOS / SAFE / HAZARD / 最後可信位置·雷達 / 重啟後狀態；package id `network.ignirelay.field`、證據夾 `tmp/a11-evidence/<timestamp>/` 不變。
  - §5 表尾 + §7 + 新 §8 修訂紀錄：結果僅 Owner 回填、READY ≠ pass。
- gates: docs-only，未碰 code，無需跑 G17 build/test gate（無 Dart/Kotlin 變更）。
- deviations: 無。
- next: **A11-D2（USER-GATE，今晚）**——Owner 兩台 Android 實機照本檔逐步實測、AI 可代跑 ADB/Gradle/logcat/截圖收證據，Owner 回填全項 → 全 PASS 後才可 A11 DONE → A12 App↔Node 契約凍結。

## [2026-06-20] A11-preflight-fix DONE — fresh install 直接進 AppShell（移除舊 onboarding gate；不宣稱 A11 通過）

- repo/commit: IgniRelay @ `a8e1cc1`
- 執行者: Claude（Owner 授權 session）；Owner 指示：修掉 fresh install 後還會先進舊 OnboardingScreen / 背景執行設定的問題，使 A11 Step 1 能直接看到新版 no-field entry（加入場域 / 建立場域 / 先看功能）。
- 範圍: 修 `main.dart` `_StartupRouter` 啟動路由。UI-F1 只把 onboarding 完成後的 production home 換成 AppShell，但 `_StartupRouter` 仍保留舊 onboarding gate，故 fresh install 實跑為「權限 → 舊 OnboardingScreen → 舊 BatteryOptimizationGuide → AppShell」，與 UI-F/UI-G 及 A11 runbook 不一致。**未碰 wire/proto/GATT/crypto/DB/native/pubspec。**
- 變更（3 檔 = 1 lib + 1 新 test + 1 doc）:
  - `lib/main.dart`：移除 `onboarding_done` pref gate 與 `_showOnboarding` 欄位——`_requestPermissions()` 回來後直接 `setState(_initialized=true)` ⇒ `build()` 回 `const AppShell()`；LocationService init 改為一律延後至首幀（每條路徑都落在殼）。移除 `_onOnboardingComplete()` 及其自動 `BatteryOptimizationGuide.checkAndGuide(context)` 呼叫——首次進殼前不再自動跳電池/背景執行設定。啟動失敗 fallback 也落在 AppShell（不再退回 OnboardingScreen）。移除已不再使用的 `onboarding_screen.dart` / `battery_optimization_guide.dart` import。**`_requestPermissions()` 保留**（Android 權限仍請求）。
  - **scope guard**：`OnboardingScreen` / `BatteryOptimizationGuide` 原始檔**不刪**（避免擴大 scope），只是在正式 first-run path 不再可達。
  - 新 `test/startup/first_run_routing_test.dart`：source guard（`_StartupRouter` 因 initState 觸發原生 plugin 無法在 flutter test pump）——讀 `lib/main.dart`、剝除 `//` 註解後斷言正式啟動路徑不含 `OnboardingScreen` 構造 / `onboarding_done` gate / `_showOnboarding` / 自動 `.checkAndGuide(`、import 不含舊兩檔、且 `return const AppShell();` 存在。AppShell→no-field 三入口的行為證明維持在 `app_shell_test.dart`。
  - `docs/ACCEPTANCE_A11_TWO_PHONE_SCRIPT.md` Step 1：fresh install 預期改為「**Android 權限 → no-field 三入口**」，明列**不再**出現「開始使用烽傳 / Start Using IgniRelay」引導頁、**不再**自動跳背景執行/電池最佳化設定。
- 狀態紅線: 本刀只修 first-run 路由，**不代表 A11 通過、不寫 A11 DONE**；A11 仍待 D2 USER-GATE（Owner 雙機實機回填）。
- gates（G17 逐字）:
  - `dart run tool/check_layers.dart --strict` → `ok — no boundary violations`，exit 0
  - `flutter analyze --no-fatal-infos --no-fatal-warnings` → `2 issues`（皆既有 baseline battery_optimization_guide.dart:27/249，0 新），exit 0
  - `flutter test --exclude-tags golden` → `All tests passed!` `+684 ~3`（UI-G 680 + 4 新 startup guard），exit 0
  - `flutter test test/conformance/wire_conformance_corpus_test.dart` → `+21`（未動 wire），exit 0
  - GATE-KOTLIN-BUILD `:app:assembleDebugAndroidTest` → **BUILD SUCCESSFUL in 1m 18s**（未碰 native，仍實跑），exit 0
  - 額外（建議項）：`flutter build apk --release` → **Built app-release.apk (70.8MB)**，確認可打包。
- deviations: 無。
- next: **A11-D2（USER-GATE，今晚）**——Owner 兩台 Android 實機照 runbook 逐步實測、AI 可代跑 ADB/Gradle/logcat/截圖收證據，Owner 回填全項 → 全 PASS 後才可 A11 DONE → A12 App↔Node 契約凍結。

## [2026-06-20] UI-H0 DONE — 正式 UI i18n / 字級 / legacy ARB 清查（docs-only audit）

- repo/commit: IgniRelay @ `8a3ac96`
- 執行者: Claude（Owner 授權 session）；依 `docs/UI_H_I18N_A11Y_PLAN.md`「UI-H0 — Audit and Task Map」施工。
- 範圍: **docs-only**。產出 `docs/UI_H_I18N_A11Y_AUDIT.md`（UI-H1..H4 施工真實來源），並把其審核基準 `docs/UI_H_I18N_A11Y_PLAN.md` 一併納管。**未改 app code、未改 ARB、未跑 gen-l10n、未刪任何檔、未碰 wire/proto/GATT/crypto/DB/native；未碰 `docs/MASTER_EXECUTION_PLAN.md`。**
- 變更（2 檔 docs，皆新增）:
  - `docs/UI_H_I18N_A11Y_AUDIT.md`：方法區（逐字記錄實跑 `rg` 指令）+ formal UI 檔分類表（18 檔、~285 條可見硬字串）+ legacy/debug 表 + large-text 風險表 + ARB legacy key 候選表 + UI-H0 十題逐題回答 + H2 設計註記 + 建議施工順序。
  - `docs/UI_H_I18N_A11Y_PLAN.md`：companion 規劃檔納入版控（先前為 untracked）。
- 主要查核結論（皆附 file:line / 指令證據於 audit）:
  - **正式 UI 零 l10n**：全 `lib/ui` 僅 2 檔呼叫 `context.l10n`，且都是 legacy（`secondary/onboarding_screen.dart`、`secondary/battery_optimization_guide.dart`）。UI-F/UI-G 正式畫面全為硬編繁中 ⇒ UI-H2 為 greenfield，新 key 與既有（legacy）key 無碰撞。
  - **全專案僅 5 個非 generated 檔引用 `S`**：`main.dart`、`app/controllers/tier_manager.dart`、上述 2 dead 畫面、`l10n/l10n_ext.dart`。
  - **舊 map/chat/supply/medical/station 等畫面已不存在**（`lib/ui` 樹中無檔），其 ARB key 全無 compiled 消費者。
  - **ARB ~99% 死碼**：`app_zh.arb` ≈1198 key-shaped 行（supply 392 / map 139 / station 78 / medical 61 / chat 55 / profile 43 / match 34 / handoff 29 …）；**唯一 live message key = `main*`(6) + `tierLabel*`(4)**（`tier_manager` 經 `Provider<TierManager>` main.dart:501 實際 wired）。`onboarding*`(14) / `battery*`(46) 為 dead-screen-bound（隨檔同刀刪）。
  - **兩個正式 startup 提示已在地化**：Bluetooth 啟用對話框 + 權限 snackbar 走 `main*` key，非硬編。
  - **UI-H1 無 blocker**：`setLocale`/`setTextScale`/`textScaleOf`（main.dart:317-334）、持久化 `app_language`/`app_text_scale`（main.dart:382-420）、`IgniTextScale` 1.00/1.15/1.30/1.45（igni_text_scale.dart:27）、root builder 套合成 textScaler（main.dart:651-657）皆就位；`my_tab.dart` 157 行、零 facade 讀取 ⇒ 加設定區遠低於 500 行規則。讀目前語言用 `Localizations.localeOf(context)`（無需新增 locale getter）。
- DoD（對照 UI-H0）: ✅ audit 檔存在；✅ 含 formal/legacy/debug 表、逐檔硬字串數、large-text 風險清單、ARB legacy key 候選、H1/H2/H3/H4 建議施工順序；✅ 無 app 行為變更；✅ 本 STATUS 記 UI-H0 DONE @ 8a3ac96 附指令與摘要證據。
- gates: **docs-only，未碰 Dart/Kotlin/ARB，依 STATUS 慣例（同 A11-D2-prep）無需跑 G17 build/test gate**。read-only 掃描指令全部記錄於 audit §0。
- deviations: 無。**未宣稱 UI-H DONE、未宣稱 A11 passed。** MASTER 仍無 UI-H 條目（依 plan §9 Q1，UI-H 暫為側規劃文件，待 Owner 授權再整合）。
- next: **UI-H1**——於 `我的` 加正式語言（中文/English）+ 字級（標準/大字/特大字/超大字）設定區，重用既有 API、不新增 singleton/依賴/locale store。
