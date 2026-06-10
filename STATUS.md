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
