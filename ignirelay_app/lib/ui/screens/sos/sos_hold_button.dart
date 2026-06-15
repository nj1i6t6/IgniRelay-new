import 'package:flutter/material.dart';

import 'package:ignirelay_app/ui/theme/igni_colors.dart';
import 'package:ignirelay_app/ui/theme/igni_typography.dart';

/// 按住 [holdDuration]（預設 1.5s）才觸發的 SOS 求救鈕（A8 誤觸防護第一關）。
///
/// 按下開始填滿進度環，放開或滑出在完成前一律中止、不觸發；填滿後呼叫
/// [onHoldComplete]。圓鈕直徑預設 160dp（DESIGN_LANGUAGE §2.3「SOS 主鈕 ≥96dp」）。
/// 進度環是 hold 的功能性回饋（非裝飾動效）。色彩經 [color] / `context.igni` 取得，
/// 不寫死 Material 調色常數。
class SosHoldButton extends StatefulWidget {
  const SosHoldButton({
    super.key,
    required this.label,
    required this.color,
    required this.onHoldComplete,
    this.holdDuration = const Duration(milliseconds: 1500),
    this.size = 160,
  });

  final String label;
  final Color color;
  final VoidCallback onHoldComplete;
  final Duration holdDuration;
  final double size;

  @override
  State<SosHoldButton> createState() => _SosHoldButtonState();
}

class _SosHoldButtonState extends State<SosHoldButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: widget.holdDuration,
  )..addStatusListener(_onStatus);

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      _ctrl.reset();
      widget.onHoldComplete();
    }
  }

  void _start() => _ctrl.forward(from: 0);

  void _end() {
    if (_ctrl.status != AnimationStatus.completed) _ctrl.reset();
  }

  @override
  void dispose() {
    _ctrl
      ..removeStatusListener(_onStatus)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.igni;
    return GestureDetector(
      onTapDown: (_) => _start(),
      onTapUp: (_) => _end(),
      onTapCancel: _end,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          return SizedBox(
            width: widget.size,
            height: widget.size,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  decoration:
                      BoxDecoration(shape: BoxShape.circle, color: widget.color),
                ),
                SizedBox(
                  width: widget.size,
                  height: widget.size,
                  child: CircularProgressIndicator(
                    value: _ctrl.value,
                    strokeWidth: 6,
                    valueColor: AlwaysStoppedAnimation<Color>(p.text0),
                    backgroundColor: p.text0.withValues(alpha: 0.25),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    widget.label,
                    textAlign: TextAlign.center,
                    style: IgniTypography.titleMedium(p.text0)
                        .copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
