// PreviewScreen —「先看功能」guided preview / tutorial (UI-G).
//
// A bounded, FIXTURE-ONLY guided tour reachable from the no-field entry. It lets
// a new user understand the product BEFORE joining a real field — WITHOUT
// pretending to join: it starts no networking, publishes no wire event, writes no
// real membership, requests no permission, and shows no real secret.
//
// HARD RULES (docs/APP_UI_IA_REWORK_PLAN.md §5 + MASTER UI-G):
//   • Fixture data only (see preview_fixtures.dart) — never fed to a publisher.
//     This screen holds NO publisher / controller / location provider, so it is
//     STRUCTURALLY incapable of sending a real event (D2/D5).
//   • Token-clean (this file is under lib/ui/screens/ → DESIGN §6 grep gate):
//     all colour via `context.igni`, no hard-coded Material colour / hex.
//   • Position copy is 「最後可信位置」, NEVER 「目前位置」 (§3.6).
//   • Exit paths: 加入場域 / 建立場域 → FieldScreen (pushReplacement, so the
//     preview never lingers on the nav stack after a join); 返回 → pop.
//   • Imports: design system + app/services (PositionEstimate via fixtures) +
//     the pure RelativeRadar + FieldScreen. It imports NO real controller,
//     publisher, location, or transport code (grep + import-guard test enforce it).

import 'package:flutter/material.dart';

import 'package:ignirelay_app/l10n/l10n_ext.dart';
import 'package:ignirelay_app/ui/screens/field/field_screen.dart';
import 'package:ignirelay_app/ui/screens/position/relative_radar.dart';
import 'package:ignirelay_app/ui/screens/preview/preview_fixtures.dart';
import 'package:ignirelay_app/ui/theme/igni_colors.dart';
import 'package:ignirelay_app/ui/theme/igni_tokens.dart';
import 'package:ignirelay_app/ui/theme/igni_typography.dart';
import 'package:ignirelay_app/ui/widgets/igni_button.dart';
import 'package:ignirelay_app/ui/widgets/igni_card.dart';
import 'package:ignirelay_app/ui/widgets/status_chip.dart';

class PreviewScreen extends StatefulWidget {
  const PreviewScreen({super.key});

  @override
  State<PreviewScreen> createState() => _PreviewScreenState();
}

class _PreviewScreenState extends State<PreviewScreen> {
  final PageController _pages = PageController();
  int _index = 0;

  static const int _count = 5;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _next() {
    if (_index < _count - 1) {
      _pages.animateToPage(_index + 1,
          duration: IgniMotion.medium, curve: IgniMotion.standard);
    }
  }

  void _prev() {
    if (_index > 0) {
      _pages.animateToPage(_index - 1,
          duration: IgniMotion.medium, curve: IgniMotion.standard);
    }
  }

  /// 加入 / 建立場域 → 既有 [FieldScreen]（A7）。用 pushReplacement 取代預覽
  /// route，避免加入成功後預覽殘留在 nav stack（與 NoFieldEntry 同目的地）。
  void _openField() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const FieldScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.igni;
    final l = context.l10n;
    final last = _index == _count - 1;
    return Scaffold(
      backgroundColor: p.bg0,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _Header(),
            Expanded(
              child: PageView(
                controller: _pages,
                onPageChanged: (i) => setState(() => _index = i),
                children: const [
                  _JoinPage(),
                  _SafetyPage(),
                  _PositionPage(),
                  _EventsPage(),
                  _AssistPage(),
                ],
              ),
            ),
            _Dots(index: _index, count: _count),
            Padding(
              padding: const EdgeInsets.fromLTRB(IgniSpacing.lg, IgniSpacing.sm,
                  IgniSpacing.lg, IgniSpacing.lg),
              child: Row(
                children: [
                  Expanded(
                    child: IgniButton(
                      label: _index == 0 ? l.previewBack : l.previewPrev,
                      variant: IgniButtonVariant.ghost,
                      onPressed: _index == 0
                          ? () => Navigator.of(context).maybePop()
                          : _prev,
                    ),
                  ),
                  const SizedBox(width: IgniSpacing.md),
                  Expanded(
                    child: IgniButton(
                      label: last ? l.noFieldJoin : l.previewNext,
                      icon: last ? Icons.qr_code_scanner : null,
                      onPressed: last ? _openField : _next,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Shared chrome ───────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final p = context.igni;
    final l = context.l10n;
    return Padding(
      padding: const EdgeInsets.fromLTRB(IgniSpacing.lg,
          IgniSpacing.screenTitleTop, IgniSpacing.lg, IgniSpacing.lg),
      child: Row(
        children: [
          Material(
            color: p.bg2,
            shape: RoundedRectangleBorder(
              borderRadius: const BorderRadius.all(IgniRadii.pill),
              side: BorderSide(color: p.border0),
            ),
            child: InkWell(
              onTap: () => Navigator.of(context).maybePop(),
              borderRadius: const BorderRadius.all(IgniRadii.pill),
              child: SizedBox(
                width: 38,
                height: 38,
                child: Icon(Icons.arrow_back, size: 18, color: p.text0),
              ),
            ),
          ),
          const SizedBox(width: IgniSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(l.noFieldPreview, style: IgniTypography.titleLarge(p.text0)),
                const SizedBox(height: 2),
                Text(l.previewModeSubtitle,
                    style: IgniTypography.bodySmall(p.text2)),
              ],
            ),
          ),
          StatusChip(
            label: l.previewBadge,
            tone: StatusTone.warn,
            icon: Icons.visibility_outlined,
          ),
        ],
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.index, required this.count});
  final int index;
  final int count;

  @override
  Widget build(BuildContext context) {
    final p = context.igni;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (int i = 0; i < count; i++)
          Container(
            width: i == index ? 18 : 7,
            height: 7,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            decoration: BoxDecoration(
              color: i == index ? p.brand : p.border2,
              borderRadius: const BorderRadius.all(IgniRadii.pill),
            ),
          ),
      ],
    );
  }
}

/// 每頁的捲動容器：標題 lead + 內容卡片。
class _Page extends StatelessWidget {
  const _Page({
    required this.icon,
    required this.title,
    required this.intro,
    required this.children,
  });

  final IconData icon;
  final String title;
  final String intro;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final p = context.igni;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
          IgniSpacing.lg, 0, IgniSpacing.lg, IgniSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 22, color: p.brand),
              const SizedBox(width: IgniSpacing.sm),
              Expanded(
                child: Text(title, style: IgniTypography.titleMedium(p.text0)),
              ),
            ],
          ),
          const SizedBox(height: IgniSpacing.sm),
          Text(intro, style: IgniTypography.bodyMedium(p.text2)),
          const SizedBox(height: IgniSpacing.lg),
          ...children,
        ],
      ),
    );
  }
}

/// 加入 / 建立場域 CTA 組（頁內結束路徑）。
class _JoinCtas extends StatelessWidget {
  const _JoinCtas();

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final state = context.findAncestorStateOfType<_PreviewScreenState>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        IgniButton(
          label: l.noFieldJoin,
          icon: Icons.qr_code_scanner,
          fullWidth: true,
          onPressed: () => state?._openField(),
        ),
        const SizedBox(height: IgniSpacing.sm),
        IgniButton(
          label: l.noFieldCreate,
          icon: Icons.add_circle_outline,
          variant: IgniButtonVariant.ghost,
          fullWidth: true,
          onPressed: () => state?._openField(),
        ),
      ],
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.title, required this.body, this.icon});
  final String title;
  final String body;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final p = context.igni;
    return IgniCard(
      margin: const EdgeInsets.only(bottom: IgniSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18, color: p.text1),
                const SizedBox(width: IgniSpacing.sm),
              ],
              Expanded(
                child:
                    Text(title, style: IgniTypography.labelLarge(p.text0)),
              ),
            ],
          ),
          const SizedBox(height: IgniSpacing.xs),
          Text(body, style: IgniTypography.bodySmall(p.text2)),
        ],
      ),
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow(this.event);
  final PreviewEvent event;

  @override
  Widget build(BuildContext context) {
    final p = context.igni;
    return IgniCard(
      margin: const EdgeInsets.only(bottom: IgniSpacing.sm),
      padding: const EdgeInsets.symmetric(
          horizontal: IgniSpacing.md, vertical: IgniSpacing.md),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(event.title, style: IgniTypography.labelLarge(p.text0)),
                const SizedBox(height: 2),
                Text('${event.detail} · ${event.agoLabel}',
                    style: IgniTypography.bodySmall(p.text2)),
              ],
            ),
          ),
          const SizedBox(width: IgniSpacing.sm),
          StatusChip(
              label: _toneLabel(context, event.tone),
              tone: event.tone,
              dense: true),
        ],
      ),
    );
  }

  String _toneLabel(BuildContext context, StatusTone t) {
    final l = context.l10n;
    switch (t) {
      case StatusTone.sos:
        return l.previewToneSos;
      case StatusTone.warn:
        return l.previewToneWarn;
      case StatusTone.info:
        return l.previewToneInfo;
      case StatusTone.ok:
        return l.previewToneOk;
      case StatusTone.brand:
      case StatusTone.neutral:
        return l.previewToneNeutral;
    }
  }
}

class _FootprintRow extends StatelessWidget {
  const _FootprintRow(this.footprint);
  final PreviewFootprint footprint;

  @override
  Widget build(BuildContext context) {
    final p = context.igni;
    final isSos = footprint.tone == StatusTone.sos;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: IgniSpacing.xs),
      child: Row(
        children: [
          Icon(isSos ? Icons.sos : Icons.person_pin_circle_outlined,
              size: 18, color: isSos ? p.sos : p.text2),
          const SizedBox(width: IgniSpacing.sm),
          Text(footprint.anon8, style: IgniTypography.monoSmall(p.text1)),
          const SizedBox(width: IgniSpacing.sm),
          Expanded(
            child: Text(context.l10n.previewFootprintLine(footprint.agoLabel),
                style: IgniTypography.bodySmall(p.text2),
                overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}

// ── Pages ─────────────────────────────────────────────────────────────────

class _JoinPage extends StatelessWidget {
  const _JoinPage();
  @override
  Widget build(BuildContext context) {
    final p = context.igni;
    final l = context.l10n;
    return _Page(
      icon: Icons.qr_code_scanner,
      title: l.noFieldJoin,
      intro: l.previewJoinIntro,
      children: [
        IgniCard(
          margin: const EdgeInsets.only(bottom: IgniSpacing.lg),
          child: Row(
            children: [
              Icon(Icons.groups_outlined, size: 20, color: p.brand),
              const SizedBox(width: IgniSpacing.sm),
              Expanded(
                child: Text(previewFieldLabel(l),
                    style: IgniTypography.labelLarge(p.text0)),
              ),
              StatusChip(
                  label: l.previewDemoChip,
                  tone: StatusTone.warn,
                  dense: true),
            ],
          ),
        ),
        const _JoinCtas(),
      ],
    );
  }
}

class _SafetyPage extends StatelessWidget {
  const _SafetyPage();
  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return _Page(
      icon: Icons.shield_outlined,
      title: l.previewSafetyTitle,
      intro: l.previewSafetyIntro,
      children: [
        _InfoCard(
          icon: Icons.my_location,
          title: l.previewSafetyFootprintTitle,
          body: l.previewSafetyFootprintBody,
        ),
        _InfoCard(
          icon: Icons.sos,
          title: l.previewSafetySosTitle,
          body: l.previewSafetySosBody,
        ),
        _EventRow(previewSos(l)),
      ],
    );
  }
}

class _PositionPage extends StatelessWidget {
  const _PositionPage();
  @override
  Widget build(BuildContext context) {
    final p = context.igni;
    final l = context.l10n;
    return _Page(
      icon: Icons.place_outlined,
      title: l.previewPositionTitle,
      intro: l.previewPositionIntro,
      children: [
        IgniCard(
          margin: const EdgeInsets.only(bottom: IgniSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final f in previewFootprints(l)) _FootprintRow(f),
            ],
          ),
        ),
        // 雷達放在固定高度的有界盒內，避免 PageView/捲動約束造成無界高度
        // （RelativeRadar 內含 Expanded + LayoutBuilder，外層須給定高度）。
        Container(
          decoration: BoxDecoration(
            color: p.bg1,
            border: Border.all(color: p.border0),
            borderRadius: const BorderRadius.all(IgniRadii.lg),
          ),
          padding: const EdgeInsets.all(IgniSpacing.md),
          child: SizedBox(
            height: 320,
            child: RelativeRadar(
              origin: kPreviewOrigin,
              subjects: previewRadarSubjects(l),
            ),
          ),
        ),
      ],
    );
  }
}

class _EventsPage extends StatelessWidget {
  const _EventsPage();
  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return _Page(
      icon: Icons.event_note_outlined,
      title: l.previewEventsTitle,
      intro: l.previewEventsIntro,
      children: [
        _EventRow(previewHazard(l)),
        _EventRow(previewBroadcast(l)),
        _EventRow(previewCheckpoint(l)),
      ],
    );
  }
}

class _AssistPage extends StatelessWidget {
  const _AssistPage();
  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return _Page(
      icon: Icons.support_agent,
      title: l.previewAssistTitle,
      intro: l.previewAssistIntro,
      children: [
        _InfoCard(
          icon: Icons.volunteer_activism_outlined,
          title: l.previewAssistMatchTitle,
          body: l.previewAssistMatchBody,
        ),
        _InfoCard(
          icon: Icons.wifi_off,
          title: l.previewAssistOfflineTitle,
          body: l.previewAssistOfflineBody,
        ),
        const SizedBox(height: IgniSpacing.sm),
        const _JoinCtas(),
      ],
    );
  }
}
