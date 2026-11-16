// The outlook on the posture result screen (Elwin, 10 Nov): pace, trend and finish date from the
// patient's own attempts; and the research behind each exercise.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:physical_treatment_and_health_support_system/core/constants/exercise_evidence.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/progress_projection/progress_projection.dart';

void main() {
  final now = DateTime(2026, 11, 10, 9);
  ScorePoint p(int daysAgo, double acc) =>
      (at: now.subtract(Duration(days: daysAgo)), accuracy: acc);

  group('ProgressProjection', () {
    test('first attempt: one try per exercise at the plan frequency', () {
      final r = ProgressProjection.compute(
        past: [p(0, 72)],
        completedExercises: 0,
        totalExercises: 3,
        sessionsPerWeek: 3,
        now: now,
      );
      expect(r.remainingExercises, 3);
      expect(r.triesPerExercise, 1);
      // 3 exercises x 1 try x 7/3 days = 7 days.
      expect(r.finishDate, now.add(const Duration(days: 7)));
      expect(r.projectedAtFinish, 72); // one point: no trend
      expect(r.reachesPassMark, isNull);
    });

    test(
      'pace counts the tries needed so far, at most the tries before moving on',
      () {
        final slow = ProgressProjection.compute(
          past: [p(6, 60), p(4, 70), p(2, 85)],
          completedExercises: 1,
          totalExercises: 4,
          sessionsPerWeek: 7,
          now: now,
        );
        expect(slow.triesPerExercise, 3); // 3 attempts for 1 exercise
        expect(
          slow.finishDate,
          now.add(const Duration(days: 9)),
        ); // 3 x 3 x 1 day
        final capped = ProgressProjection.compute(
          past: [for (var i = 0; i < 8; i++) p(8 - i, 50)],
          completedExercises: 1,
          totalExercises: 2,
          sessionsPerWeek: 7,
          now: now,
        );
        expect(
          capped.triesPerExercise,
          3,
        ); // the plan moves on after 3 tries anyway
      },
    );

    test(
      'a rising score is projected forward and reaches 80% before the finish',
      () {
        final r = ProgressProjection.compute(
          past: [p(4, 60), p(2, 70), p(0, 76)],
          completedExercises: 1,
          totalExercises: 5,
          sessionsPerWeek: 3,
          now: now,
        );
        expect(r.projectedAtFinish, greaterThan(76));
        expect(r.projectedAtFinish, lessThanOrEqualTo(100));
        expect(r.reachesPassMark, isNotNull);
        expect(r.reachesPassMark!.isAfter(now), isTrue);
        expect(r.reachesPassMark!.isAfter(r.finishDate), isFalse);
      },
    );

    test('the projection stays between 0 and 100', () {
      final up = ProgressProjection.compute(
        past: [p(2, 50), p(1, 80), p(0, 99)],
        completedExercises: 0,
        totalExercises: 10,
        sessionsPerWeek: 1,
        now: now,
      );
      expect(up.projectedAtFinish, 100);
      final down = ProgressProjection.compute(
        past: [p(2, 90), p(1, 50), p(0, 10)],
        completedExercises: 0,
        totalExercises: 10,
        sessionsPerWeek: 1,
        now: now,
      );
      expect(down.projectedAtFinish, 0);
      expect(down.reachesPassMark, isNull);
    });

    test('only the last five attempts set the trend', () {
      final r = ProgressProjection.compute(
        past: [
          p(10, 0),
          p(9, 0),
          p(4, 82),
          p(3, 82),
          p(2, 82),
          p(1, 82),
          p(0, 82),
        ],
        completedExercises: 3,
        totalExercises: 4,
        sessionsPerWeek: 3,
        now: now,
      );
      expect(
        r.projectedAtFinish,
        closeTo(82, 0.001),
      ); // flat, the early zeros ignored
    });

    test('a finished plan has nothing left', () {
      final r = ProgressProjection.compute(
        past: [p(0, 90)],
        completedExercises: 4,
        totalExercises: 4,
        sessionsPerWeek: 3,
        now: now,
      );
      expect(r.remainingExercises, 0);
      expect(r.finishDate, now);
    });
  });

  group('ExerciseEvidence', () {
    test(
      'every exercise of the catalogue has its research, each with a DOI link',
      () {
        final catalogue =
            jsonDecode(File('assets/seed/catalogue.json').readAsStringSync())
                as Map<String, dynamic>;
        final names = {
          for (final e in catalogue['exercises'] as List)
            (e as Map<String, dynamic>)['exercise_name'] as String,
        };
        expect(ExerciseEvidence.byExercise.keys.toSet(), names);
        for (final g in ExerciseEvidence.byExercise.values.toSet()) {
          expect(g.source.url, startsWith('https://doi.org/10.'));
          expect(g.finding, isNotEmpty);
          expect(g.source.citation, contains('('));
        }
        expect(ExerciseEvidence.forExercise('Unknown'), isNull);
        expect(ExerciseEvidence.forExercise(null), isNull);
      },
    );
  });
}
