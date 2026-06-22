# A11 SOS Latency + IBLT Staged Fix Plan

Status: planning document only. No code changes are made by this file.

Purpose: repair the current A11 blocker (`SOS appears on receiver within <=10s`)
and the known IBLT fast-path peel bug without mixing the two failure domains into
one untestable change. The plan intentionally produces two debug APKs so the
Owner can isolate regressions during the evening device test.

## 0. Decision Summary

Do both fixes, but not in the same code cut.

1. **A11 latency first**: make SOS / SAFE emergency delivery bypass the normal
   gossip reconnect window when no peer is currently ready. Build APK #1.
2. **IBLT second**: fix the fast-path set reconciliation contract across
   Dart/Kotlin/Swift source and fixtures. Build APK #2.
3. Test APK #1 first for SOS <=10s. If it passes, test APK #2 for regression.
   If both pass, run the full A11 USER-GATE on APK #2.

Rationale:

- SOS latency is a connection-timing problem: scan/connect/cooldown/outbox drain.
- IBLT is a sync-algorithm problem: keyHash/index/checksum/parity/corpus.
- They both live near BLE/mesh, but they fail at different layers. Mixing them
  would make a failed night test ambiguous.
- Emergency delivery must be gated by the effective wire priority and/or decoded
  `StatusUpdateData`, not by `eventType` alone. SOS, SAFE, and PRESENCE may all
  ride as `STATUS_UPDATE`; PRESENCE must not accidentally trigger emergency
  delivery.

## 1. Current Evidence and Corrections

### 1.1 SosScreen backfill is already fixed

Commit `8cf44af` adds receiver-side `SosScreen` mount backfill from
`EventStream.recentSos()` / `recentSosResolutions()`. This is not the remaining
A11 blocker. It is receiver UI read-model hydration and does not touch send path,
wire, proto, DB schema, or native code.

### 1.2 Budget hypothesis is refuted

Device evidence under `tmp/a11-live/` shows received SOS envelopes with
`drop=None` and Event_Logs rows containing coordinates. The receiver is not
dropping SOS because of the 240-byte budget.

### 1.3 Handoff evidence wording needs cleanup

`docs/A11_LIVE_TEST_HANDOFF_2026-06-22.md` currently merges two evidence chains
into one sentence:

- `019EEACE10767722`: complete A SENT -> B RECV -> B Event_Logs chain.
- `019EEAF0CADF...`: B-side post-fix DB/UI evidence chain.

This is a documentation precision issue, not a code issue. Before sending that
handoff to another reviewer, split those into two bullets so the evidence can be
checked without confusion.

## 2. APK Strategy

### APK #1: latency-only debug build

Name:

```text
tmp/apk/a11-latency-debug.apk
```

Contents:

- all current fixes through `A11-live-fix`;
- new SOS/SAFE emergency latency fix;
- no IBLT algorithm change.

Purpose:

- isolate whether the emergency delivery fix reliably satisfies A11 Step 7
  (`receiver SOS visible within <=10s`).

### APK #2: latency + IBLT debug build

Name:

```text
tmp/apk/a11-latency-iblt-debug.apk
```

Contents:

- everything in APK #1;
- IBLT fast-path peel fix.

Purpose:

- confirm the IBLT fix does not regress emergency delivery or general mesh sync;
- use this APK as the final A11 candidate if both staged checks pass.

## 3. Stage L: A11 SOS / SAFE Latency Fix

### Goal

When SOS/SAFE is published and there is no currently ready peer, the app should
not wait for the normal gossip reconnect cycle. It should trigger an emergency
connection attempt and drain the queued high-priority event as soon as a peer is
ready.

The acceptance target remains the A11 runbook Step 7: receiver SOS appears within
<=10 seconds in a two-phone test.

### Non-goals

- Do not lower `kPeerCooldownSec` globally as the main fix.
- Do not change PRESENCE / CHECKPOINT / HAZARD cadence.
- Do not change wire/proto/canonical/corpus.
- Do not change IBLT in this stage.
- Do not claim A11 passed after this stage; this only removes the known Step 7
  blocker candidate.

### Current mechanism to account for

Observed / verified current behavior:

- scan cycle: `kScanDurationSec=30`, restart delay `kScanRestartDelaySec=5`;
- normal sync connects, syncs, waits 2s, then calls `nordicDisconnect`;
- peer cooldown: `kPeerCooldownSec=60`;
- `EventPublisherV2Facade._broadcast` enqueues when bridge is missing or no peer
  is `isReadyForTraffic`;
- queue drains when peer capability state becomes ready.

### Required design shape

Prefer a narrow emergency transport request, not a global transport policy change.

Recommended shape:

1. Add an injected emergency-delivery hook at the app/service layer boundary, for
   example an `EmergencyMeshDelivery` interface owned by app/controller code.
2. Wire the implementation at root from existing mesh/runtime plumbing. Keep UI
   using facades only.
3. `EventPublisherV2Facade` invokes the hook only for emergency status updates:
   SOS_RED, SOS_YELLOW, and SAFE. Do **not** key this decision only on
   `eventType`, because SOS / SAFE / PRESENCE can all be `STATUS_UPDATE`.
4. The hook requests immediate scan/connect/drain for known nearby peers,
   bypassing peer cooldown only for emergency delivery.
5. Once a peer becomes ready, the existing queue drain path should send the
   already-enqueued envelope. Avoid creating a second envelope for the same SOS.

Layer warning:

- `lib/app/services/event_publisher_v2_facade.dart` must not import
  `lib/app/mesh/**` directly if that violates current architecture boundaries.
  If a mesh method is needed, expose it through an injected app/controller
  facade already wired at `main.dart`.

### Emergency predicate

This predicate is a hard requirement for Stage L.

Current V2 behavior to preserve:

- `TRAPPED` / SOS_RED and `INJURED` / SOS_YELLOW are `STATUS_UPDATE` payloads
  with emergency effective priorities.
- PRESENCE is not an emergency and must not trigger the emergency hook.
- SAFE currently publishes as a `STATUS_UPDATE` whose effective priority may be
  `PriorityV2.status`, not `sosRed` / `sosYellow`.

Therefore the implementation must not use `eventType == statusUpdate` as the
emergency test. It must inspect either:

- the effective priority (`PriorityV2.sosRed` / `PriorityV2.sosYellow`), and
- the decoded `StatusUpdateData.safetyState` for SAFE.

Required policy:

- SOS_RED / SOS_YELLOW: trigger emergency delivery.
- SAFE / "I am safe": trigger emergency delivery so resolved status clears
  remote SOS displays promptly.
- PRESENCE / normal status: do not trigger emergency delivery.
- HAZARD / CHECKPOINT / ADMIN_BROADCAST: do not change in this stage unless a
  separate acceptance requirement is introduced.

Before implementation, add predicate tests that lock this behavior. If SAFE's
actual send path changes priority in the future, the tests should still prove
SAFE is treated as emergency for delivery purposes and PRESENCE is not.

### Minimum tests

Add tests before or with the fix:

- SOS with ready peer sends immediately and does not call emergency hook.
- SOS with zero ready peers enqueues once and calls emergency hook once.
- INJURED / SOS_YELLOW with zero ready peers also calls emergency hook.
- SAFE / SOS resolution with zero ready peers also calls emergency hook even if
  its effective wire priority is `PriorityV2.status`.
- PRESENCE with zero ready peers enqueues but does **not** call emergency hook.
- repeated SOS publish does not duplicate the same queued envelope during one
  emergency trigger.
- emergency hook failure must not abort publish; outcome should remain queued.

### Device validation for APK #1

1. Build debug APK and copy to `tmp/apk/a11-latency-debug.apk`.
2. Clean install on both phones.
3. Owner creates field / joins both phones.
4. Confirm both phones can exchange PRESENCE.
5. Trigger SOS when the sender reports no ready peer or after waiting outside the
   previous connection window.
6. Receiver SOS page or Safety/SOS surface must show the SOS within <=10 seconds.
7. Repeat at least twice so success is not only from accidentally hitting an
   existing connection window.

If APK #1 fails Step 7, stop. Do not proceed to IBLT until latency is fixed.

## 4. Stage I: IBLT Fast-Path Peel Fix

### Goal

Fix the known IBLT peel quirk before A12 transport contract freeze, while keeping
Bloom fallback as the correctness safety net for mixed or incompatible peers.

### Important correction to older handoff

`IBLT_FIX_HANDOFF.md` is useful as a historical note but is not sufficient as an
implementation plan. A one-sided fix that only changes `_getIndices` or only
changes `_getIndicesFromHash` is not enough.

The correct plan is the newer contract in `docs/IBLT_FIX_PLAN.md`:

```text
keyHash(eventId) = CRC32(eventId)
keyBytes         = uint32_le(keyHash)
checkHash        = FNV1a(keyBytes)
indices          = MurmurHash(keyBytes, seeds 0/1/2) % 56
```

Both bucket indices and checksum must be reconstructable from the pure cell's
`keySum`, because peel no longer has the original event ID.

### Scope

Must update in one overall task:

- Dart `lib/app/mesh/iblt.dart`
- Kotlin `android/app/src/main/kotlin/.../IBLT.kt`
- Swift `ios/Runner/IBLT.swift`
- Dart tests
- Android parity / instrumentation tests as available
- Swift test sources, even though local macOS execution is unavailable
- generated IBLT parity fixture
- wire conformance corpus if IBLT samples change
- native transport spec notes

Do not pretend iOS was verified locally. The Owner has no Mac in this environment.
STATUS must explicitly say Swift source/test sources were updated but XCTest was
not executed locally.

### Capability / mixed-build rule

Do not rely on mixed old/new IBLT bytes being compatible.

Preferred guard:

- advertise capability string `iblt-keyhash-v2` in protocol hello capabilities;
- attempt IBLT fast path only when peer capability says it also supports
  `iblt-keyhash-v2`;
- otherwise use Bloom slow path.

Do not add a version byte to the existing IBLT payload in this task unless a
preflight proves capabilities cannot gate it. Changing the packet shape would be
a larger transport-frame change.

### Minimum tests

- small symmetric difference peels successfully;
- result sets equal CRC32 key hashes of the expected event IDs;
- `toBytes/fromBytes/subtract/peel` round-trip succeeds;
- too-large / overloaded difference still returns null and falls back;
- mixed capability uses Bloom path, not IBLT;
- Dart/Kotlin byte parity still matches generated fixture;
- Swift fixture/source updated; local XCTest marked not run without Mac.

### Device validation for APK #2

1. Install `tmp/apk/a11-latency-iblt-debug.apk`.
2. First use `install -r` over APK #1 to quickly check regression while keeping
   the test field.
3. Confirm SOS Step 7 still passes within <=10 seconds.
4. Confirm PRESENCE and at least one non-SOS event still propagates.
5. If quick regression passes, clean install both phones and run the full A11
   USER-GATE with APK #2 as the candidate build.

If APK #2 regresses SOS latency while APK #1 passed, isolate the regression to
IBLT or its capability gating. Do not weaken the SOS latency acceptance criterion.

## 5. Evening Test Flow

Recommended evening sequence:

1. Test APK #1 (`a11-latency-debug.apk`).
2. If SOS <=10s fails, stop and fix latency.
3. If APK #1 passes, install APK #2 (`a11-latency-iblt-debug.apk`) over it for a
   quick regression check.
4. If APK #2 regresses, stop and fix/revert IBLT.
5. If APK #2 passes quick regression, clean install both phones and run all 13
   A11 USER-GATE steps on APK #2.

Do not declare A11 passed from only the quick regression checks. A11 requires the
Owner-filled USER-GATE runbook.

## 6. Required Gates Before Each APK

Run from `ignirelay_app/`:

```powershell
dart run tool/check_layers.dart --strict
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test --exclude-tags golden
flutter test test/conformance/wire_conformance_corpus_test.dart
cd android
.\gradlew.bat :app:assembleDebugAndroidTest
```

Build and copy debug APK:

```powershell
cd C:\Users\radio\Downloads\IDE\IgniRelay\ignirelay_app
flutter build apk --debug
New-Item -ItemType Directory -Force ..\tmp\apk | Out-Null
Copy-Item build\app\outputs\flutter-apk\app-debug.apk ..\tmp\apk\a11-latency-debug.apk
```

For the IBLT build, use:

```powershell
Copy-Item build\app\outputs\flutter-apk\app-debug.apk ..\tmp\apk\a11-latency-iblt-debug.apk
```

## 7. Commit / STATUS Rules

Use separate commits:

1. `[A11-latency-fix] ...`
2. `docs: STATUS entry — A11-latency-fix DONE @ <hash>`
3. `[IBLT-fix] ...`
4. `docs: STATUS entry — IBLT-fix DONE @ <hash>`

STATUS entries must include:

- exact gates and exit codes;
- APK path produced;
- whether device validation was run;
- explicit statement that A11 is not passed until full USER-GATE is completed;
- for IBLT: explicit iOS XCTest status (`not run: no macOS available`) unless
  actual macOS/CI evidence exists.

Do not stage unrelated dirty files such as `.gitignore`, temporary evidence, or
untracked handoff docs unless the Owner explicitly says to.

## 8. Claude Review Checklist

- [ ] Agrees latency and IBLT are separate layers and should be staged.
- [ ] Confirms APK #1 contains latency fix only.
- [ ] Confirms APK #2 contains latency + IBLT.
- [ ] Confirms SOS/SAFE emergency delivery does not change PRESENCE cadence.
- [ ] Confirms emergency delivery does not create duplicate envelopes.
- [ ] Confirms IBLT fix follows `iblt-keyhash-v2`, not the older one-sided
      `_getIndices` shortcut.
- [ ] Confirms mixed IBLT contract falls back to Bloom.
- [ ] Confirms iOS XCTest cannot be claimed locally.
- [ ] Confirms final A11 pass requires full 13-step USER-GATE on APK #2.
