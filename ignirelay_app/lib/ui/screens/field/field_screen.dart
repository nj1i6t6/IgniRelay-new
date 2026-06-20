import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:ignirelay_app/app/controllers/active_field_controller.dart';
import 'package:ignirelay_app/app/services/field_qr_codec.dart';
import 'package:ignirelay_app/l10n/generated/app_localizations.dart';
import 'package:ignirelay_app/l10n/l10n_ext.dart';
import 'package:ignirelay_app/ui/screens/field/field_qr_sheet.dart';
import 'package:ignirelay_app/ui/screens/field/field_scan_screen.dart';
import 'package:ignirelay_app/ui/theme/igni_colors.dart';
import 'package:ignirelay_app/ui/theme/igni_tokens.dart';
import 'package:ignirelay_app/ui/theme/igni_typography.dart';
import 'package:ignirelay_app/ui/widgets/igni_button.dart';
import 'package:ignirelay_app/ui/widgets/igni_card.dart';
import 'package:ignirelay_app/ui/widgets/igni_chip.dart';
import 'package:ignirelay_app/ui/widgets/igni_sub_page_header.dart';
import 'package:ignirelay_app/ui/widgets/mono_text.dart';

/// 場域加入 UX（A7）— 建立場域（顯 QR）/ 掃碼加入 / 代碼加入 / 多場域切換 / 離開。
///
/// 守 DESIGN_LANGUAGE §4：一律經 `context.igni` 與 Igni 元件取值，screen 內不寫死
/// Material 調色常數 / hex 字面值。場域密鑰只在 [ActiveFieldController] / 安全儲存區內流動，
/// 本頁僅在「顯示 QR」時短暫持有以渲染——絕不寫入 log / 剪貼簿（A7 禁止事項）。
class FieldScreen extends StatefulWidget {
  const FieldScreen({super.key});

  @override
  State<FieldScreen> createState() => _FieldScreenState();
}

class _FieldScreenState extends State<FieldScreen> {
  late final ActiveFieldController _field = context.read<ActiveFieldController>();
  bool _busy = false;

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.igni;
    final l = context.l10n;
    final field = context.watch<ActiveFieldController>();
    final active = field.active;
    return Scaffold(
      backgroundColor: p.bg0,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: IgniSpacing.xl3),
          children: [
            IgniSubPageHeader(
              title: l.fieldTitle,
              subtitle: l.fieldSubtitle,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: IgniSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _activeCard(p, l, active),
                  const SizedBox(height: IgniSpacing.lg),
                  _actions(p, l),
                  if (field.joinedFieldCount > 0) ...[
                    const SizedBox(height: IgniSpacing.xl),
                    Text(l.fieldJoinedHeader(field.joinedFieldCount),
                        style: IgniTypography.sectionHeader(p.text2)),
                    const SizedBox(height: IgniSpacing.sm),
                    for (final f in field.joinedFields)
                      Padding(
                        padding: const EdgeInsets.only(bottom: IgniSpacing.sm),
                        child: _fieldRow(
                            p, l, f, active?.fieldIdHex == f.fieldIdHex),
                      ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Active field summary / empty state ─────────────────────────────────
  Widget _activeCard(IgniPalette p, S l, ActiveField? active) {
    if (active == null) {
      return IgniCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.shield_outlined, size: 18, color: p.warn),
              const SizedBox(width: IgniSpacing.sm),
              Text(l.fieldNoneTitle, style: IgniTypography.titleMedium(p.text0)),
            ]),
            const SizedBox(height: IgniSpacing.sm),
            Text(l.fieldNoneBody, style: IgniTypography.bodySmall(p.text2)),
          ],
        ),
      );
    }
    return IgniCard(
      elevated: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.shield, size: 18, color: p.ok),
            const SizedBox(width: IgniSpacing.sm),
            Expanded(
              child: Text(
                active.displayName.isEmpty ? l.fieldUnnamed : active.displayName,
                style: IgniTypography.titleMedium(p.text0),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            _roleChip(l, active),
            const SizedBox(width: IgniSpacing.xs),
            IgniChip(label: l.fieldActiveChip, tone: IgniChipTone.ok),
          ]),
          const SizedBox(height: IgniSpacing.sm),
          Row(children: [
            Text('field_id', style: IgniTypography.labelSmall(p.text2)),
            const SizedBox(width: IgniSpacing.sm),
            // UI-H3: bound the mono id so it ellipsizes under large text instead
            // of overflowing this row.
            Expanded(
              child: MonoText('${active.shortId}…',
                  color: p.text1,
                  fontSize: 12,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ),
          ]),
          if (active.cloudBaseUrl != null) ...[
            const SizedBox(height: IgniSpacing.sm),
            Row(children: [
              Icon(Icons.cloud_outlined, size: 14, color: p.info),
              const SizedBox(width: 6),
              Expanded(
                child: MonoText(active.cloudBaseUrl!,
                    color: p.text2, fontSize: 11, maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
            ]),
          ],
        ],
      ),
    );
  }

  // ── Primary actions ────────────────────────────────────────────────────
  Widget _actions(IgniPalette p, S l) {
    return Column(
      children: [
        Row(children: [
          Expanded(
            child: IgniButton(
              label: l.fieldScanJoin,
              icon: Icons.qr_code_scanner,
              onPressed: _busy ? null : _scanToJoin,
              fullWidth: true,
            ),
          ),
          const SizedBox(width: IgniSpacing.md),
          Expanded(
            child: IgniButton(
              label: l.fieldEnterCode,
              icon: Icons.keyboard,
              variant: IgniButtonVariant.ghost,
              onPressed: _busy ? null : _showCodeInput,
              fullWidth: true,
            ),
          ),
        ]),
        const SizedBox(height: IgniSpacing.md),
        IgniButton(
          label: l.fieldCreateNew,
          icon: Icons.add_circle_outline,
          variant: IgniButtonVariant.ghost,
          onPressed: _busy ? null : _createField,
          fullWidth: true,
        ),
      ],
    );
  }

  // ── Role chip (UI-F3) — owner「主辦」/ participant「成員」 ─────────────────
  Widget _roleChip(S l, ActiveField f) => IgniChip(
        label: f.isOwner ? l.roleHost : l.roleMember,
        tone: f.isOwner ? IgniChipTone.ok : IgniChipTone.info,
      );

  // ── One joined field row ───────────────────────────────────────────────
  Widget _fieldRow(IgniPalette p, S l, ActiveField f, bool isActive) {
    return IgniCard(
      padding: const EdgeInsets.symmetric(
          horizontal: IgniSpacing.md, vertical: IgniSpacing.md),
      borderColor: isActive ? p.brandBorder : null,
      onTap: _busy || isActive ? null : () => _field.setActive(f.fieldIdHex),
      child: Row(children: [
        Icon(isActive ? Icons.radio_button_checked : Icons.radio_button_off,
            size: 18, color: isActive ? p.brand : p.text3),
        const SizedBox(width: IgniSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(f.displayName.isEmpty ? l.myFieldUnnamed : f.displayName,
                  style: IgniTypography.bodyMedium(p.text0),
                  overflow: TextOverflow.ellipsis),
              MonoText('${f.shortId}…', color: p.text2, fontSize: 11),
            ],
          ),
        ),
        _roleChip(l, f),
        // Owner-only: only the field's creator can re-share its join QR
        // (UI-F3 / D5). Participants joined via QR/code cannot re-share.
        if (f.isOwner)
          IconButton(
            tooltip: l.fieldShowQr,
            icon: Icon(Icons.qr_code_2, size: 20, color: p.text1),
            onPressed: _busy ? null : () => _showQrForField(f),
          ),
        IconButton(
          tooltip: l.fieldLeave,
          icon: Icon(Icons.logout, size: 18, color: p.sos),
          onPressed: _busy ? null : () => _confirmLeave(f),
        ),
      ]),
    );
  }

  // ── Create → QR ────────────────────────────────────────────────────────
  Future<void> _createField() async {
    final l = context.l10n;
    final name = await _promptName();
    if (name == null) return;
    setState(() => _busy = true);
    try {
      final created = await _field.createField(displayName: name);
      if (!mounted) return;
      _showQrSheet(created.field, created.secret);
    } catch (e) {
      _snack(l.fieldCreateFailed('$e'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showQrForField(ActiveField f) async {
    setState(() => _busy = true);
    try {
      final secret = await _field.exportSecretForQr(f.fieldIdHex);
      if (!mounted) return;
      if (secret == null) {
        _snack(context.l10n.fieldSecretNotFound);
        return;
      }
      _showQrSheet(f, secret);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showQrSheet(ActiveField f, Uint8List secret) =>
      FieldQrSheet.show(context, field: f, secret: secret);

  // ── Scan to join ───────────────────────────────────────────────────────
  Future<void> _scanToJoin() async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const FieldScanScreen()),
    );
    if (code == null || !mounted) return;
    await _joinFromCode(code);
  }

  // ── Code input (QR string OR 64-hex secret) ────────────────────────────
  Future<void> _showCodeInput() async {
    final controller = TextEditingController();
    final p = context.igni;
    final l = context.l10n;
    final code = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: p.bg2,
        title: Text(l.fieldCodeTitle, style: IgniTypography.titleMedium(p.text0)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.fieldCodeBody, style: IgniTypography.bodySmall(p.text2)),
            const SizedBox(height: IgniSpacing.md),
            TextField(
              controller: controller,
              autofocus: true,
              minLines: 1,
              maxLines: 3,
              style: IgniTypography.monoSmall(p.text0),
              decoration: InputDecoration(
                hintText: l.fieldCodeHint,
                hintStyle: IgniTypography.monoSmall(p.text3),
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l.fieldCancel, style: TextStyle(color: p.text2)),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: Text(l.fieldJoin),
          ),
        ],
      ),
    );
    if (code == null || code.isEmpty || !mounted) return;
    await _joinFromCode(code);
  }

  /// Join from a typed/scanned string: an `IGNI1:` QR code, or a raw 64-hex
  /// secret (the upgraded A5 debug path). Bad input prompts, never crashes.
  Future<void> _joinFromCode(String code) async {
    final l = context.l10n;
    final trimmed = code.trim();
    if (trimmed.startsWith('${FieldQrCodec.prefix}:')) {
      final r = FieldQrCodec.tryDecode(trimmed);
      if (!r.ok) {
        _snack(_errorMessage(l, r.error!));
        return;
      }
      final payload = r.payload!;
      final name =
          payload.displayName.isEmpty ? l.fieldScannedName : payload.displayName;
      await _join(payload.secret, name: name, cloudBaseUrl: payload.cloudBaseUrl);
      return;
    }
    final secret = _decodeHex32(trimmed);
    if (secret == null) {
      _snack(l.fieldCodeUnrecognized);
      return;
    }
    await _join(secret, name: l.fieldDefaultNamePrefix(trimmed.substring(0, 4)));
  }

  Future<void> _join(List<int> secret,
      {required String name, String? cloudBaseUrl}) async {
    setState(() => _busy = true);
    try {
      final f = await _field.joinBySecret(secret,
          displayName: name, cloudBaseUrl: cloudBaseUrl);
      if (mounted) _snack(context.l10n.fieldJoinedSnack('${f.shortId}…'));
    } catch (e) {
      if (mounted) _snack(context.l10n.fieldJoinFailed('$e'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ── Leave (double confirm; irreversible) ───────────────────────────────
  Future<void> _confirmLeave(ActiveField f) async {
    final p = context.igni;
    final l = context.l10n;
    final name = f.displayName.isEmpty ? l.fieldUnnamed : f.displayName;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: p.bg2,
        title: Text(l.fieldLeaveTitle, style: IgniTypography.titleMedium(p.text0)),
        content: Text(
          l.fieldLeaveBody(name),
          style: IgniTypography.bodySmall(p.text1),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l.fieldCancel, style: TextStyle(color: p.text2)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: p.sos),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l.fieldLeaveConfirm),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await _field.leave(f.fieldIdHex);
      if (mounted) _snack(context.l10n.fieldLeftSnack);
    } catch (e) {
      if (mounted) _snack(context.l10n.fieldLeaveFailed('$e'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────
  Future<String?> _promptName() async {
    final controller = TextEditingController();
    final p = context.igni;
    final l = context.l10n;
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: p.bg2,
        title: Text(l.fieldCreateTitle, style: IgniTypography.titleMedium(p.text0)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: IgniTypography.bodyMedium(p.text0),
          decoration: InputDecoration(
            labelText: l.fieldNameLabel,
            hintText: l.fieldNameHint,
            hintStyle: IgniTypography.bodySmall(p.text3),
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l.fieldCancel, style: TextStyle(color: p.text2)),
          ),
          FilledButton(
            onPressed: () {
              final v = controller.text.trim();
              Navigator.of(ctx).pop(v.isEmpty ? l.fieldDefaultName : v);
            },
            child: Text(l.fieldCreateConfirm),
          ),
        ],
      ),
    );
  }

  String _errorMessage(S l, FieldQrError e) {
    switch (e) {
      case FieldQrError.empty:
        return l.fieldErrEmpty;
      case FieldQrError.badPrefix:
        return l.fieldErrBadPrefix;
      case FieldQrError.tooFewSegments:
        return l.fieldErrTooFewSegments;
      case FieldQrError.badSecret:
        return l.fieldErrBadSecret;
      case FieldQrError.badCloudUrl:
        return l.fieldErrBadCloudUrl;
      case FieldQrError.staffWithoutCloud:
        return l.fieldErrStaffWithoutCloud;
      case FieldQrError.malformed:
        return l.fieldErrMalformed;
    }
  }

  // UI-local hex decode for the 64-hex fallback. UI must not import app/proto.
  static List<int>? _decodeHex32(String hex) {
    final s = hex.trim().toLowerCase();
    if (s.length != 64) return null;
    final out = List<int>.filled(32, 0);
    for (var i = 0; i < 32; i++) {
      final byte = int.tryParse(s.substring(i * 2, i * 2 + 2), radix: 16);
      if (byte == null) return null;
      out[i] = byte;
    }
    return out;
  }
}
