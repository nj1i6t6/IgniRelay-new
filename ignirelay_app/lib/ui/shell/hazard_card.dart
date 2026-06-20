// HazardCard — A11-prep. Debug-shell surface for typed HAZARD send + receive.
//
// Mirrors `CheckpointCard` (A9-2): self-contained, reads its own providers
// (`EventPublisher` to send, the typed `EventStream.hazardEvents` to receive)
// and owns its subscription, so the mapless `DebugShell` stays under the
// 500-line facade cap. A3 only wired the typed RECEIVE side; the send UI
// retired with the old map screen, which blocked the two-phone acceptance
// (A11 step 5). This card restores a send entry behind `kDebugMode`.
//
// The MANUAL publish button: `formalSend` shows it in production (participant +
// owner); otherwise it is a `kDebugMode`-only debug stand-in. Coordinates come
// from the device's OWN `LocalPositionSource` (never a peer — same rule as the
// A10b radar origin).
//
// UI-F5b-polish / Owner rule — NO fake/sample/default coordinate in ANY runtime
// path (production OR the debug shell). BOTH the formal entry and the kDebugMode
// stand-in refuse to publish without a real fix — they show a "需要位置" prompt
// instead. The FORMAL path additionally takes ONE bounded fresh GPS fix first
// (§4.2 manual event). Coordinate-positive tests inject a real estimate through
// the `localEstimate` seam; there is no built-in sample coordinate. The received-
// hazard list always renders (read-model display is fine in release).
//
// Layer rules: lives in lib/ui/shell/, imports only app/controllers +
// app/services facades (no app/proto/mesh/db). `HazardEvent` is a plain Dart
// type. Test seams (`hazardSource` / `onPublish` / `localEstimate`) mirror the
// `LastSeenScreen` injection pattern so no providers are needed under test.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:ignirelay_app/app/controllers/event_publisher.dart';
import 'package:ignirelay_app/app/controllers/event_stream.dart';
import 'package:ignirelay_app/app/services/local_position_source.dart';
import 'package:ignirelay_app/app/services/location_refresh_coordinator.dart';
import 'package:ignirelay_app/app/services/position_estimator.dart';
import 'package:ignirelay_app/l10n/l10n_ext.dart';

/// Publish seam matching `EventPublisher.publishHazard`. A tear-off of that
/// method is assignable here (the optional named params carry their defaults on
/// the method, not on this function type).
typedef HazardPublisher = Future<String> Function({
  required String type,
  required int severity,
  required double lat,
  required double lng,
  double radiusMeters,
  String description,
});

class HazardCard extends StatefulWidget {
  const HazardCard({
    super.key,
    this.hazardSource,
    this.onPublish,
    this.localEstimate,
    this.ensureFreshLocation,
    this.formalSend = false,
  });

  /// When true, the manual send action is shown in **production** (not just
  /// `kDebugMode`) with product copy — this is the formal HAZARD report entry
  /// for the 事件 tab (UI-F2; participant+owner may send, per UI-F0 §4.0.1 F0-5).
  /// `DebugShell` leaves this `false`, keeping the original kDebugMode-only debug
  /// stand-in unchanged. No wire change either way (same `publishHazard`).
  final bool formalSend;

  /// Typed received-HAZARD stream. Defaults to `EventStream.hazardEvents`.
  final Stream<HazardEvent>? hazardSource;

  /// Publish seam. Defaults to `EventPublisher.publishHazard`.
  final HazardPublisher? onPublish;

  /// The device's own position (for the send coordinate). Defaults to
  /// `LocalPositionSource.currentEstimate`.
  final PositionEstimate? Function()? localEstimate;

  /// Bounded fresh-GPS hook for the FORMAL path (§4.2 manual event). Defaults to
  /// `LocationRefreshCoordinator.ensureFreshForManualEvent(timeout: 2s)`, read
  /// lazily at send time (so the debug `DebugShell` path, which never calls it,
  /// does not require the coordinator provider).
  final Future<void> Function()? ensureFreshLocation;

  @override
  State<HazardCard> createState() => _HazardCardState();
}

class _HazardCardState extends State<HazardCard> {
  late final Stream<HazardEvent> _hazardStream;
  late final HazardPublisher _publish;
  late final PositionEstimate? Function() _origin;
  StreamSubscription<HazardEvent>? _sub;

  final List<HazardEvent> _hazards = <HazardEvent>[];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _hazardStream =
        widget.hazardSource ?? context.read<EventStream>().hazardEvents;
    _publish = widget.onPublish ?? context.read<EventPublisher>().publishHazard;
    final seam = widget.localEstimate;
    _origin = seam ?? context.read<LocalPositionSource>().currentEstimate;
    _sub = _hazardStream.listen((h) {
      if (!mounted) return;
      setState(() {
        // 最近在前；以 eventId 去重重送（HAZARD 非 LWW，每筆獨立保留）。
        _hazards.removeWhere((e) => e.eventId == h.eventId);
        _hazards.insert(0, h);
        if (_hazards.length > 20) {
          _hazards.removeRange(20, _hazards.length);
        }
      });
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<_HazardDraft?> _promptDraft() {
    final l = context.l10n;
    String type = 'FIRE';
    final descCtl = TextEditingController(
        text: widget.formalSend ? '' : l.hazardCardDebugSampleDesc);
    return showDialog<_HazardDraft>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(widget.formalSend
            ? l.hazardCardReport
            : l.hazardCardManualDebugTitle),
        content: StatefulBuilder(
          builder: (ctx, setLocal) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButton<String>(
                isExpanded: true,
                value: type,
                items: [
                  DropdownMenuItem(
                      value: 'FIRE', child: Text(l.hazardCardTypeFire)),
                  DropdownMenuItem(
                      value: 'FLOOD', child: Text(l.hazardCardTypeFlood)),
                  DropdownMenuItem(
                      value: 'COLLAPSE', child: Text(l.hazardCardTypeCollapse)),
                  DropdownMenuItem(
                      value: 'CHEMICAL', child: Text(l.hazardCardTypeChemical)),
                  DropdownMenuItem(
                      value: 'ROADBLOCK', child: Text(l.hazardCardTypeRoadblock)),
                  DropdownMenuItem(
                      value: 'OTHER', child: Text(l.hazardCardTypeOther)),
                ],
                onChanged: (v) => setLocal(() => type = v ?? 'FIRE'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: descCtl,
                decoration: InputDecoration(
                  labelText: l.hazardCardDescLabel,
                  isDense: true,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l.commonCancel),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(ctx).pop(_HazardDraft(type, descCtl.text.trim())),
            child: Text(l.commonSend),
          ),
        ],
      ),
    );
  }

  Future<void> _promptAndPublish() async {
    final l = context.l10n;
    final draft = await _promptDraft();
    if (draft == null) return;
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      // FORMAL path: take ONE bounded fresh fix first (§4.2 manual event). Never
      // throws / never blocks past its timeout.
      if (widget.formalSend) {
        final fresh = widget.ensureFreshLocation ??
            () => context
                .read<LocationRefreshCoordinator>()
                .ensureFreshForManualEvent(
                    timeout: const Duration(seconds: 2));
        try {
          await fresh();
        } catch (_) {/* best-effort */}
        if (!mounted) return;
      }

      // Owner rule (UI-F5b-polish): NO fake/sample/default coordinate in ANY
      // runtime path — production OR debug shell. Without a real fix we do NOT
      // publish a mis-located hazard; prompt for location instead (both paths).
      final est = _origin();
      final double? lat = est?.lat;
      final double? lng = est?.lng;
      if (lat == null || lng == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l.hazardCardNoLocation)));
        return;
      }

      final id = await _publish(
        type: draft.type,
        severity: 2,
        lat: lat,
        lng: lng,
        description: draft.description,
      );
      if (!mounted) return;
      final short = id.length <= 8 ? id : id.substring(0, 8);
      final msg = widget.formalSend
          ? l.hazardCardSentFormal(draft.type)
          : l.hazardCardSentDebug(draft.type, short);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l.hazardCardSendFailed('$e'))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              // UI-H3-polish: bound the title (ellipsizes) and make the action a
              // Flexible button with an ellipsizing label, so a long title + a
              // button whose padding scales with text size cannot overflow under
              // the ~2.0 composite (the action icon + tap target stay reachable).
              Expanded(
                child: Text(
                    widget.formalSend
                        ? l.hazardCardTitleFormal
                        : l.hazardCardTitleDebug,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
              ),
              // formalSend → 正式回報入口（production，participant+owner）。
              // 否則 kDebugMode-only debug 占位（DebugShell 沿用）。
              if (widget.formalSend || kDebugMode) ...[
                const SizedBox(width: 8),
                Flexible(
                  child: FilledButton.tonalIcon(
                    onPressed: _busy ? null : _promptAndPublish,
                    icon: const Icon(Icons.warning_amber, size: 18),
                    label: Text(
                        widget.formalSend
                            ? l.hazardCardReport
                            : l.hazardCardManualDebug,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ),
                ),
              ],
            ]),
            const SizedBox(height: 4),
            Text(
              widget.formalSend ? l.hazardCardBodyFormal : l.hazardCardBodyDebug,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            if (_hazards.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(l.hazardCardEmpty,
                    style: const TextStyle(color: Colors.grey)),
              )
            else
              ..._hazards.map(_hazardRow),
          ],
        ),
      ),
    );
  }

  Widget _hazardRow(HazardEvent h) {
    final where = '${h.lat.toStringAsFixed(5)}, ${h.lng.toStringAsFixed(5)}';
    final tail = h.description.isEmpty ? '' : ' · ${h.description}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        SizedBox(
          width: 90,
          child: Text(h.type.isEmpty ? '—' : h.type,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text('sev ${h.severity} · $where$tail',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12)),
        ),
      ]),
    );
  }
}

class _HazardDraft {
  final String type;
  final String description;
  const _HazardDraft(this.type, this.description);
}
