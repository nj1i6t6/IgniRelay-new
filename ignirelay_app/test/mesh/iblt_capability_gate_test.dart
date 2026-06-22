// IBLT-fix — capability gate predicate test.
//
// The legacy BleManager IBLT fast path is gated on the peer advertising the
// `iblt-keyhash-v2` HELLO capability (else Bloom slow path). This pins the pure
// predicate main.dart wires into BleManager.ibltContractCheck.

import 'package:flutter_test/flutter_test.dart';
import 'package:ignirelay_app/app/mesh/iblt.dart';
import 'package:ignirelay_app/app/mesh/iblt_capability_gate.dart';
import 'package:ignirelay_app/app/proto/event_envelope_v2.dart';
import 'package:ignirelay_app/app/services/peer_capability_registry.dart';

ProtocolHelloData _hello({required List<String> capabilities}) =>
    ProtocolHelloData(
      peerKind: PeerKind.phoneV1,
      maxRxEnvelopeBytes: 2048,
      supportsChunking: true,
      supportsIblt: true,
      supportsBloomV2: true,
      minNegotiatedMtu: 185,
      capabilities: capabilities,
      bgState: BgState.foreground,
    );

void _markActive(
  PeerCapabilityRegistry registry,
  String peerId, {
  required List<String> capabilities,
}) {
  registry.onPeerReadyForHello(peerId);
  registry.onHelloAccepted(peerId, _hello(capabilities: capabilities).encode());
}

void main() {
  group('IBLT-fix capability gate', () {
    test('peer advertising iblt-keyhash-v2 → fast path allowed', () {
      final r = PeerCapabilityRegistry();
      addTearDown(r.dispose);
      _markActive(r, 'CAP:01', capabilities: const [IBLT.keyHashContractV2]);
      expect(peerSupportsIbltKeyHashV2(r, 'CAP:01'), isTrue);
    });

    test('peer with no capabilities → Bloom (gate false)', () {
      final r = PeerCapabilityRegistry();
      addTearDown(r.dispose);
      _markActive(r, 'CAP:02', capabilities: const <String>[]);
      expect(peerSupportsIbltKeyHashV2(r, 'CAP:02'), isFalse);
    });

    test('peer advertising a DIFFERENT capability → Bloom (gate false)', () {
      final r = PeerCapabilityRegistry();
      addTearDown(r.dispose);
      _markActive(r, 'CAP:03', capabilities: const ['some-other-cap']);
      expect(peerSupportsIbltKeyHashV2(r, 'CAP:03'), isFalse);
    });

    test('unknown peer (no registry entry) → Bloom (gate false)', () {
      final r = PeerCapabilityRegistry();
      addTearDown(r.dispose);
      expect(peerSupportsIbltKeyHashV2(r, 'NOPE:99'), isFalse);
    });

    test('peer still mid-handshake (pending, no HELLO) → Bloom (gate false)',
        () {
      final r = PeerCapabilityRegistry();
      addTearDown(r.dispose);
      // Trigger fired but HELLO not yet accepted → status pending, hello null.
      r.onPeerReadyForHello('CAP:04');
      expect(peerSupportsIbltKeyHashV2(r, 'CAP:04'), isFalse);
    });
  });
}
