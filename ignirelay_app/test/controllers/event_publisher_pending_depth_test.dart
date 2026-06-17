// UI-F4 — EventPublisher.pendingQueueDepth read-through.
//
// The 安全 tab CommunicationState reads the outbox depth via the EventPublisher
// facade (not the lower-level v2 facade directly). Verify the passthrough:
// 0 when no v2 facade is wired, and the facade's value when present.

import 'package:flutter_test/flutter_test.dart';
import 'package:ignirelay_app/app/controllers/event_publisher.dart';
import 'package:ignirelay_app/app/mesh/event_manager.dart';
import 'package:ignirelay_app/app/services/event_publisher_v2_facade.dart';
import 'package:ignirelay_app/app/services/peer_capability_registry.dart';

void main() {
  test('pendingQueueDepth is 0 when no v2 facade is wired', () {
    final ep = EventPublisher(eventManager: EventManager());
    expect(ep.pendingQueueDepth, 0);
  });

  test('pendingQueueDepth reads through to the v2 facade', () async {
    final registry = PeerCapabilityRegistry();
    final facade = EventPublisherV2Facade(registry: registry);
    addTearDown(() async {
      await facade.dispose();
      await registry.dispose();
    });
    final ep = EventPublisher(eventManager: EventManager(), v2Facade: facade);
    // Read-through, not a hardcoded literal: it tracks the facade's own depth.
    expect(ep.pendingQueueDepth, facade.pendingQueueDepth);
  });
}
