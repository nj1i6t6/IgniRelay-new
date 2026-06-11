<div align="center">

# 烽傳 IgniRelay

**離線優先的場域安全網 · Offline-First Field Safety Network**

[English](README.md) · **繁體中文**

當基地台倒了、網路斷了，每支手機、每個低成本節點，就是一座烽火台——
讓場域裡的每個人**被看見、能求救、留下最後足跡**。

</div>

---

> **English TL;DR** — IgniRelay is an offline-first field safety network: phones and low-cost
> LoRa relay nodes form a mesh that carries signed presence beacons, SOS calls and last-known
> footprints — with or without the internet. One app, one QR join flow, one cryptographically
> signed event envelope across BLE / LoRa / HTTPS; a cloud SaaS mode for connected venues and a
> fully local console for off-grid sites; AI-assisted emergency dialog via the partner project
> **E-CARE**. → **[English README](README.md)**

> 📖 **完整介紹請讀白皮書：[`docs/WHITEPAPER.md`](docs/WHITEPAPER.md)**（問題、架構、
> E-CARE 智慧應急層、安全模型、商業模式、路線圖——比賽／合作文件皆以它為基礎）。
> 工程上的單一事實來源是 [`docs/MASTER_EXECUTION_PLAN.md`](docs/MASTER_EXECUTION_PLAN.md)。

## 這是什麼

**「場域」**＝任何把一群人聚在一個範圍裡的場合：營隊、賽事、工地、校外活動、登山路線、災區安置點。烽傳給每個場域一張安全網：

- 📡 **被看見** —— 成員手機定期發出匿名存在信標，管理者即時掌握「誰還在、最後出現在哪」。
- 🆘 **能求救** —— 一鍵 SOS，自帶位置與安全狀態（受困／需醫療／已安全…），最高優先在所有可用通道上擴散；**任何設定都遮蔽不了 SOS**。
- 👣 **留下最後足跡** —— 走過的節點、遇過的手機，都替每個人留下加密簽章的足跡；搜救從「平方公里」縮小到「最後一個節點之後」。
- 🤖 **求救之後有人接住** —— 與校內 AI 專案 **E-CARE** 合作：SOS 後可進入 AI 對話（安撫、風險評估、急救引導）；斷網時退為本地急救圖卡。

## 兩種形態，一套系統

| | 純軟體形態 | 軟硬整合形態 |
|---|---|---|
| 場域 | 營區／賽事／工地（有網路） | 步道／礦場／災區（無網路） |
| 傳輸 | 手機 → HTTPS → 雲端 | 手機 → BLE → LoRa 節點 → 閘道 |
| 管理面 | 雲端後台（任何地方的瀏覽器） | 現場本地後台（零外網依賴） |

同一個 App、同一個 QR、同一種事件信封、同一套後台。硬體是場域的「離線增強包」，不是門檻。

## 30 秒看懂架構

```
[手機 App] --BLE（簽章信封）--> [LoRa 節點 ×N] --LoRa--> [閘道] --> 本地 Web 後台
     |  ^                                                   |
     |  └─ 手機↔手機 mesh / data mule（相遇即同步）            └─（有回程網路時）
     v                                                            ↓
[手機 App] ----------------HTTPS（同一份信封位元組）--------> [雲端場域服務] ←→ [E-CARE AI]
                                                                  ↓
                                                       場域主瀏覽器（雲端後台）
```

核心設計：**一種信封走天下**。每個事件是一個 141-byte 的 canonical 信封（Ed25519 作者簽章＋場域 HMAC），BLE／LoRa／HTTPS 載的是**同一份位元組**，每一跳都重新驗證——不信任何中繼，「外層有 TLS」也不能免驗。

## 與 E-CARE 的合作

> **烽傳是神經系統，E-CARE 是大腦。**

[E-CARE](https://github.com/rungyu0721/Ecare) 是校內合作團隊開發的 AI 緊急應答系統：自行微調的本地 LLM（Qwen2.5 基底，本機推論不出機房）、心理急救（PFA）對話策略、語音情緒辨識、規則底線＋LLM 的雙層風險引擎、本地語音合成、資料化急救知識庫。烽傳的 SOS 案件自動通報進 E-CARE 儀表板，求救者可與其 AI 對話；整合**零改動** E-CARE 程式碼、SOS 本體對其零依賴。詳見白皮書 §4（該章全部 AI 成果歸屬 E-CARE 團隊）。

## 專案狀態

| 範圍 | 狀態 |
|---|---|
| 通訊契約 v3（信封＋三端一致性語料 217 樣本＋13 常數 parity） | ✅ 凍結 |
| App 測試基線（469 tests）＋四層架構 lint | ✅ |
| 設計語言＋Web 後台範本（零 CDN／零外部資源） | ✅ 凍結 |
| App 核心接線（存在信標→SOS→危險回報→場域 QR→定位呈現） | 🔧 進行中 |
| 節點韌體＋閘道（先模擬器全綠，過採購關卡才買硬體） | 📋 規格凍結 |
| 現場 Web 後台／雲端場域服務／自訂地圖／E-CARE 串接 | 📋 規格凍結 |
| 實體硬體（nRF54L15＋SX1262，AS923） | 📋 排程（與雲端階段並行） |

執行順序：**A App → B 模擬器 → C 現場後台 → E 雲端＋E-CARE → D 硬體**（D 與 E 並行）。

## Monorepo 與兄弟 repo

| Repo | 角色 |
|---|---|
| 本 repo（`ignirelay_app/`） | Flutter App＋**所有 wire／金鑰契約的唯一擁有者** |
| `ignirelay-field-node` | Zephyr 韌體（nRF54L15＋SX1262） |
| `ignirelay-gateway` | LoRa 彙整＋Web 後台（Python）；同 codebase 兼雲端部署形態 |
| `ignirelay-lab` | 多節點模擬編排與混沌測試 |

```text
.
├── README.md / README.zh-Hant.md   # 首頁（本文件）
├── CLAUDE.md                        # 架構層規則（治理入口）
├── STATUS.md                        # 施工狀態紀錄（append-only）
├── docs/
│   ├── WHITEPAPER.md                # 對外白皮書 ★
│   ├── MASTER_EXECUTION_PLAN.md     # 總施工計畫（工程單一事實來源）
│   ├── DESIGN_LANGUAGE.md           # 設計語言（凍結）
│   └── specs/                       # 凍結 wire 規格
└── ignirelay_app/                   # Flutter App（lib/app · lib/ui · lib/platform 分層）
```

## 快速開始（App）

```bash
cd ignirelay_app
flutter pub get
flutter run        # 需實體裝置（BLE 是核心功能，模擬器無法驗證 mesh）
```

品質檢查：

```bash
flutter test --exclude-tags golden          # 測試基線
dart run tool/check_layers.dart --strict    # 架構 import 邊界
flutter analyze
```

## 工程原則

1. **離線優先**——每個功能先問「斷網時它是什麼」。
2. **零外部資源**——後台無 CDN、無外部字體圖磚；災區裡自成一格。
3. **契約凍結**——wire 規格逐版凍結，跨端由同一份生成語料鎖死，杜絕「兩端各自實作」的漂移。
4. **誠實定位**——永遠是「最後可信位置」＋年齡降級，不假稱即時追蹤。
5. **降級階梯**——網路→節點→手機 mesh→data mule，每層失效都有下一層接住。

## 安全與回報

本專案處理來自未知裝置的不可信輸入，含簽章與金鑰邏輯。發現安全問題請**私下回報**給維護者，勿開公開 issue。

## 授權與第三方資料

- 程式碼授權：〔待 Owner 確認——fork 基線標示為 AGPL-3.0，正式 LICENSE 檔將於對外發布前補齊〕
- `ignirelay_app/assets/` 內之離線圖資衍生自 **OpenStreetMap**（ODbL，須保留「© OpenStreetMap contributors」標示）與其他原始來源之授權條款；再散布時請自行確認權利。

## 致謝

- **E-CARE 團隊**（[github.com/rungyu0721/Ecare](https://github.com/rungyu0721/Ecare)）——智慧應急層的合作夥伴；白皮書 §4.2 所列 AI 能力均為其成果。
- 指導教授〔待填〕。
