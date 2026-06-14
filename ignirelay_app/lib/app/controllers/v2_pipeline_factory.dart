// v0.3 production receive-pipeline factory (A5 / 4-7, 施工筆記 5).
//
// Single chokepoint where `main.dart` builds the production
// `EnvelopeDispatcherV2`. Extracted so a unit test can PIN the config — in
// particular that the field-scope + field-mac membership check (spec §21.6) is
// ON and cannot be silently flipped off (A5 DoD D1 + prohibition: "為了測試
// 方便把 enableFieldScopeCheck 在 production 留 OFF").
//
// main.dart MUST build the production dispatcher through this factory.

import 'package:ignirelay_app/app/controllers/envelope_dispatcher_v2.dart';
import 'package:ignirelay_app/app/services/author_rate_limiter.dart';
import 'package:ignirelay_app/app/services/envelope_store_v2.dart';
import 'package:ignirelay_app/app/services/field_key_store.dart';
import 'package:ignirelay_app/app/services/mesh_trace_writer.dart';

/// Build the v0.3 receive dispatcher with the PRODUCTION flag set. [fieldKeys]
/// is the live, mutable membership store shared (by reference) with
/// `ActiveFieldController` so runtime joins / leaves reach the receive side.
EnvelopeDispatcherV2 createProductionDispatcherV2({
  required EnvelopeStoreV2 store,
  required MeshTraceWriter trace,
  required AuthorRateLimiter rateLimiter,
  required FieldKeyStore fieldKeys,
  Future<DateTime> Function()? now,
}) {
  return EnvelopeDispatcherV2(
    store: store,
    trace: trace,
    rateLimiter: rateLimiter,
    now: now,
    // PRODUCTION FLAGS — do NOT flip off (A5 DoD D1 / 施工筆記 5):
    //   • clock-based expiry + max-hops overcommit: spec-strict drops (3E).
    //   • field-scope check ON + real FieldKeyStore: §21.6 membership enforced.
    enableClockBasedExpiry: true,
    enableMaxHopsOvercommit: true,
    enableFieldScopeCheck: true,
    fieldKeys: fieldKeys,
  );
}
