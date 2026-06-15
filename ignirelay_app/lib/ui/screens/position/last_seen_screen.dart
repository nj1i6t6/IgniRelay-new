// LastSeenScreen — A10. Mapless "last trusted position" card list.
//
// Spec / design: MASTER_EXECUTION_PLAN §5 A10; REBUILD_PLAN §3.6 (mapless
// 位置證據). One card per subject (keyed by anon8, shared by PRESENCE +
// CHECKPOINT — the anon_user_id space), showing the fused [PositionEstimate]:
// 最後可信位置 / 相對年齡 / 可信度 / 誤差半徑.
//
// HARD RULES:
//   • Copy says 「最後可信位置 / 推估」, NEVER 「目前位置」 (§3.6 principle 5 /
//     DESIGN_LANGUAGE §4.5).
//   • Confidence/uncertainty are derived live by [PositionEstimator] from
//     evidence age — never read from or written to wire/DB (A10 prohibition).
//   • DESIGN_LANGUAGE §4: all colour via `context.igni` + Igni widgets; no raw
//     Material colour constants / hex (this screen is under lib/ui/screens/ and
//     subject to the §6 grep gate).
//
// Layer rules: imports only app/controllers (EventStream + its plain-Dart
// PresenceUpdate / CheckpointCrossing) and app/services (PositionEstimator) —
// no app/proto/mesh/db.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:ignirelay_app/app/controllers/event_stream.dart';
import 'package:ignirelay_app/app/services/position_estimator.dart';
import 'package:ignirelay_app/ui/theme/igni_colors.dart';
import 'package:ignirelay_app/ui/theme/igni_tokens.dart';
import 'package:ignirelay_app/ui/theme/igni_typography.dart';
import 'package:ignirelay_app/ui/widgets/igni_card.dart';
import 'package:ignirelay_app/ui/widgets/igni_sub_page_header.dart';
import 'package:ignirelay_app/ui/widgets/mono_text.dart';
import 'package:ignirelay_app/ui/widgets/status_chip.dart';

class LastSeenScreen extends StatefulWidget {
  const LastSeenScreen({
    super.key,
    this.presenceSource,
    this.checkpointSource,
    this.now,
    this.refreshInterval = const Duration(seconds: 30),
  });

  /// Test seams — override the typed `EventStream` streams + wall clock. The
  /// periodic age-refresh timer is disabled when [refreshInterval] is zero.
  final Stream<PresenceUpdate>? presenceSource;
  final Stream<CheckpointCrossing>? checkpointSource;
  final DateTime Function()? now;
  final Duration refreshInterval;

  @override
  State<LastSeenScreen> createState() => _LastSeenScreenState();
}

class _LastSeenScreenState extends State<LastSeenScreen> {
  static const int _maxObsPerSubject = 12;

  StreamSubscription<PresenceUpdate>? _presenceSub;
  StreamSubscription<CheckpointCrossing>? _checkpointSub;
  Timer? _refresh;

  /// anon8 → recent observations (newest appended). Estimate is derived on the
  /// fly in build(); we keep raw evidence, never a persisted estimate.
  final Map<String, List<PositionObservation>> _byAnon = {};

  DateTime _nowFn() => (widget.now ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    final events =
        (widget.presenceSource == null || widget.checkpointSource == null)
            ? context.read<EventStream>()
            : null;
    _presenceSub = (widget.presenceSource ?? events!.presenceUpdates)
        .listen(_onPresence);
    _checkpointSub = (widget.checkpointSource ?? events!.checkpointCrossings)
        .listen(_onCheckpoint);
    if (widget.refreshInterval > Duration.zero) {
      // Ages / confidence drift with wall time; refresh so the cards stay honest.
      _refresh = Timer.periodic(widget.refreshInterval, (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _presenceSub?.cancel();
    _checkpointSub?.cancel();
    _refresh?.cancel();
    super.dispose();
  }

  void _onPresence(PresenceUpdate p) {
    if (!mounted || p.anon8.isEmpty) return;
    _add(
      p.anon8,
      PositionObservation(
        lat: p.lat,
        lng: p.lng,
        accuracyM: p.accuracyM ?? 0,
        source: p.source,
        observedAt: p.observedAt,
      ),
    );
  }

  void _onCheckpoint(CheckpointCrossing c) {
    if (!mounted || c.anon8.isEmpty) return;
    _add(
      c.anon8,
      PositionObservation(
        lat: c.lat,
        lng: c.lng,
        anchorNodeId: c.checkpointId.isEmpty ? null : c.checkpointId,
        observedAt: c.observedAt,
      ),
    );
  }

  void _add(String anon8, PositionObservation obs) {
    setState(() {
      final list = _byAnon.putIfAbsent(anon8, () => <PositionObservation>[]);
      list.add(obs);
      if (list.length > _maxObsPerSubject) {
        list.removeRange(0, list.length - _maxObsPerSubject);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.igni;
    final now = _nowFn();

    // Build one estimate per subject, newest-first by evidence age.
    final entries = <({String anon8, PositionEstimate est})>[];
    for (final e in _byAnon.entries) {
      final est = PositionEstimator.estimate(e.value, now: now);
      if (est != null) entries.add((anon8: e.key, est: est));
    }
    entries.sort((a, b) => a.est.ageSeconds.compareTo(b.est.ageSeconds));

    return Scaffold(
      backgroundColor: p.bg0,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: IgniSpacing.xl3),
          children: [
            const IgniSubPageHeader(
              title: '最後可信位置',
              subtitle: '依足跡 / 點名通過推估，非即時定位',
            ),
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: IgniSpacing.lg),
              child: entries.isEmpty
                  ? _emptyState(p)
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final e in entries)
                          Padding(
                            padding:
                                const EdgeInsets.only(bottom: IgniSpacing.md),
                            child: _estimateCard(p, e.anon8, e.est),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyState(IgniPalette p) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: IgniSpacing.xl2),
      child: Text(
        '尚無位置證據 — 收到足跡（PRESENCE）或點名通過（CHECKPOINT）後，這裡會列出每人的最後可信位置。',
        style: IgniTypography.bodySmall(p.text2),
      ),
    );
  }

  Widget _estimateCard(IgniPalette p, String anon8, PositionEstimate est) {
    return IgniCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              MonoText(anon8, fontSize: 13, color: p.text0,
                  fontWeight: FontWeight.w600),
              const Spacer(),
              _confidenceChip(est.confidence),
            ],
          ),
          const SizedBox(height: IgniSpacing.sm),
          Text('最後可信位置', style: IgniTypography.sectionHeader(p.text2)),
          const SizedBox(height: 2),
          MonoText(_whereText(est), fontSize: 13, color: p.text1),
          const SizedBox(height: IgniSpacing.sm),
          Row(
            children: [
              _meta(p, _ageText(est.ageSeconds)),
              const SizedBox(width: IgniSpacing.md),
              _meta(p, '誤差 ~${est.uncertaintyM.round()} m'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _meta(IgniPalette p, String text) =>
      Text(text, style: IgniTypography.bodySmall(p.text2));

  Widget _confidenceChip(PositionConfidence c) {
    switch (c) {
      case PositionConfidence.high:
        return const StatusChip(label: '可信度 高', tone: StatusTone.ok, dense: true);
      case PositionConfidence.medium:
        return const StatusChip(
            label: '可信度 中', tone: StatusTone.warn, dense: true);
      case PositionConfidence.low:
        return const StatusChip(
            label: '可信度 低', tone: StatusTone.neutral, dense: true);
    }
  }

  String _whereText(PositionEstimate est) {
    if (est.hasLatLng) {
      return '${est.lat!.toStringAsFixed(5)}, ${est.lng!.toStringAsFixed(5)}';
    }
    if (est.anchorNodeId != null) {
      final dist = est.distanceM != null ? ' · ~${est.distanceM!.round()} m' : '';
      return '錨點 ${est.anchorNodeId}$dist';
    }
    return '（無座標）';
  }

  String _ageText(int seconds) {
    if (seconds < 60) return '$seconds 秒前';
    final mins = seconds ~/ 60;
    if (mins < 60) return '$mins 分鐘前';
    final hours = mins ~/ 60;
    return '$hours 小時前';
  }
}
