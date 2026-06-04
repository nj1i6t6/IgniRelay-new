import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:ignirelay_app/app/controllers/event_stream.dart';
import 'package:ignirelay_app/app/controllers/mesh_runtime_controller.dart';
import 'package:ignirelay_app/app/services/event_store.dart';

/// Phase 0b mapless debug shell.
///
/// 取代舊產品的 `MainShell`（地圖優先 tab 殼），作為重建期間的最小操作面。
/// 刻意 **mapless**：不打包/不渲染地圖,只呈現「mesh 狀態 + 事件 log +
/// 最後可信位置(占位)」。真正的 PRESENCE/SOS 送出與 `PositionEstimate` 會在
/// 後續 Phase 0b commit（動 v2 wire 時）接上 — 本 commit 刻意不碰 wire。
/// 見 `docs/REBUILD_PLAN.md` §3.6（mapless 定位）/ §4（Phase 0b 步驟）。
///
/// 只依賴 app 層 facade（`MeshRuntimeController` / `EventStream` / `EventStore`），
/// 不直接碰 platform / app/mesh / app/proto / app/db（符合 check_layers 規則）。
class DebugShell extends StatefulWidget {
  const DebugShell({super.key});

  @override
  State<DebugShell> createState() => _DebugShellState();
}

class _DebugShellState extends State<DebugShell> {
  late final MeshRuntimeController _runtime;
  late final EventStream _events;
  late final EventStore _store;

  StreamSubscription<EventLogChanged>? _logSub;
  StreamSubscription<TransportState>? _stateSub;

  List<Map<String, dynamic>> _recent = const [];
  TransportState? _state;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _runtime = context.read<MeshRuntimeController>();
    _events = context.read<EventStream>();
    _store = context.read<EventStore>();
    _state = _runtime.transportActive
        ? TransportState.running
        : TransportState.stopped;
    _stateSub = _runtime.transportStateChanges.listen((s) {
      if (mounted) setState(() => _state = s);
    });
    _logSub = _events.anyEventChanges.listen((_) => _refresh());
    _refresh();
  }

  @override
  void dispose() {
    _logSub?.cancel();
    _stateSub?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final rows = await _store.queryRecent(limit: 50);
      if (mounted) setState(() => _recent = rows);
    } catch (_) {
      // debug surface — 失敗不致命,留空清單即可。
    }
  }

  Future<void> _toggleMesh() async {
    setState(() => _busy = true);
    final wasActive = _runtime.transportActive;
    try {
      if (wasActive) {
        await _runtime.stopTransport();
      } else {
        await _runtime.startTransport();
      }
    } catch (e) {
      _snack('mesh toggle 失敗: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  void _todoWire(String what) => _snack(
      '$what 尚未接線 — 隨 v2 wire（PRESENCE/SOS/field_id）在後續 Phase 0b commit 接上');

  @override
  Widget build(BuildContext context) {
    final active =
        _state == TransportState.running || _runtime.transportActive;
    final stats = _runtime.transportStats;
    return Scaffold(
      appBar: AppBar(
        title: const Text('IgniRelay · Phase 0b'),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(16),
          child: Padding(
            padding: EdgeInsets.only(bottom: 6),
            child: Text('mapless debug shell — 重建中', style: TextStyle(fontSize: 11)),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _meshCard(active, stats),
          const SizedBox(height: 12),
          _actionsCard(),
          const SizedBox(height: 12),
          _positionCard(),
          const SizedBox(height: 12),
          _eventsCard(),
        ],
      ),
    );
  }

  Widget _meshCard(bool active, TransportStats stats) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  active ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
                  color: active ? Colors.green : Colors.grey,
                ),
                const SizedBox(width: 8),
                Text('BLE mesh: ${active ? "running" : "stopped"}',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                const Spacer(),
                FilledButton(
                  onPressed: _busy ? null : _toggleMesh,
                  child: Text(active ? '停止' : '啟動'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(spacing: 16, runSpacing: 4, children: [
              _stat('peers', stats.connectedPeers),
              _stat('sent', stats.sentCount),
              _stat('recv', stats.receivedCount),
              _stat('seen', stats.seenEventsCount),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _stat(String label, int v) =>
      Text('$label: $v', style: const TextStyle(fontSize: 13));

  Widget _actionsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('送出事件', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            const Text('PRESENCE / SOS 走 v2 wire；本 commit 刻意不碰 wire,故尚未接線。',
                style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              OutlinedButton.icon(
                onPressed: () => _todoWire('PRESENCE'),
                icon: const Icon(Icons.my_location, size: 18),
                label: const Text('發 PRESENCE'),
              ),
              OutlinedButton.icon(
                onPressed: () => _todoWire('SOS'),
                icon: const Icon(Icons.sos, size: 18),
                label: const Text('發 SOS'),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _positionCard() {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('最後可信位置', style: TextStyle(fontWeight: FontWeight.bold)),
            SizedBox(height: 4),
            Text(
              'mapless 定位（§3.6）：anchor 節點 / 距離方位 / 可信度 / 誤差半徑。\n'
              'LocationEvidence + PositionEstimate 隨 v2 wire 接上,本 commit 為占位。',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _eventsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Text('事件 log（最新 50）',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const Spacer(),
              IconButton(
                  onPressed: _refresh, icon: const Icon(Icons.refresh, size: 18)),
            ]),
            if (_recent.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('（尚無事件）', style: TextStyle(color: Colors.grey)),
              )
            else
              ..._recent.take(50).map(_eventRow),
          ],
        ),
      ),
    );
  }

  Widget _eventRow(Map<String, dynamic> row) {
    final id = (row['event_id'] as String?) ?? '';
    final shortId = id.length <= 8 ? id : id.substring(0, 8);
    final type = row['event_type'];
    final urg = row['urgency'];
    final ts = row['hlc_timestamp'] as int?;
    final when = ts == null
        ? ''
        : DateTime.fromMillisecondsSinceEpoch(ts)
            .toIso8601String()
            .substring(11, 19);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        SizedBox(
          width: 70,
          child: Text(shortId.isEmpty ? '—' : shortId,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
        ),
        const SizedBox(width: 8),
        Expanded(
            child: Text('type=$type  urg=$urg',
                style: const TextStyle(fontSize: 12))),
        Text(when, style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ]),
    );
  }
}
