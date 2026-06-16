// LastSeenScreen — A10 / A10b. Mapless "last trusted position" surface, with a
// 列表 (card list, A10) ⇄ 雷達 (relative-position radar, A10b) toggle.
//
// Spec / design: MASTER_EXECUTION_PLAN §5 A10 + A10b; REBUILD_PLAN §3.6 (mapless
// 位置證據). One subject per row/dot:
//   • people  — keyed by anon8 (PRESENCE + CHECKPOINT share the anon_user_id
//     space), shown ok / stale.
//   • SOS      — keyed by sender_pub_key (a DIFFERENT identity space; we do NOT
//     fabricate a link to an anon8), shown sos. SOS alerts carry their own
//     lat/lng, so they ride the radar as red dots and head the list.
// Each subject's fused [PositionEstimate] is derived on the fly from raw
// evidence (confidence/uncertainty by age) — never persisted (A10 prohibition).
//
// HARD RULES:
//   • Copy says 「最後可信位置 / 推估」, NEVER 「目前位置」 (§3.6 principle 5 /
//     DESIGN_LANGUAGE §4.5) — applies to the radar too (dots are projections of
//     the last trusted position).
//   • The radar ORIGIN ("me") is the device's own GPS fix via [LocalPositionSource]
//     — never guessed from a peer's beacon. No local fix → the radar degrades to
//     the list with a "需要本機位置" hint (A10b step 1).
//   • DESIGN_LANGUAGE §4: all colour via `context.igni` + Igni widgets; no raw
//     Material colour constants / hex (this screen is under lib/ui/screens/,
//     §6 grep gate).
//
// Layer rules: imports only app/controllers (EventStream + its plain-Dart
// projections) and app/services (PositionEstimator / RelativePositionProjector /
// LocalPositionSource) — no app/proto/mesh/db.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:ignirelay_app/app/controllers/event_stream.dart';
import 'package:ignirelay_app/app/services/local_position_source.dart';
import 'package:ignirelay_app/app/services/position_estimator.dart';
import 'package:ignirelay_app/ui/screens/position/relative_radar.dart';
import 'package:ignirelay_app/ui/theme/igni_colors.dart';
import 'package:ignirelay_app/ui/theme/igni_tokens.dart';
import 'package:ignirelay_app/ui/theme/igni_typography.dart';
import 'package:ignirelay_app/ui/widgets/igni_card.dart';
import 'package:ignirelay_app/ui/widgets/igni_sub_page_header.dart';
import 'package:ignirelay_app/ui/widgets/mono_text.dart';
import 'package:ignirelay_app/ui/widgets/status_chip.dart';

enum _ViewMode { list, radar }

class LastSeenScreen extends StatefulWidget {
  const LastSeenScreen({
    super.key,
    this.presenceSource,
    this.checkpointSource,
    this.sosSource,
    this.localEstimate,
    this.now,
    this.refreshInterval = const Duration(seconds: 30),
  });

  /// Test seams — override the typed `EventStream` streams, the local-position
  /// origin, and the wall clock. The periodic age-refresh timer is disabled when
  /// [refreshInterval] is zero.
  final Stream<PresenceUpdate>? presenceSource;
  final Stream<CheckpointCrossing>? checkpointSource;
  final Stream<SosAlert>? sosSource;

  /// The device's own [PositionEstimate] (radar origin). When omitted it is read
  /// from the DI'd [LocalPositionSource]. Returning null = "no local position".
  final PositionEstimate? Function()? localEstimate;

  final DateTime Function()? now;
  final Duration refreshInterval;

  @override
  State<LastSeenScreen> createState() => _LastSeenScreenState();
}

class _LastSeenScreenState extends State<LastSeenScreen> {
  static const int _maxObsPerSubject = 12;

  StreamSubscription<PresenceUpdate>? _presenceSub;
  StreamSubscription<CheckpointCrossing>? _checkpointSub;
  StreamSubscription<SosAlert>? _sosSub;
  Timer? _refresh;

  /// The view the user picked. The radar only *shows* while a local origin
  /// exists — if it is/becomes null the build derives the degrade state, so a
  /// position lost mid-radar falls back to the list (and auto-recovers).
  _ViewMode _mode = _ViewMode.list;

  /// anon8 → recent observations (people; PRESENCE + CHECKPOINT).
  final Map<String, List<PositionObservation>> _byAnon = {};

  /// SOS key (sender_pub_key hex, or eventId fallback) → recent observations.
  final Map<String, List<PositionObservation>> _sos = {};
  final Map<String, String> _sosLabel = {};

  DateTime _nowFn() => (widget.now ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    // Only reach for the DI'd EventStream when at least one source is not
    // injected (tests inject all three and never touch the provider tree).
    final needEvents = widget.presenceSource == null ||
        widget.checkpointSource == null ||
        widget.sosSource == null;
    final events = needEvents ? context.read<EventStream>() : null;
    _presenceSub =
        (widget.presenceSource ?? events!.presenceUpdates).listen(_onPresence);
    _checkpointSub = (widget.checkpointSource ?? events!.checkpointCrossings)
        .listen(_onCheckpoint);
    _sosSub = (widget.sosSource ?? events!.sosAlerts).listen(_onSos);
    if (widget.refreshInterval > Duration.zero) {
      // Ages / confidence drift with wall time; refresh so the view stays honest.
      _refresh = Timer.periodic(widget.refreshInterval, (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _presenceSub?.cancel();
    _checkpointSub?.cancel();
    _sosSub?.cancel();
    _refresh?.cancel();
    super.dispose();
  }

  void _onPresence(PresenceUpdate p) {
    if (!mounted || p.anon8.isEmpty) return;
    _addPerson(
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
    _addPerson(
      c.anon8,
      PositionObservation(
        lat: c.lat,
        lng: c.lng,
        anchorNodeId: c.checkpointId.isEmpty ? null : c.checkpointId,
        observedAt: c.observedAt,
      ),
    );
  }

  void _onSos(SosAlert a) {
    if (!mounted) return;
    final key = (a.senderPubKey != null && a.senderPubKey!.isNotEmpty)
        ? _hex(a.senderPubKey!)
        : 'evt:${a.eventId}';
    _sosLabel[key] = key.startsWith('evt:')
        ? a.eventId
        : key.substring(0, key.length < 8 ? key.length : 8);
    setState(() {
      final list = _sos.putIfAbsent(key, () => <PositionObservation>[]);
      list.add(PositionObservation(
        lat: a.lat,
        lng: a.lng,
        observedAt: a.timestamp,
      ));
      _cap(list);
    });
  }

  void _addPerson(String anon8, PositionObservation obs) {
    setState(() {
      final list = _byAnon.putIfAbsent(anon8, () => <PositionObservation>[]);
      list.add(obs);
      _cap(list);
    });
  }

  void _cap(List<PositionObservation> list) {
    if (list.length > _maxObsPerSubject) {
      list.removeRange(0, list.length - _maxObsPerSubject);
    }
  }

  PositionEstimate? _origin() {
    final seam = widget.localEstimate;
    if (seam != null) return seam();
    return context.read<LocalPositionSource>().currentEstimate();
  }

  /// Build every subject's fused estimate, SOS first then freshest-first.
  List<_Entry> _entries(DateTime now) {
    final out = <_Entry>[];
    for (final e in _sos.entries) {
      final est = PositionEstimator.estimate(e.value, now: now);
      if (est != null) {
        out.add(_Entry(e.key, _sosLabel[e.key] ?? e.key, est, StatusTone.sos));
      }
    }
    for (final e in _byAnon.entries) {
      final est = PositionEstimator.estimate(e.value, now: now);
      if (est != null) out.add(_Entry(e.key, e.key, est, StatusTone.ok));
    }
    out.sort((a, b) {
      final sa = a.baseTone == StatusTone.sos ? 0 : 1;
      final sb = b.baseTone == StatusTone.sos ? 0 : 1;
      if (sa != sb) return sa - sb;
      return a.est.ageSeconds.compareTo(b.est.ageSeconds);
    });
    return out;
  }

  void _selectList() => setState(() => _mode = _ViewMode.list);

  // Selecting the radar only records intent; build() decides whether it can
  // actually show (needs a local origin) or must degrade to the list + hint.
  void _selectRadar() => setState(() => _mode = _ViewMode.radar);

  /// Radar dot tap → open the subject's A10 card (§5 A10b step 2) in a sheet.
  void _showSubjectCard(String key) {
    final now = _nowFn();
    _Entry? entry;
    for (final e in _entries(now)) {
      if (e.key == key) {
        entry = e;
        break;
      }
    }
    if (entry == null) return;
    final picked = entry;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.igni.bg1,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: IgniRadii.xl),
      ),
      builder: (sheetCtx) => Padding(
        padding: const EdgeInsets.fromLTRB(
            IgniSpacing.lg, IgniSpacing.lg, IgniSpacing.lg, IgniSpacing.xl2),
        child: _estimateCard(sheetCtx.igni, picked),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.igni;
    final now = _nowFn();
    final entries = _entries(now);

    final radarRequested = _mode == _ViewMode.radar;
    final origin = radarRequested ? _origin() : null;
    // Radar is active only with a local origin; a missing/lost origin while in
    // radar mode degrades to the list with a hint (A10b step 1; covers the case
    // where the origin goes null AFTER entering the radar).
    final showHint = radarRequested && origin == null;

    return Scaffold(
      backgroundColor: p.bg0,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const IgniSubPageHeader(
              title: '最後可信位置',
              subtitle: '依足跡 / 點名通過推估，非即時定位',
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: IgniSpacing.lg),
              child: _viewToggle(p, radarActive: origin != null),
            ),
            if (showHint)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    IgniSpacing.lg, IgniSpacing.md, IgniSpacing.lg, 0),
                child: _hintBanner(p, '需要本機位置才能顯示相對方位'),
              ),
            const SizedBox(height: IgniSpacing.md),
            Expanded(
              child: origin != null
                  ? RelativeRadar(
                      origin: origin,
                      subjects: [
                        for (final e in entries)
                          RadarSubject(
                            key: e.key,
                            label: e.label,
                            estimate: e.est,
                            baseTone: e.baseTone,
                            // Anchor-derived fixes (CHECKPOINT / Field Node) draw
                            // as a triangle; SOS stays a circle (§5 A10b step 2).
                            isNode: e.baseTone != StatusTone.sos &&
                                e.est.anchorNodeId != null,
                          ),
                      ],
                      onTapSubject: _showSubjectCard,
                    )
                  : _listView(p, entries),
            ),
          ],
        ),
      ),
    );
  }

  Widget _viewToggle(IgniPalette p, {required bool radarActive}) {
    return Row(
      children: [
        _togglePill(p, '列表', !radarActive, _selectList),
        const SizedBox(width: IgniSpacing.sm),
        _togglePill(p, '雷達', radarActive, _selectRadar),
      ],
    );
  }

  Widget _togglePill(
      IgniPalette p, String label, bool selected, VoidCallback onTap) {
    return Material(
      color: selected ? p.brandSoft : p.bg2,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.all(IgniRadii.pill),
        side: BorderSide(color: selected ? p.brandBorder : p.border0),
      ),
      child: InkWell(
        borderRadius: const BorderRadius.all(IgniRadii.pill),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: IgniSpacing.lg, vertical: IgniSpacing.sm),
          child: Text(
            label,
            style: IgniTypography.labelLarge(selected ? p.brand : p.text2),
          ),
        ),
      ),
    );
  }

  Widget _hintBanner(IgniPalette p, String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(IgniSpacing.md),
      decoration: BoxDecoration(
        color: p.warnSoft,
        borderRadius: const BorderRadius.all(IgniRadii.md),
        border: Border.all(color: p.warn.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(Icons.my_location, size: 18, color: p.warn),
          const SizedBox(width: IgniSpacing.sm),
          Expanded(
            child: Text(text, style: IgniTypography.bodySmall(p.text1)),
          ),
        ],
      ),
    );
  }

  Widget _listView(IgniPalette p, List<_Entry> entries) {
    if (entries.isEmpty) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(
            IgniSpacing.lg, 0, IgniSpacing.lg, IgniSpacing.xl3),
        children: [_emptyState(p)],
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
          IgniSpacing.lg, 0, IgniSpacing.lg, IgniSpacing.xl3),
      itemCount: entries.length,
      separatorBuilder: (_, __) => const SizedBox(height: IgniSpacing.md),
      itemBuilder: (_, i) => _estimateCard(p, entries[i]),
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

  Widget _estimateCard(IgniPalette p, _Entry e) {
    final est = e.est;
    return IgniCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              MonoText(e.label,
                  fontSize: 13, color: p.text0, fontWeight: FontWeight.w600),
              if (e.baseTone == StatusTone.sos) ...[
                const SizedBox(width: IgniSpacing.sm),
                const StatusChip(label: 'SOS', tone: StatusTone.sos, dense: true),
              ],
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

  static String _hex(List<int> bytes) {
    final sb = StringBuffer();
    for (final b in bytes) {
      sb.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }
}

/// One rendered subject: its fused estimate + base semantic tone.
class _Entry {
  _Entry(this.key, this.label, this.est, this.baseTone);
  final String key;
  final String label;
  final PositionEstimate est;
  final StatusTone baseTone;
}
