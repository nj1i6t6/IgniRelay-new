# A11 — 雙機實機驗收 Runbook v1.5.1（USER-GATE）

> **狀態：READY-FOR-OWNER-TEST（A11-D2-prep）** — 本檔已對齊 UI-F/UI-G 後的 App 流程，可供今晚實跑。
>   **尚未實測；A11 未通過、未 DONE。** PASS/FAIL 僅能由 Owner 在實機逐步判讀回填。
>
> **任務**：MASTER_EXECUTION_PLAN v1.5.1 §5 A11。
> **前置**：UI-F（正式 AppShell + 五分頁 + motion-aware 定位節流）與 UI-G（先看功能 / 引導預覽）皆 DONE。
> **D1**：本檔 = AGENT 產出的可執行驗收腳本（READY）。
> **D2（USER-GATE，今晚）**：Owner 兩台 Android USB 偵錯接上後，**由 AI 在電腦端直接代跑 ADB / Gradle /
>   logcat / 截圖**，Owner 在手機端做實體操作（掃碼 / 選角色 / 按 SOS·SAFE·HAZARD / 移動手機 / 目視雷達方位），
>   逐步實測後回填全項。
>
> **USER-GATE 紅線**：AI 可代跑 ADB / Gradle / 截圖 / logcat 並彙整證據，但**不可代填 PASS/FAIL、不可宣稱
>   雙機通過、不可宣告 Stage A Exit**。下方每步的「結果」欄只能由 Owner 親自回填。

---

## 0. 角色分工

| 類別 | 內容 | 誰做 |
|---|---|---|
| 自動 / 半自動 | `adb devices`、build/install、logcat、截圖、`force-stop`、`dumpsys`、`:app:connectedDebugAndroidTest` | AI 代跑 |
| 人工操作 | QR 掃碼、選角色密鑰、按 SOS/SAFE/HAZARD、移動手機、目視五分頁 / 雷達方位、判讀 PASS/FAIL | Owner |

下方 **每一步**（Step 1–13）開頭都有一行 `> 分工：`，逐步點名「AI 代跑」指令、「Owner 手動」操作、以及該步要收的
「證據」（截圖 / logcat / dumpsys）。AI 代跑只負責執行指令與收證據，**結果欄一律由 Owner 回填**。

---

## 0.1 UI-F0 preflight 對本驗收的邊界（v1.5.1）

UI-F0（見 `APP_UI_IA_REWORK_PLAN.md` §4.0.1）已釘定 Stage A 邊界，本 runbook 對應如下：

- **HAZARD 角色**：step 9 由手機 B（participant）發 HAZARD 即為合格——Stage A 的正式 HAZARD 入口
  **participant 與 owner 皆可發**，無角色 gating。不需要也不應要求只有 owner 能發 HAZARD。
- **不驗 field lifecycle**：Stage A 只有 active/current field；本 runbook **不驗**「進行中 / 結束 /
  封存」生命週期（該模型延後）。step 11 的「離開 / 重新加入 field」只測 field-scope 隔離，非 lifecycle。
- **僅 Android 雙機**：iOS 的 motion-aware 來源已明確延後（R3/iOS source-parity），本驗收為
  Android-only；無 iOS 驗收項。
- **不驗 staff offline QR**：staff 會員資格延後到 Stage E cloud staff-token；codec 已強制 staff token
  需伴隨 https cloud URL，offline staff QR 不可能。step 3 只驗 owner/participant，看到 staff path
  必須標 deferred/disabled（已寫入 step 3 預期）。
- **motion 權限查核**：step 6 的 `ACTIVITY_RECOGNITION` dumpsys 查核必須為空（UI-F5 走窄版
  SensorManager / 注入式 source，不申請該權限、不加 `sensors_plus`）。

---

## 1. 測前檢查

- [ ] 兩台 Android 手機，USB 偵錯已開，`adb devices -l` 顯示 `device`。
- [ ] 藍牙、定位服務已開。
- [ ] App 權限可授：位置、Nearby/Bluetooth、通知、相機。
- [ ] 兩台手機系統時間大致同步。
- [ ] 室外或近窗可取得 GPS fix。
- [ ] 本次驗收使用 debug build（需要 diagnostics / kDebugMode 驗收入口）。

命名：手機 **A** = 建立場域 / owner；手機 **B** = 加入者，Stage A 驗 participant。`staff` join 延後到
Stage E cloud staff-token 或另開 QR 契約任務。

---

## 2. 電腦端準備（PowerShell）

```powershell
cd C:\Users\radio\Downloads\IDE\IgniRelay\ignirelay_app

flutter --version
adb version
adb devices -l

$DEVICE_A = "<手機A serial>"
$DEVICE_B = "<手機B serial>"

adb -s $DEVICE_A shell getprop ro.product.model
adb -s $DEVICE_B shell getprop ro.product.model
```

建置與安裝：

```powershell
cd C:\Users\radio\Downloads\IDE\IgniRelay\ignirelay_app
flutter build apk --debug
$APK = "build\app\outputs\flutter-apk\app-debug.apk"
adb -s $DEVICE_A install -r $APK
adb -s $DEVICE_B install -r $APK
adb -s $DEVICE_A shell pm list packages network.ignirelay.field
adb -s $DEVICE_B shell pm list packages network.ignirelay.field
```

清資料（fresh first-run 驗收才做；會清掉已加入場域）：

```powershell
adb -s $DEVICE_A shell pm clear network.ignirelay.field
adb -s $DEVICE_B shell pm clear network.ignirelay.field
```

啟動：

```powershell
adb -s $DEVICE_A shell monkey -p network.ignirelay.field -c android.intent.category.LAUNCHER 1
adb -s $DEVICE_B shell monkey -p network.ignirelay.field -c android.intent.category.LAUNCHER 1
```

---

## 3. 證據 helper

```powershell
cd C:\Users\radio\Downloads\IDE\IgniRelay
$STAMP = Get-Date -Format "yyyyMMdd-HHmm"
$EVID  = "tmp\a11-evidence\$STAMP"
New-Item -ItemType Directory -Force $EVID | Out-Null
"evidence dir = $EVID"

function Shot([string]$serial, [string]$name) {
  $remote = "/sdcard/a11_$name.png"
  adb -s $serial shell screencap -p $remote
  adb -s $serial pull $remote "$EVID\$name.png"
  adb -s $serial shell rm $remote
  "saved $EVID\$name.png"
}

function LogStart([string]$serial, [string]$tag) {
  adb -s $serial logcat -c
  $f = "$EVID\logcat_$tag.txt"
  $j = Start-Job -ScriptBlock {
    param($s,$out) adb -s $s logcat -v time flutter:V *:S | Out-File -Encoding utf8 $out
  } -ArgumentList $serial,$f
  Set-Variable -Name "JOB_$tag" -Value $j -Scope Global
  "logging $serial -> $f (job $($j.Id))"
}

function LogStop([string]$tag) {
  $j = Get-Variable -Name "JOB_$tag" -ValueOnly
  Stop-Job $j; Receive-Job $j | Out-Null; Remove-Job $j
  "stopped log $tag"
}
```

---

## 4. 逐步驗收

每步 Owner 回填：`PASS / FAIL + 觀察 + 證據檔名`。

### Step 1 — 首次啟動 / 權限 / no-field entry

> **分工**：AI 代跑＝§2 的 clear/install/launch、本步 `Shot`。Owner 手動＝授權位置/Nearby·藍牙/通知/相機、
>   目視三入口、確認未進 DebugShell。證據＝`step1_A_entry.png`、`step1_B_entry.png`。

操作：
1. A/B fresh install 後首次啟動。
2. 依 App 引導授權位置、Nearby/Bluetooth、通知、相機。
3. 停在 no-field entry。

預期：
- 顯示 `加入場域`、`建立場域`、`先看功能`。
- 相機拒絕時仍可看到「輸入密鑰」路徑。
- 不進 `DebugShell`。

證據：

```powershell
Shot $DEVICE_A "step1_A_entry"
Shot $DEVICE_B "step1_B_entry"
```

### Step 2 — 先看功能（UI-G 引導預覽）

> **分工**：AI 代跑＝本步 `Shot`（建議翻頁時各截一張）、可選 logcat 佐證無 mesh/權限活動。
>   Owner 手動＝點 `先看功能`、用「下一步 / 上一步」**前後翻完 5 頁**、按返回回 no-field、目視「示範資料」badge。
>   證據＝`step2_preview.png`（可多張 `step2_preview_p1..p5`）。

操作：
1. 任一手機點 `先看功能`，進入引導預覽。
2. 用「下一步 / 上一步」**雙向翻頁**走完 5 頁概念：加入 → 安全（被看見 + SOS illustrated）→
   位置（最後可信位置 + 雷達示範）→ 事件（危害 / 廣播 / 打卡）→ 協助 + 離線降級。
3. 按返回（header）回到 no-field entry；或從預覽 CTA 點 `加入場域` / `建立場域`。

預期：
- 全程使用 demo/fixture 資料，每頁有顯眼「示範資料」badge。
- **可進可退**：下一步 / 上一步雙向翻頁正常，返回回到 no-field、不殘留。
- **不啟動 mesh、不送任何事件、不建立真 field、不寫入會員資格**。
- **不需要任何權限**：即使位置 / 藍牙 / 相機全部拒絕，先看功能仍可正常瀏覽（預覽本身不請求權限）。
- 位置頁文案為「最後可信位置 / 最後足跡」，**永不**「目前位置」。
- 結束時可導向 `加入場域` / `建立場域`（→ 進入正式場域流程）。

證據：

```powershell
Shot $DEVICE_A "step2_preview"
```

（選用）AI 可在本步 `LogStart`/`LogStop` 抓 logcat 佐證預覽期間無 mesh 啟動 / 無權限請求 trace。

### Step 3 — 建立場域 + participant 加入

> **分工**：AI 代跑＝本步 `Shot`、`LogStart`/`LogStop` 抓 join 期間 logcat 並 grep raw secret 是否外洩。
>   Owner 手動＝A 建立場域、出示 participant QR / 密鑰、B 掃碼或輸入密鑰加入、目視雙方 fieldId 前 8 碼與
>   owner/participant 角色 chip。證據＝`step3_A_owner_field.png`、`step3_B_participant.png`、join logcat。

操作：
1. A 點 `建立場域`，成為 owner。
2. A 出示 participant QR/密鑰，B 加入，確認 B 角色為 participant。
3. 確認沒有要求 A 出示第二組 staff field secret；staff path 若出現，必須標示 deferred/disabled。

預期：
- A/B 顯示同一 fieldId 前 8 碼。
- A 顯示 owner；B 顯示 participant。
- `staff` 不可用第二組 `field_join_secret` 假裝完成，避免產生不同 `field_id`。
- raw join secret 不出現在 logcat 或畫面不必要處。

證據：

```powershell
LogStart $DEVICE_A "step3_A_join"; LogStart $DEVICE_B "step3_B_join"
Shot $DEVICE_A "step3_A_owner_field"
Shot $DEVICE_B "step3_B_participant"
LogStop "step3_A_join"; LogStop "step3_B_join"
```

raw join secret 不外洩查核（Owner 從 A 畫面讀出該場域密鑰填入 `$SECRET`；AI 代跑 grep，預期**無命中**）：

```powershell
$SECRET = "<Owner 從畫面讀出的 join secret>"
Select-String -Path "$EVID\logcat_step3_A_join.txt","$EVID\logcat_step3_B_join.txt" -SimpleMatch -Pattern $SECRET
```

### Step 4 — 正式 AppShell / 五分頁 / 全域 SOS

> **分工**：AI 代跑＝本步各 `Shot`。Owner 手動＝A/B 逐一切換五分頁（安全/位置/事件/協助/我的）、目視 label 精確、
>   確認無「地圖」tab、從至少兩個非安全分頁確認 global SOS 可達。證據＝`step4_A_tabs.png`、`step4_B_global_sos.png`
>   （建議五分頁各一張 `step4_A_tab_*`）。

操作：
1. A/B 進入正式 AppShell。
2. 逐一切換五分頁。
3. 從至少兩個非安全分頁確認 global SOS action 可見。

預期：
- tab label 精確為 `安全`、`位置`、`事件`、`協助`、`我的`。
- 不存在 `地圖` tab。
- global SOS 不藏在單一頁深處。

證據：

```powershell
Shot $DEVICE_A "step4_A_tabs"
Shot $DEVICE_B "step4_B_global_sos"
```

### Step 5 — 啟動 mesh + 互發 PRESENCE

> **分工**：AI 代跑＝本步 `LogStart`/`LogStop`、各 `Shot`。Owner 手動＝A/B 啟動 mesh、等待或手動觸發 PRESENCE、
>   目視對方 anon8 + 時間出現在「位置」分頁、查看 diagnostics。證據＝`step5_A_position.png`、
>   `step5_B_position.png`、`logcat_step5_A.txt`、`logcat_step5_B.txt`。

操作：A/B 啟動 mesh，等待或手動觸發 PRESENCE。

預期：
- 對方出現在 `位置` 分頁的最後可信位置列表。
- 顯示 anon8 + 時間。
- diagnostics 顯示 last presence sent / pending queue / current best path。

證據：

```powershell
LogStart $DEVICE_A "step5_A"; LogStart $DEVICE_B "step5_B"
Shot $DEVICE_A "step5_A_position"
Shot $DEVICE_B "step5_B_position"
LogStop "step5_A"; LogStop "step5_B"
```

### Step 6 — motion-aware GPS / PRESENCE 節流

> **分工**：AI 代跑＝本步 `LogStart`/`LogStop`、各 `Shot`、`dumpsys ... ACTIVITY_RECOGNITION` 查核。
>   Owner 手動＝B 靜置 2 分鐘、拿起行走/晃動 30–45 秒、目視 diagnostics interval/reason、回填數值欄。
>   證據＝`step6_B_stationary.png`、`step6_B_moving.png`、`step6_A_after_motion.png`、`logcat_step6_motion.txt`、
>   dumpsys 輸出。

操作：
1. A/B 靜置 2 分鐘，查看 diagnostics。
2. 拿起 B 行走或晃動一段，持續 30–45 秒。
3. 回到 diagnostics 與 A 的位置列表。

預期：
- 靜置時 policy reason 顯示 stationary / stationary-reuse，current interval 約 180s（低電量時 300s）。
- 移動後 policy reason 變 moving，current interval 約 30s（低電量時 60s）。
- 移動後 ≤30s 有新的 PRESENCE 或 GPS fix age 更新。
- 未使用 step counter / Activity Recognition 權限；下方 `ACTIVITY_RECOGNITION` 查核預期無輸出。

證據：

```powershell
LogStart $DEVICE_B "step6_motion"
Shot $DEVICE_B "step6_B_stationary"
Shot $DEVICE_B "step6_B_moving"
Shot $DEVICE_A "step6_A_after_motion"
adb -s $DEVICE_A shell dumpsys package network.ignirelay.field | Select-String "ACTIVITY_RECOGNITION"
adb -s $DEVICE_B shell dumpsys package network.ignirelay.field | Select-String "ACTIVITY_RECOGNITION"
LogStop "step6_motion"
```

Owner 回填：stationary interval=`____`；moving interval=`____`；policy reason=`____`；
last GPS fix age=`____`；移動後更新秒數=`____`；ACTIVITY_RECOGNITION 查核輸出=`____`。

### Step 7 — SOS：取消一次後真發

> **分工**：AI 代跑＝本步 `LogStart`/`LogStop`、各 `Shot`。Owner 手動＝A 從非安全分頁觸發 global SOS、選 RED/受困、
>   倒數中取消一次、再次觸發讓倒數完成、目視 B 端告警、回填送達秒數。證據＝`step7_A_sos_sent.png`、
>   `step7_B_sos_alert.png`、`logcat_step7_B_sos.txt`。

操作：
1. A 從非安全分頁觸發 global SOS。
2. 選 RED/受困，倒數中取消一次。
3. 再次觸發，讓倒數完成。

預期：
- 取消不送出。
- 真發後 B 端 SOS 告警 ≤10s 出現。

證據：

```powershell
LogStart $DEVICE_B "step7_B_sos"
Shot $DEVICE_A "step7_A_sos_sent"
Shot $DEVICE_B "step7_B_sos_alert"
LogStop "step7_B_sos"
```

Owner 回填：送達秒數=`____`。

### Step 8 — 我安全了

> **分工**：AI 代跑＝本步 `Shot`。Owner 手動＝A 對同一 SOS 發 `我安全了`、目視 B 端該 SOS 標記解除/已安全。
>   證據＝`step8_B_safe.png`。

操作：A 對同一 SOS 發 `我安全了`。

預期：B 端該 SOS 標記解除/已安全。

證據：

```powershell
Shot $DEVICE_B "step8_B_safe"
```

### Step 9 — HAZARD typed

> **分工**：AI 代跑＝本步各 `Shot`。Owner 手動＝B 取得真實 fix 後從「事件」分頁危害入口發 typed HAZARD、目視 A 端
>   事件/危害列表出現該事件（type/severity 可辨識）；B 無 fix 時確認其拒送並提示。證據＝`step9_B_hazard_sent.png`、
>   `step9_A_hazard_received.png`。

操作：B 在事件/安全中的危害入口發 typed HAZARD。

> **零假座標（UI-F5b-polish）**：正式危害入口的座標只取本機**真實** GPS / last-known fix。
> 若 B 當下無定位，會**拒送**並顯示「目前沒有位置，請取得位置後再回報」（不送任何樣本/假/預設座標）。
> 室內無 fix 時：靠窗或到戶外取得 fix 後再發；若仍無法取得，**延後此座標型 HAZARD 查核**，不要標 FAIL。

預期：
- B 取得真實 fix 後送出；A 端事件/危害列表出現該事件，type/severity 可辨識。
- B 無定位時：不送，顯示需要位置提示（符合零假座標規則）。

證據：

```powershell
Shot $DEVICE_B "step9_B_hazard_sent"
Shot $DEVICE_A "step9_A_hazard_received"
```

### Step 10 — 重啟 / dedup / Outbox 補送

> **分工**：AI 代跑＝本步 `LogStart`/`LogStop`、`force-stop` + relaunch、各 `Shot`。Owner 手動＝重啟後 B 再啟動 mesh、
>   目視 A 端事件不重複、B outbox/pending 補送。證據＝`step10_A_nodup.png`、`step10_B_restarted.png`、
>   `logcat_step10_B_restart.txt`。

操作（AI 代跑 force-stop + relaunch）：

```powershell
LogStart $DEVICE_B "step10_B_restart"
adb -s $DEVICE_B shell am force-stop network.ignirelay.field
adb -s $DEVICE_B shell monkey -p network.ignirelay.field -c android.intent.category.LAUNCHER 1
```

重啟後 B 再啟動 mesh。

預期：A 端事件不重複；B outbox/pending 會補送。

證據：

```powershell
Shot $DEVICE_A "step10_A_nodup"
Shot $DEVICE_B "step10_B_restarted"
LogStop "step10_B_restart"
```

### Step 11 — 場域隔離 / field-scope mismatch

> **分工**：AI 代跑＝本步 `LogStart`/`LogStop`、`Shot`、`Select-String` 比對拒收 trace。Owner 手動＝B 離開 A 的 field、
>   建立或加入另一個 field、發 PRESENCE、目視 A 收不到跨場域事件。證據＝`step11_A_no_cross_field.png`、
>   `logcat_step11_A_scope.txt`（grep mismatch/field-scope/field-mac/noField）。

操作：B 離開 A 的 field，建立或加入另一個 field，發 PRESENCE。

預期：
- A 收不到 B 新 field 的事件。
- A logcat 有 field-scope mismatch / field-mac-invalid / noField 等拒收 trace。

證據：

```powershell
LogStart $DEVICE_A "step11_A_scope"
Shot $DEVICE_A "step11_A_no_cross_field"
LogStop "step11_A_scope"
Select-String -Path "$EVID\logcat_step11_A_scope.txt" -Pattern "mismatch|field.?scope|field.?mac|noField"
```

測後：B 重新加入 A field，準備雷達測試。

### Step 12 — connectedDebugAndroidTest

> **分工**：AI 代跑＝整段 gradle 指令（AI 在電腦端跑、Tee 存檔）。Owner 手動＝確認結尾 `BUILD SUCCESSFUL` 後回填。
>   證據＝`step12_connectedTest.txt`。

操作（AI 代跑）：

```powershell
cd C:\Users\radio\Downloads\IDE\IgniRelay\ignirelay_app\android
$env:ANDROID_SERIAL = $DEVICE_A
.\gradlew.bat :app:connectedDebugAndroidTest 2>&1 | Tee-Object "$EVID\step12_connectedTest.txt"
Remove-Item Env:\ANDROID_SERIAL
```

預期：`BUILD SUCCESSFUL`。

### Step 13 — 位置分頁雷達 ≥20m

> **分工**：AI 代跑＝本步各 `Shot`。Owner 手動＝A/B 戶外相距 ≥20m、雙方進「位置」分頁切到雷達、目視方位與實際方向
>   大致一致、距離量級合理、SOS 仍 active 時點為 sos 色。證據＝`step13_A_radar.png`、`step13_B_radar.png`。

操作：A/B 戶外相距 ≥20m，雙方進 `位置` 分頁切到雷達。

預期：
- 方位與實際方向大致一致。
- 距離量級合理。
- 若 SOS 仍 active，SOS 點為 sos 色。

證據：

```powershell
Shot $DEVICE_A "step13_A_radar"
Shot $DEVICE_B "step13_B_radar"
```

---

## 5. 結果彙總表

| # | 步驟 | 預期 | 結果 | 證據 |
|---|---|---|---|---|
| 1 | first-run/no-field | 權限 + 三入口，不進 DebugShell | ☐P ☐F | |
| 2 | 先看功能 | fixture preview、不送真事件 | ☐P ☐F | |
| 3 | owner/participant join | 同 fieldId；A=owner、B=participant；staff deferred | ☐P ☐F | |
| 4 | AppShell | 安全/位置/事件/協助/我的 + global SOS | ☐P ☐F | |
| 5 | mesh/PRESENCE | 對方最後可信位置出現 | ☐P ☐F | |
| 6 | motion-aware | 靜置省電、移動 ≤30s 更新、無 ACTIVITY_RECOGNITION | ☐P ☐F | |
| 7 | SOS | 取消一次；真發 ≤10s 到 B | ☐P ☐F | |
| 8 | 我安全了 | B 端解除 SOS | ☐P ☐F | |
| 9 | HAZARD | A 端危害事件出現 | ☐P ☐F | |
| 10 | restart/dedup | 不重複 + outbox 補送 | ☐P ☐F | |
| 11 | field-scope | 跨場域收不到 + trace | ☐P ☐F | |
| 12 | connected test | 全綠 | ☐P ☐F | |
| 13 | 位置雷達 | 方位/距離量級合理 | ☐P ☐F | |

表中「結果」欄**只能由 Owner 在實機回填**；AI 不得預填、不得代判。

**A11-D2 PASS 條件**：表中 1–13 全部由 Owner 回填 PASS。任何 FAIL 或未回填都不得宣告 A11 通過 / Stage A Exit。
本檔目前狀態為 **READY-FOR-OWNER-TEST**（A11-D2-prep）——腳本就緒、尚未實測。

---

## 6. 常見排錯

**adb unauthorized/offline**

```powershell
adb kill-server
adb start-server
adb devices -l
```

**權限直接授權（必要時）**

```powershell
adb -s $DEVICE_A shell pm grant network.ignirelay.field android.permission.ACCESS_FINE_LOCATION
adb -s $DEVICE_A shell pm grant network.ignirelay.field android.permission.BLUETOOTH_SCAN
adb -s $DEVICE_A shell pm grant network.ignirelay.field android.permission.BLUETOOTH_CONNECT
adb -s $DEVICE_A shell pm grant network.ignirelay.field android.permission.BLUETOOTH_ADVERTISE
adb -s $DEVICE_A shell pm grant network.ignirelay.field android.permission.POST_NOTIFICATIONS
adb -s $DEVICE_A shell pm grant network.ignirelay.field android.permission.CAMERA
```

**雷達顯示需要本機位置**

到戶外/近窗等待 GPS fix；若 diagnostics 顯示 stationary，拿起手機移動以觸發 moving policy。

**多裝置 connectedDebugAndroidTest ambiguous**

設定 `$env:ANDROID_SERIAL` 或只留一台裝置。

---

## 7. USER-GATE 聲明

本檔只讓驗收**可執行**，本身**不代表通過**。今晚由 AI 在電腦端代跑 ADB / Gradle / logcat / 截圖並彙整證據，
Owner 在手機端做實體操作並判讀；實機 PASS/FAIL 只能由 Owner 回填。AI **不得**代填結果、**不得**宣稱雙機通過、
**不得**宣告 Stage A Exit。

## 8. 修訂紀錄

- **A11-D2-prep（READY-FOR-OWNER-TEST）**：對齊 UI-F/UI-G 後 App 流程——首次入口三鈕（加入/建立/先看功能）、
  UI-G 引導預覽（可進可退、不啟動 mesh、不需權限）、五分頁 smoke、雙機核心（同場域加入 / PRESENCE / SOS / SAFE /
  HAZARD / 最後可信位置·雷達 / 重啟後狀態）。每步加 `分工` 行點名 AI 代跑 / Owner 手動 / 證據；step 3 加 raw join
  secret 不外洩 grep。**docs-only，未碰 app code / wire / DB / native。** 狀態：READY，尚未實測。
- v1.5.1：UI-F0 preflight 釘定 Stage A 邊界（§0.1）。
- UI-F5b-polish：step 9 零假座標註記。
