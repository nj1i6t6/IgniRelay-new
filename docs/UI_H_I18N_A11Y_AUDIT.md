# IgniRelay UI-H0 Audit — Formal UI i18n / Text-Scale / Legacy Cleanup

> Version: v1.0, 2026-06-20. Produced by UI-H0 (docs-only audit).
> Source of truth for UI-H1 / UI-H2 / UI-H3 / UI-H4 construction.
> Base commit audited: `0aa5347` (working tree clean except `docs/UI_H_I18N_A11Y_PLAN.md`,
> `docs/UI_H_I18N_A11Y_AUDIT.md`).
> This audit changed **no** app code, **no** ARB, ran **no** gen-l10n, deleted **no** file.

---

## 0. Method — commands actually run

All scans were read-only, run from `ignirelay_app/` unless noted:

```bash
# l10n accessor usage across the whole UI / lib tree
rg -n "context\.l10n|S\.of|Localizations\.localeOf" lib/ui
rg -l "context\.l10n|S\.of\(|\bS\b\.delegate|import.*app_localizations" lib

# CJK per formal file — raw vs string-literal (excluding // comment lines)
rg -c '\p{Han}' <formal files>
rg -n "['\"][^'\"]*\p{Han}" <file> | rg -v "^\s*[0-9]+:\s*//"   # visible-string CJK

# legacy / debug references
rg -n "OnboardingScreen|BatteryOptimizationGuide|onboarding_done|onboarding_screen|battery_optimization_guide" lib test
rg -n "DebugShell|DesignShowcaseScreen|design_showcase" lib

# ARB inventory and group prefixes
rg -n '^\s*"[a-zA-Z]' lib/l10n/app_zh.arb | rg -v '^\s*[0-9]+:\s*"@' | wc -l
rg -o '^\s*"([a-z][a-zA-Z0-9]*)' -r '$1' lib/l10n/app_zh.arb | sed -E 's/[A-Z].*//' | sort | uniq -c | sort -rn

# exact getters consumed by the 5 S-referencing files
rg -o "l10n\.([a-zA-Z0-9]+)" -r '$1' lib/main.dart | sort -u
rg -o "\bl\.([a-zA-Z0-9]+)" -r '$1' lib/app/controllers/tier_manager.dart | sort -u

# large-text layout-risk heuristic (Row/Expanded/fixed height/maxLines/fontSize per file)
```

PowerShell note: the `\p{Han}` class works under the bundled ripgrep (Git Bash), so no
fallback CJK method was needed. UI-H2/H3 gates in §7 of the plan use PowerShell `rg` directly.

---

## 1. Headline findings

1. **The formal UI uses zero l10n.** Across all of `lib/ui`, only **two** files call
   `context.l10n` — and both are *legacy* (`onboarding_screen.dart`,
   `battery_optimization_guide.dart`). Every UI-F / UI-G formal surface is hard-coded
   Traditional Chinese. → UI-H2 is **greenfield**: it adds brand-new ARB keys with no
   collision against the existing (legacy) key set.
2. **Only 5 non-generated files reference `S` at all:** `main.dart`,
   `app/controllers/tier_manager.dart`, `ui/secondary/onboarding_screen.dart`,
   `ui/secondary/battery_optimization_guide.dart`, and the `l10n/l10n_ext.dart` extension.
3. **The legacy product screens are already deleted.** There is no map / chat / supply /
   medical / station / match / handoff / profile / survival screen left in `lib/ui`. Their
   ARB keys (the bulk of the file) therefore have **zero compiled consumers**.
4. **The ARB is ~99% dead weight.** `app_zh.arb` carries ~1198 key-shaped lines; the dominant
   groups are `supply` 392, `map` 139, `station` 78, `medical` 61, `chat` 55, `profile` 43,
   `match` 34, `handoff` 29 … The complete set of **live** message keys is just `main*` (×6,
   formal startup) + `tierLabel*` (×4). → UI-H4 removes almost the entire current ARB.
5. **Two formal startup prompts are already localized.** The Bluetooth-enable dialog and the
   permission snackbar in `main.dart` already use `main*` keys — they are *not* hard-coded and
   do not need UI-H2 work (only key-name hygiene).
6. **No blocker for UI-H1.** The reuse APIs the plan names all exist and are correctly wired.

---

## 2. Formal UI files — classification + hard-string counts

`visible-string CJK` = lines with CJK inside a quoted literal, excluding `//` comment lines
(the proxy for "strings a user sees"). `raw CJK` includes doc-comments.

| File | raw CJK | visible-string CJK | Class | UI-H stage | Notes |
|---|---:|---:|---|---|---|
| `lib/ui/screens/field/field_screen.dart` | 52 | **47** | `formal-now` | H2 (field) | Highest string load. Role chips 主辦/成員, join/create/share copy, QR re-share. Also `large-text-risk`. |
| `lib/ui/shell/tabs/safety_tab.dart` | 54 | **41** | `formal-now` | H2 (tabs) | Comms summary, GPS/motion diagnostics rows, footprint copy. Renders `communication_state` strings. `large-text-risk` (dense rows). |
| `lib/ui/screens/preview/preview_screen.dart` | 50 | **40** | `formal-now` | H2 (preview) | 5-page guided tour copy. Plan §4 = formal i18n target. |
| `lib/ui/screens/sos/sos_screen.dart` | 38 | **31** | `formal-now` | H2 (SOS) | RED/YELLOW, countdown, SAFE/cancel/status. Critical. `large-text-risk`. |
| `lib/ui/shell/hazard_card.dart` | 26 | **21** | `formal-now` | H2 (events) | Formal HAZARD send + no-fix prompt copy. `large-text-risk` (fixed heights + fontSize). |
| `lib/ui/screens/preview/preview_fixtures.dart` | 23 | **16** | `formal-now` | H2 (preview) | Demo labels are visible copy (plan §4 Q4 = yes). No decodable secrets — keep that property. |
| `lib/ui/screens/position/last_seen_screen.dart` | 20 | **16** | `formal-now` | H2 (position) | "最後可信位置" copy. §3.6 forbidden-wording rule applies. |
| `lib/ui/shell/checkpoint_card.dart` | 16 | **14** | `formal-now` | H2 (events) | `large-text-risk` (4× fontSize literals). |
| `lib/ui/shell/tabs/my_tab.dart` | 21 | **13** | `formal-now` + `settings-now` | H1 + H2 | **UI-H1 host**: language + text-size selectors land here. Role card / permission copy. 157 lines, 0 facade reads → safe to extend. |
| `lib/ui/shell/admin_broadcast_banner.dart` | 12 | **11** | `formal-now` | H2 (events) | `large-text-risk` (fixed height + fontSize). |
| `lib/ui/shell/app_shell.dart` | 55 | **10** | `formal-now` | H2 (shell, P1) | Most CJK is comments. Visible = 5 tab labels `安全/位置/事件/協助/我的` + no-field title/subtitle + 3 entry labels. `large-text-risk`: bottom-nav labels overflow at huge scale. |
| `lib/ui/screens/field/field_scan_screen.dart` | 10 | **6** | `formal-now` | H2 (field) | QR scan prompts / manual-key fallback. |
| `lib/ui/shell/tabs/events_tab.dart` | 15 | **5** | `formal-now` | H2 (tabs) | Section labels + empty-state copy. |
| `lib/ui/shell/tabs/communication_state.dart` | 27 | **5** | `formal-now` ⚠ | H2 (tabs) | **Pure non-widget file** (no `BuildContext`). Returns visible path copy: 尚未加入場域 / 離線… / 等待鄰近裝置… / 近距離網狀傳遞 / 雲端：已設定（尚未啟用）. Cannot call `context.l10n`. See §6 H2 design note. |
| `lib/ui/shell/tabs/assist_tab.dart` | 8 | **4** | `formal-now` | H2 (tabs) | Placeholder copy. |
| `lib/ui/screens/field/field_qr_sheet.dart` | 4 | **4** | `formal-now` | H2 (field) | Owner QR share sheet. |
| `lib/ui/screens/position/relative_radar.dart` | 4 | **1** | `formal-now` | H2 (position) | One caption: `北朝上 · 外環 … · 圓心為本機（最後可信位置投影）`. Distance rings are numeric. |
| `lib/ui/screens/sos/sos_hold_button.dart` | 5 | **0** | `formal-now` (no own strings) | — | Label is a constructor parameter; text comes from `sos_screen.dart`. Localized via its caller. |

**Total visible-string CJK across formal UI ≈ 285 lines / 18 files.**

---

## 3. Legacy / debug files

| File | Reachable? | Class | UI-H stage | Evidence |
|---|---|---|---|---|
| `lib/ui/secondary/onboarding_screen.dart` | **No live import.** Only self-refs + comments in `first_run_routing_test.dart`. | `legacy-delete` | H4 | A11-preflight-fix removed the startup gate (`main.dart` only mentions it in comments at 704/756/880). Consumes `onboarding*` (14 keys). |
| `lib/ui/secondary/battery_optimization_guide.dart` | **No live import.** Self-ref only. | `legacy-delete` | H4 | De-wired by A11-preflight-fix. Consumes `battery*` (~46 keys). Holds the 2 baseline `use_build_context_synchronously` analyzer infos. |
| `lib/ui/shell/debug_shell.dart` | **Live, debug-only.** `main.dart` registers `kDeveloperDiagnosticsRoute` under `kDebugMode || kProfileMode`; My-tab dev entry gates on `kDebugMode`. | `debug-only` | keep | DESIGN §4 names it the `Colors.*` exemption. May keep hard-coded debug copy. |
| `lib/ui/screens/design_showcase_screen.dart` | **Live, debug-only.** `main.dart:13` import + `/design-showcase` route under `kDebugMode || kProfileMode`. | `debug-only` | keep | Component reference page; not a product surface. |
| old map / chat / supply / medical / station / match / handoff / profile / survival screens | **Already deleted.** Not present anywhere under `lib/ui`. | n/a (gone) | — | Only their ARB keys remain (see §5). |

---

## 4. Large-text-risk list (for UI-H3)

Ranked by heuristic (fixed pixel heights and/or hard `fontSize:` literals combined with `Row`
density are the overflow seeds). Verified by per-file `Row` / `Expanded|Flexible` / `height:` /
`maxLines|TextOverflow` / `fontSize:` counts.

| Screen | Risk | Why |
|---|---|---|
| `app_shell.dart` bottom navigation | **High** | 5 fixed-slot labels (`安全/位置/事件/協助/我的`); `BottomNavigationBar` is a classic overflow point at huge scale. Must verify labels wrap/ellipsize gracefully or shrink slot text only, never hide SOS. |
| `hazard_card.dart` | **High** | 3 hard `fontSize:` + 3 fixed `height:` + 2 overflow guards already → fixed boxes will clip enlarged text. |
| `checkpoint_card.dart` | **High** | 4 hard `fontSize:` + 2 fixed `height:`. |
| `sos_screen.dart` / `sos_hold_button.dart` | **High (critical)** | SOS hold button has fixed dimensions; countdown + RED/YELLOW labels must stay readable. Plan forbids shrinking emergency labels below readable size. |
| `admin_broadcast_banner.dart` | **Medium** | Fixed height + hard `fontSize:`; banner truncation risk. |
| `field_screen.dart` | **Medium** | 8 `Row` / 47 strings; has 5 `Expanded|Flexible` + 4 overflow guards already, but role chips + QR area are dense. |
| `safety_tab.dart` | **Medium** | Diagnostics rows (label : value) are the densest formal layout; long GPS-reason labels at huge scale. |
| `my_tab.dart` | **Medium** | Will gain the H1 settings selectors → must be re-tested at huge scale after H1. |
| `preview_screen.dart` | **Low-Med** | Lots of `Row`/`Expanded` (9) already; mostly scrollable `PageView`. Radar is in a bounded box. |
| `last_seen_screen.dart` | **Low-Med** | List rows with `Expanded`; check timestamp/anon8 row. |

Composite stress note (per plan §H3): effective scale = `systemTextScale × IgniTextScale.factor`,
so H3 must inject the **effective** scaler directly (e.g. `TextScaler.linear(2.00)`) rather than
pumping `IgniRelayApp` and relying on the builder to multiply.

---

## 5. ARB legacy-key candidates (for UI-H4)

`app_zh.arb` / `app_en.arb` (≈68 KB each). Group prefixes from `app_zh.arb`:

| Prefix | Keys (approx) | Live consumer? | H4 disposition |
|---|---:|---|---|
| `supply` | 392 | none | **DEAD — delete** |
| `map` | 139 | none | **DEAD — delete** |
| `station` | 78 | none | **DEAD — delete** |
| `medical` | 61 | none | **DEAD — delete** |
| `chat` | 55 | none | **DEAD — delete** |
| `profile` | 43 | none | **DEAD — delete** |
| `match` | 34 | none | **DEAD — delete** |
| `handoff` | 29 | none | **DEAD — delete** |
| `requests` / `req` / `neg` | 19 / 18 / 18 | none | **DEAD — delete** |
| `survival` | 18 | none | **DEAD — delete** |
| `community` | 18 | none | **DEAD — delete** |
| `supplies` | 16 | none | **DEAD — delete** |
| `nav` / `tab` / `common` | 17 / 5 / 6 | none | **DEAD — delete** (verify each on regen) |
| `triage` | 9 | none | **DEAD — delete** |
| `hazard` (ARB group) | 10 | none (formal `hazard_card` is hard-coded, not l10n) | **DEAD — delete** |
| `location` (ARB group) | 14 | none | **DEAD — delete** |
| `onboarding` | 14 | `onboarding_screen.dart` (dead screen) | **DEAD-SCREEN — delete with the screen, same task** |
| `battery` | 46 | `battery_optimization_guide.dart` (dead screen) | **DEAD-SCREEN — delete with the screen, same task** |
| `main` | 17 (6 used) | `main.dart` uses 6 | **KEEP the 6 used** (`mainBleFailSnack`, `mainBluetoothDialog{Title,Content,Cancel,Confirm}`, `mainPermissionSnack`); the ~11 unused `main*` are dead → verify on regen |
| `tier` | 4 | `tier_manager.dart` (LIVE via `Provider<TierManager>` in `main.dart:501`) | **KEEP** (`tierLabel1Force/1Standard/2EcoRelay/3UltraEco`) |
| `appTitle` | 1 | none (`main.dart` title is the literal `烽傳 IgniRelay`) | **DEAD — delete** (verify) |

**Authoritative deletion rule for H4:** the compiler is the source of truth. Remove keys, run
gen-l10n, then `flutter analyze` + `flutter test` — any reference to a removed getter fails the
build. Keys not reachable from the 5 S-referencing files are safe; the only must-keep keys are
`main*`-used (6) and `tierLabel*` (4), plus whatever UI-H2 newly adds.

---

## 6. Required answers (UI-H0 task questions 1–10)

**1. Which formal UI files have no l10n at all?**
**All of them.** No formal UI file calls `context.l10n` / `S.of`. The only l10n callers in
`lib/ui` are the two legacy `secondary/` screens.

**2. Which formal UI files have the most hard strings?**
`field_screen.dart` (47), `safety_tab.dart` (41), `preview_screen.dart` (40), `sos_screen.dart`
(31), `hazard_card.dart` (21). See §2.

**3. Which strings does the A11 runbook see?**
The two-phone runbook drives these formal strings (all hard-coded today **except** the `main*`
group, already localized):
- no-field entry: `加入場域` / `建立場域` / `先看功能` + title `烽傳 IgniRelay` + subtitle (`app_shell.dart`);
- tab labels `安全 / 位置 / 事件 / 協助 / 我的` (`app_shell.dart`) — runbook asserts no `地圖`;
- field join/create + role chips 主辦/成員 + QR copy (`field_screen.dart`, `field_qr_sheet.dart`, `field_scan_screen.dart`);
- SOS RED/YELLOW + countdown + SAFE/我安全了 (`sos_screen.dart`);
- HAZARD formal send + no-fix prompt (`hazard_card.dart`);
- last-trusted-position + radar caption (`last_seen_screen.dart`, `relative_radar.dart`);
- **already localized** (`main*`): Bluetooth-enable dialog, permission snackbar, BLE-fail snackbar (`main.dart`).
UI-H2 must keep zh wording byte-identical to what the runbook expects under the zh flow.

**4. Which files are most likely to overflow at huge text scale?**
`app_shell.dart` bottom nav, `hazard_card.dart`, `checkpoint_card.dart`, `sos_screen.dart`,
`admin_broadcast_banner.dart` (fixed heights / hard fontSize). Full list in §4.

**5. Do old onboarding / battery guide still have a live route/import?**
**No.** Both were de-wired by A11-preflight-fix (`a8e1cc1`). `main.dart` references them only in
explanatory comments; the originals were intentionally not deleted to keep that change's scope
small. `first_run_routing_test.dart` is a source guard asserting they stay out of the live path
(it strips comments before asserting). They are pure `legacy-delete` candidates for UI-H4.

**6. Which ARB keys look legacy-only?**
Essentially the whole file except `main*`-used (6) and `tierLabel*` (4). `onboarding*` (14) and
`battery*` (46) are legacy-screen-bound. The rest (supply/map/station/medical/chat/profile/match/
handoff/requests/req/neg/survival/community/supplies/nav/tab/common/triage/hazard/location/appTitle)
have zero compiled consumers. See §5.

**7. Does UI-H1 need a new locale getter?**
**No.** Read the current language with `Localizations.localeOf(context)`. There is no
`IgniRelayApp.localeOf` (only `setLocale`), and adding one is unnecessary for Stage A, which ships
`中文 / English` only (no `系統`). `textScaleOf` already exists for the text-size selector's current value.

**8. Does UI-H2 need to split into H2a/H2b/H2c?**
**Recommend: split into three, but sequence them — do not parallelize.** The formal surface is ~285
visible strings; a single commit would be a large, hard-to-review diff that also touches the SOS
critical path. Suggested split mirrors the plan:
- **H2a** — `app_shell` (shell + 5 tab labels + no-field entry) + `my_tab` formal copy (pairs with H1).
- **H2b** — field flow (`field_screen` / `field_scan_screen` / `field_qr_sheet`) + preview (`preview_screen` / `preview_fixtures`).
- **H2c** — safety/events/SOS surfaces (`safety_tab` + `communication_state` mapping, `events_tab`,
  `hazard_card`, `checkpoint_card`, `admin_broadcast_banner`, `sos_screen`, `last_seen_screen`,
  `relative_radar`, `assist_tab`).
If H2a turns out small, H2a+H2b may merge; H2c (SOS critical path) should stay its own commit.

**9. UI-H4 deletion risk ordering (lowest → highest):**
1. **Pure dead ARB keys** (supply/map/station/medical/chat/profile/match/handoff/etc.) — no
   consumer, no screen; delete + regen. Lowest risk.
2. **Dead-screen + its keys, same task** — `onboarding_screen.dart`+`onboarding*`, then
   `battery_optimization_guide.dart`+`battery*`. Must update/keep `first_run_routing_test.dart`
   (it only checks the *live path*, so deleting the files is compatible — but re-run it).
3. **Unused `main*` / `appTitle` trim** — must not touch the 6 live `main*` keys; regen-verify.
   Highest risk because it sits next to live formal-startup keys.
Never touch: `tierLabel*` (live), proto/DB/corpus, `resqmesh` historical comments.

**10. Any blocker preventing UI-H1 from starting?**
**No blocker.** All reuse APIs exist and are wired: `setLocale`/`setTextScale`/`textScaleOf`
(`main.dart:317-334`), persistence keys `app_language` / `app_text_scale` (`main.dart:382-420`),
`IgniTextScale` factors 1.00/1.15/1.30/1.45 (`igni_text_scale.dart:27`), and the root
`MaterialApp.builder` already applies the composed `textScaler` (`main.dart:651-657`). `my_tab.dart`
is 157 lines and reads no facade → adding a settings section stays well under the 500-line rule.

---

## 7. Cross-cutting design notes for later stages

- **N1 (H2) — `communication_state.dart` is a pure non-widget file.** Its visible path strings can't
  call `context.l10n`. Localize at the **render seam**: have it return the existing typed
  `CommsPath` enum (it already does) and map enum → `context.l10n.*` inside `safety_tab.dart`,
  rather than passing an l10n object into the pure file. Same pattern for any other pure-Dart copy
  source. Keep the "honest cloud" wording rule (no "connected" claim in Stage A).
- **N2 (H2) — forbidden wording is normative.** DESIGN §4.5 / REBUILD §3.6: never "目前位置" for
  derived/uncertain position; gate `rg "目前位置" lib/ui` must stay clean. No staff-role-exists copy
  offline. No simplified Chinese in zh strings (DESIGN §5.8).
- **N3 (H2) — preview fixtures stay non-decodable.** When moving `preview_fixtures.dart` copy to
  ARB, do not introduce a real-looking `field_join_secret` / `IGNI1` / `field_id` hex; the UI-G
  import-guard test and the "structurally fixture-only" property must survive.
- **N4 (H3) — token discipline.** DESIGN §6 gate `rg "Colors\." lib/ui/screens lib/ui/shell`
  currently shows only the 4 `design_showcase` exemptions. Any H3 layout fix must stay token-clean.
- **N5 (general) — MASTER not yet updated.** `docs/MASTER_EXECUTION_PLAN.md` has **no** `UI-H`
  entry. Per the plan §9 Q1, UI-H stays a side planning doc until Owner authorizes integration;
  UI-H0..H4 must not edit MASTER without that explicit authorization.

---

## 8. Recommended construction order

```text
UI-H0  audit                     ← this document (DONE on commit)
  └─ UI-H1  settings entry (我的): 中文/English + 標準/大字/特大字/超大字, reuse existing APIs
       └─ UI-H2  localize formal UI  (H2a shell+my · H2b field+preview · H2c safety/events/SOS)
            └─ UI-H3  large-text QA   (app factors 1.00–1.45 + composite effective 2.00)
                 └─ UI-H4  legacy cleanup (delete dead screens + ~99% of ARB; keep main*/tierLabel*)
```

Each code stage runs the §7 gates from `UI_H_I18N_A11Y_PLAN.md` and appends `STATUS.md` with
commit hash + gate evidence. UI-H does not bypass A11; after UI-H, return to A11-D2 USER-GATE.
