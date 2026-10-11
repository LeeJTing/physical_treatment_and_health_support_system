import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:physical_treatment_and_health_support_system/core/themes/design_tokens.dart';

/// One exercise's guide animation: a looping repetition made from our own
/// correct recordings (training/build_guide_animations.py ->
/// `assets/guides/<pose_key>.json`, 11 Oct). Points are in a unit box, y down.
class GuideAnimationData {
  final String view; // front | side
  final bool hand;
  final bool hold;
  final String? near; // side view: the body side nearest the camera
  final double durationSec;
  final List<String> names;
  final List<List<int>> edges;
  final List<List<int>> fills;
  final List<List<Offset>> frames;
  final List<List<Offset>> props;

  const GuideAnimationData({
    required this.view,
    required this.hand,
    required this.hold,
    required this.near,
    required this.durationSec,
    required this.names,
    required this.edges,
    required this.fills,
    required this.frames,
    required this.props,
  });

  static List<Offset> _points(List<dynamic> flat) => [
    for (var i = 0; i + 1 < flat.length; i += 2)
      Offset((flat[i] as num).toDouble(), (flat[i + 1] as num).toDouble()),
  ];

  factory GuideAnimationData.fromJson(Map<String, dynamic> j) =>
      GuideAnimationData(
        view: j['view'] as String? ?? 'front',
        hand: j['kind'] == 'hand',
        hold: j['hold'] as bool? ?? false,
        near: j['near'] as String?,
        durationSec: (j['duration_sec'] as num?)?.toDouble() ?? 3,
        names: [for (final n in j['names'] as List) n as String],
        edges: [
          for (final e in j['edges'] as List)
            [for (final v in e as List) v as int],
        ],
        fills: [
          for (final f in (j['fills'] as List?) ?? const [])
            [for (final v in f as List) v as int],
        ],
        frames: [for (final f in j['frames'] as List) _points(f as List)],
        props: [for (final p in (j['props'] as List?) ?? const []) _points(p as List)],
      );

  static final Map<String, Future<GuideAnimationData?>> _cache = {};

  /// The animation for [poseKey], or null when the app has none for it.
  static Future<GuideAnimationData?> load(
    AssetBundle bundle,
    String poseKey,
  ) => _cache.putIfAbsent(poseKey, () async {
    try {
      final text = await bundle.loadString('assets/guides/$poseKey.json');
      return GuideAnimationData.fromJson(
        jsonDecode(text) as Map<String, dynamic>,
      );
    } catch (_) {
      return null; // no animation yet (e.g. a new exercise): nothing is shown
    }
  });
}

/// Plays an exercise's guide animation on a loop, with a short pause at the
/// start position. Shows [placeholder] when the exercise has no animation.
class ExerciseAnimation extends StatefulWidget {
  final String? poseKey;

  /// Colour of the person; props (floor, chair, wall, step) are drawn fainter.
  final Color color;

  /// Line width as a share of the shorter side of the box.
  final double strokeShare;
  final Widget placeholder;

  /// When set, the animation sits in a card of this height (only when the
  /// exercise has an animation, so no empty card is shown).
  final double? cardHeight;

  const ExerciseAnimation({
    super.key,
    required this.poseKey,
    this.color = AppTokens.primary,
    this.strokeShare = 0.022,
    this.placeholder = const SizedBox.shrink(),
    this.cardHeight,
  });

  @override
  State<ExerciseAnimation> createState() => _ExerciseAnimationState();
}

class _ExerciseAnimationState extends State<ExerciseAnimation>
    with SingleTickerProviderStateMixin {
  static const pause = 0.6; // seconds at the start position each loop

  late final AnimationController _c = AnimationController(vsync: this);
  GuideAnimationData? _data;
  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loaded) _load();
  }

  @override
  void didUpdateWidget(ExerciseAnimation old) {
    super.didUpdateWidget(old);
    if (old.poseKey != widget.poseKey) _load();
  }

  Future<void> _load() async {
    _loaded = true;
    final key = widget.poseKey;
    final data = key == null
        ? null
        : await GuideAnimationData.load(DefaultAssetBundle.of(context), key);
    if (!mounted) return;
    setState(() => _data = data);
    _c.stop();
    if (data != null && !data.hold) {
      _c.duration = Duration(
        milliseconds: ((data.durationSec + pause) * 1000).round(),
      );
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    if (data == null) return widget.placeholder;
    final h = widget.cardHeight;
    if (h != null) {
      return Container(
        height: h,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTokens.surface,
          borderRadius: BorderRadius.circular(AppTokens.radiusCard),
          border: Border.all(color: AppTokens.border),
        ),
        child: _animated(data),
      );
    }
    return _animated(data);
  }

  Widget _animated(GuideAnimationData data) {
    return Semantics(
      label: 'Animation showing how to do the exercise',
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final total = data.durationSec + pause;
          final t = (_c.value * total - pause).clamp(0.0, data.durationSec);
          return CustomPaint(
            painter: _GuidePainter(
              data,
              data.hold ? 0 : t / data.durationSec,
              widget.color,
              widget.strokeShare,
            ),
            size: Size.infinite,
          );
        },
      ),
    );
  }
}

class _GuidePainter extends CustomPainter {
  final GuideAnimationData d;
  final double phase; // 0..1 through the repetition
  final Color color;
  final double strokeShare;

  _GuidePainter(this.d, this.phase, this.color, this.strokeShare);

  List<Offset> _frame() {
    final n = d.frames.length;
    final x = phase * (n - 1);
    final i = x.floor().clamp(0, n - 1);
    final j = math.min(i + 1, n - 1);
    final w = x - i;
    return [
      for (var k = 0; k < d.frames[i].length; k++)
        Offset.lerp(d.frames[i][k], d.frames[j][k], w)!,
    ];
  }

  @override
  void paint(Canvas canvas, Size size) {
    final side = math.min(size.width, size.height);
    final origin = Offset(
      (size.width - side) / 2,
      (size.height - side) / 2,
    );
    Offset at(Offset p) => origin + p * side;
    final width = side * strokeShare;

    final propPaint = Paint()
      ..color = color.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = width * 0.7
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (final p in d.props) {
      if (p.length < 2) continue;
      final path = Path()..moveTo(at(p.first).dx, at(p.first).dy);
      for (final q in p.skip(1)) {
        path.lineTo(at(q).dx, at(q).dy);
      }
      canvas.drawPath(path, propPaint);
    }

    final pts = _frame();
    final near = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round;
    final far = Paint()
      ..color = color.withValues(alpha: 0.45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round;
    // Side view: the limbs on the far side are drawn first and fainter.
    final farPrefix = d.near == null ? null : (d.near == 'left' ? 'r_' : 'l_');
    bool isFar(List<int> e) =>
        farPrefix != null &&
        d.names[e[0]].startsWith(farPrefix) &&
        d.names[e[1]].startsWith(farPrefix);

    for (final f in d.fills) {
      final path = Path()..moveTo(at(pts[f.first]).dx, at(pts[f.first]).dy);
      for (final k in f.skip(1)) {
        path.lineTo(at(pts[k]).dx, at(pts[k]).dy);
      }
      canvas.drawPath(
        path..close(),
        Paint()..color = color.withValues(alpha: 0.55),
      );
    }
    for (final e in d.edges.where(isFar)) {
      canvas.drawLine(at(pts[e[0]]), at(pts[e[1]]), far);
    }
    for (final e in d.edges.where((e) => !isFar(e))) {
      canvas.drawLine(at(pts[e[0]]), at(pts[e[1]]), near);
    }

    // Head: a circle around the ears, sized from the shoulders.
    final i = {for (var k = 0; k < d.names.length; k++) d.names[k]: k};
    final le = i['l_ear'], re = i['r_ear'], ls = i['l_shoulder'];
    final rs = i['r_shoulder'], lh = i['l_hip'], rh = i['r_hip'];
    if (le != null && re != null && ls != null && rs != null && lh != null && rh != null) {
      final ear = (pts[le] + pts[re]) / 2;
      final shoulder = (pts[ls] + pts[rs]) / 2;
      final hip = (pts[lh] + pts[rh]) / 2;
      final r = (shoulder - hip).distance * 0.24;
      canvas.drawCircle(at(ear), r * side, Paint()..color = color);
      canvas.drawLine(at(ear), at(shoulder), near);
    }
  }

  @override
  bool shouldRepaint(_GuidePainter old) =>
      old.phase != phase || old.d != d || old.color != color;
}
