// A9 (3) — AdminBroadcastBanner widget test: a received directive renders as a
// top banner and auto-dismisses once past its `expires_at`. The receive→stream
// projection is covered by v2_inbound_projector_test; here we inject the typed
// stream + a fake clock so the prune is deterministic with no real time.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ignirelay_app/app/controllers/event_stream.dart';
import 'package:ignirelay_app/ui/shell/admin_broadcast_banner.dart';

void main() {
  test('AdminBroadcast.isExpired honours expiresAt', () {
    final now = DateTime(2026, 6, 15, 12, 0, 0);
    final noExpiry =
        AdminBroadcast(eventId: 'a', scope: 2, message: 'm', receivedAt: now);
    expect(noExpiry.isExpired(now.add(const Duration(days: 1))), isFalse);

    final withExpiry = AdminBroadcast(
      eventId: 'b',
      scope: 2,
      message: 'm',
      receivedAt: now,
      expiresAt: now.add(const Duration(minutes: 5)),
    );
    expect(withExpiry.isExpired(now), isFalse);
    expect(withExpiry.isExpired(now.add(const Duration(minutes: 6))), isTrue);
  });

  testWidgets('shows an active directive (no-expiry → no pending timer)',
      (tester) async {
    final ctrl = StreamController<AdminBroadcast>.broadcast();
    addTearDown(ctrl.close);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: AdminBroadcastBanner(source: ctrl.stream)),
    ));
    await tester.pump();

    ctrl.add(AdminBroadcast(
      eventId: 'x',
      scope: 2,
      message: '全網疏散：請往高處',
      receivedAt: DateTime.now(),
    ));
    await tester.pump(); // deliver the broadcast-stream event (microtask)
    await tester.pump(); // rebuild after setState

    expect(find.text('全網疏散：請往高處'), findsOneWidget);
    expect(find.text('全網公告'), findsOneWidget);
  });

  testWidgets('auto-dismisses a directive after its expires_at', (tester) async {
    var now = DateTime(2026, 6, 15, 12, 0, 0);
    final ctrl = StreamController<AdminBroadcast>.broadcast();
    addTearDown(ctrl.close);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AdminBroadcastBanner(
          source: ctrl.stream,
          now: () => now,
          pruneInterval: const Duration(seconds: 5),
        ),
      ),
    ));
    await tester.pump();

    ctrl.add(AdminBroadcast(
      eventId: 'y',
      scope: 1,
      message: '本場域集合',
      receivedAt: now,
      expiresAt: now.add(const Duration(seconds: 10)),
    ));
    await tester.pump(); // deliver the broadcast-stream event (microtask)
    await tester.pump(); // rebuild after setState
    expect(find.text('本場域集合'), findsOneWidget);

    // Advance past expiry and let the periodic prune fire → banner drops.
    now = now.add(const Duration(seconds: 20));
    await tester.pump(const Duration(seconds: 6));
    expect(find.text('本場域集合'), findsNothing);
  });
}
