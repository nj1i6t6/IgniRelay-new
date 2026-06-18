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
import 'package:ignirelay_app/ui/screens/position/relative_radar.dart';
import 'package:ignirelay_app/ui/widgets/status_chip.dart';

/// 示範場域顯示名——**純描述字串**。刻意不是、也不含任何可掃描 / 可解碼的 join
/// secret、QR payload、`IGNI1` 字串或 field_id 樣式 hex（Owner 邊界①）。
const String kPreviewFieldLabel = '示範場域 · DEMO-FIELD';

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

const List<PreviewFootprint> kPreviewFootprints = [
  PreviewFootprint(
    anon8: 'a1b2c3d4',
    agoLabel: '1 分鐘前',
    estimate: PositionEstimate(
      lat: 25.0425,
      lng: 121.5362,
      confidence: PositionConfidence.high,
      uncertaintyM: 15,
      ageSeconds: 60,
    ),
  ),
  PreviewFootprint(
    anon8: 'e5f6a7b8',
    agoLabel: '4 分鐘前',
    estimate: PositionEstimate(
      lat: 25.0398,
      lng: 121.5331,
      confidence: PositionConfidence.medium,
      uncertaintyM: 80,
      ageSeconds: 240,
    ),
  ),
  PreviewFootprint(
    anon8: '99887766',
    agoLabel: '受困 · 2 分鐘前',
    tone: StatusTone.sos,
    estimate: PositionEstimate(
      lat: 25.0435,
      lng: 121.5318,
      confidence: PositionConfidence.high,
      uncertaintyM: 20,
      ageSeconds: 120,
    ),
  ),
];

/// 把示範足跡轉成雷達 subjects（SOS 維持紅點；其餘 ok，雷達內部再依信心降級成灰）。
List<RadarSubject> previewRadarSubjects() => [
      for (final f in kPreviewFootprints)
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

const PreviewEvent kPreviewSos = PreviewEvent(
  title: '求救 · 受困',
  detail: '化名 99887766',
  agoLabel: '2 分鐘前',
  tone: StatusTone.sos,
);
const PreviewEvent kPreviewHazard = PreviewEvent(
  title: '危害 · 火災 FIRE',
  detail: 'sev 2 · 巷口濃煙',
  agoLabel: '6 分鐘前',
  tone: StatusTone.warn,
);
const PreviewEvent kPreviewBroadcast = PreviewEvent(
  title: '管理廣播',
  detail: '集合點改至北側出口',
  agoLabel: '10 分鐘前',
  tone: StatusTone.info,
);
const PreviewEvent kPreviewCheckpoint = PreviewEvent(
  title: '打卡 · 平安',
  detail: '化名 a1b2c3d4',
  agoLabel: '12 分鐘前',
  tone: StatusTone.ok,
);
