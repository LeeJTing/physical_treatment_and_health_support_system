import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:physical_treatment_and_health_support_system/core/themes/design_tokens.dart';

/// One point of a [TrendChart] series.
class ChartPoint {
  final DateTime x;
  final double y;

  /// Band around a forecast point (lower, upper); null for a reading.
  final double? low;
  final double? high;
  const ChartPoint(this.x, this.y, {this.low, this.high});
}

/// One line of a [TrendChart].
class ChartSeries {
  final String label;
  final List<ChartPoint> points;
  final Color color;

  /// Drawn dashed with its band shaded: a forecast (FR400_004).
  final bool forecast;
  const ChartSeries(this.label, this.points, this.color, {this.forecast = false});
}

/// A small time-series line chart without a charting package: readings as solid lines with dots,
/// a forecast as a dashed line with its shaded band, on one shared time axis (FR200_017,
/// FR400_004, FR400_025). Every series is named in the legend in words, not by colour alone.
class TrendChart extends StatelessWidget {
  final List<ChartSeries> series;
  final String unit;
  final double height;

  /// Optional horizontal guide, e.g. the target 140 mmHg.
  final double? guide;
  final String? guideLabel;

  const TrendChart({
    super.key,
    required this.series,
    required this.unit,
    this.height = 200,
    this.guide,
    this.guideLabel,
  });

  @override
  Widget build(BuildContext context) {
    final shown = series.where((s) => s.points.isNotEmpty).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: height,
          width: double.infinity,
          child: Semantics(
            label: 'Chart of ${shown.map((s) => s.label).join(', ')} in $unit',
            child: CustomPaint(painter: _ChartPainter(shown, guide)),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 16,
          runSpacing: 4,
          children: [
            for (final s in shown)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 18,
                    height: 4,
                    decoration: BoxDecoration(
                      color: s.forecast ? s.color.withValues(alpha: 0.55) : s.color,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    s.forecast ? '${s.label} (forecast)' : s.label,
                    style: const TextStyle(fontSize: 13, color: AppTokens.inkMuted),
                  ),
                ],
              ),
            if (guide != null && guideLabel != null)
              Text(
                '- - $guideLabel',
                style: const TextStyle(fontSize: 13, color: AppTokens.inkMuted),
              ),
          ],
        ),
      ],
    );
  }
}

class _ChartPainter extends CustomPainter {
  final List<ChartSeries> series;
  final double? guide;
  _ChartPainter(this.series, this.guide);

  static const _left = 40.0, _bottom = 22.0, _top = 8.0, _right = 8.0;

  @override
  void paint(Canvas canvas, Size size) {
    final pts = [for (final s in series) ...s.points];
    if (pts.isEmpty) return;
    var minX = pts.map((p) => p.x.millisecondsSinceEpoch).reduce(math.min).toDouble();
    var maxX = pts.map((p) => p.x.millisecondsSinceEpoch).reduce(math.max).toDouble();
    if (maxX - minX < 86400000) {
      minX -= 43200000;
      maxX += 43200000;
    }
    final ys = [
      for (final p in pts) ...[p.y, p.low ?? p.y, p.high ?? p.y],
      ?guide,
    ];
    var minY = ys.reduce(math.min), maxY = ys.reduce(math.max);
    final pad = math.max((maxY - minY) * 0.12, 1.0);
    minY -= pad;
    maxY += pad;
    final w = size.width - _left - _right, h = size.height - _top - _bottom;
    Offset at(DateTime x, double y) => Offset(
      _left + (x.millisecondsSinceEpoch - minX) / (maxX - minX) * w,
      _top + (1 - (y - minY) / (maxY - minY)) * h,
    );

    // grid and y labels
    final grid = Paint()
      ..color = AppTokens.cardBorder
      ..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final y = minY + (maxY - minY) * i / 3;
      final o = at(DateTime.fromMillisecondsSinceEpoch(minX.round()), y);
      canvas.drawLine(Offset(_left, o.dy), Offset(size.width - _right, o.dy), grid);
      _text(canvas, y >= 100 ? y.round().toString() : y.toStringAsFixed(1), Offset(0, o.dy - 7), 11);
    }
    // x labels: first, middle, last
    for (final f in [0.0, 0.5, 1.0]) {
      final d = DateTime.fromMillisecondsSinceEpoch((minX + (maxX - minX) * f).round());
      final x = _left + w * f;
      _text(canvas, '${d.day}/${d.month}', Offset(x - (f == 1.0 ? 30 : f == 0.5 ? 14 : 0), size.height - 16), 11);
    }
    // guide
    if (guide != null) {
      final gy = at(DateTime.fromMillisecondsSinceEpoch(minX.round()), guide!).dy;
      _dashed(canvas, Offset(_left, gy), Offset(size.width - _right, gy),
          Paint()..color = AppTokens.danger.withValues(alpha: 0.6)..strokeWidth = 1.2);
    }
    for (final s in series) {
      final sorted = [...s.points]..sort((a, b) => a.x.compareTo(b.x));
      if (s.forecast) {
        final band = Path();
        final withBand = sorted.where((p) => p.low != null && p.high != null).toList();
        if (withBand.length >= 2) {
          band.moveTo(at(withBand.first.x, withBand.first.high!).dx, at(withBand.first.x, withBand.first.high!).dy);
          for (final p in withBand) {
            band.lineTo(at(p.x, p.high!).dx, at(p.x, p.high!).dy);
          }
          for (final p in withBand.reversed) {
            band.lineTo(at(p.x, p.low!).dx, at(p.x, p.low!).dy);
          }
          band.close();
          canvas.drawPath(band, Paint()..color = s.color.withValues(alpha: 0.12));
        }
        final paint = Paint()
          ..color = s.color.withValues(alpha: 0.8)
          ..strokeWidth = 2.2;
        for (var i = 1; i < sorted.length; i++) {
          _dashed(canvas, at(sorted[i - 1].x, sorted[i - 1].y), at(sorted[i].x, sorted[i].y), paint);
        }
      } else {
        final line = Paint()
          ..color = s.color
          ..strokeWidth = 2.4
          ..style = PaintingStyle.stroke;
        final path = Path();
        for (var i = 0; i < sorted.length; i++) {
          final o = at(sorted[i].x, sorted[i].y);
          i == 0 ? path.moveTo(o.dx, o.dy) : path.lineTo(o.dx, o.dy);
        }
        canvas.drawPath(path, line);
        if (sorted.length <= 60) {
          for (final p in sorted) {
            canvas.drawCircle(at(p.x, p.y), 3, Paint()..color = s.color);
          }
        }
      }
    }
  }

  void _dashed(Canvas c, Offset a, Offset b, Paint p) {
    final d = (b - a).distance;
    if (d == 0) return;
    final dir = (b - a) / d;
    for (var t = 0.0; t < d; t += 9) {
      c.drawLine(a + dir * t, a + dir * math.min(t + 5, d), p);
    }
  }

  void _text(Canvas c, String s, Offset o, double size) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: TextStyle(fontSize: size, color: AppTokens.inkMuted)),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 60);
    tp.paint(c, o);
  }

  @override
  bool shouldRepaint(covariant _ChartPainter old) => old.series != series || old.guide != guide;
}
