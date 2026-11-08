import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:physical_treatment_and_health_support_system/core/themes/design_tokens.dart';
import 'package:physical_treatment_and_health_support_system/view/common/exercise_coaching.dart';

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

  GuideAnimationData({
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
        props: [
          for (final p in (j['props'] as List?) ?? const []) _points(p as List),
        ],
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

  /// Index of a landmark. A name without a side (knee) means the side nearest the camera, or
  /// the left in a front view.
  int? index(String? name) {
    if (name == null) return null;
    final i = names.indexOf(name);
    if (i >= 0) return i;
    final j = names.indexOf('${near == 'right' ? 'r' : 'l'}_$name');
    return j < 0 ? null : j;
  }

  /// The part of the repetition each frame belongs to (23 Oct), from how far the body has moved
  /// from the first frame: start (still near it), go (moving away), top (at least 85% of the way)
  /// and back (returning). The recordings start and end at rest, so this fits every exercise.
  late final List<String> phases = () {
    final n = frames.length;
    if (n < 2 || hold) return List.filled(n, 'start');
    double away(List<Offset> f) {
      var s = 0.0;
      for (var k = 0; k < f.length; k++) {
        s += (f[k] - frames[0][k]).distance;
      }
      return s / f.length;
    }

    final d = [for (final f in frames) away(f)];
    var peak = 0;
    for (var i = 1; i < n; i++) {
      if (d[i] > d[peak]) peak = i;
    }
    if (d[peak] < 1e-6) return List.filled(n, 'start');
    return [
      for (var i = 0; i < n; i++)
        d[i] >= 0.85 * d[peak]
            ? 'top'
            : i < peak
            ? (d[i] < 0.15 * d[peak] ? 'start' : 'go')
            : 'back',
    ];
  }();

  /// The frame shown for a step: the first frame for start, the furthest one for top, and the
  /// middle of the go and back parts.
  int keyFrame(String phase) {
    if (phase == 'start') return 0;
    final at = [
      for (var i = 0; i < phases.length; i++)
        if (phases[i] == phase) i,
    ];
    return at.isEmpty ? 0 : at[at.length ~/ 2];
  }

  /// The phase at [fraction] (0..1) of the repetition.
  String phaseAt(double fraction) =>
      phases[(fraction * (phases.length - 1)).round().clamp(
        0,
        phases.length - 1,
      )];
}

/// Plays an exercise's guide animation on a loop, with a short pause at the
/// start position. Shows [placeholder] when the exercise has no animation.
///
/// With [coaching] (23 Oct) the person is drawn body-shaped, the joint to watch gets a ring and
/// an arc, an arrow shows which way the body is moving, and [showCaption] adds the caption for
/// each part of the repetition. [still] freezes it at one part (a step card).
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

  final ExerciseCoaching? coaching;
  final bool showCaption;

  /// start, go, top or back: show that moment only, not the loop.
  final String? still;

  /// Above 1 the repetition plays slower (the pace the patient follows while recording).
  final double pace;

  /// Told each time the part of the repetition changes, with the repetition number (from 1).
  final void Function(String phase, int rep)? onPhase;

  /// A new value starts the loop again from the beginning (e.g. when recording starts).
  final Object? restartToken;

  const ExerciseAnimation({
    super.key,
    required this.poseKey,
    this.color = AppTokens.primary,
    this.strokeShare = 0.022,
    this.placeholder = const SizedBox.shrink(),
    this.cardHeight,
    this.coaching,
    this.showCaption = false,
    this.still,
    this.pace = 1,
    this.onPhase,
    this.restartToken,
  });

  @override
  State<ExerciseAnimation> createState() => _ExerciseAnimationState();
}

class _ExerciseAnimationState extends State<ExerciseAnimation>
    with SingleTickerProviderStateMixin {
  static const pause = 0.6; // seconds at the start position each loop

  late final AnimationController _c = AnimationController(vsync: this)
    ..addListener(_tick);
  GuideAnimationData? _data;
  bool _loaded = false;
  String? _phase;
  int _rep = 1;
  double _last = 0;

  double get _pause => pause * widget.pace;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loaded) _load();
  }

  @override
  void didUpdateWidget(ExerciseAnimation old) {
    super.didUpdateWidget(old);
    if (old.poseKey != widget.poseKey) {
      _load();
    } else if (old.pace != widget.pace ||
        old.still != widget.still ||
        old.restartToken != widget.restartToken) {
      _start(restart: old.restartToken != widget.restartToken);
    }
  }

  Future<void> _load() async {
    _loaded = true;
    final key = widget.poseKey;
    final data = key == null
        ? null
        : await GuideAnimationData.load(DefaultAssetBundle.of(context), key);
    if (!mounted) return;
    setState(() => _data = data);
    _start(restart: true);
  }

  void _start({required bool restart}) {
    final data = _data;
    _c.stop();
    if (data == null || data.hold || widget.still != null) return;
    _c.duration = Duration(
      milliseconds: ((data.durationSec * widget.pace + _pause) * 1000).round(),
    );
    if (restart) {
      _rep = 1;
      _phase = null;
      _last = 0;
      _c.value = 0;
    }
    _c.repeat();
  }

  /// The time into the repetition at the controller's value, after the pause.
  double _fraction(GuideAnimationData data) {
    final dur = data.durationSec * widget.pace;
    final t = (_c.value * (dur + _pause) - _pause).clamp(0.0, dur);
    return t / dur;
  }

  void _tick() {
    final data = _data;
    if (data == null) return;
    if (_c.value < _last) _rep++;
    _last = _c.value;
    final inPause =
        _c.value * (data.durationSec * widget.pace + _pause) < _pause;
    final phase = inPause ? 'start' : data.phaseAt(_fraction(data));
    if (phase != _phase) {
      _phase = phase;
      widget.onPhase?.call(phase, _rep);
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
    final coaching = widget.coaching;
    String phaseNow() => widget.still ?? _phase ?? 'start';
    // Its own node (container), so the label is not merged into the text
    // around it and a screen reader reads it as one item.
    return Semantics(
      container: true,
      image: true,
      label: 'Animation showing how to do the exercise',
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final still = widget.still;
          final fraction = data.hold
              ? 0.0
              : still != null
              ? data.keyFrame(still) / math.max(1, data.frames.length - 1)
              : _fraction(data);
          final painter = CustomPaint(
            painter: _GuidePainter(
              data,
              fraction,
              widget.color,
              widget.strokeShare,
              coaching: coaching,
            ),
            size: Size.infinite,
          );
          final caption = coaching?.captions[phaseNow()];
          if (!widget.showCaption || caption == null) return painter;
          return Column(
            children: [
              Expanded(child: painter),
              const SizedBox(height: 8),
              ExcludeSemantics(
                child: Text(
                  caption,
                  key: const Key('guide_caption'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppTokens.text,
                  ),
                ),
              ),
            ],
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
  final ExerciseCoaching? coaching;

  _GuidePainter(
    this.d,
    this.phase,
    this.color,
    this.strokeShare, {
    this.coaching,
  });

  List<Offset> _frameAt(double p) {
    final n = d.frames.length;
    final x = p.clamp(0.0, 1.0) * (n - 1);
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
    final origin = Offset((size.width - side) / 2, (size.height - side) / 2);
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

    final pts = _frameAt(phase);
    final i = {for (var k = 0; k < d.names.length; k++) d.names[k]: k};
    // Coached: a fuller, body-shaped person (23 Oct); the hand guides keep thin lines.
    final body = coaching != null && !d.hand;
    final limb = body ? width * 1.9 : width;
    final near = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = limb
      ..strokeCap = StrokeCap.round;
    final far = Paint()
      ..color = color.withValues(alpha: body ? 0.4 : 0.45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = body ? limb * 0.85 : width
      ..strokeCap = StrokeCap.round;
    // Side view: the limbs on the far side are drawn first and fainter.
    final farPrefix = d.near == null ? null : (d.near == 'left' ? 'r_' : 'l_');
    bool isFar(List<int> e) =>
        farPrefix != null &&
        d.names[e[0]].startsWith(farPrefix) &&
        d.names[e[1]].startsWith(farPrefix);
    // The trunk is drawn as one shape when coached, not as four lines.
    bool trunk(List<int> e) {
      if (!body) return false;
      bool part(String n) => n.endsWith('shoulder') || n.endsWith('hip');
      return part(d.names[e[0]]) && part(d.names[e[1]]);
    }

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
    for (final e in d.edges.where((e) => isFar(e) && !trunk(e))) {
      canvas.drawLine(at(pts[e[0]]), at(pts[e[1]]), far);
    }

    final le = i['l_ear'], re = i['r_ear'], ls = i['l_shoulder'];
    final rs = i['r_shoulder'], lh = i['l_hip'], rh = i['r_hip'];
    final hasTrunk =
        le != null &&
        re != null &&
        ls != null &&
        rs != null &&
        lh != null &&
        rh != null;
    if (body && hasTrunk) {
      final shoulder = (pts[ls] + pts[rs]) / 2;
      final hip = (pts[lh] + pts[rh]) / 2;
      canvas.drawPath(
        Path()
          ..moveTo(at(pts[ls]).dx, at(pts[ls]).dy)
          ..lineTo(at(pts[rs]).dx, at(pts[rs]).dy)
          ..lineTo(at(pts[rh]).dx, at(pts[rh]).dy)
          ..lineTo(at(pts[lh]).dx, at(pts[lh]).dy)
          ..close(),
        Paint()..color = color,
      );
      canvas.drawLine(
        at(shoulder),
        at(hip),
        Paint()
          ..color = color
          ..strokeWidth = limb * 1.6
          ..strokeCap = StrokeCap.round,
      );
    }
    for (final e in d.edges.where((e) => !isFar(e) && !trunk(e))) {
      canvas.drawLine(at(pts[e[0]]), at(pts[e[1]]), near);
    }

    // Head: a circle around the ears, sized from the shoulders.
    if (hasTrunk) {
      final ear = (pts[le] + pts[re]) / 2;
      final shoulder = (pts[ls] + pts[rs]) / 2;
      final hip = (pts[lh] + pts[rh]) / 2;
      final r = (shoulder - hip).distance * (body ? 0.3 : 0.24);
      canvas.drawCircle(at(ear), r * side, Paint()..color = color);
      canvas.drawLine(at(ear), at(shoulder), near);
    }

    final c = coaching;
    if (c == null) return;
    final accent = Paint()
      ..color = AppTokens.cta
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(2, width * 0.9)
      ..strokeCap = StrokeCap.round;

    // The joint to watch: a ring, and the arc of its angle.
    final j = d.index(c.focusJoint);
    if (j != null) {
      final p = at(pts[j]);
      canvas.drawCircle(p, limb * 0.75, accent);
      final a = d.index(c.focusFrom), b = d.index(c.focusTo);
      if (a != null && b != null) {
        final u = at(pts[a]) - p, v = at(pts[b]) - p;
        final start = u.direction;
        var sweep = v.direction - u.direction;
        if (sweep > math.pi) sweep -= 2 * math.pi;
        if (sweep < -math.pi) sweep += 2 * math.pi;
        // Inside the angle, clear of the ring: a share of the shorter limb.
        final r = math.max(limb * 1.6, math.min(u.distance, v.distance) * 0.45);
        canvas.drawArc(
          Rect.fromCircle(center: p, radius: r),
          start,
          sweep,
          false,
          accent,
        );
      }
    }

    // Which way the body is moving now: an arrow beside the moving point.
    final m = d.index(c.mover);
    if (m != null && !d.hold) {
      final ahead = _frameAt(phase + 0.06)[m],
          behind = _frameAt(phase - 0.06)[m];
      final v = ahead - behind;
      if (v.distance > 0.02) {
        final dir = v / v.distance;
        final from = at(pts[m]) + dir * side * 0.05;
        final to = from + dir * side * 0.12;
        canvas.drawLine(from, to, accent);
        for (final s in [-1, 1]) {
          final back = Offset.fromDirection(
            dir.direction + math.pi + s * 0.5,
            side * 0.04,
          );
          canvas.drawLine(to, to + back, accent);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_GuidePainter old) =>
      old.phase != phase ||
      old.d != d ||
      old.color != color ||
      old.coaching != coaching;
}
