// BleEmergencyMeshDelivery — A11-latency-fix production hook.
//
// Bridges the v2 publish facade's [EmergencyMeshDelivery] abstraction to the
// legacy [BleManager] Central scanner/connector. When an SOS / SAFE has to
// queue because no peer is ready, the facade calls [requestEmergencyConnect],
// which asks BleManager to bypass the per-peer cooldown for a short window and
// reconnect immediately — so the facade's EXISTING queue drain sends the
// already-enqueued envelope within seconds instead of waiting for the next
// gossip cycle.
//
// Lives in the mesh layer because it touches the BLE connection layer; the
// facade depends only on the [EmergencyMeshDelivery] abstraction and the UI
// never sees either. Wired at the app root (`main.dart`).

import 'package:ignirelay_app/app/mesh/ble_manager.dart';
import 'package:ignirelay_app/app/services/event_publisher_v2_facade.dart';

class BleEmergencyMeshDelivery implements EmergencyMeshDelivery {
  /// [bleManager] defaults to the process-wide [BleManager] singleton — the
  /// same instance the transport adapter scans/connects with — so the
  /// emergency request acts on the live connection state. Injectable for tests.
  BleEmergencyMeshDelivery([BleManager? bleManager])
      : _ble = bleManager ?? BleManager();

  final BleManager _ble;

  @override
  void requestEmergencyConnect() => _ble.requestEmergencyConnect();
}
