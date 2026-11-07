import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:physical_treatment_and_health_support_system/core/themes/design_tokens.dart';
import 'package:physical_treatment_and_health_support_system/view/common/exercise_animation.dart';

/// "Set up your phone" (23 Oct): where the phone goes, in two pictures. Seen from above: the
/// phone, what it sees, and the person side-on to it or facing it, as the posture check needs
/// (ExerciseSpec.view). What the phone should see: the person inside the box on the screen.
///
/// Not a side drawing: one with the phone on the left and a person facing right read as "put
/// the phone behind you" (Elwin, 23 Oct).
class SetupScene extends StatelessWidget {
  final GuideAnimationData? data;
  final bool hands;
  /// The phone goes on the floor (floor exercises), not at waist height.
  final bool floor;

  /// How far away, from the exercise's camera tip; null: 2.5 to 3 m.
  final String? distance;

  const SetupScene({
    super.key,
    required this.data,
    required this.hands,
    this.floor = false,
    this.distance,
  });

  @override
  Widget build(BuildContext context) {
    final side = !hands && data?.view == 'side';
    final distance = hands ? '0.5 to 1 m' : this.distance ?? '2.5 to 3 m';
    final above = hands
        ? 'Seen from above: the phone on the table, facing your hand.'
        : side
        ? 'Seen from above: turn sideways, so your side faces the phone.'
        : 'Seen from above: face the phone.';
    const caption = TextStyle(
      fontSize: 15,
      height: 1.3,
      fontWeight: FontWeight.w600,
      color: AppTokens.text,
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            children: [
              Semantics(
                container: true,
                image: true,
                label:
                    '$above The phone is $distance away'
                    '${hands ? '' : floor ? ', on the floor' : ', at waist height'}.',
                child: AspectRatio(
                  aspectRatio: 0.8,
                  child: CustomPaint(
                    key: const Key('setup_from_above'),
                    painter: _FromAbove(
                      side: side,
                      hands: hands,
                      distance: distance,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              ExcludeSemantics(
                child: Text(above, textAlign: TextAlign.center, style: caption),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            children: [
              Semantics(
                container: true,
                image: true,
                label: hands
                    ? 'The phone screen shows your forearm and whole hand inside the box.'
                    : 'The phone screen shows your whole body, head to feet, inside the box'
                          '${side ? ', from the side' : ''}.',
                child: AspectRatio(
                  aspectRatio: 0.8,
                  child: CustomPaint(
                    key: const Key('setup_phone_view'),
                    painter: _PhoneView(data),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              const ExcludeSemantics(
                child: Text(
                  'What the phone should see',
                  textAlign: TextAlign.center,
                  style: caption,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

TextPainter _text(String s, double size, {double maxWidth = 200}) =>
    TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(
          color: AppTokens.text,
          fontSize: size,
          fontWeight: FontWeight.w700,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: maxWidth);

void _dash(Canvas canvas, Offset a, Offset b, Paint p, {double step = 8}) {
  final n = math.max(2, ((b - a).distance / step).floor());
  for (var k = 0; k < n; k += 2) {
    canvas.drawLine(
      Offset.lerp(a, b, k / n)!,
      Offset.lerp(a, b, math.min(k + 1, n) / n)!,
      p,
    );
  }
}

/// A plan of the room: the phone at the bottom looking up, the person at the top.
class _FromAbove extends CustomPainter {
  final bool side;
  final bool hands;
  final String distance;
  _FromAbove({required this.side, required this.hands, required this.distance});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final card = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(12),
    );
    canvas.drawRRect(card, Paint()..color = AppTokens.surface);
    canvas.drawRRect(
      card,
      Paint()
        ..color = AppTokens.border
        ..style = PaintingStyle.stroke,
    );

    final phone = Offset(w / 2, h * 0.84);
    final person = Offset(w / 2, h * 0.27);
    final lens = Offset(phone.dx, phone.dy - h * 0.035);

    // What the camera sees: a wedge from the lens towards the person.
    canvas.drawPath(
      Path()
        ..moveTo(lens.dx, lens.dy)
        ..lineTo(w * 0.08, h * 0.04)
        ..lineTo(w * 0.92, h * 0.04)
        ..close(),
      Paint()..color = AppTokens.cta.withValues(alpha: 0.08),
    );
    final edge = Paint()
      ..color = AppTokens.cta.withValues(alpha: 0.7)
      ..strokeWidth = 2;
    _dash(canvas, lens, Offset(w * 0.08, h * 0.04), edge);
    _dash(canvas, lens, Offset(w * 0.92, h * 0.04), edge);

    // The phone, seen from above, lens towards the person.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: phone, width: w * 0.22, height: h * 0.06),
        const Radius.circular(4),
      ),
      Paint()..color = AppTokens.text,
    );
    canvas.drawCircle(lens, 3.5, Paint()..color = AppTokens.cta);
    final ph = _text('phone', 12);
    ph.paint(canvas, Offset(phone.dx - ph.width / 2, phone.dy + h * 0.04));

    final ink = Paint()..color = AppTokens.primary;
    if (hands) {
      // The table and a hand on it.
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: person, width: w * 0.8, height: h * 0.3),
          const Radius.circular(6),
        ),
        Paint()..color = AppTokens.border,
      );
      canvas.drawOval(
        Rect.fromCenter(center: person, width: w * 0.16, height: h * 0.2),
        ink,
      );
    } else {
      // The person from above: shoulders, head, and a nose showing which way they face.
      // Side-on, their shoulders point at the phone; facing it, they are across its view.
      canvas.save();
      canvas.translate(person.dx, person.dy);
      canvas.rotate(
        side ? 0 : math.pi / 2,
      ); // 0: faces right; pi/2: faces the phone
      canvas.drawOval(
        Rect.fromCenter(center: Offset.zero, width: w * 0.16, height: w * 0.42),
        ink,
      );
      final head = w * 0.085;
      canvas.drawCircle(
        Offset.zero,
        head,
        Paint()..color = AppTokens.brandDeep,
      );
      canvas.drawPath(
        Path()
          ..moveTo(head + w * 0.05, 0)
          ..lineTo(head - w * 0.01, -w * 0.035)
          ..lineTo(head - w * 0.01, w * 0.035)
          ..close(),
        Paint()..color = AppTokens.brandDeep,
      );
      // An arrow: the way the person faces.
      final arrow = Paint()
        ..color = AppTokens.cta
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round;
      final from = Offset(w * 0.18, 0), to = Offset(w * 0.32, 0);
      canvas.drawLine(from, to, arrow);
      canvas.drawLine(to, to + const Offset(-8, -6), arrow);
      canvas.drawLine(to, to + const Offset(-8, 6), arrow);
      canvas.restore();
    }

    // The distance between them.
    final top = Offset(w * 0.12, person.dy + h * 0.14);
    final bottom = Offset(w * 0.12, phone.dy - h * 0.01);
    final measure = Paint()
      ..color = AppTokens.textMuted
      ..strokeWidth = 2;
    canvas.drawLine(top, bottom, measure);
    for (final p in [top, bottom]) {
      canvas.drawLine(p - const Offset(6, 0), p + const Offset(6, 0), measure);
    }
    final d = _text(distance, 13, maxWidth: h);
    canvas.save();
    canvas.translate(top.dx + 6, (top.dy + bottom.dy) / 2 + d.width / 2);
    canvas.rotate(-math.pi / 2);
    d.paint(canvas, Offset.zero);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_FromAbove old) =>
      old.side != side || old.hands != hands || old.distance != distance;
}

/// The phone's screen: the person (the guide's first frame, with the chair, wall or step)
/// inside the dashed box, as on the recording screen.
class _PhoneView extends CustomPainter {
  final GuideAnimationData? d;
  _PhoneView(this.d);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final body = Rect.fromCenter(
      center: Offset(w / 2, h / 2),
      width: math.min(w * 0.82, h * 0.56),
      height: h * 0.98,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(body, const Radius.circular(14)),
      Paint()..color = AppTokens.text,
    );
    final screen = body.deflate(6);
    canvas.drawRRect(
      RRect.fromRectAndRadius(screen, const Radius.circular(10)),
      Paint()..color = AppTokens.primary,
    );
    final box = screen.deflate(screen.width * 0.08);
    final dashed = Paint()
      ..color = Colors.white70
      ..strokeWidth = 1.5;
    for (final (a, b) in [
      (box.topLeft, box.topRight),
      (box.topRight, box.bottomRight),
      (box.bottomRight, box.bottomLeft),
      (box.bottomLeft, box.topLeft),
    ]) {
      _dash(canvas, a, b, dashed, step: 6);
    }

    final data = d;
    if (data == null || data.frames.isEmpty) return;
    final f = data.frames.first;
    var minX = 1.0, maxX = 0.0, minY = 1.0, maxY = 0.0;
    for (final p in [...f, for (final q in data.props) ...q]) {
      minX = math.min(minX, p.dx);
      maxX = math.max(maxX, p.dx);
      minY = math.min(minY, p.dy);
      maxY = math.max(maxY, p.dy);
    }
    final inner = box.deflate(box.width * 0.06);
    final scale = math.min(
      inner.width / math.max(maxX - minX, 1e-3),
      inner.height / math.max(maxY - minY, 1e-3),
    );
    Offset at(Offset p) => Offset(
      inner.center.dx + (p.dx - (minX + maxX) / 2) * scale,
      inner.center.dy + (p.dy - (minY + maxY) / 2) * scale,
    );
    final prop = Paint()
      ..color = Colors.white38
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    for (final q in data.props) {
      for (var k = 0; k + 1 < q.length; k++) {
        canvas.drawLine(at(q[k]), at(q[k + 1]), prop);
      }
    }
    final person = Paint()
      ..color = Colors.white
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    for (final e in data.edges) {
      canvas.drawLine(at(f[e[0]]), at(f[e[1]]), person);
    }
    final le = data.index('l_ear'), re = data.index('r_ear');
    if (le != null && re != null) {
      canvas.drawCircle(
        (at(f[le]) + at(f[re])) / 2,
        inner.height * 0.045,
        Paint()..color = Colors.white,
      );
    }
  }

  @override
  bool shouldRepaint(_PhoneView old) => old.d != d;
}
