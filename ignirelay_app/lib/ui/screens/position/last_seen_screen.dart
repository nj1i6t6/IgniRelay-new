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
import 'package:ignirelay_app/l10n/l10n_ext.dart';
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
    this.sosResolvedSource,
    this.presenceBackfill,
    this.checkpointBackfill,
    this.sosBackfill,
    this.sosResolvedBackfill,
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

  /// SOS 解除 stream（A8；投影自 STATUS_UPDATE safetyState=SAFE）。收到後把對應
  /// author（`sender_pub_key` hex）的 SOS entry 移除，位置頁不再顯示其 SOS 標籤。
  final Stream<SosResolved>? sosResolvedSource;

  /// Mount-backfill seams (A11-debug-4-fix). When omitted they default to the
  /// DI'd `EventStream` read-model queries (`recentPresence` / `recentCheckpoints`
  /// / `recentSos` / `recentSosResolutions`); tests inject. They feed the SAME
  /// handlers as the live streams (eventId dedup + author-LWW), so the position
  /// view is populated on mount instead of staying blank after a restart until
  /// the next live event.
  final Future<List<PresenceUpdate>> Function()? presenceBackfill;
  final Future<List<CheckpointCrossing>> Function()? checkpointBackfill;
  final Future<List<SosAlert>> Function()? sosBackfill;
  final Future<List<SosResolved>> Function()? sosResolvedBackfill;

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
  StreamSubscription<SosResolved>? _sosResolvedSub;
  Timer? _refresh;

  /// Mount-backfill loaders (A11-debug-4-fix), resolved once in [initState] from
  /// the widget seam or the DI'd `EventStream`.
  late final Future<List<PresenceUpdate>> Function() _presenceBackfill;
  late final Future<List<CheckpointCrossing>> Function() _checkpointBackfill;
  late final Future<List<SosAlert>> Function() _sosBackfill;
  late final Future<List<SosResolved>> Function() _sosResolvedBackfill;

  /// eventId dedup so a row arriving via BOTH the mount backfill and the live
  /// stream is applied once (A11-debug-4-fix). SOS resolutions are an idempotent
  /// remove and need no dedup.
  final Set<String> _seenPresence = <String>{};
  final Set<String> _seenCheckpoint = <String>{};
  final Set<String> _seenSos = <String>{};

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
    // Only reach for the DI'd EventStream when at least one stream OR backfill
    // seam is not injected (tests inject all seams and never touch the provider
    // tree).
    final needEvents = widget.presenceSource == null ||
        widget.checkpointSource == null ||
        widget.sosSource == null ||
        widget.sosResolvedSource == null ||
        widget.presenceBackfill == null ||
        widget.checkpointBackfill == null ||
        widget.sosBackfill == null ||
        widget.sosResolvedBackfill == null;
    final events = needEvents ? context.read<EventStream>() : null;
    _presenceSub =
        (widget.presenceSource ?? events!.presenceUpdates).listen(_onPresence);
    _checkpointSub = (widget.checkpointSource ?? events!.checkpointCrossings)
        .listen(_onCheckpoint);
    _sosSub = (widget.sosSource ?? events!.sosAlerts).listen(_onSos);
    _sosResolvedSub = (widget.sosResolvedSource ?? events!.sosResolutions)
        .listen(_onSosResolved);

    // Mount backfill loaders default to the EventStream read-model queries.
    _presenceBackfill =
        widget.presenceBackfill ?? () => events!.recentPresence();
    _checkpointBackfill =
        widget.checkpointBackfill ?? () => events!.recentCheckpoints();
    _sosBackfill = widget.sosBackfill ?? () => events!.recentSos();
    _sosResolvedBackfill =
        widget.sosResolvedBackfill ?? () => events!.recentSosResolutions();

    if (widget.refreshInterval > Duration.zero) {
      // Ages / confidence drift with wall time; refresh so the view stays honest.
      _refresh = Timer.periodic(widget.refreshInterval, (_) {
        if (mounted) setState(() {});
      });
    }

    unawaited(_hydrate());
  }

  /// One-shot mount backfill from the read-model (A11-debug-4-fix). Feeds rows
  /// through the SAME handlers as the live streams so the dedup / author-LWW
  /// rules are defined once. SOS alerts and SAFE resolutions are merged into a
  /// single timestamp-ordered timeline and replayed oldest→newest, so the
  /// author-LWW converges identically to live arrival order:
  ///   • old SOS + later SAFE → SOS cleared
  ///   • old SAFE + later SOS → SOS shown
  /// Best-effort: a backfill failure leaves the live streams working.
  Future<void> _hydrate() async {
    try {
      // Backfill arrives newest-first (queryByType orders hlc_timestamp DESC),
      // but _cap() trims each subject's observation list from the FRONT — which
      // for live events (appended oldest→newest) drops the oldest. Replay the
      // backfill oldest→newest too, else a subject with > _maxObsPerSubject rows
      // would have its FRESHEST fix capped away (A11-debug-4-polish). Sort by
      // observedAt (the authoritative observation time) rather than relying on
      // the DESC row order, which is keyed on hlc_timestamp.
      final presence = await _presenceBackfill();
      if (!mounted) return;
      final orderedPresence = [...presence]
        ..sort((a, b) => a.observedAt.compareTo(b.observedAt));
      for (final p in orderedPresence) {
        _onPresence(p);
      }
      final checkpoints = await _checkpointBackfill();
      if (!mounted) return;
      final orderedCheckpoints = [...checkpoints]
        ..sort((a, b) => a.observedAt.compareTo(b.observedAt));
      for (final c in orderedCheckpoints) {
        _onCheckpoint(c);
      }
      final sos = await _sosBackfill();
      final resolutions = await _sosResolvedBackfill();
      if (!mounted) return;
      final timeline = <_SosEvent>[
        for (final a in sos) _SosEvent(a.timestamp, alert: a),
        for (final r in resolutions) _SosEvent(r.timestamp, resolved: r),
      ]..sort(_SosEvent.compare);
      for (final e in timeline) {
        final alert = e.alert;
        final resolved = e.resolved;
        if (alert != null) {
          _onSos(alert);
        } else if (resolved != null) {
          _onSosResolved(resolved);
        }
      }
    } catch (_) {
      // Backfill is best-effort; the live streams still populate the view.
    }
  }

  @override
  void dispose() {
    _presenceSub?.cancel();
    _checkpointSub?.cancel();
    _sosSub?.cancel();
    _sosResolvedSub?.cancel();
    _refresh?.cancel();
    super.dispose();
  }

  void _onPresence(PresenceUpdate p) {
    if (!mounted || p.anon8.isEmpty) return;
    if (p.eventId.isNotEmpty && !_seenPresence.add(p.eventId)) return;
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
    if (c.eventId.isNotEmpty && !_seenCheckpoint.add(c.eventId)) return;
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
    if (a.eventId.isNotEmpty && !_seenSos.add(a.eventId)) return;
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

  /// SOS 解除（A8 / OD-8）：該 author 已回報「我安全了」。`authorKeyHex` 對應
  /// [_onSos] 以 `sender_pub_key` hex 建立的同一把 key，故直接移除其 SOS entry，
  /// 位置頁的列表 / 雷達不再顯示該 SOS。未知 author（空 hex）不動任何項。
  void _onSosResolved(SosResolved r) {
    if (!mounted || r.authorKeyHex.isEmpty) return;
    if (!_sos.containsKey(r.authorKeyHex)) return;
    setState(() {
      _sos.remove(r.authorKeyHex);
      _sosLabel.remove(r.authorKeyHex);
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
            IgniSubPageHeader(
              title: context.l10n.lastSeenTitle,
              subtitle: context.l10n.lastSeenSubtitle,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: IgniSpacing.lg),
              child: _viewToggle(p, radarActive: origin != null),
            ),
            if (showHint)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    IgniSpacing.lg, IgniSpacing.md, IgniSpacing.lg, 0),
                child: _hintBanner(p, context.l10n.lastSeenNeedLocalPosition),
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
    final l = context.l10n;
    return Row(
      children: [
        _togglePill(p, l.lastSeenToggleList, !radarActive, _selectList),
        const SizedBox(width: IgniSpacing.sm),
        _togglePill(p, l.lastSeenToggleRadar, radarActive, _selectRadar),
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
        context.l10n.lastSeenEmpty,
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
              // UI-H3: bound the handle + SOS chip so the confidence chip never
              // gets pushed off the right edge under large text (the handle
              // ellipsizes instead).
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: MonoText(e.label,
                          fontSize: 13,
                          color: p.text0,
                          fontWeight: FontWeight.w600,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ),
                    if (e.baseTone == StatusTone.sos) ...[
                      const SizedBox(width: IgniSpacing.sm),
                      const StatusChip(
                          label: 'SOS', tone: StatusTone.sos, dense: true),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: IgniSpacing.sm),
              _confidenceChip(est.confidence),
            ],
          ),
          const SizedBox(height: IgniSpacing.sm),
          Text(context.l10n.lastSeenTitle,
              style: IgniTypography.sectionHeader(p.text2)),
          const SizedBox(height: 2),
          MonoText(_whereText(est), fontSize: 13, color: p.text1),
          const SizedBox(height: IgniSpacing.sm),
          // UI-H3: age + uncertainty wrap to a second line at large text rather
          // than overflowing the row.
          Wrap(
            spacing: IgniSpacing.md,
            runSpacing: IgniSpacing.xs,
            children: [
              _meta(p, _ageText(est.ageSeconds)),
              _meta(p, context.l10n.lastSeenUncertainty(est.uncertaintyM.round())),
            ],
          ),
        ],
      ),
    );
  }

  Widget _meta(IgniPalette p, String text) =>
      Text(text, style: IgniTypography.bodySmall(p.text2));

  Widget _confidenceChip(PositionConfidence c) {
    final l = context.l10n;
    switch (c) {
      case PositionConfidence.high:
        return StatusChip(
            label: l.confidenceHigh, tone: StatusTone.ok, dense: true);
      case PositionConfidence.medium:
        return StatusChip(
            label: l.confidenceMedium, tone: StatusTone.warn, dense: true);
      case PositionConfidence.low:
        return StatusChip(
            label: l.confidenceLow, tone: StatusTone.neutral, dense: true);
    }
  }

  String _whereText(PositionEstimate est) {
    if (est.hasLatLng) {
      return '${est.lat!.toStringAsFixed(5)}, ${est.lng!.toStringAsFixed(5)}';
    }
    if (est.anchorNodeId != null) {
      final dist = est.distanceM != null ? ' · ~${est.distanceM!.round()} m' : '';
      return '${context.l10n.lastSeenAnchor(est.anchorNodeId!)}$dist';
    }
    return context.l10n.noCoordinateParen;
  }

  String _ageText(int seconds) {
    final l = context.l10n;
    if (seconds < 60) return l.timeAgoSeconds(seconds);
    final mins = seconds ~/ 60;
    if (mins < 60) return l.timeAgoMinutes(mins);
    final hours = mins ~/ 60;
    return l.timeAgoHours(hours);
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

/// One item on the merged SOS/SAFE mount-backfill timeline (A11-debug-4-fix).
/// Exactly one of [alert] / [resolved] is set. Sorted oldest→newest; on an exact
/// timestamp tie a resolution is applied AFTER an alert (kind 1 > 0) so a
/// same-instant SAFE still clears its SOS (the terminal state wins the tie).
class _SosEvent {
  _SosEvent(this.ts, {this.alert, this.resolved});
  final DateTime ts;
  final SosAlert? alert;
  final SosResolved? resolved;
  int get _kind => resolved != null ? 1 : 0;
  static int compare(_SosEvent a, _SosEvent b) {
    final c = a.ts.compareTo(b.ts);
    return c != 0 ? c : a._kind - b._kind;
  }
}
