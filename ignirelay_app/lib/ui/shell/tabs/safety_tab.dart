// SafetyTab — UI-F2「安全」分頁。
//
// 我的安全面：近距離通訊（mesh）狀態 + 開關、立即更新足跡、自動足跡信標、最近足跡。
// 重用既有 controller（MeshRuntimeController / PresenceController /
// PresenceBeaconController / EventStream），不改任何底層行為。
//
// 全 token-clean（context.igni + ui/widgets），0 個 Colors.* / hex。文案為正式產品語：
// 「近距離通訊」「立即更新足跡」「自動足跡信標」，不出現工程/除錯字樣。通訊狀態彙整
// （cloud/peers/outbox 聚合）留 UI-F4。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:ignirelay_app/app/controllers/event_stream.dart';
import 'package:ignirelay_app/app/controllers/mesh_runtime_controller.dart';
import 'package:ignirelay_app/app/controllers/presence_beacon_controller.dart';
import 'package:ignirelay_app/app/controllers/presence_controller.dart';
import 'package:ignirelay_app/ui/theme/igni_colors.dart';
import 'package:ignirelay_app/ui/theme/igni_tokens.dart';
import 'package:ignirelay_app/ui/theme/igni_typography.dart';
import 'package:ignirelay_app/ui/widgets/igni_button.dart';
import 'package:ignirelay_app/ui/widgets/igni_card.dart';
import 'package:ignirelay_app/ui/widgets/igni_sub_page_header.dart';
import 'package:ignirelay_app/ui/widgets/mono_text.dart';

class SafetyTab extends StatefulWidget {
  const SafetyTab({super.key});

  @override
  State<SafetyTab> createState() => _SafetyTabState();
}

class _SafetyTabState extends State<SafetyTab> {
  late final MeshRuntimeController _runtime;
  late final PresenceController _presence;
  late final EventStream _events;

  StreamSubscription<TransportState>? _stateSub;
  StreamSubscription<PresenceUpdate>? _presenceSub;
  final List<PresenceUpdate> _footprints = <PresenceUpdate>[];
  TransportState? _state;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _runtime = context.read<MeshRuntimeController>();
    _presence = context.read<PresenceController>();
    _events = context.read<EventStream>();
    _state = _runtime.transportActive
        ? TransportState.running
        : TransportState.stopped;
    try {
      _stateSub = _runtime.transportStateChanges.listen((s) {
        if (mounted) setState(() => _state = s);
      });
    } catch (_) {
      // transport 未注入（widget test 未 attachTransport）：null-safe，略過。
    }
    _presenceSub = _events.presenceUpdates.listen((p) {
      if (!mounted) return;
      setState(() {
        _footprints.removeWhere((e) => e.anon8 == p.anon8);
        _footprints.insert(0, p);
        if (_footprints.length > 20) {
          _footprints.removeRange(20, _footprints.length);
        }
      });
    });
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _presenceSub?.cancel();
    super.dispose();
  }

  Future<void> _toggleComms() async {
    setState(() => _busy = true);
    try {
      if (_runtime.transportActive) {
        await _runtime.stopTransport();
      } else {
        await _runtime.startTransport();
      }
    } catch (e) {
      _snack('通訊切換失敗：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _updateFootprint() async {
    setState(() => _busy = true);
    try {
      final o = await _presence.publishPresence();
      if (!mounted) return;
      if (o.noField) {
        _snack('尚未加入場域 — 請先到「我的」加入或建立場域');
      } else if (o.anyAccepted) {
        _snack('已更新足跡（${o.attempted} 個鄰近裝置）');
      } else if (o.queued) {
        _snack('足跡已排入佇列，待鄰近裝置上線後送出');
      } else {
        _snack('已嘗試更新足跡');
      }
    } catch (e) {
      _snack('更新足跡失敗：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.igni;
    final beacon = context.watch<PresenceBeaconController>();
    final active =
        _state == TransportState.running || _runtime.transportActive;
    final stats = _runtime.transportStats;
    return ListView(
      padding: const EdgeInsets.only(bottom: IgniSpacing.xl3),
      children: [
        const IgniSubPageHeader(title: '我的安全', subtitle: '通訊與足跡'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: IgniSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _commsCard(p, active, stats),
              const SizedBox(height: IgniSpacing.md),
              _footprintCard(p, beacon),
              const SizedBox(height: IgniSpacing.md),
              _recentCard(p),
            ],
          ),
        ),
      ],
    );
  }

  Widget _commsCard(IgniPalette p, bool active, TransportStats stats) {
    return IgniCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(active ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
                size: 18, color: active ? p.ok : p.text2),
            const SizedBox(width: IgniSpacing.sm),
            Text(active ? '近距離通訊：開啟' : '近距離通訊：關閉',
                style: IgniTypography.titleMedium(p.text0)),
            const Spacer(),
            IgniButton(
              label: active ? '關閉' : '開啟',
              variant:
                  active ? IgniButtonVariant.ghost : IgniButtonVariant.primary,
              size: IgniButtonSize.small,
              onPressed: _busy ? null : _toggleComms,
            ),
          ]),
          const SizedBox(height: IgniSpacing.sm),
          Text(
            active
                ? '透過藍牙與附近裝置／節點接力傳遞，無需網路。'
                : '開啟後可在離線環境與附近裝置互相看見、接力傳遞。',
            style: IgniTypography.bodySmall(p.text2),
          ),
          const SizedBox(height: IgniSpacing.sm),
          Wrap(spacing: IgniSpacing.lg, runSpacing: IgniSpacing.xs, children: [
            _stat(p, '鄰近裝置', stats.connectedPeers),
            _stat(p, '已送', stats.sentCount),
            _stat(p, '已收', stats.receivedCount),
          ]),
          const SizedBox(height: IgniSpacing.sm),
          Text('通訊狀態彙整 — 即將提供', style: IgniTypography.bodySmall(p.text3)),
        ],
      ),
    );
  }

  Widget _stat(IgniPalette p, String label, int v) =>
      Text('$label $v', style: IgniTypography.bodySmall(p.text1));

  Widget _footprintCard(IgniPalette p, PresenceBeaconController beacon) {
    return IgniCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('足跡', style: IgniTypography.titleMedium(p.text0)),
          const SizedBox(height: IgniSpacing.xs),
          Text('讓附近的人看見你最後可信的位置。',
              style: IgniTypography.bodySmall(p.text2)),
          const SizedBox(height: IgniSpacing.sm),
          IgniButton(
            label: '立即更新足跡',
            icon: Icons.my_location,
            fullWidth: true,
            onPressed: _busy ? null : _updateFootprint,
          ),
          const SizedBox(height: IgniSpacing.xs),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            value: beacon.enabled,
            onChanged: (v) => beacon.setEnabled(v),
            title: Text('自動足跡信標', style: IgniTypography.bodyMedium(p.text0)),
            subtitle: Text(_beaconStatus(beacon),
                style: IgniTypography.bodySmall(p.text2)),
          ),
        ],
      ),
    );
  }

  String _beaconStatus(PresenceBeaconController b) {
    if (!b.enabled) return '已關閉';
    final secs = b.currentInterval.inSeconds;
    final low = b.isLowBattery ? '（低電量降頻）' : '';
    return '每 $secs 秒 · 已更新 ${b.beaconCount} 次$low';
  }

  Widget _recentCard(IgniPalette p) {
    return IgniCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('最近足跡', style: IgniTypography.titleMedium(p.text0)),
          const SizedBox(height: IgniSpacing.sm),
          if (_footprints.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: IgniSpacing.sm),
              child: Text('尚無足跡', style: IgniTypography.bodySmall(p.text2)),
            )
          else
            ..._footprints.map((f) => _footprintRow(p, f)),
        ],
      ),
    );
  }

  Widget _footprintRow(IgniPalette p, PresenceUpdate f) {
    final when = f.observedAt.toIso8601String().substring(11, 19);
    final where = (f.lat != null && f.lng != null)
        ? '${f.lat!.toStringAsFixed(5)}, ${f.lng!.toStringAsFixed(5)}'
        : '無座標';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        SizedBox(
          width: 72,
          child: MonoText(f.anon8.isEmpty ? '—' : f.anon8,
              fontSize: 11, color: p.text1),
        ),
        const SizedBox(width: IgniSpacing.sm),
        Expanded(child: Text(where, style: IgniTypography.bodySmall(p.text1))),
        MonoText(when, fontSize: 11, color: p.text2),
      ]),
    );
  }
}
