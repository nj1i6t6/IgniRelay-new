import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:ignirelay_app/app/controllers/active_field_controller.dart';
import 'package:ignirelay_app/app/controllers/event_stream.dart';
import 'package:ignirelay_app/app/controllers/mesh_runtime_controller.dart';
import 'package:ignirelay_app/app/controllers/presence_controller.dart';
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
  late final PresenceController _presence;
  late final ActiveFieldController _field;

  StreamSubscription<EventLogChanged>? _logSub;
  StreamSubscription<TransportState>? _stateSub;
  StreamSubscription<PresenceUpdate>? _presenceSub;

  List<Map<String, dynamic>> _recent = const [];
  final List<PresenceUpdate> _presences = <PresenceUpdate>[];
  TransportState? _state;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _runtime = context.read<MeshRuntimeController>();
    _events = context.read<EventStream>();
    _store = context.read<EventStore>();
    _presence = context.read<PresenceController>();
    _field = context.read<ActiveFieldController>();
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
    _refresh();
  }

  @override
  void dispose() {
    _logSub?.cancel();
    _stateSub?.cancel();
    _presenceSub?.cancel();
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
          _meshCard(active, stats),
          const SizedBox(height: 12),
          _fieldCard(context.watch<ActiveFieldController>()),
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

  // ── 場域（field-scope）─────────────────────────────────────────────────
  //
  // A5 debug-only join surface: enter a 64-hex field_join_secret, or generate
  // a new random one to read into another phone. The real QR / code UX is A7.

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
              const Text('尚未加入場域 — 送出事件前需先加入或產生一個場域。',
                  style: TextStyle(fontSize: 12, color: Colors.orange)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              OutlinedButton.icon(
                onPressed: _busy ? null : _showJoinByCodeDialog,
                icon: const Icon(Icons.vpn_key, size: 18),
                label: const Text('以代碼加入'),
              ),
              OutlinedButton.icon(
                onPressed: _busy ? null : _generateNewField,
                icon: const Icon(Icons.add_circle_outline, size: 18),
                label: const Text('產生新場域'),
              ),
            ]),
            if (field.joinedFields.length > 1) ...[
              const SizedBox(height: 8),
              const Text('切換作用場域：',
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
              Wrap(spacing: 6, children: [
                for (final f in field.joinedFields)
                  ChoiceChip(
                    label: Text(f.shortId,
                        style: const TextStyle(
                            fontFamily: 'monospace', fontSize: 11)),
                    selected: active?.fieldIdHex == f.fieldIdHex,
                    onSelected:
                        _busy ? null : (_) => _field.setActive(f.fieldIdHex),
                  ),
              ]),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _showJoinByCodeDialog() async {
    final controller = TextEditingController();
    final secret = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('以代碼加入場域'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '輸入 64 個十六進位字元的 field_join_secret（32 bytes）。'
              '此為 debug 入口；正式的 QR / 代碼流程在 A7。',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: controller,
              autofocus: true,
              maxLength: 64,
              decoration: const InputDecoration(
                hintText: 'a1b2c3…（64 hex）',
                border: OutlineInputBorder(),
              ),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('加入'),
          ),
        ],
      ),
    );
    if (secret == null || secret.isEmpty) return;
    final bytes = _decodeHex32(secret);
    if (bytes == null) {
      _snack('場域代碼格式錯誤：需為 64 個十六進位字元');
      return;
    }
    await _joinSecret(bytes, name: '場域-${secret.substring(0, 4)}');
  }

  Future<void> _generateNewField() async {
    final rng = Random.secure();
    final bytes =
        List<int>.generate(32, (_) => rng.nextInt(256), growable: false);
    final hex = _encodeHex(bytes);
    await _joinSecret(bytes, name: '新場域-${hex.substring(0, 4)}');
    if (!mounted) return;
    // Show the secret so another phone can join the same field via 以代碼加入.
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('已建立並加入新場域'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('把這串 field_join_secret 輸入另一台手機的「以代碼加入」即可同場域：',
                style: TextStyle(fontSize: 12)),
            const SizedBox(height: 10),
            SelectableText(
              hex,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(), child: const Text('關閉')),
        ],
      ),
    );
  }

  Future<void> _joinSecret(List<int> secret, {required String name}) async {
    setState(() => _busy = true);
    try {
      final field = await _field.joinBySecret(secret, displayName: name);
      if (mounted) _snack('已加入場域 ${field.shortId}…');
    } catch (e) {
      if (mounted) _snack('加入場域失敗: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // UI-local hex helpers — debug field code only; UI must not import app/proto.
  static List<int>? _decodeHex32(String hex) {
    final s = hex.trim().toLowerCase();
    if (s.length != 64) return null;
    final out = List<int>.filled(32, 0);
    for (var i = 0; i < 32; i++) {
      final byte = int.tryParse(s.substring(i * 2, i * 2 + 2), radix: 16);
      if (byte == null) return null;
      out[i] = byte;
    }
    return out;
  }

  static String _encodeHex(List<int> bytes) {
    final sb = StringBuffer();
    for (final b in bytes) {
      sb.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
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
            const Text('PRESENCE 走 v2 wire（已接線）；SOS 在 A4 接上。',
                style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              OutlinedButton.icon(
                onPressed: _busy ? null : _publishPresence,
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('最近 PRESENCE 足跡',
                style: TextStyle(fontWeight: FontWeight.bold)),
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
