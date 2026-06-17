// MyTab —「我的」分頁（UI-F2 模組搬遷；UI-F3 身分與角色實作）。
//
// 作用場域摘要 + 場域管理入口（導向既有 A7 FieldScreen）+ 身分與角色（UI-F3：
// owner「主辦」/ participant「成員」，由本機建立 vs 加入推導）+ 權限狀態正式產品佔位
// （「即將提供」，OS 權限健康度與場域角色刻意分開，D10）+ 開發者診斷入口（僅 kDebugMode，
// 從 app_shell 移來；經 debug-only 命名路由進 DebugShell）。
//
// token-clean（context.igni + ui/widgets），0 Colors.*。

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:ignirelay_app/app/controllers/active_field_controller.dart';
import 'package:ignirelay_app/ui/screens/field/field_screen.dart';
import 'package:ignirelay_app/ui/shell/app_shell.dart'
    show kDeveloperDiagnosticsRoute;
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
    final field = context.watch<ActiveFieldController>();
    final active = field.active;
    return ListView(
      padding: const EdgeInsets.only(bottom: IgniSpacing.xl3),
      children: [
        const IgniSubPageHeader(title: '我的', subtitle: '場域、身分與設定'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: IgniSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _fieldCard(context, p, active, field.joinedFieldCount),
              const SizedBox(height: IgniSpacing.md),
              _roleCard(p, active),
              const SizedBox(height: IgniSpacing.md),
              // 權限狀態 = OS permission health — kept SEPARATE from field role
              // above (UI-F3 / D10). Real status lands later (permission UX).
              _placeholderCard(p, '權限狀態', '即將提供'),
              if (kDebugMode) ...[
                const SizedBox(height: IgniSpacing.xl),
                IgniButton(
                  label: '開發者診斷',
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

  Widget _fieldCard(
      BuildContext context, IgniPalette p, ActiveField? active, int joined) {
    return IgniCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(active != null ? Icons.shield : Icons.shield_outlined,
                size: 18, color: active != null ? p.ok : p.text2),
            const SizedBox(width: IgniSpacing.sm),
            Text('場域', style: IgniTypography.titleMedium(p.text0)),
            const Spacer(),
            IgniButton(
              label: '場域管理',
              icon: Icons.tune,
              variant: IgniButtonVariant.ghost,
              size: IgniButtonSize.small,
              onPressed: () => _openField(context),
            ),
          ]),
          const SizedBox(height: IgniSpacing.sm),
          if (active != null) ...[
            Text(
              '目前場域：${active.displayName.isEmpty ? "（未命名）" : active.displayName}',
              style: IgniTypography.bodyMedium(p.text0),
            ),
            const SizedBox(height: 2),
            Row(children: [
              MonoText('${active.shortId}…', fontSize: 11, color: p.text2),
              const SizedBox(width: IgniSpacing.sm),
              Text('已加入 $joined 個', style: IgniTypography.bodySmall(p.text2)),
            ]),
          ] else
            Text('尚未加入場域。', style: IgniTypography.bodySmall(p.text2)),
        ],
      ),
    );
  }

  // 身分與角色 — field membership role (UI-F3). owner「主辦」/ participant「成員」,
  // derived from local create-vs-join. Distinct from OS 權限狀態 (D10).
  Widget _roleCard(IgniPalette p, ActiveField? active) {
    return IgniCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('身分與角色', style: IgniTypography.titleMedium(p.text0)),
                const SizedBox(height: IgniSpacing.xs),
                Text(
                  active == null
                      ? '加入或建立場域後顯示。'
                      : active.isOwner
                          ? '你建立了這個場域，可分享加入 QR。'
                          : '你已加入這個場域。',
                  style: IgniTypography.bodySmall(p.text2),
                ),
              ],
            ),
          ),
          if (active != null) ...[
            const SizedBox(width: IgniSpacing.sm),
            IgniChip(
              label: active.isOwner ? '主辦' : '成員',
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
