// A plan card's name with large phone text (emulator at 2x, 24 Oct): "Balance and Fall Preventio / n"
// and "Disuse Atrophy Reconditi / oning" were split inside a word next to the match pill.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:physical_treatment_and_health_support_system/model/entity/treatment_plan.dart';
import 'package:physical_treatment_and_health_support_system/view/planning_view/widgets/plan_card.dart';

void main() {
  final plans = [
    for (final p
        in (jsonDecode(File('assets/seed/catalogue.json').readAsStringSync())
                as Map<String, dynamic>)['plans']
            as List)
      TreatmentPlan.fromJson(p as Map<String, dynamic>),
  ];

  testWidgets(
    'at 2x phone text the longest word of every plan name fits its line',
    (tester) async {
      // 600 wide: the test font's square letters make the match pill far wider than on a phone, so a
      // 360-wide card would leave the name almost no room; here long words still need shrinking.
      tester.view.physicalSize = const Size(1800, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      for (final plan in plans) {
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: const MediaQueryData(
                size: Size(600, 800),
                textScaler: TextScaler.linear(2),
              ),
              child: Scaffold(
                body: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: PlanCard(
                    plan: plan.withScore(0.66),
                    best: false,
                    busy: false,
                    onDetails: () {},
                    onSelect: () {},
                  ),
                ),
              ),
            ),
          ),
        );
        final finder = find.text(plan.planName);
        final rp = tester.renderObject<RenderParagraph>(
          find.descendant(of: finder, matching: find.byType(RichText)),
        );
        var start = 0;
        for (final word in plan.planName.split(' ')) {
          final boxes = rp.getBoxesForSelection(
            TextSelection(baseOffset: start, extentOffset: start + word.length),
          );
          final lines = {for (final b in boxes) b.top.round()};
          expect(
            lines,
            hasLength(1),
            reason: '${plan.planName}: "$word" is split',
          );
          start += word.length + 1;
        }
      }
    },
  );
}
