import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:physical_treatment_and_health_support_system/core/themes/design_tokens.dart';
import 'package:physical_treatment_and_health_support_system/view/common/exercise_animation.dart';

/// "Set up your phone" (23 Oct): a drawing of where the phone goes. The phone on a stand at
/// waist height (table height for hand exercises), the person at the right distance, side-on or
/// facing it as the posture check needs (ExerciseSpec.view), and what the camera must see.
class SetupScene extends StatelessWidget {
  final GuideAnimationData? data;
  final bool hands;
  const SetupScene({super.key, required this.data, required this.hands});

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    image: true,
    label: hands
        ? 'Drawing: the phone propped up on a table, half a metre to one metre from your hand.'
        : 'Drawing: the phone on a stand at waist height, 2.5 to 3 metres from you, '
              '${data?.view == 'side' ? 'with you side-on to it' : 'with you facing it'}.',
    child: AspectRatio(
      aspectRatio: 1.5,
      child: CustomPaint(painter: _ScenePainter(data, hands)),
    ),
  );
}

class _ScenePainter extends CustomPainter {
  final GuideAnimationData? d;
  final bool hands;
  _ScenePainter(this.d, this.hands);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final floorY = h * 0.86;
    final ink = Paint()
      ..color = AppTokens.textMuted
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    final dashed = Paint()
      ..color = AppTokens.cta.withValues(alpha: 0.8)
      ..strokeWidth = 2;

    void dash(Offset a, Offset b) {
      final n = ((b - a).distance / 10).floor();
      for (var k = 0; k < n; k += 2) {
        canvas.drawLine(
          Offset.lerp(a, b, k / n)!,
          Offset.lerp(a, b, (k + 1) / n)!,
          dashed,
        );
      }
    }

    void label(String text, Offset at, {double size = 14}) {
      final tp = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            color: AppTokens.text,
            fontSize: size,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: w * 0.6);
      tp.paint(canvas, at - Offset(tp.width / 2, 0));
    }

    // Floor (and a table for hand exercises).
    canvas.drawLine(Offset(w * 0.04, floorY), Offset(w * 0.96, floorY), ink);
    final standTop = hands ? h * 0.5 : h * 0.5;
    if (hands) {
      canvas.drawLine(
        Offset(w * 0.08, h * 0.56),
        Offset(w * 0.92, h * 0.56),
        ink,
      );
      for (final x in [w * 0.12, w * 0.88]) {
        canvas.drawLine(Offset(x, h * 0.56), Offset(x, floorY), ink);
      }
    }

    // The phone on its stand, lens facing the person.
    final px = w * 0.16;
    final legTop = Offset(px, hands ? h * 0.47 : standTop + h * 0.06);
    if (!hands) {
      for (final dx in [-w * 0.05, 0.0, w * 0.05]) {
        canvas.drawLine(legTop, Offset(px + dx, floorY), ink);
      }
    }
    final phone = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(px, hands ? h * 0.4 : standTop),
        width: w * 0.035,
        height: h * 0.13,
      ),
      const Radius.circular(4),
    );
    canvas.drawRRect(phone, Paint()..color = AppTokens.text);
    final lens = Offset(px + w * 0.012, phone.center.dy - h * 0.035);
    canvas.drawCircle(lens, 3, Paint()..color = AppTokens.cta);

    // The person (the guide's first frame), or a hand at the table.
    final personLeft = hands ? w * 0.55 : w * 0.6;
    final personW = hands ? w * 0.3 : w * 0.34;
    final top = hands ? h * 0.18 : h * 0.06;
    final bottom = hands ? h * 0.56 : floorY;
    final data = d;
    var head = Offset(personLeft + personW / 2, top);
    var feet = Offset(personLeft + personW / 2, bottom);
    if (data != null && data.frames.isNotEmpty) {
      final f = data.frames.first;
      var minX = 1.0, maxX = 0.0, minY = 1.0, maxY = 0.0;
      // The person with their props (chair, wall, step), all fitted in.
      for (final p in [...f, for (final q in data.props) ...q]) {
        minX = math.min(minX, p.dx);
        maxX = math.max(maxX, p.dx);
        minY = math.min(minY, p.dy);
        maxY = math.max(maxY, p.dy);
      }
      final scale = math.min(
        personW / math.max(maxX - minX, 1e-3),
        (bottom - top) / math.max(maxY - minY, 1e-3),
      );
      Offset at(Offset p) => Offset(
        personLeft + personW / 2 + (p.dx - (minX + maxX) / 2) * scale,
        bottom - (maxY - p.dy) * scale,
      );
      final prop = Paint()
        ..color = AppTokens.textMuted.withValues(alpha: 0.6)
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round;
      for (final q in data.props) {
        for (var k = 0; k + 1 < q.length; k++) {
          canvas.drawLine(at(q[k]), at(q[k + 1]), prop);
        }
      }
      final body = Paint()
        ..color = AppTokens.primary
        ..strokeWidth = hands ? 5 : 9
        ..strokeCap = StrokeCap.round;
      for (final e in data.edges) {
        canvas.drawLine(at(f[e[0]]), at(f[e[1]]), body);
      }
      final ears = [data.index('l_ear'), data.index('r_ear')];
      if (ears[0] != null && ears[1] != null) {
        final ear = (at(f[ears[0]!]) + at(f[ears[1]!])) / 2;
        canvas.drawCircle(ear, h * 0.055, Paint()..color = AppTokens.primary);
      }
      head = Offset(at(Offset(0, minY)).dx, at(Offset(0, minY)).dy);
      feet = Offset(head.dx, at(Offset(0, maxY)).dy);
    }

    // What the camera sees: from the lens to above the head and below the feet.
    dash(lens, Offset(personLeft - w * 0.02, head.dy - h * 0.04));
    dash(
      lens,
      Offset(personLeft - w * 0.02, math.min(feet.dy + h * 0.03, floorY)),
    );

    // The distance along the floor.
    final y = floorY + h * 0.06;
    final a = Offset(px, y), b = Offset(personLeft + personW * 0.3, y);
    canvas.drawLine(a, b, dashed..strokeWidth = 2.5);
    for (final p in [a, b]) {
      canvas.drawLine(p - Offset(0, 6), p + Offset(0, 6), dashed);
    }
    label(
      hands ? '0.5 to 1 m' : '2.5 to 3 m',
      Offset((a.dx + b.dx) / 2, y - h * 0.1),
      size: 15,
    );
    label(
      hands ? 'table height' : 'waist height',
      Offset(px, phone.top - h * 0.12),
      size: 12,
    );
  }

  @override
  bool shouldRepaint(_ScenePainter old) => old.d != d || old.hands != hands;
}
