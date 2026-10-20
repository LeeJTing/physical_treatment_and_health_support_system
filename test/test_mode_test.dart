// Testing mode (Elwin, 20 Oct): any exercise can be recorded and checked at once, without a plan,
// the one-exercise-per-day rule or a rest day, against the full movement targets, and nothing is saved.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:physical_treatment_and_health_support_system/model/entity/exercise_session.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/exercise.dart';
import 'package:physical_treatment_and_health_support_system/view/treatment_view/test_exercises_view.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/test_mode_view_model/test_mode_view_model.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/treatment_view_model/treatment_view_model.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/ui_state.dart';

import 'treatment_test.dart' show Harness;

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('apths'));
  tearDown(() => tmp.deleteSync(recursive: true));

  Future<Exercise> anyExercise(TreatmentViewModel vm, String poseKey) async {
    await vm.loadTestExercises();
    return (vm.testExercises as UiSuccess<List<Exercise>>).data.firstWhere(
      (e) => e.poseKey == poseKey,
    );
  }

  test('the switch is offered in debug builds and starts off', () {
    final tm = TestModeViewModel();
    expect(TestModeViewModel.available, isTrue); // tests run as a debug build
    expect(tm.enabled, isFalse);
    tm.setEnabled(true);
    expect(tm.enabled, isTrue);
  });

  test('every exercise of the catalogue is offered once, by name', () async {
    final h = Harness();
    await h.setUp(tmp);
    await h.vm.loadTestExercises();
    final all = (h.vm.testExercises as UiSuccess<List<Exercise>>).data;
    final catalogue =
        jsonDecode(File('assets/seed/catalogue.json').readAsStringSync())
            as Map<String, dynamic>;
    expect(all, hasLength((catalogue['exercises'] as List).length));
    expect(all.map((e) => e.exerciseId).toSet(), hasLength(all.length));
    final names = [for (final e in all) e.exerciseName];
    expect(names, [...names]..sort());
  });

  test('with no plan at all: analysed, shown, nothing saved', () async {
    final h = Harness();
    await h.setUp(tmp);
    await h.treatments.endPlan(h.vm.activePlan!);
    await h.vm.loadPlan();
    expect(h.vm.activePlan, isNull);
    h.vm.startTest(await anyExercise(h.vm, 'bird_dog'));
    expect(h.vm.testing, isTrue);
    expect(await h.vm.submitVideo(h.clip, clipSeconds: 15), isNull);
    expect(h.server.calls, 1);
    expect(h.vm.analysis, isA<UiSuccess<PostureResult>>());
    expect(h.treatments.sessions, isEmpty);
    expect(await h.vm.acceptResult(), isTrue); // "Continue": nothing to save
    expect(h.treatments.sessions, isEmpty);
  });

  test(
    'a passing test does not move the plan, even after today\'s exercise',
    () async {
      final h = Harness();
      await h.setUp(tmp);
      await h.recordFirst(); // today's real exercise: saved, the plan moves on
      final stages = h.vm.activePlan!.completedStages;
      final saved = h.treatments.sessions.length;
      expect(h.vm.doneToday, isTrue);
      h.vm.startTest(await anyExercise(h.vm, 'heel_raise'));
      await h.vm.submitVideo(h.clip, clipSeconds: 15);
      expect(h.vm.analysis, isA<UiSuccess<PostureResult>>());
      expect(h.vm.autoAdvanced, isFalse);
      expect(h.treatments.sessions, hasLength(saved));
      expect(h.vm.activePlan!.completedStages, stages);
    },
  );

  test(
    'a failing test and Retry save nothing; Exit ends testing mode',
    () async {
      final h = Harness();
      await h.setUp(tmp);
      h.server.accuracy = 40;
      h.vm.startTest(await anyExercise(h.vm, 'mini_squat'));
      await h.vm.submitVideo(h.clip, clipSeconds: 15);
      await h.vm.retry();
      expect(h.treatments.sessions, isEmpty);
      expect(h.vm.testing, isTrue); // still testing the same exercise
      h.vm.cancelExercise();
      expect(h.vm.testing, isFalse);
    },
  );

  testWidgets('the list screen: the notice and one row per exercise', (
    tester,
  ) async {
    final h = Harness();
    await tester.runAsync(() => h.setUp(tmp));
    await tester.runAsync(h.vm.loadTestExercises);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: h.vm,
        child: const MaterialApp(home: TestExercisesView()),
      ),
    );
    await tester.pump();
    expect(find.byKey(const Key('test_mode_notice')), findsOneWidget);
    expect(find.byKey(const Key('test_exercise_bird_dog')), findsOneWidget);
  });
}
