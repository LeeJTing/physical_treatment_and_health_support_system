// Text layout for older patients (9 Nov): no line ends with one word left alone on the next line,
// a number stays with its unit, and labels stay on one line so words line up side by side.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:physical_treatment_and_health_support_system/view/common/tidy_text.dart';
import 'package:physical_treatment_and_health_support_system/view/diet_view/widgets/plan_widgets.dart';

const nbsp = '\u00A0';

/// The words on the last line of [text] laid out [width] pixels wide.
String lastLine(String text, double width) {
  final p = TextPainter(
    text: TextSpan(text: text, style: const TextStyle(fontSize: 16)),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: width);
  final lines = p.computeLineMetrics();
  final start = p.getPositionForOffset(Offset(0, lines.last.baseline - 2)).offset;
  return text.substring(start).trim();
}

void main() {
  test('the last two words and a number with its unit are kept together', () {
    expect(tidy('Eat it to stay within your limits.'), 'Eat it to stay within your${nbsp}limits.');
    expect(tidy('Sodium: 1,200 of 2,000 mg.'), contains('2,000${nbsp}mg.'));
    expect(tidy('One sentence. Another short one here.'), 'One${nbsp}sentence. Another short one${nbsp}here.');
    expect(tidy('Two words'), 'Two words'); // too short to need it
    expect(keepGroups('250 g · 410 kcal · 600 mg sodium'), '250${nbsp}g · 410${nbsp}kcal · 600${nbsp}mg${nbsp}sodium');
  });

  test('wrapped at any width, a sentence never ends with one word alone', () {
    const s = 'Your plan has Brown rice, Tauhu goreng and Steamed vegetables. Eat it to stay within your limits.';
    // Tests draw every letter as a 16 px square, so a line must hold the longest pair of joined
    // words ("Steamed vegetables.", 19 letters = 304 px); a phone line holds far more.
    for (var w = 320.0; w <= 720; w += 7) {
      final last = lastLine(tidy(s), w);
      expect(last.contains(' ') || last.contains(nbsp), isTrue, reason: 'width $w: "$last"');
    }
  });

  testWidgets('labels and values stay on one line at twice the text size', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3; // 360 x 800
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        builder: (c, child) => MediaQuery(
          data: MediaQuery.of(c).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: const Scaffold(
          body: Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              children: [
                PlanBar(label: 'Free sugars', value: 21.5, limit: 25, unit: 'g', decimals: 1),
                OneLineText('Lunch · Midday · 1,250 kcal of about 630'),
              ],
            ),
          ),
        ),
      ),
    );
    for (final t in ['Free sugars', '21.5 of 25.0 g', 'Lunch · Midday · 1,250 kcal of about 630']) {
      final p = tester.renderObject<RenderParagraph>(find.descendant(of: find.text(t), matching: find.byType(RichText)));
      expect(p.didExceedMaxLines, isFalse, reason: t);
      final tops = p.getBoxesForSelection(TextSelection(baseOffset: 0, extentOffset: t.length)).map((b) => b.top).toSet();
      expect(tops, hasLength(1), reason: '$t is on one line');
    }
    expect(tester.takeException(), isNull);
  });
}
