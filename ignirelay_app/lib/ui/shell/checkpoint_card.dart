// CheckpointCard — A9 (2). Debug-shell surface for CHECKPOINT roll-call.
//
// Self-contained so the mapless `DebugShell` stays under the 500-line facade
// cap: it reads its own providers (`CheckpointController` to publish, the typed
// `EventStream.checkpointCrossings` to receive) and owns its subscription.
//
// The MANUAL publish button is `kDebugMode`-only: in v0.3 a crossing is a debug
// stand-in (enter a checkpoint_id by hand); the real flow binds to a Field Node
// QR / physical contact in Stage D. The received-crossings list always renders
// (read-model display is fine in release).
//
// Layer rules: lives in lib/ui/shell/, imports only app/controllers facades
// (no app/proto/mesh/db). `CheckpointCrossing` is a plain Dart type.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:ignirelay_app/app/controllers/checkpoint_controller.dart';
import 'package:ignirelay_app/app/controllers/event_stream.dart';
import 'package:ignirelay_app/l10n/l10n_ext.dart';

class CheckpointCard extends StatefulWidget {
  const CheckpointCard({super.key});

  @override
  State<CheckpointCard> createState() => _CheckpointCardState();
}

class _CheckpointCardState extends State<CheckpointCard> {
  late final EventStream _events;
  late final CheckpointController _checkpoint;
  StreamSubscription<CheckpointCrossing>? _sub;

  final List<CheckpointCrossing> _crossings = <CheckpointCrossing>[];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _events = context.read<EventStream>();
    _checkpoint = context.read<CheckpointController>();
    _sub = _events.checkpointCrossings.listen((c) {
      if (!mounted) return;
      setState(() {
        // 最近在前；CHECKPOINT 非 LWW，每筆都保留（以 eventId 去重重送）。
        _crossings.removeWhere((e) => e.eventId == c.eventId);
        _crossings.insert(0, c);
        if (_crossings.length > 20) {
          _crossings.removeRange(20, _crossings.length);
        }
      });
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _promptAndPublish() async {
    final l = context.l10n;
    final controller = TextEditingController(text: 'CP-');
    final id = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.checkpointCardManual),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            labelText: 'checkpoint_id',
            hintText: l.checkpointCardIdHint,
          ),
          onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: Text(l.commonSend),
          ),
        ],
      ),
    );
    if (id == null || id.isEmpty) return;
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      final outcome = await _checkpoint.publishCheckpoint(checkpointId: id);
      if (!mounted) return;
      final String msg;
      if (outcome.noField) {
        msg = l.checkpointCardNoField;
      } else if (outcome.anyAccepted) {
        msg = l.checkpointCardSent(id, outcome.attempted);
      } else if (outcome.queued) {
        msg = l.checkpointCardQueued(id, outcome.pendingDepth);
      } else {
        msg = l.checkpointCardAttempted(id, outcome.attempted);
      }
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(msg)));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l.checkpointCardSendFailed('$e'))));
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
              // UI-H3-polish: the title carries the literal "CHECKPOINT" token
              // (non-breaking) and the action button's content padding scales
              // with the text size, so under the ~2.0 composite the button alone
              // exceeds the card width. Bound BOTH: the title ellipsizes, and the
              // button is Flexible with an ellipsizing label so the action (icon +
              // tap target) stays reachable instead of overflowing.
              Expanded(
                child: Text(l.checkpointCardTitle,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
              ),
              // 手動按鈕：debug-only 占位（真實流程綁 Node QR/接觸 → Stage D）。
              if (kDebugMode) ...[
                const SizedBox(width: 8),
                Flexible(
                  child: FilledButton.tonalIcon(
                    onPressed: _busy ? null : _promptAndPublish,
                    icon: const Icon(Icons.how_to_reg, size: 18),
                    label: Text(l.checkpointCardManual,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                ),
              ],
            ]),
            const SizedBox(height: 4),
            Text(
              l.checkpointCardBody,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            if (_crossings.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(l.checkpointCardEmpty,
                    style: const TextStyle(color: Colors.grey)),
              )
            else
              ..._crossings.map(_crossingRow),
          ],
        ),
      ),
    );
  }

  Widget _crossingRow(CheckpointCrossing c) {
    final when = c.observedAt.toIso8601String().substring(11, 19);
    final where = (c.lat != null && c.lng != null)
        ? '${c.lat!.toStringAsFixed(5)}, ${c.lng!.toStringAsFixed(5)}'
        : context.l10n.noCoordinateParen;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        SizedBox(
          width: 90,
          child: Text(c.checkpointId.isEmpty ? '—' : c.checkpointId,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text('${c.anon8.isEmpty ? "—" : c.anon8} · $where',
              style: const TextStyle(fontSize: 12)),
        ),
        Text(when, style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ]),
    );
  }
}
