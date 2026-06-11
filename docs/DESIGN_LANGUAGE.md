# 烽傳 IgniRelay — 設計語言規範 DESIGN LANGUAGE（v1.0，normative）

> **狀態：凍結（G6 管制）。** 本文件對「App 正式畫面（Stage A A7–A10）」與
> 「Web 管理台（Stage C C3）」**同時有效**。施工 AGENT 在動任何 UI 之前必須先讀完本文件；
> 違反 §5 禁用清單或 §6 enforcement gate 的 UI 交付一律 FAIL（見
> `MASTER_EXECUTION_PLAN.md` G 規則）。
>
> 單一真實來源：
> - App tokens：`ignirelay_app/lib/ui/theme/`（`IgniPalette` / `IgniTokens` / `IgniTypography`）
> - Web tokens：`ignirelay-gateway/webapp/tokens.css`（由本文件 §2 的值生成，已就位）
> - Web 範本：`ignirelay-gateway/webapp/index.html`（**首例範本——C3 必須延伸它，不得另起爐灶**）

---

## §1 定位與美學立場

烽傳是**救災場域的作業工具**，不是消費性產品官網。兩端 UI 的共同立場：

1. **戰情室（ops console）美學**：高資訊密度、表格優先、狀態一眼可讀。參考質感：
   Grafana 暗色主題、航管/調度台。**不是** SaaS landing page、不是行銷網站。
2. **暗色優先**：預設深色（省電、夜間/低光場域可讀）；App 另有 light 與
   emergency 高對比模式（`IgniPalette` 已內建）。
3. **狀態即顏色**：紅=SOS、琥珀=警示/品牌、綠=安全、藍=資訊。顏色只從 token 來。
4. **等寬字呈現機器資料**：event_id、anon8、node_id、時間戳、座標一律 monospace。
5. **克制**：品牌琥珀只用於品牌列、主要互動元素與 P1 強調；大面積永遠是中性深灰。
   畫面上同時出現的強調色 ≤3 種。

## §2 Design tokens（兩端共同值；hex 與 App `IgniPalette` dark 完全一致）

### 2.1 色彩

| Token | 值 | 用途 |
|---|---|---|
| `--ig-brand` | `#E8803B` | 品牌琥珀（烽火）；主要按鈕、active tab、焦點 |
| `--ig-brand-hover` | `#F08E4A` | hover |
| `--ig-brand-soft` | `rgba(232,128,59,.14)` | 品牌底色塊 |
| `--ig-bg-0` | `#0E1013` | 頁面底 |
| `--ig-bg-1` | `#151820` | 卡片/欄位底 |
| `--ig-bg-2` | `#1C2029` | 浮層/表頭/hover 列 |
| `--ig-bg-3` | `#242936` | 更高層（選中列、輸入框） |
| `--ig-text-0` | `#EEF0F3` | 主文字 |
| `--ig-text-1` | `#C6CAD1` | 次文字 |
| `--ig-text-2` | `#8A8F98` | 輔助/標籤 |
| `--ig-text-3` | `#5A5F68` | 失效/浮水印 |
| `--ig-border-0/1/2` | `rgba(255,255,255,.06/.10/.16)` | 邊界三級 |
| `--ig-sos` | `#E5484D` | SOS 紅（P0/RED、TRAPPED） |
| `--ig-sos-soft` | `rgba(229,72,77,.14)` | SOS 卡底 |
| `--ig-warn` | `#F5A524` | 警示（P1/YELLOW、stale、INJURED） |
| `--ig-warn-soft` | `rgba(245,165,36,.12)` | |
| `--ig-ok` | `#30A46C` | 安全/上線/通過 |
| `--ig-ok-soft` | `rgba(48,164,108,.12)` | |
| `--ig-info` | `#5B8DEF` | 資訊/連結/P3 |
| `--ig-info-soft` | `rgba(91,141,239,.12)` | |

優先級對應（全產品一致）：`P0`=sos 紅、`P1`=warn 琥珀、`P2/ALERT`=warn、
`P3/NORMAL`=info 藍、`P4/低`=text-2 灰。

### 2.2 字體

```
sans: system-ui, "Segoe UI", "Noto Sans TC", "Microsoft JhengHei",
      "PingFang TC", sans-serif
mono: ui-monospace, "Cascadia Mono", Consolas, "Courier New", monospace
```
零外部字型（**禁止** webfont/CDN——場域離線）。字級階（Web）：頁標 18/600、
區標 14/600、表格與正文 13/400、輔助 12/400、KPI 數字 22/600 mono。

### 2.3 尺寸與密度

- 間距格：4 的倍數（4/8/12/16/24）。頁面外距 16，卡片內距 12–14。
- 圓角：卡片/輸入 8px、小元件 6px、chip 可 999px。**卡片圓角上限 12px**。
- 表格列高 32px（緊湊）；表頭 sticky、`--ig-bg-2` 底、12px 大寫字距標籤。
- 觸控目標（App）≥48dp；SOS 主鈕 ≥96dp。
- 邊框細線 1px `--ig-border-1`；陰影僅兩級（淡），禁止厚重 drop-shadow。

### 2.4 狀態圖形

不用 icon font、不用 emoji。狀態以 **8px 圓點**（`.dot`，token 色）與幾何字元
（`●` `▲` `■`，僅此三個，且必須帶文字標籤）表達。方向/趨勢用 CSS 三角或 `▲▼`。

## §3 Web 管理台規則（C3 施工必讀）

1. **必須延伸 `webapp/index.html` 範本**：appbar、tab 結構、`.card/.chip/.table/.kpi`
   類名與 `tokens.css` 變數照用；新頁籤 = 新 `<section class="panel">`，不得重做殼。
2. **顏色唯一來源 = `tokens.css`**：`index.html`/`app.css`/`app.js` 內禁止出現
   hex/rgb 色字面值（enforcement 見 §6）。需要新色 → 走 G6 改本文件 + tokens.css。
3. 資料呈現：時間一律「相對時間 + hover 絕對時間」（`app.js` 已給 `relTime()`）；
   id 類欄位 `.mono` + 截短（前 8 hex）+ title 全值。空狀態要有文字（「尚無事件」），
   不留白屏。
4. 連線狀態常駐 appbar（`●` ok 綠 / 失聯 sos 紅 + 最後成功輪詢時間）。
5. 響應式下限 1280×800（管理 PC）；不必做手機版，但 1024 寬不得爆版。
6. 全部 UI 文字繁體中文；術語跟 App 一致（場域、足跡、節點、事件、匯出）。

## §4 App 正式畫面規則（A7–A10 施工必讀）

1. 一律透過 `Theme.of(context).extension<IgniPalette>()` 與 `IgniTokens` 取值；
   **禁止** 在 `lib/ui/screens/**` 直接使用 `Colors.*` 或 hex 字面值
   （現存 `debug_shell.dart` 為豁免名單，A7+ 汰換時一併清掉）。
2. 元件優先序：先用 `ui/widgets/` 既有元件（`IgniCard`/`IgniButton`/`IgniChip`/
   `StatusChip`/`SlideUpSheet`…）；不足時新元件放 `ui/widgets/` 且吃 token，
   不得在 screen 內寫死樣式。
3. `design_showcase_screen.dart` 是元件對照頁——新元件必須同步加進 showcase。
4. 急難情境規範：SOS 流程全程可單手大拇指操作；倒數取消鈕 ≥64dp；
   emergency palette（高對比）下所有狀態色仍須可辨。
5. 位置文案鐵則（REBUILD §3.6）：寫「最後可信位置 / 推估」，禁止寫「目前位置」。

## §5 禁用清單（兩端通用；出現即 FAIL）

1. ❌ emoji 當 icon 或裝飾（含按鈕/標題/空狀態）。
2. ❌ `linear-gradient` / `radial-gradient`（任何漸層）。
3. ❌ 紫/靛/粉作主色或大面積使用。
4. ❌ 卡片圓角 >12px、整頁大留白 hero 區、置中大標語 landing 版式。
5. ❌ 外部資源：CDN、Google Fonts、外站圖片/JS/CSS（離線場域 + 隱私）。
6. ❌ icon font 套件（FontAwesome 等）；v1 不引入 icon 庫。
7. ❌ 骨架閃爍動畫、彈跳動畫；允許的動效僅 150ms 內的 opacity/transform 過渡
   與 SOS 卡 2s 呼吸（範本已給 `.pulse`）。
8. ❌ 在 UI 字串混用簡體中文。

## §6 Enforcement gates（驗收時逐字執行；非 0 輸出即 FAIL）

```powershell
# Web（於 ignirelay-gateway/）—— 全部期望輸出為空：
grep -rn "linear-gradient\|radial-gradient" webapp/
grep -rn "googleapis\|cdn\.\|unpkg\|jsdelivr\|fontawesome" webapp/
grep -rEn "https?://" webapp/ --include=*.html --include=*.css --include=*.js | grep -v "^\s*//" | grep -v "<!--"
grep -rn "#[0-9a-fA-F]\{6\}\|#[0-9a-fA-F]\{3\}\b\|rgb(" webapp/index.html webapp/app.js   # 色值只准在 tokens.css 與 app.css 之外為 0；app.css 也僅允許 var(--ig-*)
python -c "import sys,glob,re;bad=[(f,l) for f in glob.glob('webapp/**/*.*',recursive=True) if f.endswith(('.html','.css','.js')) for i,l in enumerate(open(f,encoding='utf-8')) if re.search(r'[\U0001F000-\U0001FAFF☀-➿]',l) for l in [f'{f}:{i+1}']];print(*bad,sep='\n');sys.exit(1 if bad else 0)"

# App（於 ignirelay_app/）—— A7 起，豁免名單外期望為空：
grep -rn "Colors\." lib/ui/screens/ | grep -v "debug_shell.dart"
```

## §7 範本檔案清單（已就位，施工 AI 不得重寫殼）

| 檔案 | 角色 |
|---|---|
| `ignirelay-gateway/webapp/tokens.css` | §2 token 的 CSS 變數（唯一色彩來源） |
| `ignirelay-gateway/webapp/app.css` | 元件樣式（appbar/card/chip/table/kpi/sos-card） |
| `ignirelay-gateway/webapp/index.html` | 版面殼 + **SOS 看板完成例**（含 sample 資料，`data-sample` 標記） |
| `ignirelay-gateway/webapp/app.js` | tab 切換、relTime()、API 接點留 C2/C3（標 `C3-WIRE`） |
| `ignirelay-gateway/webapp/DESIGN_README.md` | 給接手 AGENT 的第一頁守則 |

範本內 `data-sample` 標記的假資料：C3 接上真 API 後**必須移除**
（gate：`grep -n "data-sample" webapp/index.html` 於 C3 結案時為 0）。

---

Changelog：v1.0（2026-06-10）初版，值取自 `IgniPalette` dark（`igni_colors.dart:120-154`）。
