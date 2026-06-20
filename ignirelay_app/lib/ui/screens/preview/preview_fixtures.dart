// Preview fixtures — UI-G「先看功能」guided preview.
//
// Display-only demo data. Pure plain Dart: NO wire/DB types, and crucially NO
// real / decodable join secret, QR payload, `IGNI1` string, or field_id-style
// hex (Owner boundary ①). Every coordinate here exists ONLY to render the radar
// / last-trusted-position list inside the tour — it is not a real location and
// is NEVER fed into any publisher (the preview holds none).
//
// Layer: lib/ui/screens/preview/ → may import the design system + app/services
// (`PositionEstimate`) + the pure `RelativeRadar`/`RadarSubject`. It must NOT
// import any real controller, publisher, location, or transport code (enforced by
// a grep gate + an import-guard test).

import 'package:ignirelay_app/app/services/position_estimator.dart';
import 'package:ignirelay_app/l10n/generated/app_localizations.dart';
import 'package:ignirelay_app/ui/screens/position/relative_radar.dart';
import 'package:ignirelay_app/ui/widgets/status_chip.dart';

/// 示範場域顯示名——**純描述字串**（UI-H2b 起經 i18n）。刻意不是、也不含任何
/// 可掃描 / 可解碼的 join secret、QR payload、`IGNI1` 字串或 field_id 樣式 hex
/// （Owner 邊界①）。zh/en 值見 ARB `previewFieldLabel`。
String previewFieldLabel(S l) => l.previewFieldLabel;

/// 雷達原點（本機示範估計）。座標僅供 demo 投影，非真實位置、永不送出。
const PositionEstimate kPreviewOrigin = PositionEstimate(
  lat: 25.041,
  lng: 121.535,
  confidence: PositionConfidence.high,
  uncertaintyM: 12,
  ageSeconds: 5,
);

/// 一筆示範足跡：anon8 化名 + 相對時間 + 最後可信位置估計（供雷達 / 列表）。
class PreviewFootprint {
  final String anon8;
  final String agoLabel;
  final PositionEstimate estimate;
  final StatusTone tone;

  const PreviewFootprint({
    required this.anon8,
    required this.agoLabel,
    required this.estimate,
    this.tone = StatusTone.ok,
  });
}

/// 示範足跡（anon8 化名是顯示資料、非可解碼物；座標僅供 demo 投影、永不送出）。
/// 相對時間字串經 i18n（agoLabel）。
List<PreviewFootprint> previewFootprints(S l) => [
      PreviewFootprint(
        anon8: 'a1b2c3d4',
        agoLabel: l.previewFpAgo1,
        estimate: const PositionEstimate(
          lat: 25.0425,
          lng: 121.5362,
          confidence: PositionConfidence.high,
          uncertaintyM: 15,
          ageSeconds: 60,
        ),
      ),
      PreviewFootprint(
        anon8: 'e5f6a7b8',
        agoLabel: l.previewFpAgo4,
        estimate: const PositionEstimate(
          lat: 25.0398,
          lng: 121.5331,
          confidence: PositionConfidence.medium,
          uncertaintyM: 80,
          ageSeconds: 240,
        ),
      ),
      PreviewFootprint(
        anon8: '99887766',
        agoLabel: l.previewFpAgoTrapped,
        tone: StatusTone.sos,
        estimate: const PositionEstimate(
          lat: 25.0435,
          lng: 121.5318,
          confidence: PositionConfidence.high,
          uncertaintyM: 20,
          ageSeconds: 120,
        ),
      ),
    ];

/// 把示範足跡轉成雷達 subjects（SOS 維持紅點；其餘 ok，雷達內部再依信心降級成灰）。
List<RadarSubject> previewRadarSubjects(S l) => [
      for (final f in previewFootprints(l))
        RadarSubject(
          key: f.anon8,
          label: f.anon8,
          estimate: f.estimate,
          baseTone: f.tone,
        ),
    ];

/// 一筆示範事件（SOS / 危害 / 廣播 / 打卡）——純顯示字串，永不送出。
class PreviewEvent {
  final String title;
  final String detail;
  final String agoLabel;
  final StatusTone tone;

  const PreviewEvent({
    required this.title,
    required this.detail,
    required this.agoLabel,
    this.tone = StatusTone.neutral,
  });
}

PreviewEvent previewSos(S l) => PreviewEvent(
      title: l.previewSosTitle,
      detail: l.previewAlias('99887766'),
      agoLabel: l.previewSosAgo,
      tone: StatusTone.sos,
    );
PreviewEvent previewHazard(S l) => PreviewEvent(
      title: l.previewHazardTitle,
      detail: l.previewHazardDetail,
      agoLabel: l.previewHazardAgo,
      tone: StatusTone.warn,
    );
PreviewEvent previewBroadcast(S l) => PreviewEvent(
      title: l.previewBroadcastTitle,
      detail: l.previewBroadcastDetail,
      agoLabel: l.previewBroadcastAgo,
      tone: StatusTone.info,
    );
PreviewEvent previewCheckpoint(S l) => PreviewEvent(
      title: l.previewCheckpointTitle,
      detail: l.previewAlias('a1b2c3d4'),
      agoLabel: l.previewCheckpointAgo,
      tone: StatusTone.ok,
    );
