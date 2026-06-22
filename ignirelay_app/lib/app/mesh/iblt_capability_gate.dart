// IBLT-fix — capability gate predicate.
//
// Bridges the v2 PeerCapabilityRegistry (which records each peer's
// PROTOCOL_HELLO) to the legacy BleManager IBLT fast-path decision. A node
// attempts the IBLT fast path only when the peer advertised the
// `iblt-keyhash-v2` peel contract; otherwise it uses the Bloom slow path, so a
// new (v2-contract) build never attempts a v2 peel against an old
// (v1-contract) peer. Extracted as a pure function so main.dart's wiring and
// the unit test share one source of truth (no inline-closure drift).

import 'package:ignirelay_app/app/mesh/iblt.dart';
import 'package:ignirelay_app/app/services/peer_capability_registry.dart';

/// True iff [deviceId]'s recorded HELLO advertises [IBLT.keyHashContractV2].
/// A peer with no registry entry, no accepted HELLO, or no matching capability
/// (incl. one still mid-handshake) → false → caller uses the Bloom slow path.
bool peerSupportsIbltKeyHashV2(
  PeerCapabilityRegistry registry,
  String deviceId,
) {
  final caps = registry.stateFor(deviceId)?.hello?.capabilities;
  return caps != null && caps.contains(IBLT.keyHashContractV2);
}
