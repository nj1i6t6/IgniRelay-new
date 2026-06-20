// A9 (2) — CheckpointCard widget test: the kDebugMode manual-publish path
// (button → checkpoint_id dialog → publish) routes through CheckpointController
// → EventPublisherV2Facade and queues (no peer in the harness). The receive→
// checkpointCrossings projection is covered by v2_inbound_projector_test.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:ignirelay_app/app/controllers/active_field_controller.dart';
import 'package:ignirelay_app/app/controllers/checkpoint_controller.dart';
import 'package:ignirelay_app/app/controllers/event_stream.dart';
import 'package:ignirelay_app/app/db/database_helper.dart';
import 'package:ignirelay_app/app/mesh/mesh_event_handler.dart';
import 'package:ignirelay_app/app/services/anon_identity.dart';
import 'package:ignirelay_app/app/services/event_decoder.dart';
import 'package:ignirelay_app/app/services/event_publisher_v2_facade.dart';
import 'package:ignirelay_app/app/services/event_store.dart';
import 'package:ignirelay_app/app/services/field_session_store.dart';
import 'package:ignirelay_app/app/services/location_evidence_builder.dart';
import 'package:ignirelay_app/app/services/peer_capability_registry.dart';
import 'package:ignirelay_app/l10n/generated/app_localizations.dart';
import 'package:ignirelay_app/ui/shell/checkpoint_card.dart';

class _Kv implements SecureKvStore {
  final Map<String, String> _m = {};
  @override
  Future<String?> read(String k) async => _m[k];
  @override
  Future<void> write(String k, String v) async => _m[k] = v;
  @override
  Future<void> delete(String k) async => _m.remove(k);
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    DatabaseHelper.testDatabasePathOverride = inMemoryDatabasePath;
  });

  setUp(() async {
    await DatabaseHelper().resetForTest();
  });

  Future<({EventPublisherV2Facade facade, Widget tree})> harness(
      {Locale locale = const Locale('zh')}) async {
    final registry = PeerCapabilityRegistry();
    final facade = EventPublisherV2Facade(registry: registry);
    final field = ActiveFieldController(
      store: FieldSessionStore(db: DatabaseHelper(), secureStore: _Kv()),
    );
    await field.joinBySecret(
      Uint8List.fromList(List<int>.filled(32, 0x6C)),
      displayName: 'f',
    );
    facade.attachActiveField(field);
    final checkpoint = CheckpointController(
      facade: facade,
      anonIdentity: AnonIdentityService(store: _Kv()),
      locationBuilder: LocationEvidenceBuilder(currentLocation: () => null),
    );
    final events = EventStream(
      handler: MeshEventHandler(),
      decoder: EventDecoder(),
      store: EventStore(databaseHelper: DatabaseHelper()),
    );
    addTearDown(() async {
      await events.dispose();
      await facade.dispose();
      await registry.dispose();
      field.dispose();
    });
    final tree = MultiProvider(
      providers: [
        Provider<EventStream>.value(value: events),
        Provider<CheckpointController>.value(value: checkpoint),
      ],
      child: MaterialApp(
        locale: locale,
        supportedLocales: S.supportedLocales,
        localizationsDelegates: S.localizationsDelegates,
        home: const Scaffold(body: CheckpointCard()),
      ),
    );
    return (facade: facade, tree: tree);
  }

  testWidgets('renders the card + empty state', (tester) async {
    final h = await harness();
    await tester.pumpWidget(h.tree);
    await tester.pump();

    expect(find.text('CHECKPOINT（點名通過）'), findsOneWidget);
    expect(find.text('手動 CHECKPOINT'), findsOneWidget); // kDebugMode is true in tests
    expect(find.textContaining('尚無 CHECKPOINT'), findsOneWidget);
  });

  testWidgets('manual button → dialog → publish queues to the active field',
      (tester) async {
    final h = await harness();
    await tester.pumpWidget(h.tree);
    await tester.pump();

    await tester.tap(find.text('手動 CHECKPOINT'));
    await tester.pumpAndSettle(); // dialog opens

    expect(find.text('checkpoint_id'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'gate-3');
    await tester.tap(find.text('送出'));
    await tester.pump(); // dialog closes + publish runs
    await tester.pump(const Duration(milliseconds: 50));

    // Active field + no peer → queued in the facade's pending queue.
    expect(h.facade.pendingQueueDepth, 1);
    expect(find.textContaining('佇列'), findsOneWidget);
  });

  testWidgets('en: card + empty state render English (UI-H2c)', (tester) async {
    final h = await harness(locale: const Locale('en'));
    await tester.pumpWidget(h.tree);
    await tester.pump();

    expect(find.text('CHECKPOINT (roll-call)'), findsOneWidget);
    expect(find.text('Manual CHECKPOINT'), findsOneWidget);
    expect(find.textContaining('no CHECKPOINT yet'), findsOneWidget);
    expect(find.text('CHECKPOINT（點名通過）'), findsNothing);
  });
}
