// UI-F5b — NativeBridge.parseMotionMagnitude + NativeMotionSource idempotency.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ignirelay_app/app/services/motion/native_motion_source.dart';
import 'package:ignirelay_app/platform/native_bridge.dart';

void main() {
  group('parseMotionMagnitude', () {
    test('valid motion map → double', () {
      expect(
        NativeBridge.parseMotionMagnitude(
            {'type': 'motion', 'magnitude': 9.81}),
        closeTo(9.81, 1e-9),
      );
    });

    test('int magnitude coerced to double', () {
      expect(
        NativeBridge.parseMotionMagnitude({'type': 'motion', 'magnitude': 10}),
        10.0,
      );
    });

    test('non-motion / non-map / missing / bad / null → null', () {
      expect(NativeBridge.parseMotionMagnitude({'type': 'handoff_result'}),
          isNull);
      expect(NativeBridge.parseMotionMagnitude(<int>[1, 2, 3]), isNull);
      expect(NativeBridge.parseMotionMagnitude({'type': 'motion'}), isNull);
      expect(
          NativeBridge.parseMotionMagnitude(
              {'type': 'motion', 'magnitude': 'x'}),
          isNull);
      expect(NativeBridge.parseMotionMagnitude(null), isNull);
    });
  });

  group('NativeMotionSource lifecycle (idempotent — Owner boundary 6)', () {
    test('start() twice invokes the channel start once; stop() once', () async {
      var starts = 0;
      var stops = 0;
      final src = NativeMotionSource(
        start: () async {
          starts++;
          return true;
        },
        stop: () async {
          stops++;
        },
        magnitudes: const Stream<double>.empty(),
      );
      await src.start();
      await src.start();
      expect(starts, 1, reason: 'idempotent start — no double register');
      await src.stop();
      await src.stop();
      expect(stops, 1, reason: 'idempotent stop');
    });

    test('stop() before start() is a safe no-op', () async {
      var stops = 0;
      final src = NativeMotionSource(
        start: () async => true,
        stop: () async {
          stops++;
        },
        magnitudes: const Stream<double>.empty(),
      );
      await src.stop();
      expect(stops, 0);
    });

    test('magnitudes forwards the injected stream', () async {
      final ctl = StreamController<double>();
      final src = NativeMotionSource(
        start: () async => true,
        stop: () async {},
        magnitudes: ctl.stream,
      );
      final seen = <double>[];
      final sub = src.magnitudes.listen(seen.add);
      ctl.add(1.0);
      ctl.add(2.0);
      await Future<void>.delayed(Duration.zero);
      expect(seen, <double>[1.0, 2.0]);
      await sub.cancel();
      await ctl.close();
    });
  });
}
