# IgniRelay App UI/IA Rework Plan

> Version: v0.2, 2026-06-16. Owner-approved planning basis for MASTER_EXECUTION_PLAN v1.5.
> Scope: formal App shell, field-first UX, motion-aware location cadence, and guided preview.
> This document does not change wire/GATT/crypto contracts.

## 0. Review Decisions

Claude review #1 was accepted where it found contract or execution-order risk, and rejected where it pulled future
service concepts into the Stage A App shell.

- **RD-1 role/QR model**: Stage A offline join uses one `field_join_secret` per field. The creator is `owner`; scanned
  joins are `participant`. Do not create separate participant/staff field secrets: that would derive different
  `field_id` values and split the field. `staff` QR/membership is deferred until the Stage E cloud staff-token flow or
  a separate Owner-approved QR-contract task.
- **RD-2 motion source**: Flutter has no built-in accelerometer/gyroscope API in this repo. UI-F must use a narrow
  native Android `SensorManager` bridge or an injected platform source. Do not add `sensors_plus`, do not add
  `ACTIVITY_RECOGNITION`, and do not use step counter/detector in Stage A.
- **RD-3 UI-F split**: UI-F is not one giant commit. Implement it as UI-F0 through UI-F5 below; each subtask must keep
  gates green and update `STATUS.md`.
- **RD-4 visibility policy**: SOS is never hidden by role or peer-visibility policy. Full `peer_visibility=staff_only`
  semantics remain a Stage E/service-policy responsibility.
- **RD-5 future models**: `IncidentCase`, E-CARE, full manager screens, and Web/cloud admin workflows are not UI-F.
  Stage A remains event-centric and field-local.

## 1. Product Direction

IgniRelay is not a chat app, not a map-first tracking app, and not a debug console.
The App must open as a field safety tool:

> Join or create a time-bounded field, stay visible through trusted last-seen evidence,
> send SOS globally, report hazards/checkpoints, and keep working through cloud, BLE mesh,
> nodes, gateway, or local store-and-forward.

The existing BLE/event/v3 envelope/SOS/presence/location components are retained.
The work is a product shell and state-model re-cut, not a ground-up rewrite.

## 2. Navigation Decision

Formal AppShell tabs:

```text
安全 | 位置 | 事件 | 協助 | 我的
```

Rules:

- SOS is a global emergency action, not a normal tab item.
- The old `DebugShell` must not be the production home. It becomes developer diagnostics only.
- The tab formerly discussed as "地圖" is named **位置**. Map/custom image layers are optional/future;
  list/radar/last-trusted-position are first-class.
- Every visible module is scoped by current field + membership + role + permissions + communication state.

## 3. Field Entry / First Run

First-run behavior after permissions:

```text
No active field
├─ 加入場域
│  ├─ 掃 QR
│  └─ 輸入密鑰
├─ 建立場域
└─ 先看功能
```

Permissions:

- First launch may request the same core permissions as today, plus camera for QR scanning:
  location, Bluetooth/Nearby devices, notifications, camera.
- Camera is not a hard device requirement. Manual key entry must work if camera is denied or absent.
- Basic accelerometer/gyroscope use for motion detection must not introduce a new runtime permission.
- Do not use Android step counter / Activity Recognition in v1; it would require `ACTIVITY_RECOGNITION`
  and adds a permission prompt we do not need.

Field role entry:

- A Stage A offline field exposes one field join secret:
  - creator -> role `owner`
  - scanner/manual-key join -> role `participant`
- Owner-created local field grants role `owner` to the creator.
- QR is an encoded join string, not a new transport. It should stay versioned (`IGNI1...`) and must not log
  raw `field_join_secret`.
- `staff` is a reserved role, but not a Stage A offline QR path. Current `IGNI1` staff token requires
  `cloud_base_url`; without cloud, the app must not pretend that staff membership exists.

## 4. UI-F: Formal AppShell + Motion-Aware Location

Purpose: finish the product shell except guided preview/tutorial mode.

### 4.0 Subtask Split

- **UI-F0 Preflight**: confirm no `staff` offline QR, choose native motion source, and add/adjust docs or STATUS if a
  dependency is missing.
- **UI-F1 AppShell entry**: first-run/no-field entry, five-tab `AppShell`, production home swap, `DebugShell` debug-only.
- **UI-F2 Module placement**: move existing SOS, field, position/radar, events, broadcast, checkpoint, hazard, and
  presence controls into their target tabs. HAZARD must have a formal product action, not only a debug card.
- **UI-F3 Field membership model**: minimal `owner`/`participant` model, role display, owner-only create/share controls.
  `staff` stays disabled/deferred with explicit copy if shown at all.
- **UI-F4 CommunicationState**: aggregate cloud stub/off, BLE/mesh, peers/nodes, outbox count, last presence, and best
  path copy.
- **UI-F5 Motion-aware cadence**: native/injected motion source, hysteresis, diagnostics, and presence/GPS cadence tests.

### 4.1 Required Scope

1. Replace production home with `AppShell`.
2. Add global layer:
   - active field status bar
   - communication status chip/banner
   - global SOS floating/anchored action
   - emergency/admin broadcast overlay
3. Add five tabs:
   - `安全`: my safety, communication state, quick actions, recent footprint summary
   - `位置`: last-trusted-position list + radar; no map SDK/tile dependency
   - `事件`: SOS, hazard, broadcast, checkpoint, system event lists
   - `協助`: offline help placeholder and SOS-after-assist entry; E-CARE remains future unless EC task active
   - `我的`: active field, identity/role, permission health, field list, developer diagnostics entry
4. Move existing working modules into the right tabs:
   - `FieldScreen`
   - `SosScreen` / `SosController`
   - `LastSeenScreen` / `RelativeRadar`
   - `AdminBroadcastBanner`
   - `CheckpointCard`
   - `HazardCard`
   - `PresenceBeaconController`
5. Move `DebugShell` behind a debug/developer diagnostics route.
6. Add minimal field membership / permission model if missing:
   - Stage A active roles: `participant`, `owner`
   - reserved future role: `staff`
   - role derived from local create vs joined field, not from a second field secret
   - role visible in "我的" and active field status
   - owner sees field QR/create/share controls; participant does not
7. Add `CommunicationState` aggregation:
   - cloud reachable (stub/off until Stage E)
   - BLE available / mesh running
   - nearby peers/nodes when known
   - pending envelope/outbox count
   - last presence sent
   - current best path copy

### 4.2 Motion-Aware Location Policy

Replace the fixed "120s always" presence/GPS policy with motion-aware cadence.

Implementation constraints:

- Use low-rate accelerometer/motion sampling via a narrow native Android `SensorManager` bridge or injected platform
  source.
- Do not add a third-party sensor dependency unless Owner explicitly approves and G13 is updated.
- Do not request `ACTIVITY_RECOGNITION`.
- Do not use step counter / step detector in v1.
- Do not make compass/magnetometer part of the radar heading in v1. Radar stays north-up.

Policy constants:

```text
moving_presence_interval       = 30s
moving_min_fix_age             = 30s
stationary_presence_interval   = 180s
stationary_min_fix_age         = 15min
low_battery_moving_interval    = 60s
low_battery_stationary_interval= 300s
low_battery_threshold          = 20%
motion_sample_rate             = low / UI-grade only
motion_window                  = 8s
moving_confirm_windows         = 2
stationary_confirm_duration    = 45s
moving_rms_threshold           = implementation constant, tested with fake source
stationary_rms_threshold       = implementation constant lower than moving threshold
```

Behavior:

- If moving:
  - refresh GPS before PRESENCE when last fix is older than `moving_min_fix_age`
  - publish PRESENCE at `moving_presence_interval`
  - publish immediately when transitioning stationary -> moving if last presence is older than 15s
- If stationary:
  - reuse last known fix
  - do not keep high-accuracy GPS stream hot
  - publish keepalive PRESENCE at `stationary_presence_interval`
- If low battery:
  - use low-battery intervals above
- Manual safety events override cadence:
  - SOS, HAZARD, CHECKPOINT, and "我安全了" may request one fresh GPS fix with timeout before sending,
    then fall back to last known fix if unavailable.
- UI must expose diagnostic state for A11:
  - moving/stationary
  - current interval
  - last GPS fix age
  - last presence sent
  - GPS policy reason (`moving`, `stationary-reuse`, `manual-event`, `low-battery`)
- Hysteresis is required: one noisy accelerometer sample must not flip stationary -> moving, and one quiet sample must
  not flip moving -> stationary. Tests should use a fake motion source and fake clock.

### 4.3 UI-F DoD

- D1 production launch no longer lands in `DebugShell`; first-run/no-field shows field entry choices.
- D2 `AppShell` five tabs exist with labels exactly `安全 | 位置 | 事件 | 協助 | 我的`.
- D3 global SOS is reachable from every tab and is not hidden inside `事件` or `協助`.
- D4 existing functional modules render in their target tabs; debug diagnostics is debug-only.
- D5 `owner`/`participant` role is visible and drives concrete UI differences: owner can create/share field join QR;
  participant cannot. `staff` is absent or visibly deferred, never faked with a second field secret.
- D6 motion-aware policy is implemented with tests for moving, stationary, transition, and low-battery cadence.
- D7 no new wire/proto/GATT/crypto changes.
- D8 debug diagnostics is not the production home and is only reachable in debug/developer mode.
- D9 HAZARD is reachable as a formal event action from the production event/safety surface.
- D10 permission naming is unambiguous: OS permission health is not mixed with field role/capability policy.
- D11 gates green:
  - `dart run tool/check_layers.dart --strict`
  - `flutter analyze --no-fatal-infos --no-fatal-warnings`
  - `flutter test --exclude-tags golden`
  - `flutter test test/conformance/wire_conformance_corpus_test.dart`
  - `cd android; .\gradlew.bat :app:assembleDebugAndroidTest`
  - grep/assert no `ACTIVITY_RECOGNITION` in Android manifests
  - grep/assert no `sensors_plus` dependency unless Owner explicitly approves a G13 update

## 5. UI-G: Guided Preview / "先看功能"

Purpose: make the no-field "先看功能" path useful without pretending to join a real field.

### 5.1 Required Scope

1. Add a guided preview route reachable from the no-field entry screen.
2. Use fixture/demo data only:
   - demo field
   - demo member footprints
   - demo SOS
   - demo hazard
   - demo broadcast/checkpoint
3. Preview mode must not:
   - start mesh
   - publish wire events
   - write real field membership
   - request GPS solely for preview
   - show real secrets
4. Explain the product in operation-oriented screens, not marketing pages:
   - Join a field
   - Stay visible
   - Send SOS
   - See last trusted positions
   - Report hazards/checkpoints
   - Work offline / degrade gracefully
5. Exit paths:
   - Join field
   - Create field
   - Back to no-field entry

### 5.2 UI-G DoD

- D1 "先看功能" opens a bounded preview/tutorial mode from no-field entry.
- D2 preview uses fixture data and cannot send real events.
- D3 preview covers safety, position, events, assist, and my/field concepts.
- D4 no permission is required solely to view preview, except permissions already requested by first-run policy.
- D5 tests cover entry, fixture rendering, and no real publish calls.
- D6 same gates as UI-F.

## 6. A11 Impact

A11 two-phone acceptance must be updated after UI-F/UI-G:

- It validates the formal `AppShell`, not `DebugShell`.
- It includes first-run permissions and no-field entry.
- It verifies owner create + participant join. `staff` join is deferred until Stage E/cloud staff-token support or a
  separate QR-contract task.
- It verifies the tab labels use `位置`, not `地圖`.
- It verifies global SOS from at least two tabs.
- It verifies motion-aware GPS/presence behavior using the diagnostic state exposed by UI-F.
- It keeps the existing BLE/event acceptance: PRESENCE, SOS, SAFE, HAZARD, restart/dedup, field-scope mismatch,
  connectedDebugAndroidTest, and radar at >=20m.

Stage A cannot exit until UI-F, UI-G, A11-D2, and A12 are complete.
