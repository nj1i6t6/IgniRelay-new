// A9 (1) — PresenceBeaconController. Asserts the periodic-beacon state machine
// under `package:fake_async` (zero real time, no platform plugins):
//   • normal cadence (120s) fires repeatedly while gates pass,
//   • low-battery (<20%) downshifts to 300s — including the FIRST interval,
//   • the two gates (mesh running / field joined) make a tick a NO-OP — the
//     prohibition "beacon 在未加入場域時發送",
//   • the enable/disable toggle stops / re-arms the loop.

// `fake_async` is the plan-mandated "fake clock" for the beacon cadence (§5 A9).
// It is already in the dependency tree (transitive via flutter_test); we suppress
// `depend_on_referenced_packages` rather than declaring it, to keep the dep
// manifest untouched (G13 — only 附錄 F whitelist deps).
import 'dart:async';

// ignore: depend_on_referenced_packages
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ignirelay_app/app/controllers/presence_beacon_controller.dart';
import 'package:ignirelay_app/app/services/motion/motion_state.dart';

void main() {
  // Build a controller with counting publish + adjustable gate/battery flags.
  // Returns the controller and a `count()` accessor over published beacons.
  ({PresenceBeaconController c, int Function() count}) make(
    FakeAsync async, {
    bool mesh = true,
    bool field = true,
    int? battery,
    bool enabled = true,
  }) {
    var published = 0;
    final c = PresenceBeaconController(
      publish: ({int? batteryHint}) async => published++,
      isMeshRunning: () => mesh,
      hasJoinedField: () => field,
      readBattery: () async => battery,
      enabled: enabled,
    );
    async.flushMicrotasks(); // let the constructor's _arm read battery + arm
    return (c: c, count: () => published);
  }

  test('default ON → beacons every 120s while gates pass', () {
    fakeAsync((async) {
      final h = make(async);
      expect(h.c.enabled, isTrue);
      expect(h.c.currentInterval, const Duration(seconds: 120));
      expect(h.count(), 0, reason: 'no beacon until the first interval elapses');

      async.elapse(const Duration(seconds: 120));
      expect(h.count(), 1);

      async.elapse(const Duration(seconds: 120));
      expect(h.count(), 2);

      async.elapse(const Duration(seconds: 240));
      expect(h.count(), 4);

      h.c.dispose();
    });
  });

  test('low battery (<20%) downshifts to 300s from the first interval', () {
    fakeAsync((async) {
      final h = make(async, battery: 15);
      expect(h.c.isLowBattery, isTrue);
      expect(h.c.currentInterval, const Duration(seconds: 300));

      // No beacon before 300s.
      async.elapse(const Duration(seconds: 299));
      expect(h.count(), 0);
      async.elapse(const Duration(seconds: 1));
      expect(h.count(), 1);

      // Second beacon at the next 300s, not 120s.
      async.elapse(const Duration(seconds: 120));
      expect(h.count(), 1);
      async.elapse(const Duration(seconds: 180));
      expect(h.count(), 2);

      h.c.dispose();
    });
  });

  test('does NOT beacon when no field is joined (gate)', () {
    fakeAsync((async) {
      final h = make(async, field: false);
      async.elapse(const Duration(seconds: 600));
      expect(h.count(), 0, reason: 'no field → never beacon (A5 §21.6)');
      // The loop stays armed so it resumes once a field is joined.
      expect(h.c.isRunning, isTrue);
      h.c.dispose();
    });
  });

  test('does NOT beacon when the mesh is stopped (gate)', () {
    fakeAsync((async) {
      final h = make(async, mesh: false);
      async.elapse(const Duration(seconds: 600));
      expect(h.count(), 0);
      h.c.dispose();
    });
  });

  test('toggle off stops the loop; toggle on re-arms it', () {
    fakeAsync((async) {
      final h = make(async);
      async.elapse(const Duration(seconds: 120));
      expect(h.count(), 1);

      h.c.setEnabled(false);
      expect(h.c.isRunning, isFalse);
      async.elapse(const Duration(seconds: 600));
      expect(h.count(), 1, reason: 'disabled → no further beacons');

      h.c.setEnabled(true);
      async.flushMicrotasks(); // re-arm reads battery
      expect(h.c.isRunning, isTrue);
      async.elapse(const Duration(seconds: 120));
      expect(h.count(), 2);

      h.c.dispose();
    });
  });

  test('constructed disabled → never arms a timer', () {
    fakeAsync((async) {
      final h = make(async, enabled: false);
      expect(h.c.isRunning, isFalse);
      async.elapse(const Duration(seconds: 600));
      expect(h.count(), 0);
      h.c.dispose();
    });
  });

  // ── UI-F5a — motion-aware cadence ──────────────────────────────────────────

  test('no motion stream → motionState unknown, cadence stays 120s/300s', () {
    fakeAsync((async) {
      final h = make(async); // no motionStates supplied
      expect(h.c.motionState, MotionState.unknown);
      expect(h.c.currentInterval, const Duration(seconds: 120));
      h.c.dispose();
    });
  });

  // Build a motion-aware controller with a counting publish + a motion stream.
  ({
    PresenceBeaconController c,
    int Function() count,
    StreamController<MotionState> motion,
  }) makeMotion(
    FakeAsync async, {
    bool mesh = true,
    bool field = true,
    int? battery,
    bool enabled = true,
  }) {
    var published = 0;
    final motion = StreamController<MotionState>.broadcast();
    final c = PresenceBeaconController(
      publish: ({int? batteryHint}) async => published++,
      isMeshRunning: () => mesh,
      hasJoinedField: () => field,
      readBattery: () async => battery,
      enabled: enabled,
      motionStates: motion.stream,
    );
    async.flushMicrotasks();
    return (c: c, count: () => published, motion: motion);
  }

  test('moving → 30s, stationary → 180s (normal battery)', () {
    fakeAsync((async) {
      final h = makeMotion(async);

      h.motion.add(MotionState.moving);
      async.flushMicrotasks();
      expect(h.c.motionState, MotionState.moving);
      expect(h.c.currentInterval, const Duration(seconds: 30));
      async.elapse(const Duration(seconds: 30));
      expect(h.count(), 1);

      h.motion.add(MotionState.stationary);
      async.flushMicrotasks();
      expect(h.c.currentInterval, const Duration(seconds: 180));

      h.c.dispose();
      h.motion.close();
    });
  });

  test('low battery → moving 60s / stationary 300s', () {
    fakeAsync((async) {
      final h = makeMotion(async, battery: 15);

      h.motion.add(MotionState.moving);
      async.flushMicrotasks();
      expect(h.c.currentInterval, const Duration(seconds: 60));

      h.motion.add(MotionState.stationary);
      async.flushMicrotasks();
      expect(h.c.currentInterval, const Duration(seconds: 300));

      h.c.dispose();
      h.motion.close();
    });
  });

  test('stationary→moving with a stale last-beacon → immediate publish', () {
    fakeAsync((async) {
      final h = makeMotion(async);
      h.motion.add(MotionState.stationary);
      async.flushMicrotasks();
      expect(h.count(), 0, reason: 'no beacon has fired yet');

      h.motion.add(MotionState.moving);
      async.flushMicrotasks();
      expect(h.count(), 1,
          reason: 'stationary→moving + stale last-beacon → publish now');

      h.c.dispose();
      h.motion.close();
    });
  });

  test('stationary→moving transition still obeys the gates (no send)', () {
    // Owner boundary 3: disabled / no field / mesh off ⇒ no transition publish.
    void noSend(String why,
        {bool mesh = true, bool field = true, bool enabled = true}) {
      fakeAsync((async) {
        final h = makeMotion(async, mesh: mesh, field: field, enabled: enabled);
        h.motion.add(MotionState.stationary);
        async.flushMicrotasks();
        h.motion.add(MotionState.moving);
        async.flushMicrotasks();
        expect(h.count(), 0, reason: why);
        h.c.dispose();
        h.motion.close();
      });
    }

    noSend('no field → suppressed', field: false);
    noSend('mesh off → suppressed', mesh: false);
    noSend('disabled → suppressed', enabled: false);
  });

  test('disabled: a stationary→moving change still notifies the UI '
      '(diagnostic refresh) without publishing or arming', () {
    // UI-F5a-polish (Owner): while paused, the immediate-publish transition
    // branch is skipped — but the motion diagnostic still changed, so the UI
    // must be notified. Regression guard: before the fix this transition took
    // the publish/arm path, both of which early-return without notifyListeners.
    fakeAsync((async) {
      final h = makeMotion(async, enabled: false);
      // Settle into stationary while paused.
      h.motion.add(MotionState.stationary);
      async.flushMicrotasks();

      // Count ONLY notifications caused by the stationary→moving transition.
      var notifications = 0;
      h.c.addListener(() => notifications++);
      h.motion.add(MotionState.moving);
      async.flushMicrotasks();

      expect(h.c.motionState, MotionState.moving,
          reason: 'diagnostic reflects motion even while paused');
      expect(notifications, 1,
          reason: 'paused stationary→moving must still refresh the diagnostic');
      expect(h.count(), 0, reason: 'disabled → never publishes');
      expect(h.c.isRunning, isFalse, reason: 'disabled → no timer armed');

      h.c.dispose();
      h.motion.close();
    });
  });
}
