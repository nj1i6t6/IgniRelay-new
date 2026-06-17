// MyTab — UI-F2「我的」分頁。
//
// 作用場域摘要 + 場域管理入口（導向既有 A7 FieldScreen）+ 身分/角色、權限狀態的正式
// 產品佔位（「即將提供」，角色模型留 UI-F3）+ 開發者診斷入口（僅 kDebugMode，從
// app_shell 移來；經 debug-only 命名路由進 DebugShell）。
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
              _placeholderCard(p, '身分與角色', '即將提供'),
              const SizedBox(height: IgniSpacing.md),
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

  Widget _placeholderCard(IgniPalette p, String title, String note) {
    return IgniCard(
      child: Row(children: [
        Expanded(child: Text(title, style: IgniTypography.titleMedium(p.text0))),
        Text(note, style: IgniTypography.bodySmall(p.text3)),
      ]),
    );
  }
}
