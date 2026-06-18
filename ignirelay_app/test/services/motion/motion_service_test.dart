// UI-F5b — MotionService: wires a source to the classifier; idempotent lifecycle.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ignirelay_app/app/services/motion/motion_service.dart';
import 'package:ignirelay_app/app/services/motion/motion_source.dart';
import 'package:ignirelay_app/app/services/motion/motion_state.dart';

class _FakeSource implements MotionSource {
  final StreamController<double> ctl = StreamController<double>.broadcast();
  int starts = 0;
  int stops = 0;

  @override
  Stream<double> get magnitudes => ctl.stream;

  @override
  Future<void> start() async => starts++;

  @override
  Future<void> stop() async => stops++;
}

void main() {
  late DateTime t;
  late _FakeSource source;
  late MotionService service;

  setUp(() {
    t = DateTime(2026, 1, 1, 0, 0, 0);
    source = _FakeSource();
    service = MotionService(source: source, now: () => t);
  });

  Future<void> pump() => Future<void>.delayed(Duration.zero);

  // Feed one quiet window through the source, then a trailing sample (after
  // advancing the clock) so the just-filled window is finalized & classified.
  Future<void> quietWindow() async {
    for (var i = 0; i < 20; i++) {
      source.ctl.add(9.8);
    }
    await pump();
    t = t.add(const Duration(seconds: 8));
    source.ctl.add(9.8);
    await pump();
  }

  test('start() twice → source started once; stop() idempotent', () async {
    await service.start();
    await service.start();
    expect(source.starts, 1, reason: 'idempotent start');
    await service.stop();
    await service.stop();
    expect(source.stops, 1, reason: 'idempotent stop');
    await service.dispose();
  });

  test('stop() before start() is safe; start/stop/start resumes', () async {
    await service.stop();
    expect(source.stops, 0);
    await service.start();
    await service.stop();
    await service.start();
    expect(source.starts, 2, reason: 'resume re-subscribes + re-starts source');
    await service.dispose();
  });

  test('source magnitudes drive the classifier → stateChanges emits stationary',
      () async {
    final seen = <MotionState>[];
    final sub = service.stateChanges.listen(seen.add);
    await service.start();
    for (var i = 0; i < 9; i++) {
      await quietWindow();
    }
    expect(service.state, MotionState.stationary);
    expect(seen, contains(MotionState.stationary));
    await sub.cancel();
    await service.dispose();
  });

  test('dispose stops the source and closes stateChanges (no leak)', () async {
    await service.start();
    final done = expectLater(service.stateChanges, emitsDone);
    await service.dispose();
    await done;
    expect(source.stops, 1);
  });
}
