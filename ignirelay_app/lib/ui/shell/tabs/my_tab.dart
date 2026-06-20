// MyTab —「我的」分頁（UI-F2 模組搬遷；UI-F3 身分與角色實作；UI-H1 設定區）。
//
// 作用場域摘要 + 場域管理入口（導向既有 A7 FieldScreen）+ 身分與角色（UI-F3：
// owner「主辦」/ participant「成員」，由本機建立 vs 加入推導）+ 設定（UI-H1：語言 /
// 字體大小，接既有 IgniRelayApp.setLocale/setTextScale）+ 權限狀態正式產品佔位
// （「即將提供」，OS 權限健康度與場域角色刻意分開，D10）+ 開發者診斷入口（僅 kDebugMode，
// 從 app_shell 移來；經 debug-only 命名路由進 DebugShell）。
//
// token-clean（context.igni + ui/widgets），0 Colors.*。

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:ignirelay_app/app/controllers/active_field_controller.dart';
import 'package:ignirelay_app/l10n/generated/app_localizations.dart';
import 'package:ignirelay_app/l10n/l10n_ext.dart';
import 'package:ignirelay_app/main.dart' show IgniRelayApp;
import 'package:ignirelay_app/ui/screens/field/field_screen.dart';
import 'package:ignirelay_app/ui/shell/app_shell.dart'
    show kDeveloperDiagnosticsRoute;
import 'package:ignirelay_app/ui/shell/tabs/settings_section.dart';
import 'package:ignirelay_app/ui/theme/igni_colors.dart';
import 'package:ignirelay_app/ui/theme/igni_tokens.dart';
import 'package:ignirelay_app/ui/theme/igni_typography.dart';
import 'package:ignirelay_app/ui/widgets/igni_button.dart';
import 'package:ignirelay_app/ui/widgets/igni_card.dart';
import 'package:ignirelay_app/ui/widgets/igni_chip.dart';
import 'package:ignirelay_app/ui/widgets/igni_sub_page_header.dart';
import 'package:ignirelay_app/ui/widgets/mono_text.dart';

class MyTab extends StatelessWidget {
  const MyTab({super.key});

  void _openField(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const FieldScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.igni;
    final l = context.l10n;
    final field = context.watch<ActiveFieldController>();
    final active = field.active;
    return ListView(
      padding: const EdgeInsets.only(bottom: IgniSpacing.xl3),
      children: [
        IgniSubPageHeader(title: l.myTitle, subtitle: l.mySubtitle),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: IgniSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _fieldCard(context, p, l, active, field.joinedFieldCount),
              const SizedBox(height: IgniSpacing.md),
              _roleCard(p, l, active),
              const SizedBox(height: IgniSpacing.md),
              // UI-H1：設定區（語言 / 字體大小）。目前值用 Localizations.localeOf /
              // IgniRelayApp.textScaleOf 讀；選擇後交給既有 root API 持久化（無新 store /
              // 無 locale getter）。SettingsSection 本身純展示、不 import main.dart。
              SettingsSection(
                languageCode: Localizations.localeOf(context).languageCode,
                textScale: IgniRelayApp.textScaleOf(context),
                onLanguageSelected: (locale) =>
                    IgniRelayApp.setLocale(context, locale),
                onTextScaleSelected: (scale) =>
                    IgniRelayApp.setTextScale(context, scale),
              ),
              const SizedBox(height: IgniSpacing.md),
              // 權限狀態 = OS permission health — kept SEPARATE from field role
              // above (UI-F3 / D10). Real status lands later (permission UX).
              _placeholderCard(p, l.myPermissionSection, l.myComingSoon),
              if (kDebugMode) ...[
                const SizedBox(height: IgniSpacing.xl),
                IgniButton(
                  label: l.myDeveloperDiagnostics,
                  icon: Icons.bug_report_outlined,
                  variant: IgniButtonVariant.ghost,
                  onPressed: () => Navigator.of(context)
                      .pushNamed(kDeveloperDiagnosticsRoute),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _fieldCard(BuildContext context, IgniPalette p, S l,
      ActiveField? active, int joined) {
    return IgniCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(active != null ? Icons.shield : Icons.shield_outlined,
                size: 18, color: active != null ? p.ok : p.text2),
            const SizedBox(width: IgniSpacing.sm),
            Text(l.myFieldSection, style: IgniTypography.titleMedium(p.text0)),
            const Spacer(),
            IgniButton(
              label: l.myFieldManage,
              icon: Icons.tune,
              variant: IgniButtonVariant.ghost,
              size: IgniButtonSize.small,
              onPressed: () => _openField(context),
            ),
          ]),
          const SizedBox(height: IgniSpacing.sm),
          if (active != null) ...[
            Text(
              l.myCurrentField(
                  active.displayName.isEmpty ? l.myFieldUnnamed : active.displayName),
              style: IgniTypography.bodyMedium(p.text0),
            ),
            const SizedBox(height: 2),
            // UI-H3-polish: the short-id + joined-count metadata can exceed one
            // line under the ~2.0 composite (the mono id does not break), so let
            // the two items flow onto a second line instead of overflowing.
            Wrap(
              spacing: IgniSpacing.sm,
              runSpacing: IgniSpacing.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                MonoText('${active.shortId}…', fontSize: 11, color: p.text2),
                Text(l.myFieldJoinedCount(joined),
                    style: IgniTypography.bodySmall(p.text2)),
              ],
            ),
          ] else
            Text(l.myNoField, style: IgniTypography.bodySmall(p.text2)),
        ],
      ),
    );
  }

  // 身分與角色 — field membership role (UI-F3). owner「主辦」/ participant「成員」,
  // derived from local create-vs-join. Distinct from OS 權限狀態 (D10).
  Widget _roleCard(IgniPalette p, S l, ActiveField? active) {
    return IgniCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.myRoleSection, style: IgniTypography.titleMedium(p.text0)),
                const SizedBox(height: IgniSpacing.xs),
                Text(
                  active == null
                      ? l.myRoleEmptyHint
                      : active.isOwner
                          ? l.myRoleOwnerDesc
                          : l.myRoleParticipantDesc,
                  style: IgniTypography.bodySmall(p.text2),
                ),
              ],
            ),
          ),
          if (active != null) ...[
            const SizedBox(width: IgniSpacing.sm),
            IgniChip(
              label: active.isOwner ? l.roleHost : l.roleMember,
              tone: active.isOwner ? IgniChipTone.ok : IgniChipTone.info,
            ),
          ],
        ],
      ),
    );
  }

  Widget _placeholderCard(IgniPalette p, String title, String note) {
    return IgniCard(
      child: Row(children: [
        Expanded(child: Text(title, style: IgniTypography.titleMedium(p.text0))),
        Text(note, style: IgniTypography.bodySmall(p.text3)),
      ]),
    );
  }
}
