// AdminBroadcastBanner — A9 (3). Top-of-screen banner for received
// ADMIN_BROADCAST authority directives, with auto-dismiss by `expires_at`.
//
// Self-contained (lives in lib/ui/shell/, like CheckpointCard) so the mapless
// `DebugShell` stays under the 500-line facade cap. It subscribes to the typed
// `EventStream.adminBroadcasts` (receive) and renders one banner per active
// (non-expired) directive. Distinct directives coexist (spec §10.2 — not LWW).
//
// AUTO-DISMISS: each directive carries an `expiresAt`; a prune timer (armed ONLY
// while at least one directive has an expiry) drops expired ones. When no
// directive is active the timer is cancelled — so an idle banner leaves no
// pending timer (important for widget tests).
//
// PUBLISH BACK-DOOR: a `kDebugMode`-only button sends a test directive via
// `EventPublisherV2Facade.publishAdminBroadcast`. The A9 prohibition is that NO
// admin publish entry may appear in a RELEASE build — `DebugShell` ships as the
// release home, so the entry MUST be `kDebugMode`-gated. The facade read is lazy
// (button handler only), so the receive path needs no facade provider.
//
// Layer rules: imports only app/controllers + app/services facades (no
// app/proto/mesh/db). `AdminBroadcast` is a plain Dart type; scope is an int
// mapped to a label locally.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:ignirelay_app/app/controllers/event_stream.dart';
import 'package:ignirelay_app/app/services/event_publisher_v2_facade.dart';
import 'package:ignirelay_app/l10n/generated/app_localizations.dart';
import 'package:ignirelay_app/l10n/l10n_ext.dart';

class AdminBroadcastBanner extends StatefulWidget {
  const AdminBroadcastBanner({
    super.key,
    this.source,
    this.now,
    this.pruneInterval = const Duration(seconds: 10),
  });

  /// Test seam — overrides `EventStream.adminBroadcasts` when provided.
  final Stream<AdminBroadcast>? source;

  /// Test seam — overrides the wall clock used for expiry checks.
  final DateTime Function()? now;

  /// How often expired directives are pruned (while any has an expiry).
  final Duration pruneInterval;

  @override
  State<AdminBroadcastBanner> createState() => _AdminBroadcastBannerState();
}

class _AdminBroadcastBannerState extends State<AdminBroadcastBanner> {
  StreamSubscription<AdminBroadcast>? _sub;
  Timer? _pruneTimer;
  final List<AdminBroadcast> _active = <AdminBroadcast>[];

  DateTime _nowFn() => (widget.now ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    final source = widget.source ?? context.read<EventStream>().adminBroadcasts;
    _sub = source.listen(_onBroadcast);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _pruneTimer?.cancel();
    super.dispose();
  }

  void _onBroadcast(AdminBroadcast b) {
    if (!mounted) return;
    if (b.isExpired(_nowFn())) return; // already stale on arrival
    setState(() {
      _active.removeWhere((e) => e.eventId == b.eventId); // dedup on resend
      _active.insert(0, b);
    });
    _ensurePruneTimer();
  }

  void _ensurePruneTimer() {
    final needsTimer = _active.any((e) => e.expiresAt != null);
    if (needsTimer) {
      _pruneTimer ??= Timer.periodic(widget.pruneInterval, (_) => _prune());
    } else {
      _pruneTimer?.cancel();
      _pruneTimer = null;
    }
  }

  void _prune() {
    final now = _nowFn();
    final before = _active.length;
    _active.removeWhere((e) => e.isExpired(now));
    if (_active.length != before && mounted) setState(() {});
    _ensurePruneTimer(); // cancels the timer once nothing has an expiry left
  }

  Future<void> _publishTest() async {
    final facade = context.read<EventPublisherV2Facade>();
    final messenger = ScaffoldMessenger.of(context);
    final l = context.l10n;
    try {
      final outcome = await facade.publishAdminBroadcast(
        message: l.adminTestMessage(
            DateTime.now().toIso8601String().substring(11, 19)),
        ttl: const Duration(minutes: 10),
      );
      final String msg;
      if (outcome.noField) {
        msg = l.adminNoField;
      } else if (outcome.anyAccepted) {
        msg = l.adminSent(outcome.attempted);
      } else if (outcome.queued) {
        msg = l.adminQueued(outcome.pendingDepth);
      } else {
        msg = l.adminAttempted(outcome.attempted);
      }
      messenger.showSnackBar(SnackBar(content: Text(msg)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(l.adminSendFailed('$e'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = _nowFn();
    final visible =
        _active.where((b) => !b.isExpired(now)).toList(growable: false);
    if (visible.isEmpty && !kDebugMode) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ...visible.map(_bannerCard),
          if (kDebugMode)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _publishTest,
                icon: const Icon(Icons.campaign, size: 18),
                label: Text(context.l10n.adminPublishTest),
              ),
            ),
        ],
      ),
    );
  }

  Widget _bannerCard(AdminBroadcast b) {
    final l = context.l10n;
    return Card(
      color: Colors.amber.shade100,
      margin: const EdgeInsets.only(bottom: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.campaign, color: Colors.amber.shade900, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Text(_scopeLabel(l, b.scope),
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.amber.shade900)),
                    if (b.expiresAt != null) ...[
                      const Spacer(),
                      Text(
                          l.adminExpiry(
                              b.expiresAt!.toIso8601String().substring(11, 16)),
                          style:
                              const TextStyle(fontSize: 11, color: Colors.black54)),
                    ],
                  ]),
                  const SizedBox(height: 2),
                  Text(b.message,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // AdminScope.* → label（UI-H2c 經 l10n）。UI 不 import app/proto，故以本地數值對照。
  static String _scopeLabel(S l, int scope) {
    switch (scope) {
      case 1:
        return l.adminScopeField;
      case 2:
        return l.adminScopeAll;
      default:
        return l.adminScopeDefault;
    }
  }
}
