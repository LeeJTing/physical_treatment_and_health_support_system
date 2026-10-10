// Guide animations (11 Oct): one looping repetition per exercise, made from our own correct
// recordings by training/build_guide_animations.py.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:physical_treatment_and_health_support_system/view/common/exercise_animation.dart';

void main() {
  final files = Directory('assets/guides')
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.json'))
      .toList();

  test('every catalogue exercise has an animation (Wrist Extension waits for clips)', () {
    final catalogue =
        jsonDecode(File('assets/seed/catalogue.json').readAsStringSync())
            as Map<String, dynamic>;
    final keys = {
      for (final e in catalogue['exercises'] as List)
        (e as Map<String, dynamic>)['pose_key'] as String?,
    }..remove(null);
    final have = {
      for (final f in files) f.uri.pathSegments.last.replaceAll('.json', ''),
    };
    expect(keys.difference(have), {'wrist_extension'});
  });

  test('each animation is a closed loop of points inside the unit box', () {
    for (final f in files) {
      final d = GuideAnimationData.fromJson(
        jsonDecode(f.readAsStringSync()) as Map<String, dynamic>,
      );
      expect(d.frames, hasLength(40), reason: f.path);
      expect(d.durationSec, greaterThan(0), reason: f.path);
      for (final fr in d.frames) {
        expect(fr, hasLength(d.names.length), reason: f.path);
        for (final p in fr) {
          expect(p.dx, inInclusiveRange(0, 1), reason: f.path);
          expect(p.dy, inInclusiveRange(0, 1), reason: f.path);
        }
      }
      for (final e in [...d.edges, ...d.fills]) {
        expect(e.every((k) => k >= 0 && k < d.names.length), isTrue);
      }
      if (!d.hold) {
        // Last frame back at the first: the loop does not jump.
        for (var k = 0; k < d.names.length; k++) {
          expect((d.frames.last[k] - d.frames.first[k]).distance, lessThan(0.02),
              reason: '${f.path} ${d.names[k]}');
        }
      }
    }
  });

  testWidgets('plays in a card; nothing is shown for an exercise without one', (tester) async {
    await tester.runAsync(() async {
      expect(await GuideAnimationData.load(rootBundle, 'sit_to_stand'), isNotNull);
      expect(await GuideAnimationData.load(rootBundle, 'no_such_exercise'), isNull);
    });
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              ExerciseAnimation(poseKey: 'sit_to_stand', cardHeight: 200),
              ExerciseAnimation(
                poseKey: 'no_such_exercise',
                cardHeight: 200,
                placeholder: Text('none'),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 900));
    expect(find.bySemanticsLabel('Animation showing how to do the exercise'), findsOneWidget);
    expect(find.text('none'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
