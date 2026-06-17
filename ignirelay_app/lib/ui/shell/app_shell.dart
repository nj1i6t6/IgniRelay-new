// AppShell — 烽傳 IgniRelay 正式產品殼（UI-F1 殼骨架 + UI-F2 模組搬遷）。
//
// 取代舊的 mapless `DebugShell` 成為 production home（main.dart `_StartupRouter`
// 在 onboarding/權限完成後改回傳本殼）：
//
//   • 無 active field → [NoFieldEntry]（加入場域 / 建立場域 / 先看功能）。
//   • 有 active field → 五分頁 scaffold（安全 / 位置 / 事件 / 協助 / 我的）
//     + 全域 SOS（每個分頁都可達）。
//
// UI-F2 將既有模組移入各分頁（`lib/ui/shell/tabs/`）：安全=SafetyTab、
// 位置=LastSeenScreen、事件=EventsTab、協助=AssistTab、我的=MyTab。
//
// 刻意不做（留後續小任務，見 docs/APP_UI_IA_REWORK_PLAN.md §4.0）：
//   • owner/participant 角色模型 → UI-F3（「我的」顯示產品佔位）。
//   • CommunicationState 聚合 → UI-F4（「安全」顯示產品佔位）。
//   • motion-aware 定位節流 → UI-F5。
//   • 「先看功能」引導模式 → UI-G（此處僅提示佔位）。
//
// DESIGN_LANGUAGE §4：本殼是正式畫面，一律經 `context.igni` 與 `ui/widgets/`
// 既有元件取值，檔內不寫死 `Colors.*` / hex。`DebugShell` 僅能經
// [kDeveloperDiagnosticsRoute]（main.dart 中只在 kDebugMode/kProfileMode 註冊）
// 進入，且該入口只在 kDebugMode 渲染——release/production home 不得直接落 DebugShell。

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:ignirelay_app/app/controllers/active_field_controller.dart';
import 'package:ignirelay_app/ui/screens/field/field_screen.dart';
import 'package:ignirelay_app/ui/screens/position/last_seen_screen.dart';
import 'package:ignirelay_app/ui/screens/sos/sos_screen.dart';
import 'package:ignirelay_app/ui/shell/tabs/assist_tab.dart';
import 'package:ignirelay_app/ui/shell/tabs/events_tab.dart';
import 'package:ignirelay_app/ui/shell/tabs/my_tab.dart';
import 'package:ignirelay_app/ui/shell/tabs/safety_tab.dart';
import 'package:ignirelay_app/ui/theme/igni_colors.dart';
import 'package:ignirelay_app/ui/theme/igni_tokens.dart';
import 'package:ignirelay_app/ui/theme/igni_typography.dart';
import 'package:ignirelay_app/ui/widgets/igni_button.dart';

/// 開發者診斷路由名。`main.dart` 只在 `kDebugMode || kProfileMode` 註冊此路由
/// （與 `/design-showcase` 同模式），release build 完全不存在。
const String kDeveloperDiagnosticsRoute = '/debug-shell';

/// 五分頁 label——**單一真實來源**。UI-F1 DoD：精確為這五個、順序固定，
/// 且不得出現「地圖」。tab 列與 smoke test 都引用本常數。
const List<String> kAppShellTabLabels = <String>[
  '安全',
  '位置',
  '事件',
  '協助',
  '我的',
];

/// 全域 SOS 鈕的 key——讓 smoke test 能不靠文字（避免與分頁內容裡的「SOS」字面
/// 衝突）就定位到「每個分頁都可達」的那顆求救鍵。
const Key kGlobalSosButtonKey = Key('app_shell_global_sos');

/// production home。依 active field 狀態切「no-field entry」或「五分頁殼」。
class AppShell extends StatelessWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context) {
    // ActiveFieldController 是 ChangeNotifier：join/leave 時自動 rebuild，
    // no-field entry ⇄ 五分頁殼 自動切換。
    final hasField = context.watch<ActiveFieldController>().hasActiveField;
    return hasField ? const _AppShellTabs() : const NoFieldEntry();
  }
}

/// 無 active field 時的入口畫面：加入場域 / 建立場域 / 先看功能。
///
/// 「加入場域」「建立場域」導向既有的 [FieldScreen]（A7，已含掃碼/代碼/建立）；
/// 加入或建立成功後 [ActiveFieldController] 變動 → [AppShell] 自動切到五分頁殼。
/// 「先看功能」在 UI-F1 僅佔位（引導模式實作留 UI-G）。
class NoFieldEntry extends StatelessWidget {
  const NoFieldEntry({super.key});

  void _openField(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const FieldScreen()),
    );
  }

  void _previewStub(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('先看功能即將提供。')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.igni;
    return Scaffold(
      backgroundColor: p.bg0,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
            horizontal: IgniSpacing.xl2,
            vertical: IgniSpacing.xl3,
          ),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '烽傳 IgniRelay',
                    style: IgniTypography.titleLarge(p.text0),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: IgniSpacing.sm),
                  Text(
                    '加入或建立一個場域，開始被看見、能求救、留下最後足跡。',
                    style: IgniTypography.bodyMedium(p.text2),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: IgniSpacing.xl3),
                  IgniButton(
                    label: '加入場域',
                    icon: Icons.qr_code_scanner,
                    size: IgniButtonSize.large,
                    fullWidth: true,
                    onPressed: () => _openField(context),
                  ),
                  const SizedBox(height: IgniSpacing.md),
                  IgniButton(
                    label: '建立場域',
                    icon: Icons.add_circle_outline,
                    variant: IgniButtonVariant.ghost,
                    size: IgniButtonSize.large,
                    fullWidth: true,
                    onPressed: () => _openField(context),
                  ),
                  const SizedBox(height: IgniSpacing.md),
                  IgniButton(
                    label: '先看功能',
                    icon: Icons.visibility_outlined,
                    variant: IgniButtonVariant.ghost,
                    size: IgniButtonSize.large,
                    fullWidth: true,
                    onPressed: () => _previewStub(context),
                  ),
                  const SizedBox(height: IgniSpacing.sm),
                  Text(
                    '先看功能即將提供。',
                    style: IgniTypography.bodySmall(p.text3),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 五分頁 scaffold + 全域 SOS。分頁內容由 `lib/ui/shell/tabs/` 的模組提供（UI-F2）。
class _AppShellTabs extends StatefulWidget {
  const _AppShellTabs();

  @override
  State<_AppShellTabs> createState() => _AppShellTabsState();
}

class _AppShellTabsState extends State<_AppShellTabs> {
  int _index = 0;

  // 與 [kAppShellTabLabels] 平行對位的分頁圖示（Material 內建向量圖示，
  // 非 icon-font 套件/emoji，符合 DESIGN §5）。
  static const List<IconData> _tabIcons = <IconData>[
    Icons.shield_outlined, // 安全
    Icons.place_outlined, // 位置（非「地圖」）
    Icons.event_note_outlined, // 事件
    Icons.support_agent, // 協助
    Icons.person_outline, // 我的
  ];

  // 與 [kAppShellTabLabels] 平行對位的分頁內容（UI-F2 模組搬遷）。順序＝
  // 安全 / 位置 / 事件 / 協助 / 我的。位置直接嵌入既有 LastSeenScreen（A10/A10b）。
  static const List<Widget> _tabBodies = <Widget>[
    SafetyTab(),
    LastSeenScreen(),
    EventsTab(),
    AssistTab(),
    MyTab(),
  ];

  @override
  Widget build(BuildContext context) {
    final p = context.igni;
    return Scaffold(
      backgroundColor: p.bg0,
      body: SafeArea(
        bottom: false,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Each tab is wrapped in TickerMode(enabled: i == _index) so the
            // non-selected tabs' tickers AND their periodic UI refreshes pause
            // while offstage (UI-F5a power-saving). IndexedStack keeps them
            // built; TickerMode just mutes the inactive ones.
            IndexedStack(
              index: _index,
              children: <Widget>[
                for (int i = 0; i < _tabBodies.length; i++)
                  TickerMode(enabled: i == _index, child: _tabBodies[i]),
              ],
            ),
            // 全域 SOS：錨在 body 右下、位於 bottom tab bar 之上（不重疊分頁切換
            // 的點擊區）。每個分頁都看得到、都可觸發。
            const Positioned(
              right: IgniSpacing.lg,
              bottom: IgniSpacing.lg,
              child: _GlobalSosButton(),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _BottomTabBar(
        index: _index,
        icons: _tabIcons,
        labels: kAppShellTabLabels,
        onTap: (i) => setState(() => _index = i),
      ),
    );
  }
}

/// 全域 SOS 進入鈕——導向既有 [SosScreen]（A8）。不改動 SOS 底層行為，只是入口。
class _GlobalSosButton extends StatelessWidget {
  const _GlobalSosButton();

  @override
  Widget build(BuildContext context) {
    return IgniButton(
      key: kGlobalSosButtonKey,
      label: 'SOS',
      icon: Icons.sos,
      variant: IgniButtonVariant.sos,
      size: IgniButtonSize.large,
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const SosScreen()),
      ),
    );
  }
}

/// 底部五分頁列（自繪以完全吃 token；避免 Material NavigationBar 主題外漏色）。
class _BottomTabBar extends StatelessWidget {
  const _BottomTabBar({
    required this.index,
    required this.icons,
    required this.labels,
    required this.onTap,
  });

  final int index;
  final List<IconData> icons;
  final List<String> labels;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.igni;
    return Material(
      color: p.bg1,
      child: Container(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: p.border1)),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: IgniSpacing.bottomTabBarHeight,
            child: Row(
              children: [
                for (int i = 0; i < labels.length; i++)
                  Expanded(child: _item(p, i)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _item(IgniPalette p, int i) {
    final selected = i == index;
    final color = selected ? p.brand : p.text2;
    return InkWell(
      onTap: () => onTap(i),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icons[i], size: 22, color: color),
          const SizedBox(height: 4),
          Text(labels[i], style: IgniTypography.bodySmall(color)),
        ],
      ),
    );
  }
}
