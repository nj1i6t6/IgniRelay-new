// HazardCard — A11-prep. Debug-shell surface for typed HAZARD send + receive.
//
// Mirrors `CheckpointCard` (A9-2): self-contained, reads its own providers
// (`EventPublisher` to send, the typed `EventStream.hazardEvents` to receive)
// and owns its subscription, so the mapless `DebugShell` stays under the
// 500-line facade cap. A3 only wired the typed RECEIVE side; the send UI
// retired with the old map screen, which blocked the two-phone acceptance
// (A11 step 5). This card restores a send entry behind `kDebugMode`.
//
// The MANUAL publish button is `kDebugMode`-only: in v0.3 a hazard send is a
// debug stand-in. Coordinates come from the device's OWN `LocalPositionSource`
// (never a peer — same rule as the A10b radar origin); with no GPS fix it falls
// back to a clearly-marked sample coordinate so the send still rides the wire
// for acceptance. The received-hazard list always renders (read-model display
// is fine in release).
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
import 'package:ignirelay_app/app/services/position_estimator.dart';

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

/// Debug fallback coordinate used only when the device has no GPS fix, so the
/// acceptance send still produces a typed HAZARD on the wire. Marked in the
/// snackbar so the operator knows it is not a real location.
const double _kSampleLat = 25.0339;
const double _kSampleLng = 121.5645;

class HazardCard extends StatefulWidget {
  const HazardCard({
    super.key,
    this.hazardSource,
    this.onPublish,
    this.localEstimate,
  });

  /// Typed received-HAZARD stream. Defaults to `EventStream.hazardEvents`.
  final Stream<HazardEvent>? hazardSource;

  /// Publish seam. Defaults to `EventPublisher.publishHazard`.
  final HazardPublisher? onPublish;

  /// The device's own position (for the send coordinate). Defaults to
  /// `LocalPositionSource.currentEstimate`.
  final PositionEstimate? Function()? localEstimate;

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
    String type = 'FIRE';
    final descCtl = TextEditingController(text: '測試危害（debug）');
    return showDialog<_HazardDraft>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('手動 HAZARD（debug）'),
        content: StatefulBuilder(
          builder: (ctx, setLocal) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButton<String>(
                isExpanded: true,
                value: type,
                items: const [
                  DropdownMenuItem(value: 'FIRE', child: Text('火災 FIRE')),
                  DropdownMenuItem(value: 'FLOOD', child: Text('淹水 FLOOD')),
                  DropdownMenuItem(
                      value: 'COLLAPSE', child: Text('倒塌 COLLAPSE')),
                  DropdownMenuItem(
                      value: 'CHEMICAL', child: Text('化學 CHEMICAL')),
                  DropdownMenuItem(
                      value: 'ROADBLOCK', child: Text('路阻 ROADBLOCK')),
                  DropdownMenuItem(value: 'OTHER', child: Text('其他 OTHER')),
                ],
                onChanged: (v) => setLocal(() => type = v ?? 'FIRE'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: descCtl,
                decoration: const InputDecoration(
                  labelText: '描述（≤800B）',
                  isDense: true,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(ctx).pop(_HazardDraft(type, descCtl.text.trim())),
            child: const Text('送出'),
          ),
        ],
      ),
    );
  }

  Future<void> _promptAndPublish() async {
    final draft = await _promptDraft();
    if (draft == null) return;
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      final est = _origin();
      final hasFix = est != null && est.lat != null && est.lng != null;
      final lat = hasFix ? est.lat! : _kSampleLat;
      final lng = hasFix ? est.lng! : _kSampleLng;
      final id = await _publish(
        type: draft.type,
        severity: 2,
        lat: lat,
        lng: lng,
        description: draft.description,
      );
      if (!mounted) return;
      final short = id.length <= 8 ? id : id.substring(0, 8);
      final note = hasFix ? '' : '（無 GPS，用樣本座標）';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            'HAZARD「${draft.type}」已送出（id $short）$note · 需已加入場域才會實際廣播'),
      ));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('HAZARD 送出失敗: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Text('危害（HAZARD）',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const Spacer(),
              // 手動按鈕：debug-only 占位（真實流程綁 Field Node / 危害回報 UI）。
              if (kDebugMode)
                FilledButton.tonalIcon(
                  onPressed: _busy ? null : _promptAndPublish,
                  icon: const Icon(Icons.warning_amber, size: 18),
                  label: const Text('手動 HAZARD'),
                ),
            ]),
            const SizedBox(height: 4),
            const Text(
              '收到的 typed HAZARD 事件（A3 接收側）。手動送出為 debug 占位'
              '（座標取本機 GPS，無則用樣本）。',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            if (_hazards.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('（尚無 HAZARD）', style: TextStyle(color: Colors.grey)),
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
