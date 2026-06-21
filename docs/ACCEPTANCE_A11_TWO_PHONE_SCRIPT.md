# A11 — 雙機實機驗收 Runbook v1.5.1（USER-GATE）

> **狀態：READY-FOR-OWNER-TEST（A11-runbook-prep）** — 本檔已對齊 UI-F/UI-G 後的 App 流程，並納入
>   今天 A11-debug-1~4 修正後的重測重點，可供今晚實跑。
>   **尚未實測；A11 未通過、未 DONE。** PASS/FAIL 僅能由 Owner 在實機逐步判讀回填。
>
> **今晚兩台手機務必先 clean install / clear app data**（見 §0.2）；前置可 dot-source
>   `ignirelay_app/scripts/a11_devicetest.ps1` 一鍵處理（卸載 3 個包 → 裝 APK → 查包名）。
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

## 0.2 今晚必做：clean install + A11-debug-1~4 重測重點（A11-runbook-prep）

### 強制 clean install / clear app data（兩台都要，測前一次）

今晚務必對 **A 與 B 兩台**做 clean install（卸載後重裝）或至少 clear app data，理由：

- **HAZARD 髒列（A11-debug-2-fix）**：修正前的舊 DB 可能對同一危害留下 v1 + v2 兩列（不同 `event_id`）。
  不清資料會在「事件」分頁看到重複，誤判 Step 10 dedup FAIL。
- **舊密文 allowBackup 清不掉（A11-debug-3）**：`allowBackup="false"` 只防「之後」被雲端/D2D 備份；裝置上
  **已經被還原**的舊密文 / 舊 app data 不會自動消失，必須 clean install / clear data 才會走乾淨重生路徑
  （否則仍可能 BAD_DECRYPT）。**切勿用 `adb install -r` 蓋在舊資料上**。
- **舊包殘留**：改名前曾安裝的 bare `network.ignirelay` 會與正式包並存、干擾驗收。

一鍵（helper，見 §2／§3）：

```powershell
. C:\Users\radio\Downloads\IDE\IgniRelay\ignirelay_app\scripts\a11_devicetest.ps1
Reset-A11Device -Serial $DEVICE_A   # 卸載 network.ignirelay(.field)(.field.test) → 裝 debug APK → 查包名
Reset-A11Device -Serial $DEVICE_B
```

測前 package 檢查應只見 `network.ignirelay.field`（＋可選 `.field.test`）；**不得**再見 bare
`network.ignirelay`。測後（Step 12）同樣不得出現 bare 包。

### A11-debug-1~4 重測重點（晚上特別確認）

| 修正 | 重測點（應為這樣，否則 FAIL） | 對應步驟 |
|---|---|---|
| debug-1-fix 送端帶座標 ＋ debug-4-fix 收端讀對欄位 | **收方 SOS 應顯示座標，不應再是「（無座標）」**（座標來自 `received_lat/received_lng`） | Step 7 / Step 8（B 位置分頁 SOS 卡） |
| debug-4-fix（LastSeen 訂 sosResolutions） | B 發「我安全了」後，A 位置頁該 author 的 SOS 標籤/紅點消失 | Step 8 |
| debug-2-fix（HAZARD 改 v2-only） | 重啟後 HAZARD **不重複兩列**。⚠️**發送者本機不再自列自己的 HAZARD**＝**刻意行為**（與 SOS 一致），B 看不到自己剛發的 HAZARD 不算 FAIL；驗收看 A（接收端）是否收到 | Step 9 / Step 10 |
| debug-4-fix（LastSeen mount hydrate） | A/B **重啟後**位置頁應**從 read-model 立即回填** PRESENCE/SOS（含座標），不必等下一筆 live PRESENCE | Step 10 |
| debug-3（secure_storage BAD_DECRYPT self-heal） | fresh install / 重啟**不卡死**在啟動；最差是身份/場域需重建，但 app 必須能起來、不白屏崩潰 | Step 1 / Step 10 |

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

建置：

```powershell
cd C:\Users\radio\Downloads\IDE\IgniRelay\ignirelay_app
flutter build apk --debug
```

**clean install（今晚強制，見 §0.2）**——卸載 3 個包 → 裝新 APK → 查包名。用 helper 一鍵：

```powershell
. C:\Users\radio\Downloads\IDE\IgniRelay\ignirelay_app\scripts\a11_devicetest.ps1
Reset-A11Device -Serial $DEVICE_A
Reset-A11Device -Serial $DEVICE_B
```

不用 helper 的等價手動指令（**不要用 `install -r` 蓋舊資料**——見 [[secure-storage-backup-decrypt]]）：

```powershell
$APK = "build\app\outputs\flutter-apk\app-debug.apk"
foreach ($d in @($DEVICE_A, $DEVICE_B)) {
  # 卸載 3 個 id（不存在會 Failure，忽略即可）＝真 clean slate：
  #   network.ignirelay        舊 bare 包（改名前；不得殘留）
  #   network.ignirelay.field      正式包
  #   network.ignirelay.field.test instrumentation 包
  adb -s $d uninstall network.ignirelay
  adb -s $d uninstall network.ignirelay.field
  adb -s $d uninstall network.ignirelay.field.test
  # 裝新 APK（fresh install，無舊資料 → 無被還原的舊密文、無舊 HAZARD/DB 髒列）：
  adb -s $d install $APK
  # 查包名：預期只有 network.ignirelay.field（＋可選 .field.test），不得有 bare network.ignirelay：
  adb -s $d shell pm list packages | Select-String "ignirelay"
}
```

> 若因故只想 clear data 而非重裝：`adb -s $d shell pm clear network.ignirelay.field`——但**仍須先確認
> 無 bare `network.ignirelay` 殘留**，且 clear 無法移除舊 bare 包，clean install 較保險。

啟動：

```powershell
adb -s $DEVICE_A shell monkey -p network.ignirelay.field -c android.intent.category.LAUNCHER 1
adb -s $DEVICE_B shell monkey -p network.ignirelay.field -c android.intent.category.LAUNCHER 1
```

---

## 3. 證據 helper

> **快捷**：`. ignirelay_app\scripts\a11_devicetest.ps1` 提供等價的前置 + 證據函式
> （`New-A11Evidence` / `Get-A11Shot -Serial -Name` / `Save-A11Logcat -Serial -Tag` /
> `Reset-A11Device` / `Get-A11Packages`），且**只做前置與證據擷取、絕不判 PASS/FAIL**。
> 下方為等價的 inline 版本（步驟 4 起用 `Shot` / `LogStart` / `LogStop`），不想 dot-source 時可直接貼用。

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
2. 依系統權限對話框授權位置、Nearby/Bluetooth、通知、相機。
3. 權限完成後**直接**停在 no-field entry。

預期：
- 流程為 **Android 權限 → no-field 三入口**。
- 顯示 `加入場域`、`建立場域`、`先看功能`。
- **不再**出現舊版「開始使用烽傳 / Start Using IgniRelay」引導頁，也**不再**在首次進入前自動跳出
  背景執行 / 電池最佳化（Background Execution）設定（A11-preflight-fix：移除舊 onboarding gate）。
- 相機拒絕時仍可看到「輸入密鑰」路徑。
- 不進 `DebugShell`。
- **啟動不卡死（A11-debug-3）**：fresh install 後 app 正常起到 no-field entry，**不**因 secure_storage
  `BAD_DECRYPT` 白屏 / 崩潰。logcat 出現 `secure-storage read failed (...); regenerating / minting fresh`
  屬自癒（重生身份），不算 FAIL；起不來才是 FAIL。

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
- **收方 SOS 帶座標（A11-debug-1-fix + debug-4-fix）**：A 發 SOS 時若有 GPS/last-known fix，B 端 SOS
  在「位置」分頁的卡片應顯示座標（lat/lng），**不應再是「（無座標）」**。座標來自 read-model 的
  `received_lat/received_lng`（debug-4-fix 修正了 EventStream 原本讀錯欄位）。A 當下完全無定位時顯示
  「（無座標）」屬合理（零假座標規則：寧可無座標也不假造）。

證據：

```powershell
LogStart $DEVICE_B "step7_B_sos"
Shot $DEVICE_A "step7_A_sos_sent"
Shot $DEVICE_B "step7_B_sos_alert"
LogStop "step7_B_sos"
```

Owner 回填：送達秒數=`____`。

### Step 8 — 我安全了

> **分工**：AI 代跑＝本步各 `Shot`。Owner 手動＝A 對同一 SOS 發 `我安全了`、目視 B 端該 SOS 標記解除/已安全、
>   並切到 B 的「位置」分頁確認該 author 的 SOS 標籤/點已消失。證據＝`step8_B_safe.png`、`step8_B_position_cleared.png`。

操作：
1. A 對同一 SOS 發 `我安全了`。
2. B 切到「位置」分頁（列表或雷達）觀察該 author 的 SOS 是否退場。

預期：
- B 端該 SOS 標記解除/已安全。
- **B 的「位置」分頁不再顯示該 author 的 SOS 標籤/紅點**（A11-fix：LastSeenScreen 訂閱
  `sosResolutions`，收到 SAFE 後以 author 公鑰 hex 移除該 SOS）。

證據：

```powershell
Shot $DEVICE_B "step8_B_safe"
Shot $DEVICE_B "step8_B_position_cleared"
```

### Step 9 — HAZARD typed

> **分工**：AI 代跑＝本步各 `Shot`。Owner 手動＝B 取得真實 fix 後從「事件」分頁危害入口發 typed HAZARD、目視 A 端
>   事件/危害列表出現該事件（type/severity 可辨識）；B 無 fix 時確認其拒送並提示。證據＝`step9_B_hazard_sent.png`、
>   `step9_A_hazard_received.png`。

操作：
1. **先讓 A 不在「事件」分頁**（停在安全/位置），再由 B 發出 typed HAZARD。
2. A 之後才切到「事件」分頁——驗證**分頁開啟前就收到**的 HAZARD 仍會顯示（backfill）。
3. 接著 B 在 A 仍停留「事件」分頁時再發一筆——驗證 live 即時追加。

> **零假座標（UI-F5b-polish）**：正式危害入口的座標只取本機**真實** GPS / last-known fix。
> 若 B 當下無定位，會**拒送**並顯示「目前沒有位置，請取得位置後再回報」（不送任何樣本/假/預設座標）。
> 室內無 fix 時：靠窗或到戶外取得 fix 後再發；若仍無法取得，**延後此座標型 HAZARD 查核**，不要標 FAIL。

預期：
- B 取得真實 fix 後送出；A 端事件/危害列表出現該事件，type/severity 可辨識。
- **分頁開啟前已收到**的 HAZARD，A 切到「事件」分頁後仍顯示（A11-fix：HazardCard mount 時讀
  `EventStream.recentHazards` 補齊已落地的 HAZARD，不再只靠不重播的 live broadcast stream）。
- 之後 B 再發的 HAZARD，A 停在「事件」分頁時也即時出現（live 追加，eventId 去重）。
- B 無定位時：不送，顯示需要位置提示（符合零假座標規則）。
- ⚠️**發送者本機不再自列自己的 HAZARD（A11-debug-2-fix，刻意）**：HAZARD 改 v2-only 後，**B（發送端）
  自己的「事件」分頁不會列出剛發的 HAZARD**（與 SOS 一致，自送不自投影）。**這不是 FAIL**——本步驗收看
  **A（接收端）**是否收到即可。

證據：

```powershell
Shot $DEVICE_B "step9_B_hazard_sent"
Shot $DEVICE_A "step9_A_hazard_received"
```

### Step 10 — 重啟 / dedup / Outbox 補送

> **分工**：AI 代跑＝本步 `LogStart`/`LogStop`、**A 與 B** `force-stop` + relaunch、各 `Shot`。Owner 手動＝
>   重啟後**先開「位置」分頁**確認 read-model 回填（不先重啟 mesh）、再啟動 mesh、目視 A 端事件不重複、
>   B outbox/pending 補送。證據＝`step10_A_hydrate.png`、`step10_B_hydrate.png`、`step10_A_nodup.png`、
>   `step10_B_restarted.png`、`logcat_step10_B_restart.txt`。

操作（AI 代跑 force-stop + relaunch；**A、B 兩台都重啟**）：

```powershell
LogStart $DEVICE_B "step10_B_restart"
adb -s $DEVICE_A shell am force-stop network.ignirelay.field
adb -s $DEVICE_B shell am force-stop network.ignirelay.field
adb -s $DEVICE_A shell monkey -p network.ignirelay.field -c android.intent.category.LAUNCHER 1
adb -s $DEVICE_B shell monkey -p network.ignirelay.field -c android.intent.category.LAUNCHER 1
```

操作順序（重要）：
1. 重啟後**先進「位置」分頁、暫不重啟 mesh / 不等新事件**，確認先前看到的對方 PRESENCE/SOS 仍在。
2. 再啟動 mesh，讓 outbox 補送、live 事件續流。

預期：
- **重啟後位置頁立即回填（A11-debug-4-fix mount hydrate）**：尚未收到任何新 live PRESENCE 前，「位置」分頁
  就應從 read-model 顯示先前的對方足跡/SOS（含座標）。空白到下一筆 live 才出現＝FAIL。
- **HAZARD 不重複（A11-debug-2-fix）**：A 端「事件」分頁同一 HAZARD **不出現兩列**（v2-only，已無 v1+v2 雙寫；
  前提是測前已 clean install，無舊髒列）。
- A 端事件整體不重複；B outbox/pending 會補送。
- **重啟不卡死（A11-debug-3）**：A/B 重啟皆正常起到殼，不因 secure_storage 卡死/白屏（logcat 若見
  `regenerating / minting fresh` 屬自癒，非 FAIL）。

證據：

```powershell
Shot $DEVICE_A "step10_A_hydrate"   # 重啟後、重啟 mesh 前的位置頁
Shot $DEVICE_B "step10_B_hydrate"
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

### Step 12 — connectedDebugAndroidTest + 包名驗證

> **分工**：AI 代跑＝整段 gradle 指令（AI 在電腦端跑、Tee 存檔）＋ gate 後的 `pm list packages` 包名查核。
>   Owner 手動＝確認結尾 `BUILD SUCCESSFUL`、確認包名查核結果後回填。
>   證據＝`step12_connectedTest.txt`、`step12_packages.txt`。

操作（AI 代跑）：

```powershell
cd C:\Users\radio\Downloads\IDE\IgniRelay\ignirelay_app\android
$env:ANDROID_SERIAL = $DEVICE_A
.\gradlew.bat :app:connectedDebugAndroidTest 2>&1 | Tee-Object "$EVID\step12_connectedTest.txt"
Remove-Item Env:\ANDROID_SERIAL
```

預期：`BUILD SUCCESSFUL`。

**包名驗證（A11-fix-prep）**：`connectedDebugAndroidTest` 安裝的是
- app-under-test（debug 變體）＝ `network.ignirelay.field`（與正式同 applicationId，**非** bare 包），
- instrumentation 測試 APK ＝ `network.ignirelay.field.test`（預設後綴，gate 後常駐／可卸）。

它**不會**產生 bare `network.ignirelay`——本專案 applicationId 已是 `network.ignirelay.field`，
無 `testApplicationId` / `applicationIdSuffix` 污染。gate 後查核（預期只見 `.field`，可含 `.field.test`，
**不得**出現 bare `network.ignirelay`；若有即為舊版殘留，依 §2 卸除）：

```powershell
adb -s $DEVICE_A shell pm list packages | Select-String "ignirelay" | Tee-Object "$EVID\step12_packages.txt"
# 清掉 gate 殘留的 instrumentation 包（可選，保持裝置乾淨）
adb -s $DEVICE_A uninstall network.ignirelay.field.test
```

Owner 回填：gate 後 `findstr ignirelay` 輸出＝`____`（應僅 `network.ignirelay.field`〔+ 可選 `.field.test`〕）。

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
| 7 | SOS | 取消一次；真發 ≤10s 到 B；**收方 SOS 帶座標（非「（無座標）」）** | ☐P ☐F | |
| 8 | 我安全了 | B 端解除 SOS（位置頁該 author 的 SOS 標籤消失） | ☐P ☐F | |
| 9 | HAZARD | A 端危害事件出現（含分頁開啟前已收到者也顯示）；發送端不自列屬刻意 | ☐P ☐F | |
| 10 | restart/dedup/hydrate | 不重複（v2-only）+ outbox 補送 + **重啟後位置頁從 read-model 回填** + 不卡死 | ☐P ☐F | |
| 11 | field-scope | 跨場域收不到 + trace | ☐P ☐F | |
| 12 | connected test + 包名 | gate 全綠；包名僅 `network.ignirelay.field`（無 bare `network.ignirelay`） | ☐P ☐F | |
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

- **A11-runbook-prep**（docs/script only，未碰 app code）：把今天 A11-debug-1~4 修正後的實機前置與重測重點寫入。
  (1) 新 §0.2「今晚必做：clean install + A11-debug-1~4 重測重點」——強制兩台 clean install / clear app data
  並說明理由（debug-2-fix 舊 HAZARD v1+v2 髒列、debug-3 allowBackup 清不掉已還原舊密文、舊 bare 包殘留），
  附 debug→重測點→步驟對照表。(2) §2 安裝流程改為**強制 clean install**（卸載 3 個 id `network.ignirelay`
  /`.field`/`.field.test` → `adb install` 新 APK → 查包名；**移除 `install -r` 蓋舊資料**）。(3) 新增前置/證據
  helper `ignirelay_app/scripts/a11_devicetest.ps1`（dot-source：`Reset-A11Device`/`Get-A11Shot`/`Save-A11Logcat`
  /`Get-A11Packages` 等；**只做前置與證據擷取、絕不判 PASS/FAIL**）。(4) 重測點寫入步驟：Step 1（secure_storage
  BAD_DECRYPT 不卡死）、Step 7（收方 SOS 帶座標、非「（無座標）」）、Step 9（HAZARD v2-only：發送端不自列自己的
  HAZARD 屬刻意非 FAIL）、Step 10（重啟先看位置頁 read-model 回填 + v2-only 不重複 + 不卡死）；彙總表 7/10 同步。
  **A11 仍未通過；今晚仍須 Owner 手動回填 PASS/FAIL。**
- **A11-fix-prep**：補齊實測暴露的兩個 read-model 缺口 + 釐清包名——(1) Step 8 加「B 位置分頁該 author 的
  SOS 標籤/紅點消失」（LastSeenScreen 訂閱 `sosResolutions`）；(2) Step 9 加「分頁開啟前已收到的 HAZARD 仍顯示」
  （HazardCard mount 時讀 `EventStream.recentHazards` 補齊 + live 追加）；(3) §2 加舊 bare 包 `network.ignirelay`
  卸除、Step 12 加 gate 後包名查核（應僅 `network.ignirelay.field`〔+ 可選 `.field.test`〕，無 bare 包；經查
  applicationId 已是 `.field`，gradle 不會產生 bare 包，殘留者為舊版安裝）。
- **A11-D2-prep（READY-FOR-OWNER-TEST）**：對齊 UI-F/UI-G 後 App 流程——首次入口三鈕（加入/建立/先看功能）、
  UI-G 引導預覽（可進可退、不啟動 mesh、不需權限）、五分頁 smoke、雙機核心（同場域加入 / PRESENCE / SOS / SAFE /
  HAZARD / 最後可信位置·雷達 / 重啟後狀態）。每步加 `分工` 行點名 AI 代跑 / Owner 手動 / 證據；step 3 加 raw join
  secret 不外洩 grep。**docs-only，未碰 app code / wire / DB / native。** 狀態：READY，尚未實測。
- v1.5.1：UI-F0 preflight 釘定 Stage A 邊界（§0.1）。
- UI-F5b-polish：step 9 零假座標註記。
