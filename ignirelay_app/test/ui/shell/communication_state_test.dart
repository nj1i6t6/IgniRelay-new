// UI-F4 / UI-H2c — CommunicationState pure-builder + presence-counts predicate
// tests.
//
// communication_state.dart is pure (no widgets / no app / no l10n imports) so
// the best-path derivation and Owner req 1's "only a real send stamps presence"
// rule are unit-testable directly. UI-H2c moved the best-path / cloud *display
// copy* out of this pure file to the SafetyTab render seam (enum/bool → l10n);
// the Stage A "cloud is never reachable" honesty invariant is now asserted at the
// l10n layer (both locales) below.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ignirelay_app/l10n/generated/app_localizations.dart';
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
  group('best-path matrix (enum derivation; copy lives at the SafetyTab seam)',
      () {
    test('no field → noField', () {
      final s = _state(hasField: false, meshRunning: true, peers: 3);
      expect(s.bestPath, CommsPath.noField);
    });

    test('field but mesh off → offline (regardless of stale peers)', () {
      final s = _state(meshRunning: false, peers: 5);
      expect(s.bestPath, CommsPath.offline);
    });

    test('mesh on, no peers → waitingPeers', () {
      final s = _state(meshRunning: true, peers: 0);
      expect(s.bestPath, CommsPath.waitingPeers);
    });

    test('mesh on, peers > 0 → meshRelay', () {
      final s = _state(meshRunning: true, peers: 2);
      expect(s.bestPath, CommsPath.meshRelay);
    });

    test('cloudConfigured passes through unchanged', () {
      expect(_state(cloudConfigured: false).cloudConfigured, isFalse);
      expect(_state(cloudConfigured: true).cloudConfigured, isTrue);
    });
  });

  // UI-H2c — the Stage A "cloud is configured-only, never reachable/connected"
  // honesty rule moved from the pure getter to the ARB; assert it at the l10n
  // layer in BOTH locales so neither cloud string can ever claim connectivity.
  group('cloud copy is honest in every locale (Stage A never reachable)', () {
    for (final loc in const [Locale('zh'), Locale('en')]) {
      test('${loc.languageCode}: neither cloud string claims reachable/connected',
          () {
        final l = lookupS(loc);
        for (final s in [l.cloudOffline, l.cloudConfigured]) {
          expect(s.contains('已連線'), isFalse, reason: s);
          expect(s.contains('可達'), isFalse, reason: s);
          expect(s.toLowerCase().contains('connected'), isFalse, reason: s);
          expect(s.toLowerCase().contains('reachable'), isFalse, reason: s);
        }
      });
    }

    test('configured copy still signals "not active yet"', () {
      expect(lookupS(const Locale('zh')).cloudConfigured, contains('尚未啟用'));
      expect(
          lookupS(const Locale('en')).cloudConfigured.toLowerCase(),
          contains('not active'));
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
