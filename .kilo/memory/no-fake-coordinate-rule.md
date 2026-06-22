Owner standing rule（2026-06-18，UI-F5b → UI-F5b-polish 兩刀確立並擴大）：IgniRelay production path must **never** emit a fake / sample / default coordinate — 此規則自 UI-F5b-polish 起延伸至 **debug shell**，不只 release build。

- **HAZARD（座標型）**：先取一次有界 fresh GPS fix → 否則 last-known **真實** fix → 仍無 ⇒ **不發**，顯示「目前沒有位置，請取得位置後再回報」。**不得** fallback 到樣本/預設座標。
- **SOS / 我安全了 / PRESENCE / CHECKPOINT**：缺位置 ⇒ `location = null` / 無 `LocationEvidence`，**永不**用座標 stand-in。GPS 取得失敗/逾時**不得中止或延遲** SOS（zero-delay 紅線；手動事件 fresh-fix 上限 SOS/markSafe≤1500ms、HAZARD/CHECKPOINT≤2000ms）。
- **測試**要驗「有座標正常」時：用 test seam（例：`hazard_card.dart` 的 `localEstimate` 注入真實 `PositionEstimate`），**不可**在 app runtime 內建 sample coordinate。雙機驗收只用真實 GPS/last-known；室內無 fix 則延後座標型查核，不標 FAIL（見 A11 runbook Step 9）。

**Why:** 假座標會污染驗收判斷、誤導收方/DB/事後分析（wire 只看得到 lat/lng，看不出是樣本），且 debug 入口若意外進 production 會變成真正的錯誤災害點。

**How to apply:** 任何新的座標型發佈路徑都要走「真實 fix 或不送」。Grep gate＝`rg "_kSampleLat|_kSampleLng" lib` 必須 0、座標數值常數不得出現在任何 publish 路徑。實作參考 [[master-execution-plan]] 的 UI-F5b / UI-F5b-polish 段（`hazard_card.dart` 單一 no-fix 守衛、正式路徑 `LocationRefreshCoordinator.ensureFreshForManualEvent`）。
