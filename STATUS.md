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
