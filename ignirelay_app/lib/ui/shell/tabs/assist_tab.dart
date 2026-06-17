// AssistTab — UI-F2「協助」分頁。
//
// UI-F1/F2 階段為正式產品佔位：離線協助資源與「求救後續引導」屬後續任務（E-CARE 為
// 更後面的 EC 系列），目前沒有可搬入的既有模組。文案為正式產品語（「即將提供」），
// 不出現內部任務名/除錯字樣。緊急求救由全域求救鍵負責（AppShell 已提供）。
//
// token-clean（context.igni + ui/widgets），0 Colors.*。

import 'package:flutter/material.dart';

import 'package:ignirelay_app/ui/theme/igni_colors.dart';
import 'package:ignirelay_app/ui/theme/igni_tokens.dart';
import 'package:ignirelay_app/ui/theme/igni_typography.dart';
import 'package:ignirelay_app/ui/widgets/igni_card.dart';
import 'package:ignirelay_app/ui/widgets/igni_sub_page_header.dart';

class AssistTab extends StatelessWidget {
  const AssistTab({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.igni;
    return ListView(
      padding: const EdgeInsets.only(bottom: IgniSpacing.xl3),
      children: [
        const IgniSubPageHeader(title: '協助', subtitle: '離線協助與求助資源'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: IgniSpacing.lg),
          child: IgniCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('離線協助', style: IgniTypography.titleMedium(p.text0)),
                const SizedBox(height: IgniSpacing.xs),
                Text(
                  '離線求助資源與求救後續引導即將提供。需要緊急求救時，'
                  '可隨時使用畫面上的全域求救鍵。',
                  style: IgniTypography.bodySmall(p.text2),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
