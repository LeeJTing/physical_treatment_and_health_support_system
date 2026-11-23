import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;

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
class TrendChart extends StatefulWidget {
  final List<ChartSeries> series;
  final String unit;
  final double height;

  /// Optional horizontal guide, e.g. the target 140 mmHg.
  final double? guide;
  final String? guideLabel;
  final bool inspectable;
  final bool zoomable;
  final String? interactionId;
  final Widget Function(DateTime at)? inspectionBuilder;

  const TrendChart({
    super.key,
    required this.series,
    required this.unit,
    this.height = 200,
    this.guide,
    this.guideLabel,
    this.inspectable = false,
    this.zoomable = false,
    this.interactionId,
    this.inspectionBuilder,
  });

  @override
  State<TrendChart> createState() => _TrendChartState();
}

class _TrendChartState extends State<TrendChart> {
  DateTime? _selected;
  double _zoom = 1, _start = 0;
  double _gestureZoom = 1, _gestureStart = 0, _scaleReference = 1;
  Offset _gestureFocal = Offset.zero;
  int _gesturePointers = 0;

  (double, double)? _visibleBounds(List<ChartSeries> shown) {
    final base = _timeBounds(shown);
    if (base == null) return null;
    final span = base.$2 - base.$1;
    final left = base.$1 + span * _start;
    return (left, left + span / _zoom);
  }

  void _zoomTo(double value) {
    final next = value.clamp(1.0, 16.0);
    setState(() {
      final centre = _start + .5 / _zoom;
      _start = (centre - .5 / next).clamp(0.0, 1 - 1 / next);
      _zoom = next;
      _selected = null;
    });
  }

  void _scaleStart(ScaleStartDetails details) {
    _gestureZoom = _zoom;
    _gestureStart = _start;
    _gestureFocal = details.localFocalPoint;
    _gesturePointers = details.pointerCount;
    _scaleReference = 1;
  }

  void _scaleUpdate(ScaleUpdateDetails details, Size size, List<ChartSeries> shown) {
    if (_gesturePointers != details.pointerCount) {
      _gestureZoom = _zoom;
      _gestureStart = _start;
      _gestureFocal = details.localFocalPoint;
      _gesturePointers = details.pointerCount;
      _scaleReference = details.scale;
    }
    final width = size.width - _ChartPainter._left - _ChartPainter._right;
    if (width <= 0) return;
    if (details.pointerCount >= 2) {
      final next = (_gestureZoom * details.scale / _scaleReference).clamp(1.0, 16.0);
      final anchor = ((_gestureFocal.dx - _ChartPainter._left) / width).clamp(0.0, 1.0);
      final focus = ((details.localFocalPoint.dx - _ChartPainter._left) / width).clamp(0.0, 1.0);
      setState(() {
        _start = (_gestureStart + anchor / _gestureZoom - focus / next).clamp(0.0, 1 - 1 / next);
        _zoom = next;
        _selected = null;
      });
    } else if (_zoom > 1) {
      setState(() {
        _start = (_gestureStart - (details.localFocalPoint.dx - _gestureFocal.dx) / width / _gestureZoom).clamp(
          0.0,
          1 - 1 / _zoom,
        );
        _selected = null;
      });
    } else if (widget.inspectable) {
      _inspect(details.localFocalPoint, size, shown);
    }
  }

  @override
  void didUpdateWidget(covariant TrendChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.inspectable || !widget.series.any((s) => s.points.any((p) => p.x == _selected))) {
      _selected = null;
    }
    if (!widget.zoomable || _timeBounds(widget.series) == null) {
      _zoom = 1;
      _start = 0;
    }
    final visible = _visibleBounds(widget.series);
    if (_selected != null &&
        visible != null &&
        (_selected!.millisecondsSinceEpoch < visible.$1 || _selected!.millisecondsSinceEpoch > visible.$2)) {
      _selected = null;
    }
  }

  void _clear() {
    if (_selected != null) setState(() => _selected = null);
  }

  void _inspect(Offset position, Size size, List<ChartSeries> shown) {
    final bounds = _visibleBounds(shown);
    final plot = Rect.fromLTRB(
      _ChartPainter._left,
      _ChartPainter._top,
      size.width - _ChartPainter._right,
      size.height - _ChartPainter._bottom,
    );
    if (bounds == null || !plot.contains(position)) {
      _clear();
      return;
    }
    final (minX, maxX) = bounds;
    DateTime? nearest;
    var distance = 12.0;
    for (final series in shown) {
      for (final point in series.points) {
        if (point.x.millisecondsSinceEpoch < minX || point.x.millisecondsSinceEpoch > maxX) continue;
        final x = plot.left + (point.x.millisecondsSinceEpoch - minX) / (maxX - minX) * plot.width;
        final delta = (position.dx - x).abs();
        if (delta < distance) {
          distance = delta;
          nearest = point.x;
        }
      }
    }
    if (_selected != nearest) setState(() => _selected = nearest);
  }

  Widget _defaultInspection(DateTime at, List<ChartSeries> shown) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(DateFormat('d MMM yyyy, HH:mm').format(at), style: const TextStyle(fontWeight: FontWeight.w600)),
      for (final series in shown)
        for (final point in series.points.where((p) => p.x == at))
          Text('${series.label}: ${point.y.toStringAsFixed(1)} ${widget.unit}'),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final shown = widget.series.where((s) => s.points.isNotEmpty).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.zoomable && shown.isNotEmpty)
          Row(
            children: [
              IconButton(
                tooltip: 'Zoom out',
                onPressed: _zoom > 1 ? () => _zoomTo(_zoom / 2) : null,
                icon: const Icon(Icons.zoom_out),
              ),
              Semantics(
                container: true,
                identifier: 'chart-zoom-level',
                label: 'Zoom level ${_zoom.toStringAsFixed(1)} times',
                excludeSemantics: true,
                child: Text('${_zoom.toStringAsFixed(1)}×', key: const ValueKey('chart-zoom-level')),
              ),
              IconButton(
                tooltip: 'Zoom in',
                onPressed: _zoom < 16 ? () => _zoomTo(_zoom * 2) : null,
                icon: const Icon(Icons.zoom_in),
              ),
              const Spacer(),
              TextButton(onPressed: _zoom > 1 ? () => _zoomTo(1) : null, child: const Text('Reset zoom')),
            ],
          ),
        SizedBox(
          key: widget.interactionId == null ? null : ValueKey(widget.interactionId!),
          height: widget.height,
          width: double.infinity,
          child: Semantics(
            identifier: widget.interactionId,
            label: 'Chart of ${shown.map((s) => s.label).join(', ')} in ${widget.unit}',
            child: LayoutBuilder(
              builder: (context, constraints) {
                final size = Size(constraints.maxWidth, widget.height);
                final bounds = _visibleBounds(shown);
                final selected = _selected;
                final tooltipWidth = math.min(240.0, math.max(0.0, size.width - 24));
                final x = selected == null || bounds == null
                    ? 0.0
                    : _ChartPainter._left +
                          (selected.millisecondsSinceEpoch - bounds.$1) /
                              (bounds.$2 - bounds.$1) *
                              (size.width - _ChartPainter._left - _ChartPainter._right);
                final tooltipLeft = (x > size.width / 2 ? x - tooltipWidth - 10 : x + 10).clamp(
                  0.0,
                  math.max(0.0, size.width - tooltipWidth),
                );
                return MouseRegion(
                  onHover: widget.inspectable ? (event) => _inspect(event.localPosition, size, shown) : null,
                  onExit: widget.inspectable ? (_) => _clear() : null,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: widget.inspectable ? (event) => _inspect(event.localPosition, size, shown) : null,
                    onTapCancel: widget.inspectable ? _clear : null,
                    onHorizontalDragStart: widget.inspectable && !widget.zoomable
                        ? (event) => _inspect(event.localPosition, size, shown)
                        : null,
                    onHorizontalDragUpdate: widget.inspectable && !widget.zoomable
                        ? (event) => _inspect(event.localPosition, size, shown)
                        : null,
                    onLongPressStart: widget.inspectable ? (event) => _inspect(event.localPosition, size, shown) : null,
                    onLongPressMoveUpdate: widget.inspectable
                        ? (event) => _inspect(event.localPosition, size, shown)
                        : null,
                    onScaleStart: widget.zoomable ? _scaleStart : null,
                    onScaleUpdate: widget.zoomable ? (details) => _scaleUpdate(details, size, shown) : null,
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: CustomPaint(painter: _ChartPainter(shown, widget.guide, selected, bounds)),
                        ),
                        if (selected != null && bounds != null)
                          Positioned(
                            left: tooltipLeft.toDouble(),
                            top: 8,
                            width: tooltipWidth,
                            child: Semantics(
                              container: true,
                              identifier: 'chart-reading-details',
                              child: Material(
                                key: const ValueKey('chart-reading-details'),
                                color: AppTokens.surface,
                                elevation: 5,
                                borderRadius: BorderRadius.circular(10),
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(maxHeight: widget.height - 16),
                                  child: SingleChildScrollView(
                                    padding: const EdgeInsets.all(10),
                                    child: DefaultTextStyle(
                                      style: const TextStyle(fontSize: 13, color: AppTokens.ink, fontFamily:'Roboto'),
                                      child:
                                          widget.inspectionBuilder?.call(selected) ??
                                          _defaultInspection(selected, shown),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
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
                  Flexible(child:Text(
                    s.forecast ? '${s.label} (forecast)' : s.label,
                    style: const TextStyle(fontSize: 13, color: AppTokens.inkMuted),
                  )),
                ],
              ),
            if (widget.guide != null && widget.guideLabel != null)
              Text('- - ${widget.guideLabel}', style: const TextStyle(fontSize: 13, color: AppTokens.inkMuted)),
          ],
        ),
      ],
    );
  }
}

(double, double)? _timeBounds(List<ChartSeries> series) {
  final times = [
    for (final s in series)
      for (final p in s.points) p.x.millisecondsSinceEpoch.toDouble(),
  ];
  if (times.isEmpty) return null;
  var minX = times.reduce(math.min), maxX = times.reduce(math.max);
  if (maxX - minX < 86400000) {
    minX -= 43200000;
    maxX += 43200000;
  }
  return (minX, maxX);
}

class _ChartPainter extends CustomPainter {
  final List<ChartSeries> series;
  final double? guide;
  final DateTime? selected;
  final (double, double)? visibleBounds;
  _ChartPainter(this.series, this.guide, this.selected, this.visibleBounds);

  static const _left = 40.0, _bottom = 22.0, _top = 8.0, _right = 8.0;

  @override
  void paint(Canvas canvas, Size size) {
    final pts = [for (final s in series) ...s.points];
    if (pts.isEmpty) return;
    final (minX, maxX) = visibleBounds ?? _timeBounds(series)!;
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
      final label = maxX - minX < 86400000 ? DateFormat('HH:mm').format(d) : '${d.day}/${d.month}';
      _text(
        canvas,
        label,
        Offset(
          x -
              (f == 1.0
                  ? 30
                  : f == 0.5
                  ? 14
                  : 0),
          size.height - 16,
        ),
        11,
      );
    }
    // guide
    if (guide != null) {
      final gy = at(DateTime.fromMillisecondsSinceEpoch(minX.round()), guide!).dy;
      _dashed(
        canvas,
        Offset(_left, gy),
        Offset(size.width - _right, gy),
        Paint()
          ..color = AppTokens.danger.withValues(alpha: 0.6)
          ..strokeWidth = 1.2,
      );
    }
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(_left, _top, size.width - _right, size.height - _bottom));
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
    canvas.restore();
    if (selected case final time?) {
      final x = at(time, minY).dx;
      canvas.drawLine(
        Offset(x, _top),
        Offset(x, size.height - _bottom),
        Paint()
          ..color = AppTokens.ink.withValues(alpha: .55)
          ..strokeWidth = 1.2,
      );
      for (final s in series) {
        for (final p in s.points.where((p) => p.x == time)) {
          canvas.drawCircle(at(p.x, p.y), 5, Paint()..color = AppTokens.surface);
          canvas.drawCircle(
            at(p.x, p.y),
            4,
            Paint()
              ..color = s.color
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2,
          );
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
      text: TextSpan(
        text: s,
        style: TextStyle(fontSize: size, color: AppTokens.inkMuted, fontFamily:'Roboto'),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 60);
    tp.paint(c, o);
  }

  @override
  bool shouldRepaint(covariant _ChartPainter old) =>
      old.series != series || old.guide != guide || old.selected != selected || old.visibleBounds != visibleBounds;
}
