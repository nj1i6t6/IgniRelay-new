# IgniRelay UI-H i18n / A11y / Legacy Cleanup Plan

> Version: v0.1, 2026-06-20. Draft for Owner / Claude review.
> Scope: formal App UI localization, user text-size controls, large-text QA, and legacy UI cleanup.
> This document does not change wire/GATT/crypto/DB contracts and does not claim A11 completion.

## 0. Document Status

This is a planning document for a proposed **UI-H** stage.

### 0.1 Review Notes Incorporated

Claude review #1 checked this plan against the actual codebase and confirmed the core premise:

- l10n infrastructure exists, but the formal UI-F / UI-G surfaces are still largely hard-coded Chinese;
- text-scale infrastructure exists, but the formal settings entry and large-text QA are incomplete;
- old localized UI does not count as formal App i18n completion.

This version incorporates the review's required corrections:

- text scale is **multiplicative**: the app's `IgniTextScale` factor is applied on top of the platform/system text
  scale (`system × appFactor`), so UI-H3 must test both app factors and a composite stress scale;
- `rg OnboardingScreen` is only a smell-check because explanatory comments may mention legacy onboarding; the actual
  startup guard is the existing source test that strips comments before asserting the live path;
- Stage A language settings will expose only explicit `中文` / `English`; a true `System` option is deferred unless a
  later task adds a clean nullable/sentinel locale API;
- UI-H4 legacy cleanup is the highest-risk UI-H cut and must delete old screens and their l10n keys in the same scoped
  task after UI-H0 audit.

UI-F and UI-G produced the formal App shell:

```text
No active field
├─ 加入場域
├─ 建立場域
└─ 先看功能

Formal tabs
安全 | 位置 | 事件 | 協助 | 我的
```

A11-preflight-fix now routes fresh install directly to the formal `AppShell` after Android permissions.
A11-D2 remains a USER-GATE and is not passed until Owner performs the two-phone test.

UI-H is allowed before A11 only because it is UI/product polish:

- no wire change;
- no BLE / mesh behavior change;
- no A12 contract material;
- no Node / Gateway / Web / Cloud implementation;
- no claim that A11 or Stage A Exit has passed.

## 1. Problem Statement

The repo already has **partial infrastructure**:

- Flutter gen-l10n is configured:
  - `ignirelay_app/l10n.yaml`
  - `ignirelay_app/lib/l10n/app_zh.arb`
  - `ignirelay_app/lib/l10n/app_en.arb`
  - generated `S`
  - `MaterialApp.localizationsDelegates`
  - `IgniRelayApp.setLocale(...)`
- Text-size scaling already exists:
  - `IgniTextScale`
  - `SharedPreferences('app_text_scale')`
  - root `MaterialApp.builder` applying `MediaQuery.textScaler`
  - `IgniRelayApp.setTextScale(...)`

But the formal UI-F / UI-G product surface is not complete:

- new formal screens still contain many hard-coded Chinese visible strings;
- the user has no obvious formal settings entry for language or text size;
- large text has not been systematically tested on A11-visible screens;
- legacy localized screens still exist, but they are no longer the formal product surface.

Important distinction:

> Old UI localization does **not** count as formal App i18n completion.

The goal is not to rescue old onboarding or old battery-guide UI.
The goal is to finish the new formal product shell.

## 2. Product Decision

UI-H makes the formal App usable in:

1. Traditional Chinese;
2. English;
3. user-selectable text sizes:
   - standard;
   - large;
   - xLarge;
   - huge.

The user-facing settings must live in the formal product UI, most likely under `我的`.

Legacy screens that are no longer reachable from the formal product path should be removed or explicitly isolated.

## 3. Hard Boundaries

UI-H must not:

- edit wire/proto/GATT/crypto/DB/schema;
- edit A12 contract files or conformance corpus shape;
- change BLE, mesh, event semantics, field membership crypto, or publish behavior;
- change Stage B/C/D/E dependencies;
- claim A11 passed;
- revive old onboarding or old battery optimization guide;
- translate dead legacy screens as if they are the product;
- introduce a new localization framework;
- introduce a new settings persistence mechanism;
- add network/cloud behavior;
- weaken tests, skip gates, or lower assertions;
- edit `docs/MASTER_EXECUTION_PLAN.md` unless Owner explicitly authorizes a later plan-integration task.

## 4. Formal UI Surface In Scope

The following formal product surfaces are in scope for localization and text-scale QA:

- startup / no-field entry;
- `AppShell`;
- five tabs:
  - `安全`;
  - `位置`;
  - `事件`;
  - `協助`;
  - `我的`;
- `FieldScreen`;
- `FieldScanScreen`;
- `FieldQrSheet`;
- field create / join / manual-key dialogs;
- SOS flow:
  - `SosScreen`;
  - `SosHoldButton`;
  - SAFE / cancel / status copy;
- position surfaces:
  - `LastSeenScreen`;
  - `RelativeRadar` visible labels;
- guided preview:
  - `PreviewScreen`;
  - preview fixture copy;
- visible cards / banners:
  - `AdminBroadcastBanner`;
  - `HazardCard`;
  - `CheckpointCard`;
- startup/product prompts still reachable:
  - Bluetooth enable dialog;
  - permission snackbar;
  - no-field and field-management copy.

## 5. Legacy / Debug Surface Treatment

The following are not formal product i18n targets unless a task explicitly keeps them:

- `onboarding_screen.dart`;
- `battery_optimization_guide.dart`;
- `DebugShell`;
- `DesignShowcaseScreen`;
- old map/chat/supply/medical surfaces that are no longer formal product paths.

Treatment rules:

- debug-only screens may keep debug copy if they are only reachable in debug/profile mode;
- dead legacy screens should be removed in UI-H4, not polished;
- compatibility comments and old wire/proto names must not be removed merely because they contain `resqmesh`;
- generated proto packages, DB names, and corpus paths are outside this cleanup unless a separate contract task approves it.

## 6. Task Split

UI-H is not one big commit. It must be split into UI-H0 through UI-H4.

```text
UI-H0 audit
  └─ UI-H1 settings entry
       └─ UI-H2 formal UI localization
            └─ UI-H3 large-text QA
                 └─ UI-H4 legacy cleanup
```

Each task must keep gates green and append `STATUS.md` with evidence.

---

## UI-H0 — Audit and Task Map

### Purpose

Build a concrete inventory before moving strings or deleting files.

### Required Reads

Read in order:

1. `docs/MASTER_EXECUTION_PLAN.md`
2. `STATUS.md`
3. `AGENTS.md`
4. `docs/DESIGN_LANGUAGE.md`
5. `docs/APP_UI_IA_REWORK_PLAN.md`
6. current formal UI source files under `ignirelay_app/lib/ui/shell/` and `ignirelay_app/lib/ui/screens/`

### Work

1. Scan formal UI files for hard-coded visible strings.
2. Classify each finding:
   - `formal-now`: must move to ARB during UI-H2;
   - `settings-now`: belongs in UI-H1 settings;
   - `large-text-risk`: needs UI-H3 layout test;
   - `debug-only`: may remain hard-coded if debug/profile-only;
   - `legacy-delete`: candidate for UI-H4 deletion;
   - `compatibility`: keep, do not touch.
3. Scan l10n ARB keys for legacy-only groups.
4. Scan old screens for references:
   - imports;
   - routes;
   - tests;
   - generated l10n accessors;
   - runbook references.
5. Produce `docs/UI_H_I18N_A11Y_AUDIT.md`.

### DoD

- `docs/UI_H_I18N_A11Y_AUDIT.md` exists.
- Audit includes:
  - formal UI files;
  - legacy files;
  - debug-only files;
  - hard-coded string count by file;
  - large-text risk list;
  - proposed UI-H1 / H2 / H3 / H4 scope.
- No app behavior changes.
- `STATUS.md` records UI-H0 DONE with commit hash and evidence.

### Forbidden

- Do not move strings yet.
- Do not delete legacy screens yet.
- Do not edit `MASTER_EXECUTION_PLAN.md`.
- Do not claim UI-H DONE.

### Suggested Commit

```text
[UI-H0] audit formal UI i18n and text-scale gaps
docs: STATUS entry — UI-H0 DONE @ <hash>
```

---

## UI-H1 — Formal Settings Entry: Language + Text Size

### Purpose

Expose the already-existing locale and text-scale infrastructure to users.

### Work

1. Add a formal settings section under `我的`.
2. Add language selector:
   - Stage A options: `中文` / `English`;
   - do **not** add `系統` in UI-H1. The current app state can represent `_locale == null`, but the public setter is
     `setLocale(Locale)` and persistence is a string key. A real system-following option needs either a nullable setter
     or a `"system"` sentinel. That is deferred unless Owner explicitly asks for it now.
3. Add text-size selector:
   - `標準`;
   - `大字`;
   - `特大字`;
   - `超大字`.
4. Reuse existing app-level APIs:
   - `IgniRelayApp.setLocale(...)`;
   - `IgniRelayApp.setTextScale(...)`;
   - `IgniRelayApp.textScaleOf(...)`.
   - There is no `IgniRelayApp.localeOf(...)`; read the resolved current locale with
     `Localizations.localeOf(context)`. Because Stage A only exposes explicit `中文` / `English` and defers true
     system-following mode, the resolved locale is sufficient for selected-state display.
5. Reuse existing persistence:
   - `app_language`;
   - `app_text_scale`.
6. Do not add a new settings service unless the current app-level API is insufficient and Owner approves.

### Tests

- Widget test: `我的` shows settings section.
- Widget test: language selector shows current selected language.
- Widget test: text-size selector shows current selected size.
- Widget test: selecting a text size updates visible selected state.
- Widget test: `我的` under huge text scale has no overflow.

### DoD

- User can change language and text size from formal UI.
- Settings persist through existing keys.
- No new singleton.
- No new dependency.
- `STATUS.md` records UI-H1 DONE with gate evidence.

### Forbidden

- Do not introduce a second locale store.
- Do not silently cap text scale globally.
- Do not put settings only in `DebugShell`.
- Do not revive old profile/settings screens.

### Suggested Commit

```text
[UI-H1] add formal language and text-size settings
docs: STATUS entry — UI-H1 DONE @ <hash>
```

---

## UI-H2 — Localize the Formal New UI

### Purpose

Move formal product strings from hard-coded Dart into ARB.

### Files

Primary localization files:

- `ignirelay_app/lib/l10n/app_zh.arb`
- `ignirelay_app/lib/l10n/app_en.arb`

Generated files must be regenerated by Flutter gen-l10n / build process.

### Priority Order

1. `AppShell` / no-field entry / tab labels.
2. `MyTab` / formal settings.
3. Field flow:
   - `FieldScreen`;
   - `FieldScanScreen`;
   - `FieldQrSheet`;
   - create / join / manual-key dialogs.
4. Guided preview:
   - `PreviewScreen`;
   - preview fixture visible copy.
5. Formal tabs:
   - safety;
   - position;
   - events;
   - assist.
6. Emergency and event actions:
   - SOS;
   - hazard;
   - checkpoint;
   - admin broadcast.

### Work

1. Add ARB keys with clear names.
2. Provide zh and en values for every formal string.
3. Replace formal hard-coded visible strings with `context.l10n`.
4. Keep domain terms consistent:
   - `場域` = `field`;
   - `最後可信位置` = `last trusted position`;
   - `最後足跡` = `last footprint`;
   - `先看功能` = `guided preview` or `preview features` (choose one and use consistently).
5. Keep forbidden product wording:
   - do not use `目前位置` for uncertain / derived position;
   - do not imply cloud is connected in Stage A;
   - do not imply staff role exists offline.

### Tests

- English locale smoke:
  - no-field entry shows English;
  - tab labels show English;
  - Preview first page shows English;
  - My settings shows English.
- Chinese locale smoke:
  - same surfaces show Chinese.
- Guard test:
  - formal AppShell / tabs / Preview should not expose obvious hard-coded Chinese strings under English locale, except allowlisted domain terms if documented.
- Existing A11 runbook-visible strings must still match intended zh flow.

### DoD

- Formal UI surfaces in §4 are localized or explicitly documented as deferred.
- `app_zh.arb` and `app_en.arb` are in sync.
- Generated localization files are updated.
- `STATUS.md` records UI-H2 DONE with gate evidence.

### Forbidden

- Do not localize dead legacy screens as a substitute for formal UI.
- Do not remove ARB keys used by still-compiled files until UI-H4.
- Do not hard-code English fallback strings in widgets unless documented and tested.

### Suggested Commit

```text
[UI-H2] localize formal AppShell and field flows
docs: STATUS entry — UI-H2 DONE @ <hash>
```

If UI-H2 grows too large, split by surface:

```text
[UI-H2a] localize AppShell and settings
[UI-H2b] localize field and preview flows
[UI-H2c] localize safety events and SOS surfaces
```

---

## UI-H3 — Large Text QA and Layout Fixes

### Purpose

Make the text-size feature real. The app must remain usable at larger text scales.

Important runtime fact: the current root builder multiplies the user's App setting on top of the platform/system text
scale:

```dart
effectiveTextScale = systemTextScale * IgniTextScale.factor
```

Therefore `huge = 1.45` is the App factor, not a universal upper bound.

### Required Text Scales

Test the App setting factors at system scale 1.0:

- standard (`1.00`);
- large (`1.15`);
- xLarge (`1.30`);
- huge (`1.45`).

Also add at least one composite stress test representing `system × appFactor`, for example:

- effective `1.80`;
- or effective `2.00`.

UI-H3 does not promise perfect layout for unbounded OS accessibility scales. It promises:

- all App-provided text-size options work at normal system scale;
- the composite stress scale keeps critical actions visible and the app non-crashing;
- any remaining extreme-system-scale limitation is documented rather than hidden.

### Required Screens

At minimum:

- no-field entry;
- `AppShell` bottom navigation;
- `MyTab` settings;
- `SafetyTab`;
- `FieldScreen`;
- `PreviewScreen`;
- `SosScreen`;
- `LastSeenScreen`.

### Fix Policy

Prefer:

- wrapping;
- scrolling;
- `Flexible` / `Expanded`;
- stable responsive constraints;
- icon + tooltip where text is too dense;
- moving secondary copy below instead of squeezing it.

Do not:

- disable user text scaling;
- cap the entire app silently;
- use viewport-width font scaling;
- hide critical safety text;
- rely on overflow clipping;
- shrink SOS / emergency action labels below readable size.

### Tests

- Widget tests under:
  - `TextScaler.linear(1.15)`;
  - `TextScaler.linear(1.30)`;
  - `TextScaler.linear(1.45)`;
  - one composite stress scale such as `TextScaler.linear(2.00)`.
- At least no-field, My settings, FieldScreen, PreviewScreen, SosScreen under huge text scale.
- At least no-field and global SOS reachability under the composite stress scale.
- Tests should fail on Flutter overflow exceptions.

### DoD

- A11-visible screens do not overflow under App huge (`1.45`) at system scale 1.0.
- Composite stress scale keeps critical actions visible and non-crashing; if a non-critical dense panel still needs
  follow-up at extreme system scale, document it explicitly in `STATUS.md`.
- Global SOS remains reachable.
- No-field entry still presents all three actions.
- Field join / create actions remain reachable.
- `STATUS.md` records UI-H3 DONE with gate evidence.

### Forbidden

- Do not mark huge as unsupported.
- Do not change `IgniTextScale.huge` factor without Owner approval.
- Do not solve overflow by removing product-critical copy.

### Suggested Commit

```text
[UI-H3] harden formal UI for large text scales
docs: STATUS entry — UI-H3 DONE @ <hash>
```

---

## UI-H4 — Legacy UI and l10n Cleanup

### Purpose

Remove no-longer-used UI and l10n keys after the formal UI is localized and tested.

This is the highest-risk UI-H task because the existing ARB files contain many historical keys.
Deletion must be audit-driven. If a legacy screen is deleted, its legacy-only ARB keys should be removed in the same
scoped task after proving no compiled file still uses them. Do not leave half-removed screens or half-removed keys.

### Work

Use UI-H0 audit as the source of truth.

Potential cleanup candidates:

- old onboarding screen;
- old battery optimization guide;
- old onboarding l10n keys;
- old battery-guide l10n keys;
- misleading formal-startup comments that imply onboarding is still live;
- old product strings for removed chat / supply / medical surfaces if no compiled file uses them;
- stale docs that refer to old first-run flow, if they are not normative historical records.

### Required Checks Before Deletion

For every candidate file/key:

1. `rg` import/use references; comments are allowed when they accurately document historical behavior.
2. Verify no route points to it.
3. Verify no test requires it.
4. Verify generated l10n remains valid after key removal.
5. Verify A11 runbook still matches actual first-run flow.

### DoD

- Legacy screens not reachable from formal product path are removed or explicitly documented as debug-only.
- Dead l10n keys removed from both `app_zh.arb` and `app_en.arb`.
- Generated localization files updated.
- Startup first-run tests still pass.
- `STATUS.md` records UI-H4 DONE with gate evidence.

### Forbidden

Do not touch:

- proto package names;
- generated wire files;
- DB filenames or migrations;
- conformance corpus;
- compatibility comments that are still semantically true;
- `resqmesh` references inside normative historical specs unless a separate doc-cleanup task approves it.

### Suggested Commit

```text
[UI-H4] remove dead legacy onboarding and l10n keys
docs: STATUS entry — UI-H4 DONE @ <hash>
```

---

## 7. Gates

Every UI-H code task must run:

```powershell
dart run tool/check_layers.dart --strict
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test --exclude-tags golden
flutter test test/conformance/wire_conformance_corpus_test.dart
cd android; .\gradlew.bat :app:assembleDebugAndroidTest
```

For UI-H2 / UI-H3 also run targeted checks:

```powershell
rg "目前位置" lib/ui
rg "Colors\." lib/ui/screens lib/ui/shell
rg "OnboardingScreen|BatteryOptimizationGuide|onboarding_done" lib/main.dart test/startup  # smell-check only
flutter test test/startup/first_run_routing_test.dart
```

Expected:

- layer check passes;
- analyze has no new issues;
- tests pass;
- conformance remains unchanged;
- Kotlin build succeeds;
- no new direct `Colors.` in formal screens;
- no forbidden `目前位置` wording in uncertain-position UI;
- startup test remains green. The `rg OnboardingScreen...` line is informational only because comments may accurately
  describe historical behavior; live-code assertions belong in `first_run_routing_test.dart`.

## 8. UI-H Exit

UI-H is DONE only when all are true:

1. UI-H0 through UI-H4 are DONE in `STATUS.md`, each with commit hash and gate evidence.
2. Formal App UI supports Traditional Chinese and English.
3. User can change language from formal UI.
4. User can change text size from formal UI.
5. Key A11-visible screens survive huge text scale.
6. Old onboarding / battery-guide UI is removed or explicitly isolated from formal product paths.
7. A11 runbook remains accurate.
8. No wire/proto/GATT/crypto/DB/schema changes occurred.

After UI-H:

```text
return to A11-D2 USER-GATE
  └─ if Owner passes two-phone test → A11 DONE
       └─ then A12 App↔Node contract freeze
```

UI-H must not be used to bypass A11.

## 9. Review Questions for Claude / Owner

1. Should UI-H be inserted into `MASTER_EXECUTION_PLAN.md` before A11 after review, or remain a side planning document?
2. Confirm Stage A language mode: explicit `中文` / `English` only; true `System` mode deferred unless Owner requests the
   nullable/sentinel locale API now.
3. Should UI-H2 be split into H2a/H2b/H2c immediately, or only split if the diff grows large?
4. Is `PreviewScreen` fixture copy considered formal product copy for i18n? This plan says yes.
5. Should old `onboarding_screen.dart` and `battery_optimization_guide.dart` be deleted in UI-H4 if no formal route imports them?
6. Which English term should be frozen:
   - `先看功能` = `Guided Preview`;
   - or `Preview Features`;
   - or another Owner-preferred term?
