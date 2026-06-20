// RelativeRadar — A10b. A "me-centric" relative-position radar: concentric
// distance rings + bearing dots, fixed NORTH-UP (no compass/magnetometer — v1),
// rendered from the SAME A10 [PositionEstimate] data as the card list.
//
// Spec / design: MASTER_EXECUTION_PLAN §5 A10b step 2.
//
// HARD RULES:
//   • Every dot is the projection of a "最後可信位置" (last trusted position) —
//     copy NEVER says 「目前位置」 (§3.6 principle 5).
//   • Distance / bearing are derived live by [RelativePositionProjector] from
//     each subject's estimate — never read from or written to wire/DB (A10b
//     prohibition).
//   • DESIGN_LANGUAGE §4: all colour via `context.igni`; no raw Material colour
//     constants / hex (this screen is under lib/ui/screens/, §6 grep gate).
//   • North is FIXED up; the radar does not rotate to a heading (v1 — no sensor).
//
// The host screen guarantees a non-null [origin] (it shows the "需要本機位置"
// degrade path itself); this widget only plots subjects that have a lat/lng.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:ignirelay_app/app/services/position_estimator.dart';
import 'package:ignirelay_app/app/services/relative_position.dart';
import 'package:ignirelay_app/l10n/l10n_ext.dart';
import 'package:ignirelay_app/ui/theme/igni_colors.dart';
import 'package:ignirelay_app/ui/theme/igni_tokens.dart';
import 'package:ignirelay_app/ui/theme/igni_typography.dart';
import 'package:ignirelay_app/ui/widgets/status_chip.dart';

/// One subject to plot. [baseTone] is the subject's semantic status BEFORE the
/// staleness rule (SOS subjects → [StatusTone.sos]; ordinary people →
/// [StatusTone.ok]); a non-SOS subject whose estimate is LOW confidence is shown
/// as stale (grey). [isNode] true draws a triangle (Field Node / anchor).
class RadarSubject {
  final String key;
  final String label;
  final PositionEstimate estimate;
  final StatusTone baseTone;
  final bool isNode;

  const RadarSubject({
    required this.key,
    required this.label,
    required this.estimate,
    this.baseTone = StatusTone.ok,
    this.isNode = false,
  });
}

/// Distance-ring tiers (metres). The radar picks the smallest tier whose OUTER
/// ring covers the farthest subject; subjects beyond the largest tier are pinned
/// to the rim. Each tier draws three rings.
const List<List<double>> kRadarRingTiers = [
  [100, 250, 500],
  [500, 1000, 2000],
  [2000, 5000, 10000],
  [10000, 25000, 50000],
  [50000, 100000, 200000],
];

/// Map a [StatusTone] to its palette colour (mirrors [StatusChip] foregrounds).
Color radarToneColor(IgniPalette p, StatusTone tone) {
  switch (tone) {
    case StatusTone.sos:
      return p.sos;
    case StatusTone.warn:
      return p.warn;
    case StatusTone.ok:
      return p.ok;
    case StatusTone.info:
      return p.info;
    case StatusTone.brand:
      return p.brand;
    case StatusTone.neutral:
      return p.text3; // stale / unknown
  }
}

class RelativeRadar extends StatelessWidget {
  const RelativeRadar({
    super.key,
    required this.origin,
    required this.subjects,
    this.onTapSubject,
  });

  final PositionEstimate origin;
  final List<RadarSubject> subjects;
  final void Function(String key)? onTapSubject;

  @override
  Widget build(BuildContext context) {
    final p = context.igni;

    // Project every subject; drop ones with no lat/lng (anchor-only stay in the
    // list). The staleness rule downgrades a non-SOS LOW-confidence dot to grey.
    final placed = <_Placed>[];
    var maxDist = 0.0;
    for (final s in subjects) {
      final rel = RelativePositionProjector.relativeTo(origin, s.estimate);
      if (rel == null) continue;
      if (rel.distanceM > maxDist) maxDist = rel.distanceM;
      final tone = s.baseTone == StatusTone.sos
          ? StatusTone.sos
          : (rel.confidence == PositionConfidence.low
              ? StatusTone.neutral
              : StatusTone.ok);
      placed.add(_Placed(subject: s, rel: rel, tone: tone));
    }

    // Pick the smallest ring tier that covers the farthest subject.
    var tier = kRadarRingTiers.first;
    for (final t in kRadarRingTiers) {
      tier = t;
      if (t.last >= maxDist) break;
    }
    final maxRange = tier.last;

    return Column(
      children: [
        Expanded(
          child: Center(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final side = math.min(
                  constraints.maxWidth.isFinite ? constraints.maxWidth : 320.0,
                  constraints.maxHeight.isFinite
                      ? constraints.maxHeight
                      : 320.0,
                );
                final radius = side / 2 - 18; // rim padding for rim labels
                final center = Offset(side / 2, side / 2);

                final markers = <Widget>[];
                for (final pl in placed) {
                  final pinned = pl.rel.distanceM > maxRange;
                  final rPx =
                      pinned ? radius : (pl.rel.distanceM / maxRange) * radius;
                  final thetaRad = pl.rel.bearingDeg * math.pi / 180.0;
                  // North up: east → +x (right), north → −y (up).
                  final dx = rPx * math.sin(thetaRad);
                  final dy = -rPx * math.cos(thetaRad);
                  pl.screenOffset = Offset(center.dx + dx, center.dy + dy);
                  pl.uncertaintyPx =
                      (pl.rel.uncertaintyM / maxRange) * radius;
                  pl.pinned = pinned;

                  const markerBox = 28.0;
                  markers.add(Positioned(
                    left: pl.screenOffset.dx - markerBox / 2,
                    top: pl.screenOffset.dy - markerBox / 2,
                    width: markerBox,
                    height: markerBox,
                    child: RadarMarker(
                      tone: pl.tone,
                      isNode: pl.subject.isNode,
                      label: pl.subject.label,
                      onTap: onTapSubject == null
                          ? null
                          : () => onTapSubject!(pl.subject.key),
                    ),
                  ));
                  if (pinned) {
                    // Beyond the outer ring: pinned to the rim, labelled ">env".
                    markers.add(Positioned(
                      left: pl.screenOffset.dx + 8,
                      top: pl.screenOffset.dy - 20,
                      child: Text(
                        '>${_fmtRange(maxRange)}',
                        style: IgniTypography.labelSmall(p.text2)
                            .copyWith(fontSize: 10, letterSpacing: 0),
                      ),
                    ));
                  }
                }

                return SizedBox(
                  width: side,
                  height: side,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned.fill(
                        child: CustomPaint(
                          painter: _RadarPainter(
                            palette: p,
                            center: center,
                            radius: radius,
                            tierValues: tier,
                            maxRange: maxRange,
                            placed: placed,
                          ),
                        ),
                      ),
                      ...markers,
                    ],
                  ),
                );
              },
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: IgniSpacing.lg,
            vertical: IgniSpacing.sm,
          ),
          child: Text(
            context.l10n.radarCaption(_fmtRange(maxRange)),
            style: IgniTypography.bodySmall(p.text2),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }

  static String _fmtRange(double m) =>
      m >= 1000 ? '${(m / 1000).toStringAsFixed(m % 1000 == 0 ? 0 : 1)} km'
                : '${m.round()} m';
}

/// A single plotted marker — a dot (person) or triangle (node/anchor). Public so
/// widget tests can assert e.g. a [StatusTone.sos] marker is present.
class RadarMarker extends StatelessWidget {
  const RadarMarker({
    super.key,
    required this.tone,
    this.isNode = false,
    this.label,
    this.onTap,
  });

  final StatusTone tone;
  final bool isNode;

  /// Subject handle (anon8 / short pubkey) — exposed as the marker's semantics
  /// label; not drawn (the radar stays uncluttered, tap opens the A10 card).
  final String? label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.igni;
    final color = radarToneColor(p, tone);
    return Semantics(
      label: label,
      button: onTap != null,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: CustomPaint(
          painter: _MarkerPainter(color: color, isNode: isNode, ring: p.bg0),
        ),
      ),
    );
  }
}

/// Mutable layout slot for a projected subject (filled in during build()).
class _Placed {
  _Placed({required this.subject, required this.rel, required this.tone});

  final RadarSubject subject;
  final RelativePosition rel;
  final StatusTone tone;

  Offset screenOffset = Offset.zero;
  double uncertaintyPx = 0;
  bool pinned = false;
}

class _MarkerPainter extends CustomPainter {
  _MarkerPainter({required this.color, required this.isNode, required this.ring});

  final Color color;
  final bool isNode;
  final Color ring;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final halo = Paint()
      ..color = ring
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    if (isNode) {
      const r = 8.0;
      final path = Path()
        ..moveTo(c.dx, c.dy - r)
        ..lineTo(c.dx + r * 0.9, c.dy + r * 0.7)
        ..lineTo(c.dx - r * 0.9, c.dy + r * 0.7)
        ..close();
      canvas.drawPath(path, fill);
      canvas.drawPath(path, halo);
    } else {
      canvas.drawCircle(c, 6, fill);
      canvas.drawCircle(c, 6, halo);
    }
  }

  @override
  bool shouldRepaint(covariant _MarkerPainter old) =>
      old.color != color || old.isNode != isNode || old.ring != ring;
}

class _RadarPainter extends CustomPainter {
  _RadarPainter({
    required this.palette,
    required this.center,
    required this.radius,
    required this.tierValues,
    required this.maxRange,
    required this.placed,
  });

  final IgniPalette palette;
  final Offset center;
  final double radius;
  final List<double> tierValues;
  final double maxRange;
  final List<_Placed> placed;

  @override
  void paint(Canvas canvas, Size size) {
    final p = palette;

    // Crosshair (N–S / E–W).
    final axis = Paint()
      ..color = p.border1
      ..strokeWidth = 1;
    canvas.drawLine(Offset(center.dx, center.dy - radius),
        Offset(center.dx, center.dy + radius), axis);
    canvas.drawLine(Offset(center.dx - radius, center.dy),
        Offset(center.dx + radius, center.dy), axis);

    // Concentric distance rings + their value labels (placed at the top).
    final ringPaint = Paint()
      ..color = p.border2
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final v in tierValues) {
      final rr = (v / maxRange) * radius;
      canvas.drawCircle(center, rr, ringPaint);
      _label(canvas, _fmt(v), Offset(center.dx + 4, center.dy - rr - 12),
          p.text3);
    }

    // "N" marker at the top.
    _label(canvas, 'N', Offset(center.dx - 4, center.dy - radius - 16),
        p.text2,
        bold: true);

    // Per-subject dashed uncertainty circle for LOW-confidence (stale) dots.
    for (final pl in placed) {
      if (pl.rel.confidence != PositionConfidence.low) continue;
      final ur = pl.uncertaintyPx.clamp(0.0, radius);
      if (ur < 4) continue;
      _dashedCircle(canvas, pl.screenOffset, ur,
          radarToneColor(p, pl.tone).withValues(alpha: 0.55));
    }

    // Centre = local device.
    canvas.drawCircle(center, 4, Paint()..color = p.brand);
    canvas.drawCircle(
        center,
        7,
        Paint()
          ..color = p.brand
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5);
  }

  void _dashedCircle(Canvas canvas, Offset c, double r, Color color) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    const segments = 24;
    const sweep = (2 * math.pi / segments) * 0.6; // 60% on, 40% gap
    for (var i = 0; i < segments; i++) {
      final start = (2 * math.pi / segments) * i;
      canvas.drawArc(
          Rect.fromCircle(center: c, radius: r), start, sweep, false, paint);
    }
  }

  void _label(Canvas canvas, String text, Offset at, Color color,
      {bool bold = false}) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: IgniTypography.labelSmall(color).copyWith(
          fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
          letterSpacing: 0,
          fontSize: 10,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, at);
  }

  static String _fmt(double m) =>
      m >= 1000 ? '${(m / 1000).toStringAsFixed(m % 1000 == 0 ? 0 : 1)}k' : '${m.round()}';

  @override
  bool shouldRepaint(covariant _RadarPainter old) =>
      old.maxRange != maxRange ||
      old.radius != radius ||
      old.placed != placed ||
      old.palette != palette;
}
