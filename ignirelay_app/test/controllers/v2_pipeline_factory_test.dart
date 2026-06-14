// A5 (4-7) 施工筆記 5 — production-config guard. Pins that the dispatcher
// `main.dart` builds via createProductionDispatcherV2 has the field-scope +
// field-mac membership check (§21.6) ON, so it can't be silently flipped off.

import 'package:flutter_test/flutter_test.dart';
import 'package:ignirelay_app/app/controllers/v2_pipeline_factory.dart';
import 'package:ignirelay_app/app/db/database_helper.dart';
import 'package:ignirelay_app/app/services/author_rate_limiter.dart';
import 'package:ignirelay_app/app/services/envelope_store_v2.dart';
import 'package:ignirelay_app/app/services/field_key_store.dart';
import 'package:ignirelay_app/app/services/mesh_trace_writer.dart';

void main() {
  test('production dispatcher pins field-scope + strict-drop flags ON', () {
    final db = DatabaseHelper();
    final dispatcher = createProductionDispatcherV2(
      store: EnvelopeStoreV2(db),
      trace: MeshTraceWriter(db),
      rateLimiter: AuthorRateLimiter(),
      fieldKeys: FieldKeyStore.empty(),
    );
    addTearDown(dispatcher.dispose);

    expect(dispatcher.isFieldScopeCheckEnabled, isTrue,
        reason: 'A5 DoD D1 — field-scope must not be flipped off in production');
    expect(dispatcher.isClockBasedExpiryEnabled, isTrue);
    expect(dispatcher.isMaxHopsOvercommitEnabled, isTrue);
  });
}
