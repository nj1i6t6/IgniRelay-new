// SafetyTab —「安全」分頁（UI-F2 搬遷；UI-F4 通訊狀態彙整）。
//
// 我的安全面：近距離通訊（mesh）狀態 + 開關、通訊狀態彙整（UI-F4 CommunicationState：
// 最佳路徑 / cloud / 待送 outbox / 最後足跡）、立即更新足跡、自動足跡信標、最近足跡。
// 重用既有 controller（MeshRuntimeController / PresenceController /
// PresenceBeaconController / EventStream / EventPublisher / ActiveFieldController），
// 只讀不改任何底層行為——彙整純由已存在的數值推導（見 communication_state.dart）。
//
// 全 token-clean（context.igni + ui/widgets），0 個 Colors.* / hex。文案為正式產品語，
// 不出現工程/除錯字樣；cloud 文案 Stage A 一律不宣稱「可達/已連線」。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:ignirelay_app/app/controllers/active_field_controller.dart';
import 'package:ignirelay_app/app/controllers/event_publisher.dart';
import 'package:ignirelay_app/app/controllers/event_stream.dart';
import 'package:ignirelay_app/app/controllers/mesh_runtime_controller.dart';
import 'package:ignirelay_app/app/controllers/presence_beacon_controller.dart';
import 'package:ignirelay_app/app/controllers/presence_controller.dart';
import 'package:ignirelay_app/app/services/location_refresh_coordinator.dart';
import 'package:ignirelay_app/app/services/motion/gps_refresh_policy.dart';
import 'package:ignirelay_app/app/services/motion/motion_state.dart';
import 'package:ignirelay_app/l10n/generated/app_localizations.dart';
import 'package:ignirelay_app/l10n/l10n_ext.dart';
import 'package:ignirelay_app/ui/shell/tabs/communication_state.dart';
import 'package:ignirelay_app/ui/theme/igni_colors.dart';
import 'package:ignirelay_app/ui/theme/igni_tokens.dart';
import 'package:ignirelay_app/ui/theme/igni_typography.dart';
import 'package:ignirelay_app/ui/widgets/igni_button.dart';
import 'package:ignirelay_app/ui/widgets/igni_card.dart';
import 'package:ignirelay_app/ui/widgets/igni_sub_page_header.dart';
import 'package:ignirelay_app/ui/widgets/mono_text.dart';

class SafetyTab extends StatefulWidget {
  const SafetyTab({super.key});

  /// Test-only: counts 5 s refresh ticks that actually ran `setState` (i.e.
  /// passed the mounted + TickerMode guard). Lets the AppShell-context test
  /// prove the refresh pauses while the 安全 tab is offstage (UI-F5a / Owner
  /// boundary 6). Same-library writes only; tests reset it before use.
  @visibleForTesting
  static int debugRefreshTicks = 0;

  @override
  State<SafetyTab> createState() => _SafetyTabState();
}

class _SafetyTabState extends State<SafetyTab> {
  late final MeshRuntimeController _runtime;
  late final PresenceController _presence;
  late final EventStream _events;
  late final EventPublisher _publisher;

  StreamSubscription<TransportState>? _stateSub;
  StreamSubscription<PresenceUpdate>? _presenceSub;

  /// Periodic UI-refresh tick so live counters (peers / outbox) stay fresh while
  /// the tab is visible. UI-only — the callback just rebuilds; it never mutates
  /// or accumulates state. Cancelled in [dispose] (UI-F4 / Owner req 2).
  Timer? _refreshTimer;

  /// Last time a MANUAL「立即更新足跡」actually sent or queued. Only stamped on a
  /// real send (UI-F4 / Owner req 1) — never on noField / failure / throw.
  DateTime? _lastManualPresenceAt;

  final List<PresenceUpdate> _footprints = <PresenceUpdate>[];
  TransportState? _state;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _runtime = context.read<MeshRuntimeController>();
    _presence = context.read<PresenceController>();
    _events = context.read<EventStream>();
    _publisher = context.read<EventPublisher>();
    _state = _runtime.transportActive
        ? TransportState.running
        : TransportState.stopped;
    // UI-refresh only: keep the live peers / outbox counters fresh. Cancelled
    // in dispose so no timer leaks and no setState fires after unmount. UI-F5a:
    // also skip the rebuild while this tab is offstage (TickerMode disabled by
    // AppShell for non-selected tabs) so it costs ~0 when not visible.
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || !TickerMode.valuesOf(context).enabled) return;
      SafetyTab.debugRefreshTicks++;
      setState(() {});
    });
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
    _refreshTimer?.cancel();
    _stateSub?.cancel();
    _presenceSub?.cancel();
    super.dispose();
  }

  Future<void> _toggleComms() async {
    final l = context.l10n;
    setState(() => _busy = true);
    try {
      if (_runtime.transportActive) {
        await _runtime.stopTransport();
      } else {
        await _runtime.startTransport();
      }
    } catch (e) {
      _snack(l.safetyToggleFailed('$e'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _updateFootprint() async {
    final l = context.l10n;
    setState(() => _busy = true);
    try {
      final o = await _presence.publishPresence();
      if (!mounted) return;
      // Owner req 1: only a real send (accepted OR queued) stamps the manual
      // presence time. noField / "已嘗試" / the catch path below never do.
      if (presenceCountsAsSent(anyAccepted: o.anyAccepted, queued: o.queued)) {
        _lastManualPresenceAt = DateTime.now();
      }
      if (o.noField) {
        _snack(l.safetyUpdateNoField);
      } else if (o.anyAccepted) {
        _snack(l.safetyUpdateSent(o.attempted));
      } else if (o.queued) {
        _snack(l.safetyUpdateQueued);
      } else {
        _snack(l.safetyUpdateAttempted);
      }
    } catch (e) {
      _snack(l.safetyUpdateFailed('$e'));
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
    final field = context.watch<ActiveFieldController>();
    final coord = context.read<LocationRefreshCoordinator>();
    final active =
        _state == TransportState.running || _runtime.transportActive;
    final stats = _runtime.transportStats;
    final comms = CommunicationState.from(
      hasField: field.hasActiveField,
      meshRunning: active,
      peers: stats.connectedPeers,
      sentCount: stats.sentCount,
      receivedCount: stats.receivedCount,
      outboxDepth: _publisher.pendingQueueDepth,
      lastPresenceAt: _latestPresenceAt(beacon),
      cloudConfigured: field.active?.cloudBaseUrl != null,
    );
    final l = context.l10n;
    return ListView(
      padding: const EdgeInsets.only(bottom: IgniSpacing.xl3),
      children: [
        IgniSubPageHeader(title: l.safetyTitle, subtitle: l.safetySubtitle),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: IgniSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _commsCard(p, l, comms),
              const SizedBox(height: IgniSpacing.md),
              _footprintCard(p, l, beacon, coord),
              const SizedBox(height: IgniSpacing.md),
              _recentCard(p, l),
            ],
          ),
        ),
      ],
    );
  }

  /// Most recent of the auto-beacon's last send and the manual update.
  DateTime? _latestPresenceAt(PresenceBeaconController beacon) {
    final auto = beacon.lastBeaconAt;
    final manual = _lastManualPresenceAt;
    if (auto == null) return manual;
    if (manual == null) return auto;
    return auto.isAfter(manual) ? auto : manual;
  }

  Widget _commsCard(IgniPalette p, S l, CommunicationState comms) {
    final active = comms.meshRunning;
    return IgniCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(active ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
                size: 18, color: active ? p.ok : p.text2),
            const SizedBox(width: IgniSpacing.sm),
            Text(active ? l.safetyCommsOn : l.safetyCommsOff,
                style: IgniTypography.titleMedium(p.text0)),
            const Spacer(),
            IgniButton(
              label: active ? l.safetyTurnOff : l.safetyTurnOn,
              variant:
                  active ? IgniButtonVariant.ghost : IgniButtonVariant.primary,
              size: IgniButtonSize.small,
              onPressed: _busy ? null : _toggleComms,
            ),
          ]),
          const SizedBox(height: IgniSpacing.sm),
          // 最佳路徑：一眼看懂訊息目前怎麼送出。CommunicationState 維持純 Dart；
          // bestPath enum → 文案在這個 render seam 經 l10n（UI-H2c）。
          Row(children: [
            Icon(_pathIcon(comms.bestPath),
                size: 16, color: _pathColor(p, comms.bestPath)),
            const SizedBox(width: 6),
            Expanded(
              child: Text(l.safetyCurrentPath(_bestPathLabel(l, comms.bestPath)),
                  style: IgniTypography.bodyMedium(p.text0)),
            ),
          ]),
          const SizedBox(height: IgniSpacing.xs),
          Text(_cloudLabel(l, comms.cloudConfigured),
              style: IgniTypography.bodySmall(p.text2)),
          const SizedBox(height: IgniSpacing.sm),
          Wrap(spacing: IgniSpacing.lg, runSpacing: IgniSpacing.xs, children: [
            _stat(p, l.safetyStatPeers, comms.peers),
            _stat(p, l.safetyStatSent, comms.sentCount),
            _stat(p, l.safetyStatReceived, comms.receivedCount),
            _stat(p, l.safetyStatQueued, comms.outboxDepth),
          ]),
          const SizedBox(height: IgniSpacing.xs),
          Text(l.safetyLastFootprint(_fmtClock(comms.lastPresenceAt)),
              style: IgniTypography.bodySmall(p.text2)),
        ],
      ),
    );
  }

  Widget _stat(IgniPalette p, String label, int v) =>
      Text('$label $v', style: IgniTypography.bodySmall(p.text1));

  // CommsPath enum → 使用者文案（產品語、無工程/階段名）。communication_state.dart
  // 維持純 Dart 不 import l10n，故映射放在這個 render seam（UI-H2c）。
  String _bestPathLabel(S l, CommsPath path) {
    switch (path) {
      case CommsPath.noField:
        return l.commsPathNoField;
      case CommsPath.offline:
        return l.commsPathOffline;
      case CommsPath.waitingPeers:
        return l.commsPathWaiting;
      case CommsPath.meshRelay:
        return l.commsPathMesh;
    }
  }

  // Cloud 狀態一行 —— Stage A 永不宣稱可達/已連線（誠實措辭由 ARB 保證）。
  String _cloudLabel(S l, bool configured) =>
      configured ? l.cloudConfigured : l.cloudOffline;

  IconData _pathIcon(CommsPath path) {
    switch (path) {
      case CommsPath.meshRelay:
        return Icons.hub_outlined;
      case CommsPath.waitingPeers:
        return Icons.hourglass_empty;
      case CommsPath.offline:
        return Icons.cloud_off_outlined;
      case CommsPath.noField:
        return Icons.shield_outlined;
    }
  }

  Color _pathColor(IgniPalette p, CommsPath path) {
    switch (path) {
      case CommsPath.meshRelay:
        return p.ok;
      case CommsPath.waitingPeers:
        return p.warn;
      case CommsPath.offline:
      case CommsPath.noField:
        return p.text2;
    }
  }

  String _fmtClock(DateTime? t) =>
      t == null ? '—' : t.toIso8601String().substring(11, 19);

  Widget _footprintCard(IgniPalette p, S l, PresenceBeaconController beacon,
      LocationRefreshCoordinator coord) {
    return IgniCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.safetyFootprintTitle,
              style: IgniTypography.titleMedium(p.text0)),
          const SizedBox(height: IgniSpacing.xs),
          Text(l.safetyFootprintBody, style: IgniTypography.bodySmall(p.text2)),
          const SizedBox(height: IgniSpacing.sm),
          IgniButton(
            label: l.safetyUpdateNow,
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
            title: Text(l.safetyAutoBeacon,
                style: IgniTypography.bodyMedium(p.text0)),
            subtitle: Text(_beaconStatus(l, beacon),
                style: IgniTypography.bodySmall(p.text2)),
          ),
          const SizedBox(height: IgniSpacing.xs),
          Text(l.safetyMotion(_motionLabel(l, beacon.motionState)),
              style: IgniTypography.bodySmall(p.text3)),
          // §4.2 A11 diagnostics — last GPS fix age + honest GPS policy reason.
          // Low-battery cadence stays on the beacon line above, NOT mixed in here
          // (Owner boundary 8).
          Text(l.safetyGpsFix(_gpsAgeLabel(l, coord.lastFixAge)),
              style: IgniTypography.bodySmall(p.text3)),
          Text(l.safetyGpsPolicy(_gpsReasonLabel(l, coord.lastReason)),
              style: IgniTypography.bodySmall(p.text3)),
        ],
      ),
    );
  }

  String _gpsAgeLabel(S l, Duration? age) {
    if (age == null) return l.gpsNoFix;
    if (age.inSeconds < 60) return l.timeAgoSeconds(age.inSeconds);
    if (age.inMinutes < 60) return l.timeAgoMinutes(age.inMinutes);
    return l.timeAgoHours(age.inHours);
  }

  // Honest GPS policy reason (Owner boundary 8) — never shows low-battery here.
  String _gpsReasonLabel(S l, GpsPolicyReason r) {
    switch (r) {
      case GpsPolicyReason.movingRefresh:
        return l.gpsReasonMovingRefresh;
      case GpsPolicyReason.movingReuseFreshFix:
        return l.gpsReasonMovingReuse;
      case GpsPolicyReason.stationaryReuse:
        return l.gpsReasonStationary;
      case GpsPolicyReason.unknownReuse:
        return l.gpsReasonUnknown;
      case GpsPolicyReason.manualEvent:
        return l.gpsReasonManual;
      case GpsPolicyReason.unavailable:
        return l.gpsReasonUnavailable;
    }
  }

  String _beaconStatus(S l, PresenceBeaconController b) {
    if (!b.enabled) return l.beaconOff;
    final secs = b.currentInterval.inSeconds;
    final low = b.isLowBattery ? l.beaconLowSuffix : '';
    return l.beaconStatus(secs, b.beaconCount, low);
  }

  // UI-F5a diagnostic. `unknown` (no motion source yet — the F5a default) must
  // read「尚未啟用」, never「靜止」(Owner boundary 2).
  String _motionLabel(S l, MotionState m) {
    switch (m) {
      case MotionState.moving:
        return l.motionMoving;
      case MotionState.stationary:
        return l.motionStationary;
      case MotionState.unknown:
        return l.motionUnknown;
    }
  }

  Widget _recentCard(IgniPalette p, S l) {
    return IgniCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.safetyRecentTitle, style: IgniTypography.titleMedium(p.text0)),
          const SizedBox(height: IgniSpacing.sm),
          if (_footprints.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: IgniSpacing.sm),
              child:
                  Text(l.safetyNoFootprint, style: IgniTypography.bodySmall(p.text2)),
            )
          else
            ..._footprints.map((f) => _footprintRow(p, l, f)),
        ],
      ),
    );
  }

  Widget _footprintRow(IgniPalette p, S l, PresenceUpdate f) {
    final when = f.observedAt.toIso8601String().substring(11, 19);
    final where = (f.lat != null && f.lng != null)
        ? '${f.lat!.toStringAsFixed(5)}, ${f.lng!.toStringAsFixed(5)}'
        : l.noCoordinate;
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
