// UI-F4 — CommunicationState pure-builder + presence-counts predicate tests.
//
// communication_state.dart is pure (no widgets / no app imports) so the
// best-path derivation, the honest cloud copy, and Owner req 1's
// "only a real send stamps presence" rule are all unit-testable directly.

import 'package:flutter_test/flutter_test.dart';
import 'package:ignirelay_app/ui/shell/tabs/communication_state.dart';

CommunicationState _state({
  bool hasField = true,
  bool meshRunning = true,
  int peers = 0,
  int sent = 0,
  int received = 0,
  int outbox = 0,
  DateTime? lastPresenceAt,
  bool cloudConfigured = false,
}) =>
    CommunicationState.from(
      hasField: hasField,
      meshRunning: meshRunning,
      peers: peers,
      sentCount: sent,
      receivedCount: received,
      outboxDepth: outbox,
      lastPresenceAt: lastPresenceAt,
      cloudConfigured: cloudConfigured,
    );

void main() {
  group('best-path matrix', () {
    test('no field → noField', () {
      final s = _state(hasField: false, meshRunning: true, peers: 3);
      expect(s.bestPath, CommsPath.noField);
      expect(s.bestPathLabel, '尚未加入場域');
    });

    test('field but mesh off → offline (regardless of stale peers)', () {
      final s = _state(meshRunning: false, peers: 5);
      expect(s.bestPath, CommsPath.offline);
      expect(s.bestPathLabel, '離線（近距離通訊未開啟）');
    });

    test('mesh on, no peers → waitingPeers', () {
      final s = _state(meshRunning: true, peers: 0);
      expect(s.bestPath, CommsPath.waitingPeers);
      expect(s.bestPathLabel, '等待鄰近裝置…');
    });

    test('mesh on, peers > 0 → meshRelay', () {
      final s = _state(meshRunning: true, peers: 2);
      expect(s.bestPath, CommsPath.meshRelay);
      expect(s.bestPathLabel, '近距離網狀傳遞');
    });
  });

  group('cloud copy is honest (Stage A never reachable)', () {
    test('not configured → 離線', () {
      expect(_state(cloudConfigured: false).cloudLabel, '雲端：離線');
    });

    test('configured → 已設定（尚未啟用）, never "已連線"/"可達"', () {
      final label = _state(cloudConfigured: true).cloudLabel;
      expect(label, '雲端：已設定（尚未啟用）');
      expect(label.contains('已連線'), isFalse);
      expect(label.contains('可達'), isFalse);
    });
  });

  test('outbox depth and lastPresence pass through unchanged', () {
    final t = DateTime(2026, 6, 17, 9, 30, 0);
    final s = _state(outbox: 4, lastPresenceAt: t, sent: 7, received: 9, peers: 1);
    expect(s.outboxDepth, 4);
    expect(s.lastPresenceAt, t);
    expect(s.sentCount, 7);
    expect(s.receivedCount, 9);
    expect(s.peers, 1);
  });

  group('presenceCountsAsSent (Owner req 1)', () {
    test('accepted → true', () {
      expect(presenceCountsAsSent(anyAccepted: true, queued: false), isTrue);
    });
    test('queued → true', () {
      expect(presenceCountsAsSent(anyAccepted: false, queued: true), isTrue);
    });
    test('neither accepted nor queued (noField / attempted-only / fail) → false',
        () {
      expect(presenceCountsAsSent(anyAccepted: false, queued: false), isFalse);
    });
  });
}
