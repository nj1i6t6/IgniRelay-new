import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:ignirelay_app/app/controllers/event_stream.dart';
import 'package:ignirelay_app/app/controllers/sos_controller.dart';
import 'package:ignirelay_app/l10n/l10n_ext.dart';
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
    final l = context.l10n;
    final sos = context.watch<SosController>();
    final alerts = _alerts.values.toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return Scaffold(
      backgroundColor: p.bg0,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: IgniSpacing.xl3),
          children: [
            IgniSubPageHeader(
              title: l.sosTitle,
              subtitle: l.sosSubtitle,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: IgniSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _senderCard(p, sos),
                  const SizedBox(height: IgniSpacing.xl),
                  Text(l.sosNearbyHeader(alerts.length),
                      style: IgniTypography.sectionHeader(p.text2)),
                  const SizedBox(height: IgniSpacing.sm),
                  if (alerts.isEmpty)
                    Text(l.sosNoneNearby,
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
          Text(context.l10n.sosSending,
              style: IgniTypography.bodyMedium(p.text0)),
        ]),
      );
    }
    if (sos.hasActiveSos) return _activeSosCard(p, sos);
    return _triggerCard(p);
  }

  Widget _triggerCard(IgniPalette p) {
    final l = context.l10n;
    return IgniCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l.sosTriggerTitle, style: IgniTypography.titleMedium(p.text0)),
          const SizedBox(height: IgniSpacing.xs),
          Text(l.sosTriggerBody, style: IgniTypography.bodySmall(p.text2)),
          const SizedBox(height: IgniSpacing.lg),
          Center(
            child: SosHoldButton(
              label: l.sosHoldButton,
              color: p.sos,
              onHoldComplete: _chooseSeverity,
            ),
          ),
        ],
      ),
    );
  }

  Widget _countdownCard(IgniPalette p, SosController sos) {
    final l = context.l10n;
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
            Text(isTrapped ? l.sosCountdownTrapped : l.sosCountdownInjured,
                style: IgniTypography.titleMedium(p.text0)),
          ]),
          const SizedBox(height: IgniSpacing.md),
          Center(
            child: Text('${sos.secondsRemaining}',
                style: IgniTypography.display(tone)
                    .copyWith(fontSize: 56, fontWeight: FontWeight.w700)),
          ),
          Center(
            child: Text(l.sosCountdownHint,
                style: IgniTypography.bodySmall(p.text2)),
          ),
          const SizedBox(height: IgniSpacing.lg),
          // 取消鈕 ≥64dp（DESIGN_LANGUAGE §4.4 急難情境）。
          SizedBox(
            height: 64,
            child: IgniButton(
              label: l.commonCancel,
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
    final l = context.l10n;
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
              child: Text(l.sosActiveTitle,
                  style: IgniTypography.titleMedium(p.text0)),
            ),
            IgniChip(
              label: isTrapped ? l.sosChipTrapped : l.sosChipInjured,
              tone: isTrapped ? IgniChipTone.sos : IgniChipTone.warn,
            ),
          ]),
          const SizedBox(height: IgniSpacing.sm),
          Text(_outcomeText(sos),
              style: IgniTypography.bodySmall(p.text2)),
          const SizedBox(height: IgniSpacing.lg),
          IgniButton(
            label: l.sosMarkSafe,
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
    final l = context.l10n;
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
              Text(l.sosChooseStatus,
                  style: IgniTypography.titleMedium(p.text0),
                  textAlign: TextAlign.center),
              const SizedBox(height: IgniSpacing.lg),
              IgniButton(
                label: l.sosSeverityTrapped,
                variant: IgniButtonVariant.sos,
                size: IgniButtonSize.large,
                fullWidth: true,
                onPressed: () => Navigator.of(ctx).pop(SosSeverity.trapped),
              ),
              const SizedBox(height: IgniSpacing.md),
              IgniButton(
                label: l.sosChipInjured,
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
    final l = context.l10n;
    final outcome = await _sos.markSafe();
    if (!mounted) return;
    if (outcome != null && outcome.noField) {
      _snack(l.sosMarkSafeNoField);
    } else {
      _snack(l.sosMarkSafeSent);
    }
  }

  // ── Receiver ───────────────────────────────────────────────────────────
  Widget _alertCard(IgniPalette p, SosAlert a) {
    final l = context.l10n;
    final isResolved = _resolved.contains(_authorKey(a));
    final isTrapped = a.urgency >= 3;
    final tone = isResolved ? p.text3 : (isTrapped ? p.sos : p.warn);
    final where = (a.lat != null && a.lng != null)
        ? '${a.lat!.toStringAsFixed(5)}, ${a.lng!.toStringAsFixed(5)}'
        : l.noCoordinate;
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
              IgniChip(label: l.sosResolvedChip, tone: IgniChipTone.ok)
            else
              IgniChip(
                label: isTrapped ? l.sosChipTrapped : l.sosChipInjured,
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
    final l = context.l10n;
    final o = sos.lastOutcome;
    if (o == null) return l.sosOutcomeSent;
    if (o.noField) return l.sosOutcomeNoField;
    if (o.anyAccepted) return l.sosOutcomeAccepted(o.attempted);
    if (o.queued) return l.sosOutcomeQueued(o.pendingDepth);
    return l.sosOutcomeAttempted(o.attempted);
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

  String _relTime(DateTime t) {
    final l = context.l10n;
    final d = DateTime.now().difference(t);
    if (d.inSeconds < 60) return l.timeJustNow;
    if (d.inMinutes < 60) return l.timeAgoMinutes(d.inMinutes);
    if (d.inHours < 24) return l.timeAgoHours(d.inHours);
    return l.timeAgoDays(d.inDays);
  }
}
