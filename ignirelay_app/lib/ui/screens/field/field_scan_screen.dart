import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'package:ignirelay_app/app/services/field_qr_codec.dart';
import 'package:ignirelay_app/l10n/generated/app_localizations.dart';
import 'package:ignirelay_app/l10n/l10n_ext.dart';
import 'package:ignirelay_app/ui/theme/igni_colors.dart';
import 'package:ignirelay_app/ui/theme/igni_tokens.dart';
import 'package:ignirelay_app/ui/theme/igni_typography.dart';

/// 掃碼加入場域（A7）。掃到第一個合法的 `IGNI1` 場域代碼即 `pop(rawValue)` 回
/// [FieldScreen]，由其驗證並加入；不合法 / 非 IgniRelay 的碼只提示、繼續掃，
/// 全程不 crash（DoD D2）。實機掃碼真實驗證歸 A11 USER-GATE。
///
/// 守 DESIGN_LANGUAGE §4：經 `context.igni` 取色，screen 內不寫死 Material 調色常數。
class FieldScanScreen extends StatefulWidget {
  const FieldScanScreen({super.key});

  @override
  State<FieldScanScreen> createState() => _FieldScanScreenState();
}

class _FieldScanScreenState extends State<FieldScanScreen> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _handled = false;
  String? _lastReject;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null || raw.isEmpty) continue;
      final result = FieldQrCodec.tryDecode(raw);
      if (result.ok) {
        _handled = true;
        Navigator.of(context).pop(raw);
        return;
      }
      // Non-IgniRelay or malformed QR — keep scanning, hint once.
      if (mounted && _lastReject != raw) {
        setState(() => _lastReject = raw);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.igni;
    final l = context.l10n;
    return Scaffold(
      backgroundColor: p.bg0,
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (ctx, error, child) => _cameraError(p, l, error),
          ),
          // Scan reticle.
          Center(
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                border: Border.all(color: p.brand, width: 3),
                borderRadius: const BorderRadius.all(IgniRadii.md),
              ),
            ),
          ),
          // Top bar: back + title.
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(IgniSpacing.md),
              child: Row(children: [
                _scrimButton(
                  p,
                  icon: Icons.arrow_back,
                  tooltip: l.fieldScanBack,
                  onTap: () => Navigator.of(context).pop(),
                ),
                const SizedBox(width: IgniSpacing.md),
                _scrimLabel(p, l.fieldScanTitle),
              ]),
            ),
          ),
          // Bottom hint.
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(IgniSpacing.xl),
                child: _scrimLabel(
                  p,
                  _lastReject == null ? l.fieldScanHint : l.fieldScanReject,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _cameraError(IgniPalette p, S l, MobileScannerException error) {
    return Container(
      color: p.bg0,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(IgniSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.no_photography_outlined, size: 40, color: p.text3),
          const SizedBox(height: IgniSpacing.md),
          Text(l.fieldScanNoCameraTitle,
              style: IgniTypography.titleMedium(p.text0),
              textAlign: TextAlign.center),
          const SizedBox(height: IgniSpacing.sm),
          Text(
            l.fieldScanNoCameraBody,
            style: IgniTypography.bodySmall(p.text2),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _scrimButton(IgniPalette p,
      {required IconData icon,
      required String tooltip,
      required VoidCallback onTap}) {
    return Material(
      color: p.bg0.withValues(alpha: 0.6),
      shape: const CircleBorder(),
      child: IconButton(
        tooltip: tooltip,
        icon: Icon(icon, color: p.text0, size: 20),
        onPressed: onTap,
      ),
    );
  }

  Widget _scrimLabel(IgniPalette p, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: IgniSpacing.md, vertical: IgniSpacing.sm),
      decoration: BoxDecoration(
        color: p.bg0.withValues(alpha: 0.6),
        borderRadius: const BorderRadius.all(IgniRadii.sm),
      ),
      child: Text(text, style: IgniTypography.bodySmall(p.text0)),
    );
  }
}
