import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:physical_treatment_and_health_support_system/core/themes/design_tokens.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';

/// Drawn pictures for the diet plan. The catalogue has no photos it may share (the food photo set
/// is for research only), so each food is shown by its place on the plate: a coloured picture for
/// a dish, rice or bread, a protein, vegetables, fruit, a drink, a snack, a dessert or a soup. The
/// same colours mark the parts of the healthy plate picture, so the two can be matched.
class FoodLook {
  final IconData icon;
  final Color back;
  final Color fore;
  final String label;
  const FoodLook(this.icon, this.back, this.fore, this.label);

  static const _veg = Color(0xFF3B7D23);
  static const _vegBack = Color(0xFFE3F1D9);
  static const _starch = Color(0xFF9A6A00);
  static const _starchBack = Color(0xFFFBEFCB);
  static const _protein = Color(0xFFB2472E);
  static const _proteinBack = Color(0xFFFBE3DC);

  static FoodLook of(String role) => switch (role) {
    'meal' => const FoodLook(Icons.rice_bowl, AppTokens.tint, AppTokens.brandDeep, 'Complete dish'),
    'staple' => const FoodLook(Icons.bakery_dining, _starchBack, _starch, 'Rice, bread or noodles'),
    'protein' => const FoodLook(Icons.set_meal, _proteinBack, _protein, 'Protein'),
    'veg' => const FoodLook(Icons.eco, _vegBack, _veg, 'Vegetables'),
    'fruit' => const FoodLook(Icons.circle, Color(0xFFFFE9D6), Color(0xFFE07B1F), 'Fruit'),
    'drink' => const FoodLook(Icons.local_cafe, Color(0xFFE6EEF8), Color(0xFF345C8C), 'Drink'),
    'snack' => const FoodLook(Icons.cookie, AppTokens.cautionContainer, AppTokens.caution, 'Light snack'),
    'dessert' => const FoodLook(Icons.icecream, Color(0xFFF6E3EF), Color(0xFF8C3D6E), 'Sweet treat'),
    'soup' => const FoodLook(Icons.soup_kitchen, Color(0xFFFDEFD9), Color(0xFF8B5200), 'Soup'),
    _ => const FoodLook(Icons.restaurant, AppTokens.tint, AppTokens.brandDeep, 'Food'),
  };

  static const plateVeg = _veg;
  static const plateStarch = _starch;
  static const plateProtein = _protein;
}

/// A food's picture: its plate role in a soft circle (fruit is drawn as a small fruit).
class FoodRoleAvatar extends StatelessWidget {
  final String role;
  final double size;
  const FoodRoleAvatar(this.role, {super.key, this.size = 44});

  @override
  Widget build(BuildContext context) {
    final look = FoodLook.of(role);
    return Semantics(
      label: look.label,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [look.back, Color.lerp(look.back, look.fore, 0.18)!],
          ),
        ),
        alignment: Alignment.center,
        child: role == 'fruit'
            ? CustomPaint(size: Size.square(size * 0.56), painter: _FruitPainter(look.fore))
            : Icon(look.icon, size: size * 0.52, color: look.fore),
      ),
    );
  }
}

class _FruitPainter extends CustomPainter {
  final Color colour;
  _FruitPainter(this.colour);

  @override
  void paint(Canvas canvas, Size s) {
    final r = s.width * 0.42;
    final c = Offset(s.width / 2, s.height * 0.56);
    canvas.drawCircle(c, r, Paint()..color = colour);
    canvas.drawCircle(c.translate(-r * 0.35, -r * 0.35), r * 0.22, Paint()..color = Colors.white.withValues(alpha: 0.45));
    final stalk = Paint()
      ..color = const Color(0xFF6B4A1F)
      ..strokeWidth = s.width * 0.07
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(c.dx, c.dy - r), Offset(c.dx + r * 0.1, c.dy - r * 1.3), stalk);
    final leaf = Path()
      ..moveTo(c.dx + r * 0.1, c.dy - r * 1.15)
      ..quadraticBezierTo(c.dx + r * 0.9, c.dy - r * 1.6, c.dx + r * 0.95, c.dy - r * 1.05)
      ..quadraticBezierTo(c.dx + r * 0.5, c.dy - r * 0.9, c.dx + r * 0.1, c.dy - r * 1.15);
    canvas.drawPath(leaf, Paint()..color = FoodLook.plateVeg);
  }

  @override
  bool shouldRepaint(_FruitPainter old) => old.colour != colour;
}

/// The look of a meal slot: its picture, colours and the time of day.
class SlotLook {
  final IconData icon;
  final IconData sky;
  final Color back;
  final Color fore;
  final String time;
  const SlotLook(this.icon, this.sky, this.back, this.fore, this.time);

  static SlotLook of(MealSlot s) => switch (s) {
    MealSlot.breakfast => const SlotLook(
      Icons.free_breakfast,
      Icons.wb_twilight,
      Color(0xFFFFF1D6),
      Color(0xFF9A5B00),
      'Morning',
    ),
    MealSlot.lunch => const SlotLook(Icons.lunch_dining, Icons.wb_sunny, Color(0xFFE2F2EC), AppTokens.brandDeep, 'Midday'),
    MealSlot.dinner => const SlotLook(
      Icons.dinner_dining,
      Icons.nightlight_round,
      Color(0xFFE5E8F6),
      Color(0xFF3A4A8C),
      'Evening',
    ),
    MealSlot.snack => const SlotLook(Icons.cookie, Icons.schedule, Color(0xFFF7E8EF), Color(0xFF8C3D6E), 'Between meals'),
  };
}

/// A meal slot's picture: the meal in a circle with the sun or moon of its time of day.
class SlotPicture extends StatelessWidget {
  final MealSlot slot;
  final double size;
  const SlotPicture(this.slot, {super.key, this.size = 52});

  @override
  Widget build(BuildContext context) {
    final l = SlotLook.of(slot);
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(color: l.back, borderRadius: BorderRadius.circular(size * 0.3)),
            alignment: Alignment.center,
            child: Icon(l.icon, color: l.fore, size: size * 0.52),
          ),
          Positioned(
            right: -size * 0.12,
            top: -size * 0.12,
            child: Container(
              width: size * 0.42,
              height: size * 0.42,
              decoration: BoxDecoration(
                color: AppTokens.surface,
                shape: BoxShape.circle,
                border: Border.all(color: l.back, width: 2),
              ),
              child: Icon(l.sky, size: size * 0.26, color: l.fore),
            ),
          ),
        ],
      ),
    );
  }
}

/// The Malaysian Healthy Plate (quarter, quarter, half): half vegetables and fruit, a quarter rice,
/// bread or noodles, a quarter protein, drawn as a plate. [highlight] (veg, staple, protein) brings
/// one part forward.
class HealthyPlatePicture extends StatelessWidget {
  final double size;
  final String? highlight;
  const HealthyPlatePicture({super.key, this.size = 120, this.highlight});

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Healthy plate: half vegetables and fruit, a quarter rice or bread, a quarter protein',
    child: CustomPaint(size: Size.square(size), painter: _PlatePainter(highlight)),
  );
}

class _PlatePainter extends CustomPainter {
  final String? highlight;
  _PlatePainter(this.highlight);

  @override
  void paint(Canvas canvas, Size s) {
    final c = s.center(Offset.zero);
    final r = s.width / 2;
    canvas.drawCircle(c.translate(0, r * 0.04), r, Paint()..color = Colors.black.withValues(alpha: 0.08));
    canvas.drawCircle(c, r, Paint()..color = AppTokens.surface);
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = AppTokens.cardBorder,
    );
    final inner = Rect.fromCircle(center: c, radius: r * 0.82);
    void part(double start, double sweep, Color colour, String key) {
      final dim = highlight != null && highlight != key;
      canvas.drawArc(inner, start, sweep, true, Paint()..color = colour.withValues(alpha: dim ? 0.35 : 0.9));
    }

    // Half on the left: vegetables and fruit. Top right: rice. Bottom right: protein.
    part(math.pi / 2, math.pi, FoodLook.plateVeg, 'veg');
    part(-math.pi / 2, math.pi / 2, FoodLook.plateStarch, 'staple');
    part(0, math.pi / 2, FoodLook.plateProtein, 'protein');
    final gap = Paint()
      ..color = AppTokens.surface
      ..strokeWidth = r * 0.05;
    canvas.drawLine(c.translate(0, -r * 0.82), c.translate(0, r * 0.82), gap);
    canvas.drawLine(c, c.translate(r * 0.82, 0), gap);
    void label(String text, Offset at) {
      final tp = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(color: Colors.white, fontSize: r * 0.16, fontWeight: FontWeight.w700),
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: r);
      tp.paint(canvas, at - Offset(tp.width / 2, tp.height / 2));
    }

    label('½\nveg', c.translate(-r * 0.42, 0));
    label('¼\nrice', c.translate(r * 0.4, -r * 0.38));
    label('¼\nprotein', c.translate(r * 0.4, r * 0.38));
  }

  @override
  bool shouldRepaint(_PlatePainter old) => old.highlight != highlight;
}
