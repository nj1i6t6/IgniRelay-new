import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:ignirelay_app/app/controllers/active_field_controller.dart';
import 'package:ignirelay_app/app/services/field_qr_codec.dart';
import 'package:ignirelay_app/ui/theme/igni_colors.dart';
import 'package:ignirelay_app/ui/theme/igni_tokens.dart';
import 'package:ignirelay_app/ui/theme/igni_typography.dart';
import 'package:ignirelay_app/ui/widgets/igni_button.dart';
import 'package:ignirelay_app/ui/widgets/mono_text.dart';

/// Bottom sheet that renders a field's join QR (A7). Built from the field's
/// public state + its `field_join_secret`, which the caller supplies transiently
/// for rendering only — it is never logged or copied to the clipboard. The raw
/// code text (which embeds the secret) is shown ONLY in debug builds.
///
/// Rendered dark-on-light via design tokens so scanners read it in any theme.
class FieldQrSheet extends StatelessWidget {
  const FieldQrSheet._({required this.field, required this.code});

  final ActiveField field;
  final String code;

  /// Show the join QR for [field], encoding [secret] into the code on the fly.
  static void show(
    BuildContext context, {
    required ActiveField field,
    required Uint8List secret,
  }) {
    final code = FieldQrCodec.encode(FieldQrPayload(
      secret: secret,
      displayName: field.displayName,
      cloudBaseUrl: field.cloudBaseUrl,
    ));
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.igni.bg1,
      builder: (_) => FieldQrSheet._(field: field, code: code),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.igni;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(IgniSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(field.displayName.isEmpty ? '場域 QR' : field.displayName,
                style: IgniTypography.titleMedium(p.text0),
                textAlign: TextAlign.center),
            const SizedBox(height: IgniSpacing.xs),
            Text('讓對方掃描即可加入同一場域',
                style: IgniTypography.bodySmall(p.text2),
                textAlign: TextAlign.center),
            const SizedBox(height: IgniSpacing.lg),
            Center(
              child: Container(
                padding: const EdgeInsets.all(IgniSpacing.lg),
                decoration: BoxDecoration(
                  color: p.text0, // light panel → dark QR modules stay scannable
                  borderRadius: const BorderRadius.all(IgniRadii.md),
                ),
                child: QrImageView(
                  data: code,
                  version: QrVersions.auto,
                  size: 240,
                  backgroundColor: p.text0,
                  eyeStyle:
                      QrEyeStyle(eyeShape: QrEyeShape.square, color: p.bg0),
                  dataModuleStyle: QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.square, color: p.bg0),
                ),
              ),
            ),
            const SizedBox(height: IgniSpacing.md),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text('field_id', style: IgniTypography.labelSmall(p.text2)),
              const SizedBox(width: IgniSpacing.sm),
              MonoText('${field.shortId}…', color: p.text1, fontSize: 12),
            ]),
            if (kDebugMode) ...[
              const SizedBox(height: IgniSpacing.md),
              Text('（debug）此代碼含場域密鑰，請勿外流：',
                  style: IgniTypography.labelSmall(p.warn)),
              const SizedBox(height: IgniSpacing.xs),
              SelectableText(code, style: IgniTypography.monoSmall(p.text2)),
            ],
            const SizedBox(height: IgniSpacing.lg),
            IgniButton(
              label: '完成',
              onPressed: () => Navigator.of(context).pop(),
              fullWidth: true,
            ),
          ],
        ),
      ),
    );
  }
}
