// EventsTab — UI-F2「事件」分頁。
//
// 彙整既有事件模組：ADMIN_BROADCAST 橫幅、危害回報（HazardCard 正式發送入口
// formalSend，participant+owner 皆可發）、定點通過（CheckpointCard）、以及最近事件
// 列表（SOS 與系統事件皆會出現於此）。重用既有 widget / EventStore，未改底層。
//
// 包裝層 token-clean（context.igni + ui/widgets），0 Colors.*。被重用的
// AdminBroadcastBanner / HazardCard / CheckpointCard 為既有 shell 卡片（其本身樣式之
// DESIGN token 化為後續 polish，非本刀）。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:ignirelay_app/app/controllers/event_stream.dart';
import 'package:ignirelay_app/app/services/event_store.dart';
import 'package:ignirelay_app/l10n/generated/app_localizations.dart';
import 'package:ignirelay_app/l10n/l10n_ext.dart';
import 'package:ignirelay_app/ui/shell/admin_broadcast_banner.dart';
import 'package:ignirelay_app/ui/shell/checkpoint_card.dart';
import 'package:ignirelay_app/ui/shell/hazard_card.dart';
import 'package:ignirelay_app/ui/theme/igni_colors.dart';
import 'package:ignirelay_app/ui/theme/igni_tokens.dart';
import 'package:ignirelay_app/ui/theme/igni_typography.dart';
import 'package:ignirelay_app/ui/widgets/igni_card.dart';
import 'package:ignirelay_app/ui/widgets/igni_sub_page_header.dart';
import 'package:ignirelay_app/ui/widgets/mono_text.dart';

class EventsTab extends StatefulWidget {
  const EventsTab({super.key});

  @override
  State<EventsTab> createState() => _EventsTabState();
}

class _EventsTabState extends State<EventsTab> {
  late final EventStore _store;
  late final EventStream _events;
  StreamSubscription<EventLogChanged>? _logSub;
  List<Map<String, dynamic>> _recent = const [];

  @override
  void initState() {
    super.initState();
    _store = context.read<EventStore>();
    _events = context.read<EventStream>();
    _logSub = _events.anyEventChanges.listen((_) => _refresh());
    _refresh();
  }

  @override
  void dispose() {
    _logSub?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final rows = await _store.queryRecent(limit: 50);
      if (mounted) setState(() => _recent = rows);
    } catch (_) {
      // 讀取失敗不致命，保留現有清單。
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.igni;
    final l = context.l10n;
    return ListView(
      padding: const EdgeInsets.only(bottom: IgniSpacing.xl3),
      children: [
        IgniSubPageHeader(title: l.eventsTitle, subtitle: l.eventsSubtitle),
        // ADMIN_BROADCAST 置頂橫幅（無有效公告時收合）。
        const AdminBroadcastBanner(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: IgniSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 正式危害回報入口（participant+owner 皆可發）。
              const HazardCard(formalSend: true),
              const SizedBox(height: IgniSpacing.md),
              const CheckpointCard(),
              const SizedBox(height: IgniSpacing.md),
              _recentCard(p, l),
            ],
          ),
        ),
      ],
    );
  }

  Widget _recentCard(IgniPalette p, S l) {
    return IgniCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text(l.eventsRecentTitle, style: IgniTypography.titleMedium(p.text0)),
            const Spacer(),
            IconButton(
              onPressed: _refresh,
              icon: Icon(Icons.refresh, size: 18, color: p.text2),
              tooltip: l.eventsRefresh,
            ),
          ]),
          if (_recent.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: IgniSpacing.sm),
              child: Text(l.eventsEmpty, style: IgniTypography.bodySmall(p.text2)),
            )
          else
            ..._recent.take(50).map((r) => _eventRow(p, l, r)),
        ],
      ),
    );
  }

  Widget _eventRow(IgniPalette p, S l, Map<String, dynamic> row) {
    final id = (row['event_id'] as String?) ?? '';
    final shortId = id.length <= 8 ? id : id.substring(0, 8);
    final type = row['event_type'];
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
          width: 72,
          child: MonoText(shortId.isEmpty ? '—' : shortId,
              fontSize: 11, color: p.text1),
        ),
        const SizedBox(width: IgniSpacing.sm),
        Expanded(
            child: Text(l.eventsRowType('$type'),
                style: IgniTypography.bodySmall(p.text1))),
        MonoText(when, fontSize: 11, color: p.text2),
      ]),
    );
  }
}
