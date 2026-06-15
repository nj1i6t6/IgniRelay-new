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
// ignore: depend_on_referenced_packages
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ignirelay_app/app/controllers/presence_beacon_controller.dart';

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
}
