import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:ignirelay_app/app/controllers/event_stream.dart';
import 'package:ignirelay_app/app/controllers/sos_controller.dart';
import 'package:ignirelay_app/ui/screens/sos/sos_hold_button.dart';
import 'package:ignirelay_app/ui/theme/igni_colors.dart';
import 'package:ignirelay_app/ui/theme/igni_tokens.dart';
import 'package:ignirelay_app/ui/theme/igni_typography.dart';
import 'package:ignirelay_app/ui/widgets/igni_button.dart';
import 'package:ignirelay_app/ui/widgets/igni_card.dart';
import 'package:ignirelay_app/ui/widgets/igni_chip.dart';
import 'package:ignirelay_app/ui/widgets/igni_sub_page_header.dart';
import 'package:ignirelay_app/ui/widgets/mono_text.dart';

/// SOS UX（A8 / 白皮書 §13.4）。發送端：長按 1.5s→選 RED/YELLOW→5s 倒數可取消→
/// 帶位置發送→「我安全了」解除。收方：`sosAlerts` 告警卡（含位置、相對時間），
/// 收到同 author 的 SAFE（`sosResolutions`）即標「已解除」。
///
/// 守 DESIGN_LANGUAGE §4：經 `context.igni` 與 Igni 元件取值，screen 內不寫死
/// Material 調色常數。
class SosScreen extends StatefulWidget {
  const SosScreen({super.key});

  @override
  State<SosScreen> createState() => _SosScreenState();
}

class _SosScreenState extends State<SosScreen> {
  late final SosController _sos = context.read<SosController>();
  late final EventStream _events = context.read<EventStream>();

  StreamSubscription<SosAlert>? _alertSub;
  StreamSubscription<SosResolved>? _resolvedSub;

  // Latest incoming SOS per author (sender_pub_key hex); plus the authors who
  // have since reported SAFE so the card shows 已解除.
  final Map<String, SosAlert> _alerts = <String, SosAlert>{};
  final Set<String> _resolved = <String>{};

  @override
  void initState() {
    super.initState();
    _alertSub = _events.sosAlerts.listen((a) {
      if (!mounted) return;
      final key = _authorKey(a);
      setState(() {
        _alerts[key] = a;
        _resolved.remove(key); // a fresh SOS un-resolves the author
      });
    });
    _resolvedSub = _events.sosResolutions.listen((r) {
      if (!mounted) return;
      if (r.authorKeyHex.isEmpty) return;
      setState(() => _resolved.add(r.authorKeyHex));
    });
  }

  @override
  void dispose() {
    _alertSub?.cancel();
    _resolvedSub?.cancel();
    super.dispose();
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.igni;
    final sos = context.watch<SosController>();
    final alerts = _alerts.values.toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return Scaffold(
      backgroundColor: p.bg0,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: IgniSpacing.xl3),
          children: [
            const IgniSubPageHeader(
              title: '緊急求救',
              subtitle: '長按求救鈕 1.5 秒，選擇狀態後 5 秒內可取消',
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: IgniSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _senderCard(p, sos),
                  const SizedBox(height: IgniSpacing.xl),
                  Text('附近求救（${alerts.length}）',
                      style: IgniTypography.sectionHeader(p.text2)),
                  const SizedBox(height: IgniSpacing.sm),
                  if (alerts.isEmpty)
                    Text('目前沒有收到求救訊號。',
                        style: IgniTypography.bodySmall(p.text3))
                  else
                    for (final a in alerts)
                      Padding(
                        padding: const EdgeInsets.only(bottom: IgniSpacing.sm),
                        child: _alertCard(p, a),
                      ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Sender ─────────────────────────────────────────────────────────────
  Widget _senderCard(IgniPalette p, SosController sos) {
    if (sos.isCountingDown) return _countdownCard(p, sos);
    if (sos.phase == SosPhase.sending) {
      return IgniCard(
        child: Row(children: [
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: p.sos),
          ),
          const SizedBox(width: IgniSpacing.md),
          Text('求救傳送中…', style: IgniTypography.bodyMedium(p.text0)),
        ]),
      );
    }
    if (sos.hasActiveSos) return _activeSosCard(p, sos);
    return _triggerCard(p);
  }

  Widget _triggerCard(IgniPalette p) {
    return IgniCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('發出求救', style: IgniTypography.titleMedium(p.text0)),
          const SizedBox(height: IgniSpacing.xs),
          Text('長按下方按鈕 1.5 秒，再選擇你的狀態。送出前還有 5 秒可取消。',
              style: IgniTypography.bodySmall(p.text2)),
          const SizedBox(height: IgniSpacing.lg),
          Center(
            child: SosHoldButton(
              label: '按住求救',
              color: p.sos,
              onHoldComplete: _chooseSeverity,
            ),
          ),
        ],
      ),
    );
  }

  Widget _countdownCard(IgniPalette p, SosController sos) {
    final isTrapped = sos.armedSeverity == SosSeverity.trapped;
    final tone = isTrapped ? p.sos : p.warn;
    return IgniCard(
      borderColor: tone,
      background: isTrapped ? p.sosSoft : p.warnSoft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Icon(Icons.warning_amber_rounded, color: tone, size: 20),
            const SizedBox(width: IgniSpacing.sm),
            Text(isTrapped ? '受困求救' : '受傷求救',
                style: IgniTypography.titleMedium(p.text0)),
          ]),
          const SizedBox(height: IgniSpacing.md),
          Center(
            child: Text('${sos.secondsRemaining}',
                style: IgniTypography.display(tone)
                    .copyWith(fontSize: 56, fontWeight: FontWeight.w700)),
          ),
          Center(
            child: Text('秒後送出 — 仍可取消',
                style: IgniTypography.bodySmall(p.text2)),
          ),
          const SizedBox(height: IgniSpacing.lg),
          // 取消鈕 ≥64dp（DESIGN_LANGUAGE §4.4 急難情境）。
          SizedBox(
            height: 64,
            child: IgniButton(
              label: '取消',
              variant: IgniButtonVariant.ghost,
              size: IgniButtonSize.large,
              fullWidth: true,
              onPressed: sos.cancelCountdown,
            ),
          ),
        ],
      ),
    );
  }

  Widget _activeSosCard(IgniPalette p, SosController sos) {
    final isTrapped = sos.activeSeverity == SosSeverity.trapped;
    final tone = isTrapped ? p.sos : p.warn;
    return IgniCard(
      borderColor: tone,
      background: isTrapped ? p.sosSoft : p.warnSoft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Icon(Icons.sos_rounded, color: tone, size: 20),
            const SizedBox(width: IgniSpacing.sm),
            Expanded(
              child: Text('你已發出求救',
                  style: IgniTypography.titleMedium(p.text0)),
            ),
            IgniChip(
              label: isTrapped ? '受困' : '受傷',
              tone: isTrapped ? IgniChipTone.sos : IgniChipTone.warn,
            ),
          ]),
          const SizedBox(height: IgniSpacing.sm),
          Text(_outcomeText(sos),
              style: IgniTypography.bodySmall(p.text2)),
          const SizedBox(height: IgniSpacing.lg),
          IgniButton(
            label: '我安全了',
            variant: IgniButtonVariant.ghost,
            icon: Icons.check_circle_outline,
            fullWidth: true,
            onPressed: _markSafe,
          ),
        ],
      ),
    );
  }

  Future<void> _chooseSeverity() async {
    final p = context.igni;
    final choice = await showModalBottomSheet<SosSeverity>(
      context: context,
      backgroundColor: p.bg1,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(IgniSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('選擇你的狀態',
                  style: IgniTypography.titleMedium(p.text0),
                  textAlign: TextAlign.center),
              const SizedBox(height: IgniSpacing.lg),
              IgniButton(
                label: '受困（最高優先）',
                variant: IgniButtonVariant.sos,
                size: IgniButtonSize.large,
                fullWidth: true,
                onPressed: () => Navigator.of(ctx).pop(SosSeverity.trapped),
              ),
              const SizedBox(height: IgniSpacing.md),
              IgniButton(
                label: '受傷',
                variant: IgniButtonVariant.warn,
                size: IgniButtonSize.large,
                fullWidth: true,
                onPressed: () => Navigator.of(ctx).pop(SosSeverity.injured),
              ),
            ],
          ),
        ),
      ),
    );
    if (choice == null || !mounted) return;
    _sos.arm(choice);
  }

  Future<void> _markSafe() async {
    final outcome = await _sos.markSafe();
    if (!mounted) return;
    if (outcome != null && outcome.noField) {
      _snack('尚未加入場域 — 無法送出狀態更新');
    } else {
      _snack('已送出「我安全了」');
    }
  }

  // ── Receiver ───────────────────────────────────────────────────────────
  Widget _alertCard(IgniPalette p, SosAlert a) {
    final isResolved = _resolved.contains(_authorKey(a));
    final isTrapped = a.urgency >= 3;
    final tone = isResolved ? p.text3 : (isTrapped ? p.sos : p.warn);
    final where = (a.lat != null && a.lng != null)
        ? '${a.lat!.toStringAsFixed(5)}, ${a.lng!.toStringAsFixed(5)}'
        : '無座標';
    return IgniCard(
      borderColor: tone,
      background: isResolved
          ? null
          : (isTrapped ? p.sosSoft : p.warnSoft),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(isResolved ? Icons.check_circle : Icons.sos_rounded,
                color: tone, size: 18),
            const SizedBox(width: IgniSpacing.sm),
            Expanded(
              child: Text(
                a.description.isEmpty ? 'SOS' : a.description,
                style: IgniTypography.titleMedium(
                    isResolved ? p.text2 : p.text0),
              ),
            ),
            if (isResolved)
              const IgniChip(label: '已解除', tone: IgniChipTone.ok)
            else
              IgniChip(
                label: isTrapped ? '受困' : '受傷',
                tone: isTrapped ? IgniChipTone.sos : IgniChipTone.warn,
              ),
          ]),
          const SizedBox(height: IgniSpacing.sm),
          Row(children: [
            Icon(Icons.place_outlined, size: 14, color: p.text2),
            const SizedBox(width: 4),
            MonoText(where, color: p.text2, fontSize: 11),
            const Spacer(),
            Text(_relTime(a.timestamp),
                style: IgniTypography.labelSmall(p.text3)),
          ]),
        ],
      ),
    );
  }

  String _outcomeText(SosController sos) {
    final o = sos.lastOutcome;
    if (o == null) return '已送出。';
    if (o.noField) return '尚未加入場域 — 求救未送出，請先加入場域。';
    if (o.anyAccepted) return '已送達 ${o.attempted} 個鄰近裝置。';
    if (o.queued) return '已排入佇列（無在線鄰近裝置，深度 ${o.pendingDepth}）。';
    return '已嘗試送出（${o.attempted} 個，暫無人接收）。';
  }

  static String _authorKey(SosAlert a) {
    final k = a.senderPubKey;
    if (k == null || k.isEmpty) return 'eid:${a.eventId}';
    return _hex(k);
  }

  static String _hex(Uint8List bytes) {
    final sb = StringBuffer();
    for (final b in bytes) {
      sb.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }

  static String _relTime(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inSeconds < 60) return '剛剛';
    if (d.inMinutes < 60) return '${d.inMinutes} 分鐘前';
    if (d.inHours < 24) return '${d.inHours} 小時前';
    return '${d.inDays} 天前';
  }
}
