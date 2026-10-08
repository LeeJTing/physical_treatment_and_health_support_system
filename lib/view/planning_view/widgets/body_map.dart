import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import 'package:physical_treatment_and_health_support_system/core/themes/design_tokens.dart';
import 'package:physical_treatment_and_health_support_system/core/utils/body_regions.dart';
import 'package:physical_treatment_and_health_support_system/view/common/rehab_labels.dart';

/// Tappable front/back body figure for the planning questionnaire (FR500_03,
/// affected body area), and a small read-only version for the plan cards.
/// Drawn in code (no image assets). UI-only classes, not in the Chapter 4
/// class diagram (PROJECT_STATE §11).

// ---- geometry --------------------------------------------------------------

/// Shapes in a 200 x 500 figure space. Paired shapes are defined for the
/// screen's left half and mirrored for the right.
class BodyShapes {
  BodyShapes._();

  static const double width = 200;
  static const double height = 500;

  /// Small parts get a hit area of at least 44 x 44 logical pixels.
  static const small = {'elbow', 'hand', 'foot'};
  static const double minTarget = 44;

  static final Map<String, Path> _left = {
    'head': _oval(const Offset(100, 36), 40, 52),
    'neck': _capsule(const Offset(100, 58), const Offset(100, 82), 21, 27),
    'torsoUpper': _blob(const [
      Offset(72, 82),
      Offset(128, 82),
      Offset(138, 96),
      Offset(133, 142),
      Offset(67, 142),
      Offset(62, 96),
    ]),
    'torsoLower': _blob(const [
      Offset(68, 141),
      Offset(132, 141),
      Offset(129, 180),
      Offset(125, 213),
      Offset(75, 213),
      Offset(71, 180),
    ]),
    'shoulder': _oval(const Offset(59, 98), 30, 28),
    'upperArm': _capsule(const Offset(51, 113), const Offset(44, 170), 22, 17),
    'elbow': _oval(const Offset(43, 181), 19, 17),
    'forearm': _capsule(const Offset(42, 191), const Offset(36, 244), 18, 12),
    'hand': _oval(const Offset(34, 262), 17, 28),
    'hip': _blob(const [
      Offset(75, 212),
      Offset(100, 212),
      Offset(100, 250),
      Offset(84, 254),
      Offset(70, 242),
    ]),
    'thigh': _capsule(const Offset(87, 258), const Offset(89, 338), 30, 22),
    'knee': _oval(const Offset(89, 352), 23, 21),
    'shin': _capsule(const Offset(89, 367), const Offset(89, 446), 21, 14),
    'foot': _oval(const Offset(87, 470), 21, 32),
  };

  static final Map<String, Path> _right = {
    for (final e in _left.entries) e.key: _mirror(e.value),
  };

  static const _centre = {'head', 'neck', 'torsoUpper', 'torsoLower'};

  static Path path(String shape, {required bool screenLeft}) =>
      (screenLeft || _centre.contains(shape) ? _left : _right)[shape]!;

  static Path of(BodyRegion r) => path(r.shape, screenLeft: r.onScreenLeft);

  static Offset centreOf(BodyRegion r) => of(r).getBounds().center;

  /// Shapes drawn but not selectable in a view (the back view has no
  /// forearm or hand regions).
  static List<Path> decor(BodyView view) => [
    _left['head']!,
    if (view == BodyView.back)
      for (final s in ['forearm', 'hand']) ...[_left[s]!, _right[s]!],
  ];

  static Path _oval(Offset c, double w, double h) =>
      Path()..addOval(Rect.fromCenter(center: c, width: w, height: h));

  /// A tapered limb segment with slightly bulging sides and rounded ends.
  static Path _capsule(Offset a, Offset b, double wa, double wb) {
    final d = b - a;
    final len = d.distance;
    final u = d / len;
    final n = Offset(-u.dy, u.dx);
    final a1 = a + n * (wa / 2), a2 = a - n * (wa / 2);
    final b1 = b + n * (wb / 2), b2 = b - n * (wb / 2);
    final m1 = (a1 + b1) / 2 + n * (wa * 0.12);
    final m2 = (a2 + b2) / 2 - n * (wa * 0.12);
    final cb = b + u * (wb * 0.7);
    final ca = a - u * (wa * 0.7);
    return Path()
      ..moveTo(a1.dx, a1.dy)
      ..quadraticBezierTo(m1.dx, m1.dy, b1.dx, b1.dy)
      ..quadraticBezierTo(cb.dx, cb.dy, b2.dx, b2.dy)
      ..quadraticBezierTo(m2.dx, m2.dy, a2.dx, a2.dy)
      ..quadraticBezierTo(ca.dx, ca.dy, a1.dx, a1.dy)
      ..close();
  }

  /// A smooth closed shape through the midpoints of [pts], cornering at each point.
  static Path _blob(List<Offset> pts) {
    Offset mid(int i) => (pts[i % pts.length] + pts[(i + 1) % pts.length]) / 2;
    final start = mid(0);
    final p = Path()..moveTo(start.dx, start.dy);
    for (var i = 1; i <= pts.length; i++) {
      final c = pts[i % pts.length];
      final m = mid(i);
      p.quadraticBezierTo(c.dx, c.dy, m.dx, m.dy);
    }
    return p..close();
  }

  static Path _mirror(Path p) => p.transform(
    (Matrix4.identity()
          ..translateByDouble(width, 0, 0, 1)
          ..scaleByDouble(-1, 1, 1, 1))
        .storage,
  );
}

/// Places the 200 x 500 figure in a widget of [size]: height-limited, at most
/// 46 % of the width, centred, leaving side margins for the labels.
class BodyMapLayout {
  final double scale;
  final Offset origin;

  BodyMapLayout._(this.scale, this.origin);

  factory BodyMapLayout(Size size, {double maxWidthShare = 0.46}) {
    var s = size.height / BodyShapes.height;
    if (BodyShapes.width * s > size.width * maxWidthShare) {
      s = size.width * maxWidthShare / BodyShapes.width;
    }
    final origin = Offset(
      (size.width - BodyShapes.width * s) / 2,
      (size.height - BodyShapes.height * s) / 2,
    );
    return BodyMapLayout._(s, origin);
  }

  Offset toScreen(Offset p) => origin + p * scale;
  Offset toFigure(Offset p) => (p - origin) / scale;
  Rect rectOf(Path p) {
    final b = p.getBounds();
    return Rect.fromPoints(toScreen(b.topLeft), toScreen(b.bottomRight));
  }

  double get figureRight => origin.dx + BodyShapes.width * scale;
}

/// The region at [local] (widget coordinates), or null. Exact shapes first,
/// then the enlarged 44 x 44 px target of the small parts.
BodyRegion? bodyRegionAt(BodyView view, Size size, Offset local) {
  final layout = BodyMapLayout(size);
  final p = layout.toFigure(local);
  final regions = BodyRegions.of(view);
  final ordered = [
    ...regions.where((r) => BodyShapes.small.contains(r.shape)),
    ...regions.where((r) => !BodyShapes.small.contains(r.shape)),
  ];
  for (final r in ordered) {
    if (BodyShapes.of(r).contains(p)) return r;
  }
  final radius = BodyShapes.minTarget / 2 / layout.scale;
  BodyRegion? best;
  var bestDistance = double.infinity;
  for (final r in regions.where((r) => BodyShapes.small.contains(r.shape))) {
    final d = (BodyShapes.centreOf(r) - p).distance;
    if (d <= radius && d < bestDistance) {
      best = r;
      bestDistance = d;
    }
  }
  return best;
}

// ---- painting --------------------------------------------------------------

class _BodyPainter extends CustomPainter {
  final BodyView view;
  final Set<String> selected;

  /// Leader lines: from a label edge to the region centre, in widget coordinates.
  final List<(Offset, Offset)> leaders;

  /// Null for the read-only thumbnail (no semantics per region).
  final ValueChanged<BodyRegion>? onToggle;
  final double maxWidthShare;

  _BodyPainter({
    required this.view,
    required this.selected,
    this.leaders = const [],
    this.onToggle,
    this.maxWidthShare = 0.46,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final l = BodyMapLayout(size, maxWidthShare: maxWidthShare);
    final px = 1 / l.scale; // one logical pixel in figure units
    final base = Paint()..color = AppTokens.tint;
    final outline = Paint()
      ..color = AppTokens.outline
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2 * px;
    final chosen = Paint()..color = AppTokens.highlight;
    final chosenOutline = Paint()
      ..color = AppTokens.primary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6 * px;
    final muscle = Paint()
      ..color = AppTokens.outline.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 1 * px;

    canvas.save();
    canvas.translate(l.origin.dx, l.origin.dy);
    canvas.scale(l.scale);
    for (final p in BodyShapes.decor(view)) {
      canvas
        ..drawPath(p, base)
        ..drawPath(p, outline);
    }
    final regions = BodyRegions.of(view);
    for (final r in regions) {
      canvas
        ..drawPath(BodyShapes.of(r), base)
        ..drawPath(BodyShapes.of(r), outline);
    }
    _muscleLines(canvas, muscle);
    // Selected on top: fill plus a thick outline, so colour is not the only cue.
    for (final r in regions.where((r) => selected.contains(r.id))) {
      canvas
        ..drawPath(BodyShapes.of(r), chosen)
        ..drawPath(BodyShapes.of(r), chosenOutline);
    }
    canvas.restore();

    final leader = Paint()
      ..color = AppTokens.primary
      ..strokeWidth = 1.4;
    for (final (from, to) in leaders) {
      canvas
        ..drawLine(from, to, leader)
        ..drawCircle(to, 3, Paint()..color = AppTokens.primary);
    }
  }

  /// Light separation lines so the figure reads as muscles, not a silhouette.
  void _muscleLines(Canvas c, Paint p) {
    void curve(
      double x1,
      double y1,
      double cx,
      double cy,
      double x2,
      double y2,
    ) {
      c.drawPath(
        Path()
          ..moveTo(x1, y1)
          ..quadraticBezierTo(cx, cy, x2, y2),
        p,
      );
      // Mirror for the other half.
      c.drawPath(
        Path()
          ..moveTo(200 - x1, y1)
          ..quadraticBezierTo(200 - cx, cy, 200 - x2, y2),
        p,
      );
    }

    c.drawLine(const Offset(100, 92), const Offset(100, 208), p);
    if (view == BodyView.front) {
      curve(72, 112, 86, 132, 100, 126); // pectoral
      for (final y in [158.0, 176.0, 194.0]) {
        c.drawLine(Offset(86, y), Offset(114, y), p); // abdominals
      }
      curve(80, 300, 88, 320, 92, 336); // thigh
      curve(84, 380, 86, 410, 88, 438); // shin
    } else {
      curve(74, 100, 84, 120, 92, 132); // shoulder blade
      curve(76, 186, 88, 196, 100, 200); // lower back
      c.drawLine(const Offset(100, 214), const Offset(100, 250), p); // buttocks
      curve(84, 380, 90, 396, 92, 414); // calf
    }
  }

  @override
  bool shouldRepaint(_BodyPainter old) =>
      old.view != view ||
      old.selected != selected ||
      old.leaders != leaders ||
      old.maxWidthShare != maxWidthShare;

  @override
  SemanticsBuilderCallback? get semanticsBuilder {
    final toggle = onToggle;
    if (toggle == null) return null;
    return (size) {
      final l = BodyMapLayout(size, maxWidthShare: maxWidthShare);
      return [
        for (final r in BodyRegions.of(view))
          CustomPainterSemantics(
            key: ValueKey(r.id),
            rect: _atLeast(l.rectOf(BodyShapes.of(r)), BodyShapes.minTarget),
            properties: SemanticsProperties(
              label: r.label,
              selected: selected.contains(r.id),
              button: true,
              textDirection: TextDirection.ltr,
              onTap: () => toggle(r),
            ),
          ),
      ];
    };
  }

  @override
  bool shouldRebuildSemantics(_BodyPainter old) =>
      old.view != view || old.selected != selected;

  static Rect _atLeast(Rect r, double min) => Rect.fromCenter(
    center: r.center,
    width: math.max(r.width, min),
    height: math.max(r.height, min),
  );
}

// ---- interactive map -------------------------------------------------------

/// Front/back body map with multiple selection. [selected] holds region ids
/// of both views, so switching the view keeps the selection.
class BodyMap extends StatefulWidget {
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;

  /// Figure height in logical pixels.
  final double height;

  const BodyMap({
    super.key,
    required this.selected,
    required this.onChanged,
    this.height = 380,
  });

  static const canvasKey = ValueKey('body-map-canvas');

  @override
  State<BodyMap> createState() => _BodyMapState();
}

class _BodyMapState extends State<BodyMap> {
  BodyView _view = BodyView.front;

  void _toggle(BodyRegion r) {
    final next = {...widget.selected};
    if (!next.remove(r.id)) next.add(r.id);
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final selectedRegions = [
      for (final id in widget.selected) ?BodyRegions.byId[id],
    ];
    final area = BodyRegions.areaFor(selectedRegions);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: SegmentedButton<BodyView>(
            segments: const [
              ButtonSegment(value: BodyView.front, label: Text('Front')),
              ButtonSegment(value: BodyView.back, label: Text('Back')),
            ],
            selected: {_view},
            showSelectedIcon: false,
            // App colours instead of the Material default purple.
            style: SegmentedButton.styleFrom(
              selectedBackgroundColor: AppTokens.primary,
              selectedForegroundColor: Colors.white,
              foregroundColor: AppTokens.primary,
              side: const BorderSide(color: AppTokens.primary),
              minimumSize: const Size(96, AppTokens.minTarget),
              textStyle: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            onSelectionChanged: (s) => setState(() => _view = s.single),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: widget.height,
          child: LayoutBuilder(
            builder: (context, box) {
              final size = Size(box.maxWidth, widget.height);
              final labels = _layoutLabels(context, size, selectedRegions);
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (d) {
                  final r = bodyRegionAt(_view, size, d.localPosition);
                  if (r != null) _toggle(r);
                },
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      child: CustomPaint(
                        key: BodyMap.canvasKey,
                        painter: _BodyPainter(
                          view: _view,
                          selected: widget.selected,
                          leaders: [
                            for (final l in labels) (l.lineFrom, l.anchor),
                          ],
                          onToggle: _toggle,
                        ),
                      ),
                    ),
                    for (final l in labels)
                      Positioned.fromRect(
                        rect: l.rect,
                        child: ExcludeSemantics(
                          child: Text(
                            l.region.label,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            textAlign: l.left
                                ? TextAlign.right
                                : TextAlign.left,
                            style: _labelStyle,
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Tap where it hurts or feels weak. You can choose more than one place.',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 14, color: AppTokens.textMuted),
        ),
        if (selectedRegions.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final r in selectedRegions)
                InputChip(
                  label: Text(r.label),
                  onDeleted: () => _toggle(r),
                  deleteButtonTooltipMessage: 'Remove ${r.label}',
                ),
            ],
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              // App green, not the theme's default text-button colour.
              style: TextButton.styleFrom(
                foregroundColor: AppTokens.accent,
                minimumSize: const Size(48, AppTokens.minTarget),
                textStyle: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              onPressed: () => widget.onChanged(<String>{}),
              child: const Text('Clear'),
            ),
          ),
        ],
        if (area != null)
          Text(
            'Your plan will focus on: ${RehabLabels.area(area)}',
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppTokens.accent,
            ),
          ),
      ],
    );
  }

  static const _labelStyle = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w600,
    color: AppTokens.primary,
  );

  /// Places a label per selected region of the current view in the side
  /// margins (the region's own screen side; centre regions on the right),
  /// stacked so they do not overlap, with a leader line to the region.
  List<_Label> _layoutLabels(
    BuildContext context,
    Size size,
    List<BodyRegion> selected,
  ) {
    final l = BodyMapLayout(size);
    final scaler = MediaQuery.textScalerOf(context);
    final leftWidth = math.max(0.0, l.origin.dx - 12);
    final rightX = l.figureRight + 12;
    final rightWidth = math.max(0.0, size.width - rightX);
    final out = <_Label>[];
    for (final left in [true, false]) {
      final side =
          [
            for (final r in selected)
              if (r.view == _view && r.onScreenLeft == left) r,
          ]..sort(
            (a, b) =>
                BodyShapes.centreOf(a).dy.compareTo(BodyShapes.centreOf(b).dy),
          );
      var nextTop = 0.0;
      for (final r in side) {
        // Measure at exactly the width the label is drawn at, or a label that
        // wraps on the device is clipped to its first line.
        final width = math.max(0.0, (left ? leftWidth : rightWidth) - 4);
        final tp = TextPainter(
          text: TextSpan(text: r.label, style: _labelStyle),
          textScaler: scaler,
          maxLines: 3,
          ellipsis: '…',
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: width);
        final anchor = l.toScreen(BodyShapes.centreOf(r));
        final h = tp.height + 2;
        final top = math.max(anchor.dy - h / 2, nextTop);
        nextTop = top + h + 4;
        final rect = Rect.fromLTWH(left ? 4 : rightX, top, width, h);
        final lineFrom = Offset(
          left ? rect.right + 2 : rect.left - 2,
          rect.center.dy,
        );
        out.add(_Label(r, rect, lineFrom, anchor, left));
      }
    }
    return out;
  }
}

class _Label {
  final BodyRegion region;
  final Rect rect;
  final Offset lineFrom;
  final Offset anchor;
  final bool left;
  const _Label(this.region, this.rect, this.lineFrom, this.anchor, this.left);

  @override
  bool operator ==(Object other) =>
      other is _Label && other.region.id == region.id && other.rect == rect;

  @override
  int get hashCode => Object.hash(region.id, rect);
}

// ---- plan card thumbnail ---------------------------------------------------

/// Small read-only front figure with the plan's target area highlighted.
class BodyMapThumbnail extends StatelessWidget {
  final String area;
  final double height;

  const BodyMapThumbnail({super.key, required this.area, this.height = 64});

  /// Regions drawn highlighted for [area].
  Set<BodyRegion> get highlighted => BodyRegions.forArea(area, BodyView.front);

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Target area: ${RehabLabels.area(area)}',
    excludeSemantics: true,
    child: SizedBox(
      width: height * 0.45,
      height: height,
      child: CustomPaint(
        painter: _BodyPainter(
          view: BodyView.front,
          selected: {for (final r in highlighted) r.id},
          maxWidthShare: 1,
        ),
      ),
    ),
  );
}
