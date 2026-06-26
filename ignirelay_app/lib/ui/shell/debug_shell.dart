import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:ignirelay_app/app/controllers/active_field_controller.dart';
import 'package:ignirelay_app/app/controllers/event_stream.dart';
import 'package:ignirelay_app/app/controllers/mesh_runtime_controller.dart';
import 'package:ignirelay_app/app/controllers/presence_beacon_controller.dart';
import 'package:ignirelay_app/app/controllers/presence_controller.dart';
import 'package:ignirelay_app/app/services/event_decoder.dart';
import 'package:ignirelay_app/app/services/event_store.dart';
import 'package:ignirelay_app/ui/shell/admin_broadcast_banner.dart';
import 'package:ignirelay_app/ui/shell/checkpoint_card.dart';
import 'package:ignirelay_app/ui/shell/hazard_card.dart';
import 'package:ignirelay_app/ui/screens/field/field_screen.dart';
import 'package:ignirelay_app/ui/screens/position/last_seen_screen.dart';
import 'package:ignirelay_app/ui/screens/sos/sos_screen.dart';

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
  late final PresenceController _presence;

  StreamSubscription<EventLogChanged>? _logSub;
  StreamSubscription<TransportState>? _stateSub;
  StreamSubscription<PresenceUpdate>? _presenceSub;
  StreamSubscription<NodeReceipt>? _receiptSub;

  List<Map<String, dynamic>> _recent = const [];
  final List<PresenceUpdate> _presences = <PresenceUpdate>[];
  final List<NodeReceipt> _receipts = <NodeReceipt>[];
  TransportState? _state;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _runtime = context.read<MeshRuntimeController>();
    _events = context.read<EventStream>();
    _store = context.read<EventStore>();
    _presence = context.read<PresenceController>();
    _state = _runtime.transportActive
        ? TransportState.running
        : TransportState.stopped;
    try {
      _stateSub = _runtime.transportStateChanges.listen((s) {
        if (mounted) setState(() => _state = s);
      });
    } catch (_) {
      // transport 尚未注入（例如 widget test 未 attachTransport）：
      // transportActive / transportStats 仍 null-safe,略過狀態訂閱即可。
    }
    _logSub = _events.anyEventChanges.listen((_) => _refresh());
    _presenceSub = _events.presenceUpdates.listen((p) {
      if (!mounted) return;
      setState(() {
        // 最近在前；同 anon 只留最新一筆。
        _presences.removeWhere((e) => e.anon8 == p.anon8);
        _presences.insert(0, p);
        if (_presences.length > 20) _presences.removeRange(20, _presences.length);
      });
    });
    // A12 — App↔Node first-hop receipts (NODE_RECEIPT 105). Newest first; same
    // ref_envelope_id collapses to the latest receipt for that sent envelope.
    _receiptSub = _events.nodeReceipts.listen((r) {
      if (!mounted) return;
      setState(() {
        _receipts.removeWhere((e) => e.refEnvelopeIdHex == r.refEnvelopeIdHex);
        _receipts.insert(0, r);
        if (_receipts.length > 20) _receipts.removeRange(20, _receipts.length);
      });
    });
    _refresh();
  }

  @override
  void dispose() {
    _logSub?.cancel();
    _stateSub?.cancel();
    _presenceSub?.cancel();
    _receiptSub?.cancel();
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

  Future<void> _publishPresence() async {
    setState(() => _busy = true);
    try {
      final outcome = await _presence.publishPresence();
      if (!mounted) return;
      if (outcome.noField) {
        _snack('尚未加入場域 — 請先在「場域」卡片加入或產生一個場域');
      } else if (outcome.anyAccepted) {
        _snack('PRESENCE 已送出（${outcome.attempted} peer）');
      } else if (outcome.queued) {
        _snack('PRESENCE 已排入佇列（無在線 peer，深度 ${outcome.pendingDepth}）');
      } else {
        _snack('PRESENCE 已嘗試送出（${outcome.attempted} peer，無人接受）');
      }
    } catch (e) {
      _snack('PRESENCE 送出失敗: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

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
          // A9 (3) — ADMIN_BROADCAST 置頂橫幅（依 expires_at 自動下架；發佈端
          // 僅 kDebugMode 後門）。無有效公告時收合。
          const AdminBroadcastBanner(),
          _meshCard(active, stats),
          const SizedBox(height: 12),
          _fieldCard(context.watch<ActiveFieldController>()),
          const SizedBox(height: 12),
          _actionsCard(),
          const SizedBox(height: 12),
          _positionCard(),
          const SizedBox(height: 12),
          _nodeReceiptCard(),
          const SizedBox(height: 12),
          const CheckpointCard(),
          const SizedBox(height: 12),
          // A11-prep — typed HAZARD send（kDebugMode 鈕）+ receive list（解開
          // 兩機驗收 A11 step 5；A3 原只接收，發送 UI 隨舊地圖頁退役）。
          const HazardCard(),
          const SizedBox(height: 12),
          _eventsCard(),
        ],
      ),
    );
  }

  // ── 場域（field-scope）─────────────────────────────────────────────────
  //
  // Compact status + a launcher into the full A7 field page (建立 / 顯示 QR /
  // 掃碼加入 / 代碼加入 / 多場域切換 / 離開). The A5 inline hex dialog was
  // superseded by `FieldScreen` (the code-input there accepts both an IGNI1 QR
  // string and the legacy 64-hex secret).

  Widget _fieldCard(ActiveFieldController field) {
    final active = field.active;
    final joined = field.joinedFieldCount;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(active != null ? Icons.shield : Icons.shield_outlined,
                  color: active != null ? Colors.green : Colors.grey, size: 18),
              const SizedBox(width: 6),
              const Text('場域（field-scope）',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const Spacer(),
              FilledButton.tonalIcon(
                onPressed: _busy ? null : _openFieldScreen,
                icon: const Icon(Icons.tune, size: 18),
                label: const Text('場域管理'),
              ),
            ]),
            const SizedBox(height: 6),
            if (active != null) ...[
              Text('目前場域：${active.displayName.isEmpty ? "（未命名）" : active.displayName}',
                  style: const TextStyle(fontSize: 13)),
              Text('field_id：${active.shortId}…  ·  已加入 $joined 個',
                  style: const TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                      fontFamily: 'monospace')),
            ] else
              const Text('尚未加入場域 — 送出事件前需先加入或建立一個場域。',
                  style: TextStyle(fontSize: 12, color: Colors.orange)),
          ],
        ),
      ),
    );
  }

  Future<void> _openFieldScreen() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const FieldScreen()),
    );
  }

  Future<void> _openSosScreen() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const SosScreen()),
    );
  }

  Future<void> _openLastSeen() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const LastSeenScreen()),
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
    final beacon = context.watch<PresenceBeaconController>();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('送出事件', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            const Text('PRESENCE 走 v2 wire（已接線）；SOS UX 在 A8 接上。',
                style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              OutlinedButton.icon(
                onPressed: _busy ? null : _publishPresence,
                icon: const Icon(Icons.my_location, size: 18),
                label: const Text('發 PRESENCE'),
              ),
              OutlinedButton.icon(
                onPressed: _openSosScreen,
                icon: const Icon(Icons.sos, size: 18),
                label: const Text('發 SOS'),
              ),
            ]),
            const Divider(height: 20),
            // A9 (1) — automatic PRESENCE beacon toggle. Only beacons while the
            // mesh is running AND a field is joined; cadence 120s / 300s(<20%).
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: beacon.enabled,
              onChanged: (v) => beacon.setEnabled(v),
              title: const Text('自動 PRESENCE 信標',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              subtitle: Text(_beaconStatus(beacon),
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ),
          ],
        ),
      ),
    );
  }

  String _beaconStatus(PresenceBeaconController b) {
    if (!b.enabled) return '已關閉';
    final secs = b.currentInterval.inSeconds;
    final low = b.isLowBattery ? '（低電降頻）' : '';
    return '每 $secs 秒 · 已發 ${b.beaconCount} 次$low';
  }

  Widget _positionCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Text('最近 PRESENCE 足跡',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const Spacer(),
              // A10 — 開啟「最後可信位置」推估卡片頁（mapless）。
              FilledButton.tonalIcon(
                onPressed: _openLastSeen,
                icon: const Icon(Icons.location_searching, size: 18),
                label: const Text('最後可信位置'),
              ),
            ]),
            const SizedBox(height: 4),
            const Text(
              'mapless 定位（§3.6）：收到的 PRESENCE evidence（anon / 來源 / 時間 / 經緯）。',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            if (_presences.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('（尚無 PRESENCE）', style: TextStyle(color: Colors.grey)),
              )
            else
              ..._presences.map(_presenceRow),
          ],
        ),
      ),
    );
  }

  Widget _presenceRow(PresenceUpdate p) {
    final when = p.observedAt.toIso8601String().substring(11, 19);
    final where = (p.lat != null && p.lng != null)
        ? '${p.lat!.toStringAsFixed(5)}, ${p.lng!.toStringAsFixed(5)}'
        : '（無座標）';
    final src = _sourceLabel(p.source);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        SizedBox(
          width: 70,
          child: Text(p.anon8.isEmpty ? '—' : p.anon8,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
        ),
        const SizedBox(width: 8),
        Expanded(child: Text('$src · $where', style: const TextStyle(fontSize: 12))),
        Text(when, style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ]),
    );
  }

  // LocationSource.* → label。UI 不 import app/proto，故以本地數值對照。
  static String _sourceLabel(int source) {
    switch (source) {
      case 1:
        return 'GPS';
      case 2:
        return 'NODE';
      case 3:
        return 'RSSI';
      case 4:
        return 'PDR';
      default:
        return '—';
    }
  }

  // ── A12: App↔Node first-hop receipts (NODE_RECEIPT 105) ─────────────────
  //
  // NODE_RECEIPT is a transport-layer ack from a Field Node, NOT a field event
  // (it is never projected into Event_Logs). The sender (Node/simulator) is a
  // Stage B component, so in this build this list stays empty until a Node is
  // present. Keyed by ref_envelope_id ↔ the sent envelope_id.
  Widget _nodeReceiptCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Node 收據（已送達節點）',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            const Text(
              'App↔Node 第一跳收據（NODE_RECEIPT 105）。對應送出的 envelope_id；'
              '節點端為 Stage B 元件，未接前此清單為空。',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            if (_receipts.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('（尚無 Node 收據）', style: TextStyle(color: Colors.grey)),
              )
            else
              ..._receipts.map(_receiptRow),
          ],
        ),
      ),
    );
  }

  Widget _receiptRow(NodeReceipt r) {
    final when = r.receivedAt.toIso8601String().substring(11, 19);
    final ref =
        r.refEnvelopeIdHex.length <= 8 ? r.refEnvelopeIdHex : r.refEnvelopeIdHex.substring(0, 8);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        SizedBox(
          width: 70,
          child: Text(ref.isEmpty ? '—' : ref,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
        ),
        const SizedBox(width: 8),
        Expanded(
            child: Text('${_receiptLabel(r)} · queue=${r.queueDepth}',
                style: const TextStyle(fontSize: 12))),
        Text(when, style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ]),
    );
  }

  static String _receiptLabel(NodeReceipt r) {
    if (r.isAcceptedStored) return '已送達節點';
    if (r.isDuplicate) return '節點：重複';
    if (r.isRejected) return '節點：拒收';
    return '節點：回報（未知狀態）';
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
