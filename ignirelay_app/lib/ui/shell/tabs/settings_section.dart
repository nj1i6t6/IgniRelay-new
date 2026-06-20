// SettingsSection —「我的」分頁的「設定」區（UI-H1）。
//
// 提供語言（中文 / English）與字體大小（標準 / 大字 / 特大字 / 超大字）兩個選擇器。
//
// 設計：純展示 widget，無自有 state。目前值由 [languageCode] / [textScale] 傳入，
// 使用者選擇以 [onLanguageSelected] / [onTextScaleSelected] 回呼出去。實際持久化由
// 呼叫端（MyTab → `IgniRelayApp.setLocale` / `setTextScale`）負責。
//
// 刻意不 import main.dart、不碰 SharedPreferences、不持有任何 controller ⇒
// 可獨立 pump 測互動（tap → 回呼 → 父層改值 → 選中狀態跟著走），且不把重型啟動
// 圖拉進單元測試。
//
// Stage A 僅 中文 / English，不做「系統」跟隨（plan §H1：現有 setLocale 簽名無法
// 乾淨表達 null/system，且 Stage A 不需要）。所有顏色走 token，0 Colors.*。

import 'package:flutter/material.dart';

import 'package:ignirelay_app/l10n/l10n_ext.dart';
import 'package:ignirelay_app/ui/theme/igni_colors.dart';
import 'package:ignirelay_app/ui/theme/igni_text_scale.dart';
import 'package:ignirelay_app/ui/theme/igni_tokens.dart';
import 'package:ignirelay_app/ui/theme/igni_typography.dart';
import 'package:ignirelay_app/ui/widgets/igni_card.dart';
import 'package:ignirelay_app/ui/widgets/igni_chip.dart';

class SettingsSection extends StatelessWidget {
  const SettingsSection({
    super.key,
    required this.languageCode,
    required this.textScale,
    required this.onLanguageSelected,
    required this.onTextScaleSelected,
  });

  /// 目前語系碼（'zh' / 'en'）。非 'en' 一律視為中文（含 'zh_Hant' 等）。
  final String languageCode;

  /// 目前字體大小。
  final IgniTextScale textScale;

  /// 使用者點選語言時回呼，帶上對應 [Locale]。
  final ValueChanged<Locale> onLanguageSelected;

  /// 使用者點選字體大小時回呼。
  final ValueChanged<IgniTextScale> onTextScaleSelected;

  @override
  Widget build(BuildContext context) {
    final p = context.igni;
    final l = context.l10n;
    final isEnglish = languageCode == 'en';
    // 字級標籤經 i18n（UI-H2a）；「中文」「English」是語言本名（endonym），兩語系皆
    // 維持原樣、刻意不翻譯。
    final textScaleChoices = <(IgniTextScale, String)>[
      (IgniTextScale.standard, l.settingsTextSizeStandard),
      (IgniTextScale.large, l.settingsTextSizeLarge),
      (IgniTextScale.xLarge, l.settingsTextSizeXLarge),
      (IgniTextScale.huge, l.settingsTextSizeHuge),
    ];
    return IgniCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.settingsSection, style: IgniTypography.titleMedium(p.text0)),
          const SizedBox(height: IgniSpacing.md),
          _fieldLabel(p, l.settingsLanguage),
          const SizedBox(height: IgniSpacing.xs),
          Wrap(
            spacing: IgniSpacing.sm,
            runSpacing: IgniSpacing.sm,
            children: [
              _choice(
                label: '中文',
                selected: !isEnglish,
                onTap: () => onLanguageSelected(const Locale('zh')),
              ),
              _choice(
                label: 'English',
                selected: isEnglish,
                onTap: () => onLanguageSelected(const Locale('en')),
              ),
            ],
          ),
          const SizedBox(height: IgniSpacing.md),
          _fieldLabel(p, l.settingsTextSize),
          const SizedBox(height: IgniSpacing.xs),
          Wrap(
            spacing: IgniSpacing.sm,
            runSpacing: IgniSpacing.sm,
            children: [
              for (final (scale, label) in textScaleChoices)
                _choice(
                  label: label,
                  selected: textScale == scale,
                  onTap: () => onTextScaleSelected(scale),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _fieldLabel(IgniPalette p, String text) =>
      Text(text, style: IgniTypography.bodySmall(p.text2));

  // 選中 = 品牌琥珀底（active）；未選 = 中性。InkWell 由 IgniChip.onTap 提供。
  Widget _choice({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return IgniChip(
      label: label,
      tone: selected ? IgniChipTone.brand : IgniChipTone.neutral,
      onTap: onTap,
    );
  }
}
