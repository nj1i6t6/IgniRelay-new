# A11 — 雙機實機驗收 Runbook（USER-GATE）

> **任務**：MASTER_EXECUTION_PLAN §5 A11。
> **這份文件 = A11-D1**（AGENT 產出的可執行驗收腳本）。**A11-D2** = Owner 晚上接兩台 Android
> 手機、照此腳本實測 + 截圖 + logcat + 回填證據。
>
> **USER-GATE 鐵則**：
> - AGENT（Claude / Codex）**只能**產出本腳本，並可在 Owner 接好手機後**代跑 ADB/gradle 等
>   半自動步驟**。
> - **AGENT 不得代填證據、不得宣稱「雙機通過」。** A11-D2 是否 PASS 只由 Owner 實機回填判定。
> - Stage A Exit（§5.13）在 A11-D2 全項 PASS 前**不得宣告**。
>
> **狀態**：D1 = ✅（本檔存在、含 A11 表 1–9 全步驟 + 證據欄）；D2 = ⏳ pending Owner 實機。

---

## 0. 角色分工（晚上誰做什麼）

| 類別 | 內容 | 誰做 |
|---|---|---|
| **自動 / 半自動（ADB 區）** | `adb devices`、build/install、清/抓 logcat、截圖、`force-stop` 重啟、`:app:connectedDebugAndroidTest` | AI 可代跑（Owner 手機接好、授權後） |
| **人工操作區** | QR 出示/掃碼、按「啟動」mesh、發 PRESENCE/SOS、「我安全了」、手機相距 20m、目視雷達方位 | **Owner 親手操作手機**（AI 無法代） |

> Android Studio **非必要**。只要電腦有 Flutter / Android SDK / `adb`，CLI 就夠。Android Studio 只在
> 「手機抓不到 / 授權跳不出來 / 要圖形化 Logcat / SDK 壞掉」時才需要。晚上前可選擇性開 Android
> Studio 確認兩台手機出現在 Device Manager，但不是必要步驟。

---

## 1. 測前檢查（兩台手機各做一次）

開測前逐項打勾（這些沒到位，後面 ADB 一定卡）：

- [ ] **USB 偵錯**已開（設定 → 開發者選項 → USB debugging）。
- [ ] 手機接上電腦後，畫面跳「**允許這台電腦 USB 偵錯？**」→ 勾「一律允許」→ 確定（RSA 授權）。
- [ ] **藍牙**已開（BLE mesh 必需）。
- [ ] App 權限：**位置（精確/一律允許）**、**附近的裝置 Nearby devices**、**通知**全部允許。
- [ ] **省電限制**：對本 app 關閉電池最佳化 / 允許前景服務（設定 → 電池 → 不受限制），否則
      背景 mesh / 前景服務可能被殺。
- [ ] 兩台手機**系統時間大致同步**（HLC/事件時間用；差幾秒可、差幾分鐘會讓「≤10s」「12h」之類
      判斷失真）。
- [ ] 兩台手機**戶外或近窗**能拿到 GPS fix（PRESENCE 帶座標、雷達 origin、step 9 都需要）。

> 命名約定：本檔以 **A** = 手機 A（建立場域者）、**B** = 手機 B（掃碼加入者）。Step 7 會讓 B 暫時
> 切到別的場域充當「外人」，不需要第三台手機。

---

## 2. 環境與裝置確認（電腦端，PowerShell）

```powershell
# 專案根
cd C:\Users\radio\Downloads\IDE\IgniRelay\ignirelay_app

flutter --version            # 確認 Flutter/Dart 可用
adb version                  # 確認 platform-tools 可用
flutter doctor -v            # 可選：確認 Android toolchain 綠

# 兩台手機都接上後：
adb devices -l               # 應列出 2 台、狀態 device（非 unauthorized / offline）
```

把兩台手機的 serial 設成變數（之後所有指令都用它）：

```powershell
# 從 adb devices -l 複製各自 serial（第一欄），填進來：
$DEVICE_A = "<手機A的serial>"
$DEVICE_B = "<手機B的serial>"

# 驗證：分別印出型號，確認沒貼反
adb -s $DEVICE_A shell getprop ro.product.model
adb -s $DEVICE_B shell getprop ro.product.model
```

> 若 `adb devices` 顯示 `unauthorized` / `offline` / 只看到 1 台 → 見 §8 排錯。

---

## 3. 建置與安裝（debug build；兩台都裝同一份 APK）

> 用 **debug** build：A9 CHECKPOINT 手動鈕、A9 ADMIN 發佈鈕等是 `kDebugMode` gated，release 不會出現。

```powershell
cd C:\Users\radio\Downloads\IDE\IgniRelay\ignirelay_app

# 方式一（推薦）：build 一次，兩台各裝
flutter build apk --debug
$APK = "build\app\outputs\flutter-apk\app-debug.apk"
adb -s $DEVICE_A install -r $APK
adb -s $DEVICE_B install -r $APK

# 方式二：flutter 直接裝到指定機
# flutter install -d $DEVICE_A
# flutter install -d $DEVICE_B
```

applicationId（安裝後的套件名）= **`network.ignirelay.field`**。啟動 App：

```powershell
# 任一台啟動（LAUNCHER intent，最穩）
adb -s $DEVICE_A shell monkey -p network.ignirelay.field -c android.intent.category.LAUNCHER 1
adb -s $DEVICE_B shell monkey -p network.ignirelay.field -c android.intent.category.LAUNCHER 1
# 或： adb -s $DEVICE_A shell am start -n network.ignirelay.field/network.ignirelay.ignirelay_app.MainActivity
```

---

## 4. 證據資料夾 + 共用 helper（PowerShell）

所有截圖 / logcat 落同一個時間戳資料夾：

```powershell
cd C:\Users\radio\Downloads\IDE\IgniRelay
$STAMP = Get-Date -Format "yyyyMMdd-HHmm"
$EVID  = "tmp\a11-evidence\$STAMP"
New-Item -ItemType Directory -Force $EVID | Out-Null
"evidence dir = $EVID"
```

截圖 helper（手機上截一張、拉回電腦、刪手機暫存）：

```powershell
function Shot([string]$serial, [string]$name) {
  $remote = "/sdcard/a11_$name.png"
  adb -s $serial shell screencap -p $remote
  adb -s $serial pull $remote "$EVID\$name.png"
  adb -s $serial shell rm $remote
  "saved $EVID\$name.png"
}
# 例： Shot $DEVICE_A "step1_A_qr"
```

logcat helper（抓 Dart `debugPrint`＝`flutter` tag；落檔，可同時開兩台）：

```powershell
# 開始錄（背景 job）。建議每個 step 開新檔。
function LogStart([string]$serial, [string]$tag) {
  adb -s $serial logcat -c                       # 清舊 log
  $f = "$EVID\logcat_$tag.txt"
  $j = Start-Job -ScriptBlock {
    param($s,$out) adb -s $s logcat -v time flutter:V *:S | Out-File -Encoding utf8 $out
  } -ArgumentList $serial,$f
  Set-Variable -Name "JOB_$tag" -Value $j -Scope Global
  "logging $serial → $f (job $($j.Id))"
}
function LogStop([string]$tag) {
  $j = Get-Variable -Name "JOB_$tag" -ValueOnly
  Stop-Job $j; Receive-Job $j | Out-Null; Remove-Job $j
  "stopped log $tag"
}
# 例： LogStart $DEVICE_B "step6"   ... 操作 ...   LogStop "step6"
```

> 想要某台 app 的**完整** logcat（非只 flutter tag）：
> `$p = adb -s $DEVICE_B shell pidof network.ignirelay.field; adb -s $DEVICE_B logcat --pid=$p -v time`

---

## 5. 逐步驗收（A11 表 1–9）

> 每步格式：**目的 / 操作（人工 or ADB）/ 預期 / 證據指令 / Owner 回填**。
> Owner 回填欄請直接在本檔（或另存 `..._FILLED.md`）寫 `PASS / FAIL + 觀察 + 證據檔名`。

### Step 1 — 建立場域 + 掃碼加入
- **目的**：A7 場域加入 UX（QR 五段式）在真機可用。
- **操作（人工）**：
  1. A：debug shell →「場域管理」→ 建立場域 → 顯示 QR。
  2. B：「場域管理」→ 掃碼 → 掃 A 的 QR → 加入。
- **預期**：兩機都顯示**同一 fieldId 前 8 碼**。
- **證據（ADB）**：
  ```powershell
  Shot $DEVICE_A "step1_A_qr"
  Shot $DEVICE_B "step1_B_joined"
  ```
- **Owner 回填**：fieldId 前 8 碼 A=`______` B=`______`；結果 ☐PASS ☐FAIL；證據：`step1_*.png`

### Step 2 — 啟動 mesh + 互發 PRESENCE
- **目的**：A2 PRESENCE 接線 + BLE mesh 雙機互通。
- **操作（人工）**：兩機各按「**啟動**」(mesh)；各按「**發 PRESENCE**」（或開「自動 PRESENCE 信標」）。
- **預期**：對方的「最後可信位置」列表（或「最近 PRESENCE 足跡」）出現**本機 anon8 + 時間**。
- **證據**：
  ```powershell
  LogStart $DEVICE_A "step2_A"; LogStart $DEVICE_B "step2_B"
  # …操作後…
  Shot $DEVICE_A "step2_A_peerlist"; Shot $DEVICE_B "step2_B_peerlist"
  LogStop "step2_A"; LogStop "step2_B"
  ```
- **Owner 回填**：A 看到 B 的 anon8？☐ B 看到 A 的 anon8？☐；☐PASS ☐FAIL；證據：`step2_*`

### Step 3 — A 長按發 SOS(RED)，倒數中取消一次後再真發
- **目的**：A8 SOS 狀態機（長按→倒數→可取消→送出）+ 收端 ≤10s 告警。
- **操作（人工）**：A：「發 SOS」→ 長按 1.5s 選 **受困(RED)** → 5s 倒數中**按取消**（驗證可取消）→
  再長按一次 → 這次**讓倒數跑完**送出。**用碼錶記 A 送出 → B 告警卡出現的秒數。**
- **預期**：B 端 `sosAlerts` 告警卡 **≤10s** 出現。
- **證據**：
  ```powershell
  LogStart $DEVICE_B "step3_B"
  # …操作…（碼錶計時）
  Shot $DEVICE_A "step3_A_sent"; Shot $DEVICE_B "step3_B_alert"
  LogStop "step3_B"
  ```
- **Owner 回填**：取消成功？☐；送達秒數 ≈`____`s（需 ≤10）；☐PASS ☐FAIL；證據：`step3_*`

### Step 4 — A 發「我安全了」
- **目的**：A8 markSafe → STATUS_UPDATE(SAFE) → 收端標解除（OD-8 不新增 SOS_CANCELLED）。
- **操作（人工）**：A：在 SOS 畫面按「**我安全了**」。
- **預期**：B 端**該 author 的 SOS 卡標「已解除」**。
- **證據**：
  ```powershell
  Shot $DEVICE_B "step4_B_resolved"
  ```
- **Owner 回填**：B 端標已解除？☐；☐PASS ☐FAIL；證據：`step4_B_resolved.png`

### Step 5 — B 發 HAZARD（typed） ⚠ 已知阻塞
- **目的**：A3 typed HAZARD 收發。
- **⚠ 現況（誠實標註，AI 查核）**：目前 **mapless debug shell 無 HAZARD 發送入口**——A3 只接了
  **typed 接收側**（`hazardEvents` 流 + `V2InboundProjector` 投影都在），但**發送 UI 隨舊地圖頁退役**，
  `publishHazardMarker` 僅存在於 facade 層、無任何畫面呼叫它。
- **結論**：本步驟 **D2 暫標 BLOCKED**。需先補一個 `kDebugMode` 的「發 HAZARD」測試鈕（建議獨立小任務
  〔例如 `A-hazard-send`〕，**不在 A11 範圍、不在本腳本動 app code**）。補上後再回來跑本步。
- **可先做的接收側 sanity（若有任何 HAZARD 來源）**：A 端「危害」列表出現該事件即證明接收/投影鏈路活著。
- **Owner 回填**：☐ BLOCKED（無發送入口）／☐PASS（補鈕後）；備註：`__________`

### Step 6 — 殺掉 B 進程重啟 → 不重複 + Outbox 補送
- **目的**：envelope_id dedup + Outbox_V2 持久化補送。
- **操作（ADB + 人工）**：
  ```powershell
  LogStart $DEVICE_B "step6_B"
  adb -s $DEVICE_B shell am force-stop network.ignirelay.field          # 殺進程
  adb -s $DEVICE_B shell monkey -p network.ignirelay.field -c android.intent.category.LAUNCHER 1  # 重啟
  ```
  重啟後人工：B 再按「啟動」mesh（若未自動）；觀察先前未送達的事件是否補送、且 A 端不出現重複。
- **預期**：事件**不重複**（dedup by envelope_id）；B 重啟後 Outbox **補送**先前佇列事件。
- **證據**：
  ```powershell
  Shot $DEVICE_A "step6_A_nodup"; Shot $DEVICE_B "step6_B_restarted"
  LogStop "step6_B"   # 檢查 log 內補送 / dedup 字樣
  ```
- **Owner 回填**：A 端有無重複？`____`；B 有補送？☐；☐PASS ☐FAIL；證據：`step6_*`

### Step 7 — 場域隔離（field-scope mismatch）
- **目的**：未同場域的事件**收不到**，trace 顯示 mismatch。
- **操作（人工，B 充當外人）**：B：「場域管理」→ **離開**目前場域 → **建立另一個新場域**（或加入別的）→
  在新場域按「發 PRESENCE」。A 維持原場域。
- **預期**：A **收不到** B 的新 anon8；A 端 logcat 出現 **field-scope mismatch**（或同義拒收 trace）。
- **證據**：
  ```powershell
  LogStart $DEVICE_A "step7_A"
  # …B 切場域後發 PRESENCE…
  Shot $DEVICE_A "step7_A_noshow"
  LogStop "step7_A"   # grep mismatch / field-scope
  ```
  ```powershell
  Select-String -Path "$EVID\logcat_step7_A.txt" -Pattern "mismatch|field.?scope|noField"
  ```
- **Owner 回填**：A 沒出現 B 新 anon8？☐；log 有 mismatch？☐；☐PASS ☐FAIL；證據：`step7_*`
- **測後復原**：B「場域管理」→ 重新掃 A 的 QR 回到 A 的場域（為 step 9 準備）。

### Step 8 — GATE-KOTLIN-RUN（其中一機跑儀器測試）
- **目的**：在真機跑 wire-conformance 儀器測試（`connectedDebugAndroidTest`）全綠。
- **操作（ADB；建議只接其中一台，避免多機 ambiguous）**：
  ```powershell
  cd C:\Users\radio\Downloads\IDE\IgniRelay\ignirelay_app\android
  # 只留一台連著，或設 $env:ANDROID_SERIAL 指定
  $env:ANDROID_SERIAL = $DEVICE_A
  .\gradlew.bat :app:connectedDebugAndroidTest 2>&1 | Tee-Object "$EVID\step8_connectedTest.txt"
  Remove-Item Env:\ANDROID_SERIAL
  ```
- **預期**：`BUILD SUCCESSFUL`、儀器測試全綠。
- **證據**：`step8_connectedTest.txt`（貼最後 ~20 行）；測試報告另在
  `app\build\reports\androidTests\connected\`。
- **Owner 回填**：☐PASS ☐FAIL；證據：`step8_connectedTest.txt`

### Step 9 — 相距 ≥20m 開雷達視圖（A10b）
- **目的**：A10b 相對位置雷達——方位/距離量級正確、SOS 點為 sos 色。
- **操作（人工）**：兩機戶外相距 **≥20m**（確保各自有 GPS fix）；各開「**最後可信位置**」→ 切「**雷達**」。
  （若顯示「需要本機位置才能顯示相對方位」→ 該機尚無 GPS fix，到空曠處等定位再切。）
- **預期**：對方點的**方位**與實際方向**目視大致一致**（北朝上）、**距離量級正確**（~20m 量級，不會是
  km）；若 step 3 的 SOS 仍在，**SOS 點為 sos（紅）色**。
- **證據**：
  ```powershell
  Shot $DEVICE_A "step9_A_radar"; Shot $DEVICE_B "step9_B_radar"
  ```
- **Owner 回填**：方位大致對？☐ 距離量級對？☐ SOS 紅點？☐(或N/A)；☐PASS ☐FAIL；證據：`step9_*`

---

## 6. 結果彙總表（Owner 回填）

| # | 步驟 | 預期 | 結果 | 證據檔 |
|---|---|---|---|---|
| 1 | 建場域 + 掃碼加入 | 同 fieldId 前 8 碼 | ☐P ☐F | |
| 2 | mesh + 互發 PRESENCE | 對方位置卡出現 anon8+時間 | ☐P ☐F | |
| 3 | SOS(RED) 取消後真發 | B 告警 ≤10s | ☐P ☐F | |
| 4 | 我安全了 | B 標解除 | ☐P ☐F | |
| 5 | HAZARD(typed) | A 危害列表出現 | ☐**BLOCKED**(無發送 UI) ☐P | |
| 6 | 殺 B 重啟 | 不重複 + Outbox 補送 | ☐P ☐F | |
| 7 | 場域隔離 | A 收不到 + mismatch trace | ☐P ☐F | |
| 8 | connectedDebugAndroidTest | 全綠 | ☐P ☐F | |
| 9 | 雷達 ≥20m | 方位/量級對、SOS 紅點 | ☐P ☐F | |

> **A11-D2 PASS 條件**：除 step 5（已知 BLOCKED，待補發送鈕的獨立小任務）外，其餘步驟全 PASS。
> Owner 在 **App repo `STATUS.md`** 記 `A11-D2: <日期> <PASS/部分>`。Stage A Exit 另見 §5.13。

---

## 7. 排錯（常見卡點）

**`adb devices` 看不到手機 / unauthorized**
```powershell
adb kill-server; adb start-server; adb devices -l
```
- 仍 `unauthorized`：手機重新插拔，注意彈窗「允許 USB 偵錯」勾「一律允許」。
- 仍空白：換 USB 線/孔（要資料線非充電線）；確認手機「USB 用途」選「檔案傳輸/MTP」而非僅充電；
  必要時開 Android Studio → Device Manager 看是否辨識。

**權限沒授權（BLE/位置/Nearby）**
```powershell
# 查目前授權
adb -s $DEVICE_A shell dumpsys package network.ignirelay.field | Select-String "permission"
# 直接授（省去手點；Android 12+ 需要 BLUETOOTH_SCAN/CONNECT/ADVERTISE）
adb -s $DEVICE_A shell pm grant network.ignirelay.field android.permission.ACCESS_FINE_LOCATION
adb -s $DEVICE_A shell pm grant network.ignirelay.field android.permission.BLUETOOTH_SCAN
adb -s $DEVICE_A shell pm grant network.ignirelay.field android.permission.BLUETOOTH_CONNECT
adb -s $DEVICE_A shell pm grant network.ignirelay.field android.permission.BLUETOOTH_ADVERTISE
```
（`POST_NOTIFICATIONS` 也可同法授；位置「一律允許」背景定位仍建議手機上手動確認。）

**BLE 不通（兩機互看不到 / PRESENCE 不到）**
- 兩機**藍牙都開**、距離 1–3m 起測。
- 對 app 關電池最佳化（前景服務被殺會斷 mesh）。
- 兩機都按過「啟動」mesh，狀態顯示已啟動。
- 看 logcat 有無 scan/advertise 失敗：`Select-String -Path "$EVID\logcat_*.txt" -Pattern "scan|advert|BLE|gatt"`。

**QR 掃不到**
- B 的相機權限已給；光線足、QR 不反光；A 的 QR sheet 是深字白底（可掃）。
- 退路：A 場域頁（debug build）可顯示原始 join code 文字，B 用「輸入代碼」手動貼上 IGNI1 字串。

**`connectedDebugAndroidTest` ambiguous / 找不到裝置**
- 多台連著會 ambiguous：用 `$env:ANDROID_SERIAL = $DEVICE_A` 指定單機，或只留一台。
- 必須用 `:app:` 前綴（`.\gradlew.bat :app:connectedDebugAndroidTest`）——全模組版本因 flutter_secure_storage
  androidTest minSdk 合併問題會失敗（既知，見 STATUS）。

**雷達顯示「需要本機位置」**
- 該機尚無 GPS fix：到戶外/近窗等定位；確認位置權限與定位服務開啟。這是 A10b 正常退化行為，非 bug。

---

## 8. USER-GATE 聲明（再強調）

- 本檔（D1）由 AGENT 產出。**晚上的實測、截圖、logcat、結果判定（D2）必須由 Owner 親自於雙機完成**。
- AI 可代跑 §2–§4 的 ADB/gradle 與證據蒐集指令，但 QR 掃碼、按鈕、SOS 長按、手機移動 20m 等**人工
  操作只能 Owner 做**；且 **AI 不得代填結果、不得宣稱通過**。
- A11-D2 全項 PASS（step 5 除外，另案）前，**不得宣告 Stage A Exit**，亦**不應**進入 A12 之前未經
  Owner 確認的收尾宣稱。
