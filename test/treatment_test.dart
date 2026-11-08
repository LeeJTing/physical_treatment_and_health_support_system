import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import 'package:physical_treatment_and_health_support_system/model/business_logic/recommendation_service/recommendation_service.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/ui_state.dart';
import 'package:physical_treatment_and_health_support_system/core/constants/app_constants.dart';
import 'package:physical_treatment_and_health_support_system/shared_client/api_client/api_client.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/pose_estimation_service/pose_estimation_service.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/exercise_session.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/patient_treatment_plan.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/treatment_plan.dart';
import 'package:physical_treatment_and_health_support_system/core/routes/routes.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/auth_repository/fake_auth_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/treatment_repository/fake_treatment_repository.dart';
import 'package:physical_treatment_and_health_support_system/view/treatment_view/treatment_view.dart';
import 'package:physical_treatment_and_health_support_system/view/treatment_view/posture_result_view.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/treatment_view_model/treatment_view_model.dart';

final String catalogueJson = File(
  'assets/seed/catalogue.json',
).readAsStringSync();

class FakeProbe implements VideoProbe {
  VideoInfo info = const VideoInfo(Duration(seconds: 15), 720, 1280);
  @override
  Future<VideoInfo> probe(File file) async => info;
}

/// Stand-in for /pose.
class FakePoseServer {
  double accuracy = 90;
  String? errorCode;
  String errorMessage = 'x';
  String? fallMessage; // set: the clip looked like a fall (safety_alert)
  int calls = 0;
  late final client = MockClient((req) async {
    calls++;
    if (errorCode != null) {
      return http.Response(
        jsonEncode({
          'error': {'code': errorCode, 'message': errorMessage},
        }),
        422,
      );
    }
    return http.Response(
      jsonEncode({
        'exercise_key': 'knee_extension',
        'accuracy': accuracy,
        'repetitions': 4,
        'hold_seconds': null,
        'feedback': [
          ?fallMessage,
          accuracy >= 80
              ? 'Good form. Keep it up!'
              : 'Hold the straight leg for 2 seconds before lowering it.',
        ],
        if (fallMessage != null)
          'safety_alert': {
            'type': 'possible_fall',
            'at_sec': 3.0,
            'message': fallMessage,
          },
        'mistakes': accuracy >= 80 ? {} : {'no_hold': 3},
        'full_body_visible': true,
        'visible_ratio': 0.97,
        'rep_details': [],
        'model_version': 'rules-1.0',
      }),
      200,
    );
  });
}

class Harness {
  final server = FakePoseServer();
  final probe = FakeProbe();
  final auth = FakeAuthRepository();
  final treatments = FakeTreatmentRepository.fromJson(catalogueJson);
  late final pose = PoseEstimationService(
    ApiClient(
      baseUrl: 'http://ai',
      tokenProvider: () => 'dev-token',
      httpClient: server.client,
    ),
    probe: probe,
  );
  late final vm = TreatmentViewModel(treatments, pose, auth);
  late final File clip;

  Future<void> setUp(Directory tmp) async {
    final account = (await auth.login(
      'demo@apths.test',
      'password123',
    )).dataOrNull!;
    final plan = (await treatments.getCatalogue()).dataOrNull!.firstWhere(
      (p) => p.planName == 'Early Knee Recovery',
    );
    await treatments.assignPlan(
      PatientTreatmentPlan(
        patientPlanId: 'pp1',
        accountId: account.accountId,
        plan: plan,
        selectedAt: DateTime.now(),
      ),
    );
    clip = File('${tmp.path}/clip.mp4')..writeAsBytesSync(List.filled(2048, 0));
    await vm.loadPlan();
  }

  Future<ExerciseSession?> recordFirst() async {
    await vm.startExercise(vm.pathway.first.item.exercise);
    return vm.submitVideo(clip, clipSeconds: 15);
  }
}

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('apths'));
  tearDown(() => tmp.deleteSync(recursive: true));

  group('pathway (FR300_01, FR300_02)', () {
    test('first exercise is current, the rest upcoming', () async {
      final h = Harness();
      await h.setUp(tmp);
      expect(h.vm.pathway.map((s) => s.status), [
        StageStatus.current,
        StageStatus.upcoming,
        StageStatus.upcoming,
      ]);
      expect(
        h.vm.pathway.first.item.exercise.exerciseName,
        'Seated Knee Extension',
      );
    });

    test('no plan gives an empty pathway', () async {
      final h = Harness();
      await h.auth.login('demo@apths.test', 'password123');
      await h.vm.loadPlan();
      expect(h.vm.activePlan, isNull);
      expect(h.vm.pathway, isEmpty);
    });
  });

  group('validateVideo (FR300_14 to FR300_16)', () {
    test('accepts a 15 s 720p MP4', () async {
      final h = Harness();
      await h.setUp(tmp);
      expect((await h.pose.validateVideo(h.clip)).ok, isTrue);
    });

    test('rejects the wrong format, length and resolution', () async {
      final h = Harness();
      await h.setUp(tmp);
      final avi = File('${tmp.path}/clip.avi')..writeAsBytesSync([0]);
      expect((await h.pose.validateVideo(avi)).message, Messages.videoInvalid);
      h.probe.info = const VideoInfo(Duration(seconds: 6), 720, 1280);
      expect(
        (await h.pose.validateVideo(h.clip)).message,
        Messages.videoInvalid,
      );
      h.probe.info = const VideoInfo(Duration(seconds: 45), 720, 1280);
      expect(
        (await h.pose.validateVideo(h.clip)).message,
        Messages.videoInvalid,
      );
      h.probe.info = const VideoInfo(Duration(seconds: 15), 480, 854);
      expect(
        (await h.pose.validateVideo(h.clip)).message,
        Messages.deviceCompatibility,
      );
    });

    test('an invalid clip is never uploaded', () async {
      final h = Harness();
      await h.setUp(tmp);
      h.probe.info = const VideoInfo(Duration(seconds: 5), 720, 1280);
      await h.recordFirst();
      expect(h.server.calls, 0);
      expect((h.vm.analysis as UiError).message, Messages.videoInvalid);
    });
  });

  group('several active plans', () {
    // Early Knee Recovery (pp1) at stage 2 and Disuse Atrophy Reconditioning
    // (pp2) at stage 1 share their current exercise.
    Future<Harness> twoPlans(Directory tmp, {double knee = 34}) async {
      final h = Harness();
      await h.setUp(tmp);
      final catalogue = (await h.treatments.getCatalogue()).dataOrNull!;
      PatientTreatmentPlan assign(String id, String name, double pct) =>
          PatientTreatmentPlan(
            patientPlanId: id,
            accountId: h.vm.activePlan!.accountId,
            plan: catalogue.firstWhere((p) => p.planName == name),
            progressPercentage: pct,
            selectedAt: DateTime.now(),
          );
      await h.treatments.assignPlan(assign('pp1', 'Early Knee Recovery', knee));
      await h.treatments.assignPlan(
        assign('pp2', 'Disuse Atrophy Reconditioning', 0),
      );
      await h.vm.loadPlan();
      h.vm.selectPlan('pp1');
      return h;
    }

    Future<void> recordCurrent(Harness h) async {
      await h.vm.startExercise(h.vm.activePlan!.currentExercise()!);
      await h.vm.submitVideo(h.clip, clipSeconds: 15);
    }

    test('both plans load and can be switched', () async {
      final h = await twoPlans(tmp);
      expect([for (final a in h.vm.plans) a.patientPlanId], ['pp1', 'pp2']);
      expect(h.vm.activePlan!.patientPlanId, 'pp1');
      h.vm.selectPlan('pp2');
      expect(h.vm.activePlan!.plan.planName, 'Disuse Atrophy Reconditioning');
    });

    test('a shared exercise done once counts for both plans', () async {
      final h = await twoPlans(tmp);
      final shared = h.vm.activePlan!.currentExercise()!.exerciseId;
      await recordCurrent(h); // 90 %: passes and is saved
      final byPlan = {for (final a in h.vm.plans) a.patientPlanId: a};
      expect(byPlan['pp1']!.completedStages, 2);
      expect(byPlan['pp2']!.completedStages, 1);
      expect(
        h.treatments.sessions
            .where((s) => s.exerciseId == shared)
            .map((s) => s.patientPlanId),
        unorderedEquals(['pp1', 'pp2']),
      );
      // Each plan has now had its exercise today.
      h.vm.selectPlan('pp2');
      expect(h.vm.doneToday, isTrue);
      expect(
        h.vm.canStart(h.vm.activePlan!.currentExercise()!.exerciseId),
        isFalse,
      );
    });

    test('one exercise per plan per day: the other plan is still open', () async {
      // Early Knee at stage 1: its exercise is not in Disuse Atrophy's first stage.
      final h = await twoPlans(tmp, knee: 0);
      await recordCurrent(h);
      expect(h.vm.doneToday, isTrue);
      h.vm.selectPlan('pp2');
      expect(h.vm.doneToday, isFalse);
      expect(
        h.vm.canStart(h.vm.activePlan!.currentExercise()!.exerciseId),
        isTrue,
      );
    });

    test('a possible fall in one plan is a rest day for every plan', () async {
      final h = await twoPlans(tmp, knee: 0);
      h.server.fallMessage =
          'Stop and rest: it looks like you may have lost your balance or fallen.';
      await recordCurrent(h);
      expect(h.vm.restDayToday, isTrue);
      expect(
        h.vm.canStart(h.vm.activePlan!.currentExercise()!.exerciseId),
        isFalse,
      );
      // Continue saves the attempt (with the fall message in its feedback).
      expect(await h.vm.acceptResult(), isTrue);
      h.vm.selectPlan('pp2');
      expect(
        h.vm.canStart(h.vm.activePlan!.currentExercise()!.exerciseId),
        isFalse,
      );
      // Also after the app restarts (a new view model, same data): the fall
      // is found in the saved feedback.
      final restarted = TreatmentViewModel(h.treatments, h.pose, h.auth);
      await restarted.loadPlan();
      expect(restarted.restDayToday, isTrue);
      expect(
        restarted.canStart(restarted.activePlan!.currentExercise()!.exerciseId),
        isFalse,
      );
    });

    test('stopping one plan keeps the other', () async {
      final h = await twoPlans(tmp);
      expect(await h.vm.endPlan(), isTrue);
      expect([for (final a in h.vm.plans) a.patientPlanId], ['pp2']);
      expect(h.vm.activePlan!.patientPlanId, 'pp2');
    });
  });

  group('one exercise per day', () {
    ExerciseSession at(DateTime t, {bool completed = true}) => ExerciseSession(
      sessionId: 's',
      accountId: 'a',
      exerciseId: 'e',
      completionStatus: completed
          ? CompletionStatus.completed
          : CompletionStatus.retried,
      completedAt: t,
    );

    test('the shared rule uses the local calendar date', () {
      final day = DateTime(2026, 10, 9);
      expect(
        ExerciseSession.anyCompletedOn([
          at(DateTime(2026, 10, 9, 23, 50)),
        ], day),
        isTrue,
      );
      expect(
        ExerciseSession.anyCompletedOn([
          at(DateTime(2026, 10, 8, 23, 50)),
        ], day),
        isFalse,
      );
      expect(
        ExerciseSession.anyCompletedOn([
          at(DateTime(2026, 10, 9, 8), completed: false),
        ], day),
        isFalse,
      );
      // Stored as UTC (Supabase): 9 Oct 17:00 UTC is 10 Oct 01:00 in Malaysia (UTC+8).
      final utc = DateTime.utc(2026, 10, 9, 17).toLocal();
      expect(
        ExerciseSession.anyCompletedOn([
          at(DateTime.utc(2026, 10, 9, 17)),
        ], DateTime(utc.year, utc.month, utc.day)),
        isTrue,
      );
    });

    test(
      'after a passing exercise today the next one is locked until tomorrow',
      () async {
        final h = Harness();
        await h.setUp(tmp);
        final first = h.vm.pathway.first.item.exerciseId;
        final second = h.vm.pathway[1].item.exerciseId;
        expect(h.vm.doneToday, isFalse);
        expect(h.vm.canStart(first), isTrue);
        await h.recordFirst(); // 90 %: passes and is saved as COMPLETED
        expect(h.vm.doneToday, isTrue);
        expect(h.vm.canStart(second), isFalse);
        expect(h.vm.canStart(first), isFalse); // passed, nothing to retry today
        h.vm.clock = () => DateTime.now().add(const Duration(days: 1));
        expect(h.vm.doneToday, isFalse);
        expect(h.vm.canStart(second), isTrue);
      },
    );

    test(
      'a failed exercise continued today can still be retried, the next one cannot',
      () async {
        final h = Harness();
        await h.setUp(tmp);
        final first = h.vm.pathway.first.item.exerciseId;
        final second = h.vm.pathway[1].item.exerciseId;
        h.server.accuracy = 60;
        await h.recordFirst();
        expect(h.vm.doneToday, isFalse); // nothing saved until Continue
        expect(await h.vm.acceptResult(), isTrue);
        expect(h.vm.doneToday, isTrue);
        expect(h.vm.canStart(first), isTrue);
        expect(h.vm.canStart(second), isFalse);
      },
    );
  });

  group('Exit and missing exercises (FR300_13, FR300_23)', () {
    test('Exit while the clip is checked: nothing is sent or saved', () async {
      final h = Harness();
      await h.setUp(tmp);
      await h.vm.startExercise(h.vm.pathway.first.item.exercise);
      final pending = h.vm.submitVideo(h.clip, clipSeconds: 15);
      h.vm.cancelExercise();
      expect(await pending, isNull);
      expect(h.server.calls, 0);
      expect(h.treatments.sessions, isEmpty);
      expect(h.vm.analysis, isA<Idle<PostureResult>>());
      expect(h.vm.current, isNull);
      expect(h.vm.activePlan!.completedStages, 0);
    });

    test('Exit after a failing result leaves it unsaved', () async {
      final h = Harness();
      await h.setUp(tmp);
      h.server.accuracy = 60;
      await h.recordFirst();
      h.vm.cancelExercise();
      expect(h.vm.lastResult, isNull);
      expect(h.treatments.sessions, isEmpty);
      expect(await h.vm.acceptResult(), isFalse); // nothing left to save
    });

    test(
      'a plan that comes without its exercises shows the FR300_23 message',
      () async {
        final h = Harness();
        final account = (await h.auth.login(
          'demo@apths.test',
          'password123',
        )).dataOrNull!;
        final p = (await h.treatments.getCatalogue()).dataOrNull!.first;
        await h.treatments.assignPlan(
          PatientTreatmentPlan(
            patientPlanId: 'pp-empty',
            accountId: account.accountId,
            plan: TreatmentPlan(
              planId: p.planId,
              planName: p.planName,
              aim: p.aim,
              targetBodyArea: p.targetBodyArea,
              recoveryStage: p.recoveryStage,
              mobilityLevel: p.mobilityLevel,
              frequencyPerWeek: p.frequencyPerWeek,
              goal: p.goal,
            ),
            selectedAt: DateTime.now(),
          ),
        );
        await h.vm.loadPlan();
        expect(
          (h.vm.plan as UiError<PatientTreatmentPlan?>).message,
          Messages.exerciseRetrieveFailed,
        );
      },
    );

    testWidgets('Exit on the result screen goes back to the home page', (
      tester,
    ) async {
      final h = Harness();
      h.server.accuracy = 70;
      await tester.runAsync(() async {
        await h.setUp(tmp);
        await h.recordFirst();
      });
      await tester.pumpWidget(
        MaterialApp(
          routes: {Routes.home: (_) => const Text('HOME PAGE')},
          home: ChangeNotifierProvider.value(
            value: h.vm,
            child: const PostureResultView(),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('Exit'));
      await tester.pumpAndSettle();
      expect(find.text('HOME PAGE'), findsOneWidget);
      expect(
        h.treatments.sessions,
        isEmpty,
      ); // the failing attempt was not kept
    });
  });

  group('posture result (FR300_09 to FR300_21)', () {
    test('80% or more saves the session and advances automatically', () async {
      final h = Harness();
      await h.setUp(tmp);
      final s = await h.recordFirst();
      expect(s!.postureAccuracy, 90);
      expect(h.vm.autoAdvanced, isTrue);
      expect(h.vm.activePlan!.completedStages, 1);
      expect(
        h.treatments.sessions.single.completionStatus,
        CompletionStatus.completed,
      );
      expect(
        await h.vm.acceptResult(),
        isTrue,
      ); // Continue afterwards does not save twice
      expect(h.treatments.sessions, hasLength(1));
      expect(h.vm.pathway.first.status, StageStatus.done);
      expect(h.vm.pathway[1].status, StageStatus.current);
    });

    test(
      'below 80%: Continue saves the try, the plan moves on only at the third (Elwin, 23 Oct)',
      () async {
        final h = Harness();
        await h.setUp(tmp);
        h.server.accuracy = 60;
        for (var t = 1; t <= 2; t++) {
          await h.recordFirst();
          expect(await h.vm.acceptResult(), isTrue);
          expect(h.vm.activePlan!.completedStages, 0, reason: 'try $t');
          expect(h.vm.lastMovedOn, isFalse);
          expect(h.vm.lastTriesBelowPass, t);
        }
        await h.recordFirst();
        expect(await h.vm.acceptResult(), isTrue);
        expect(h.vm.activePlan!.completedStages, 1); // third try: moves on
        expect(h.vm.lastMovedOn, isTrue);
        expect(h.treatments.sessions.map((s) => s.postureAccuracy), [
          60,
          60,
          60,
        ]);
      },
    );

    test(
      'below 80% then a pass: moves on at the pass, and the count starts again',
      () async {
        final h = Harness();
        await h.setUp(tmp);
        h.server.accuracy = 60;
        await h.recordFirst();
        await h.vm.acceptResult();
        h.server.accuracy = 90;
        await h.recordFirst(); // 80%+ saves and moves on by itself
        expect(h.vm.activePlan!.completedStages, 1);
        final first = h.treatments.sessions.first;
        expect(
          TreatmentViewModel.triesBelowPass([
            first,
            h.treatments.sessions.last,
          ], first),
          1,
        );
      },
    );

    test(
      'retry keeps the attempt as RETRIED without advancing (FR300_20)',
      () async {
        final h = Harness();
        await h.setUp(tmp);
        h.server.accuracy = 55;
        await h.recordFirst();
        await h.vm.retry();
        expect(
          h.treatments.sessions.single.completionStatus,
          CompletionStatus.retried,
        );
        expect(h.vm.activePlan!.completedStages, 0);
        expect(h.vm.pathway.first.status, StageStatus.attempted);
        expect(h.vm.pathway.first.bestAccuracy, 55);
      },
    );

    test('two failed tries in a row are counted for the rest hint', () async {
      final h = Harness();
      await h.setUp(tmp);
      h.server.accuracy = 50;
      await h.recordFirst();
      expect(h.vm.retriesInARow, 0);
      await h.vm.retry();
      await h.recordFirst();
      expect(h.vm.retriesInARow, 1);
      await h.vm.retry();
      await h.recordFirst();
      expect(h.vm.retriesInARow, 2);
    });

    test(
      'retries from an earlier visit do not count as in a row (audit, 23 Oct)',
      () async {
        final h = Harness();
        await h.setUp(tmp);
        h.server.accuracy = 50;
        for (var i = 0; i < 2; i++) {
          await h.recordFirst();
          await h.vm.retry();
        }
        // The next day the screen opens again and reads the stored attempts.
        final again = TreatmentViewModel(h.treatments, h.pose, h.auth);
        await again.loadPlan();
        await again.startExercise(again.pathway.first.item.exercise);
        await again.submitVideo(h.clip, clipSeconds: 15);
        expect(again.retriesInARow, 0); // not "try again tomorrow" at once
      },
    );

    test('server errors map to the UC500 messages', () async {
      for (final (code, message) in [
        ('full_body_not_visible', Messages.fullBodyNotVisible),
        ('pose_not_detected', Messages.poseDetectFailed),
        ('no_repetitions', Messages.postureAnalyseFailed),
        ('invalid_video', Messages.videoInvalid),
      ]) {
        final h = Harness();
        await h.setUp(tmp);
        h.server.errorCode = code;
        await h.recordFirst();
        expect((h.vm.analysis as UiError).message, message, reason: code);
      }
    });

    test(
      'a video of another exercise shows the server reason and saves nothing',
      () async {
        final h = Harness();
        await h.setUp(tmp);
        final progressBefore = h.vm.activePlan!.progressPercentage;
        const reason =
            'This video does not look like Seated Knee Extension (you stood up). '
            'Please check that you chose the right exercise and record it as '
            'shown in the steps.';
        h.server
          ..errorCode = 'wrong_exercise'
          ..errorMessage = reason;
        await h.recordFirst();
        expect((h.vm.analysis as UiError).message, reason);
        expect(h.treatments.sessions, isEmpty); // no attempt saved
        expect(h.vm.activePlan!.progressPercentage, progressBefore);
      },
    );

    test('a hand out of the picture shows the server reason', () async {
      final h = Harness();
      await h.setUp(tmp);
      const reason =
          'Your hand was not visible for most of the video. Keep your whole '
          'hand in the picture.';
      h.server
        ..errorCode = 'hand_not_visible'
        ..errorMessage = reason;
      await h.recordFirst();
      expect((h.vm.analysis as UiError).message, reason);
      expect(h.treatments.sessions, isEmpty);
    });

    test('stopping the plan', () async {
      final h = Harness();
      await h.setUp(tmp);
      expect(await h.vm.endPlan(), isTrue);
      expect(h.vm.activePlan, isNull);
    });
  });

  group('screens', () {
    testWidgets('pathway shows progress and Start exercise', (tester) async {
      final h = Harness();
      await tester.runAsync(() => h.setUp(tmp));
      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider.value(
            value: h.vm,
            child: const TreatmentView(),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('My treatment plan'), findsOneWidget);
      expect(find.text('0 of 3 done'), findsOneWidget);
      expect(find.text('Start exercise'), findsOneWidget);
      expect(find.text('Not started'), findsOneWidget);
      // Each number stays with its unit with large phone text (24 Oct: "10 reps · 1 / min").
      expect(find.textContaining('10 reps · 1.5 min'), findsWidgets);
    });

    testWidgets(
      'after today\'s exercise the pathway says the next one unlocks tomorrow',
      (tester) async {
        final h = Harness();
        await tester.runAsync(() async {
          await h.setUp(tmp);
          await h.recordFirst(); // passes and is saved
        });
        await tester.pumpWidget(
          MaterialApp(
            home: ChangeNotifierProvider.value(
              value: h.vm,
              child: const TreatmentView(),
            ),
          ),
        );
        await tester.pump();
        expect(find.text('1 of 3 done'), findsOneWidget);
        expect(
          find.text(TreatmentViewModel.nextUnlocksTomorrow),
          findsOneWidget,
        );
        expect(find.text('Start exercise'), findsNothing);
      },
    );

    testWidgets('result screen shows the score, guidance and both buttons', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 3600);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final h = Harness();
      h.server.accuracy = 70;
      await tester.runAsync(() async {
        await h.setUp(tmp);
        await h.recordFirst();
      });
      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider.value(
            value: h.vm,
            child: const PostureResultView(),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('70%'), findsOneWidget);
      expect(find.text('Needs improvement'), findsOneWidget);
      expect(find.text('Corrective guidance'), findsOneWidget);
      expect(find.textContaining('Hold the straight leg'), findsOneWidget);
      expect(find.text('Retry exercise'), findsOneWidget);
      expect(find.text('Continue'), findsOneWidget);
      expect(
        find.text('Rest for a minute before you try again.'),
        findsOneWidget,
      );
      // Below 80% (Elwin, 23 Oct): what Continue does is said before it is tapped.
      expect(find.byKey(const Key('below_pass_rule')), findsOneWidget);
    });

    testWidgets('a possible fall shows its message once and no retry', (
      tester,
    ) async {
      final h = Harness();
      h.server.accuracy = 40;
      h.server.fallMessage = 'Stop and rest: you may have fallen.';
      // Tall phone-width screen so the whole ListView is built: with the default 800x600
      // surface the banner pushes Continue below the fold and it is never built.
      tester.view.physicalSize = const Size(1080, 6000);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.runAsync(() async {
        await h.setUp(tmp);
        await h.recordFirst();
      });
      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider.value(
            value: h.vm,
            child: const PostureResultView(),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Stop and rest: you may have fallen.'), findsOneWidget);
      expect(find.text('Retry exercise'), findsNothing);
      expect(
        find.text('Rest now and try this exercise another day.'),
        findsOneWidget,
      );
      expect(find.text('Continue'), findsOneWidget);
    });

    // Older users are told to raise the phone's font size (chatbot text_size answer).
    testWidgets('result screen has no overflow with 2x phone text on 360x800', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3;
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      // A failing score with retry and rest hint, then a possible fall with the banner.
      for (final fall in [null, 'Stop and rest: you may have fallen.']) {
        final h = Harness();
        h.server.accuracy = 40;
        h.server.fallMessage = fall;
        await tester.runAsync(() async {
          await h.setUp(tmp);
          await h.recordFirst();
        });
        await tester.pumpWidget(
          MaterialApp(
            home: ChangeNotifierProvider.value(
              value: h.vm,
              child: const PostureResultView(),
            ),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        // Scroll to the end so every item of the ListView is built and laid out.
        await tester.scrollUntilVisible(find.text('Continue'), 300);
        await tester.pump();
        expect(tester.takeException(), isNull);
      }
    });
  });

  group('next plan (hybrid-3.0)', () {
    test(
      'moved on after three tries below 80%: gentler plans are offered (bug list #9)',
      () async {
        final h = Harness();
        await h.setUp(tmp);
        h.server.accuracy = 50;
        for (var t = 1; t <= 3; t++) {
          await h.vm.startExercise(h.vm.activePlan!.currentExercise()!);
          await h.vm.submitVideo(h.clip, clipSeconds: 15);
          await h.vm.acceptResult();
        }
        expect(h.vm.lastMovedOn, isTrue);
        expect(
          h.vm.activePlan!.currentExercise()!.exerciseName,
          'Seated Marching',
        );
        expect(h.vm.failsAtCurrent, 0);
        expect(
          h.vm.suggestEasier,
          isTrue,
        ); // was false: never offered on this path
        expect(h.vm.movedOnFromName, 'Seated Knee Extension');
        // The server is told which exercise failed, so it can ease and leave it out.
        final plan = h.vm.activePlan!;
        final json = RecommendationService.progressJson((
          plans: [plan],
          sessions: {plan.patientPlanId: h.vm.sessions},
        ));
        final sent = (json['plans'] as List).single as Map;
        expect(sent['consecutive_fails'], 3);
        expect(
          sent['current_exercise_id'],
          plan.plan.orderedExercises().first.exerciseId,
        );
      },
    );

    test('three tries that did not pass suggest gentler plans', () async {
      final h = Harness();
      await h.setUp(tmp);
      h.server.accuracy = 50;
      for (var i = 0; i < 2; i++) {
        await h.recordFirst();
        await h.vm.retry();
      }
      expect(h.vm.failsAtCurrent, 2);
      expect(h.vm.suggestEasier, isFalse);
      await h.recordFirst();
      await h.vm.retry();
      expect(h.vm.failsAtCurrent, 3);
      expect(h.vm.suggestEasier, isTrue);
      expect(h.vm.planComplete, isFalse);
    });

    test(
      'passing the last exercise completes the plan, which is remembered',
      () async {
        final h = Harness();
        await h.setUp(tmp);
        final first = h.vm.activePlan!;
        await h.treatments.assignPlan(
          PatientTreatmentPlan(
            patientPlanId: 'pp1',
            accountId: first.accountId,
            plan: first.plan,
            progressPercentage: 66.67,
            selectedAt: first.selectedAt,
          ),
        );
        await h.vm.loadPlan();
        final last = h.vm.activePlan!.currentExercise()!;
        expect(last.exerciseName, 'Heel Raise');
        await h.vm.startExercise(last);
        await h.vm.submitVideo(h.clip, clipSeconds: 15); // 90 %: saved
        expect(h.vm.planComplete, isTrue);
        expect(h.vm.suggestEasier, isFalse);
        await h.vm.loadPlan(); // a COMPLETED plan is no longer active
        expect(h.vm.activePlan, isNull);
        expect(h.vm.lastCompleted?.plan.planName, 'Early Knee Recovery');
      },
    );

    Future<Harness> pumpTreatment(
      WidgetTester tester,
      Future<void> Function(Harness h) arrange,
    ) async {
      final h = Harness();
      await tester.runAsync(() async {
        await h.setUp(tmp);
        await arrange(h);
      });
      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider.value(
            value: h.vm,
            child: const TreatmentView(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      return h;
    }

    testWidgets('a completed plan offers Find my next plan', (tester) async {
      await pumpTreatment(tester, (h) async {
        final p = h.vm.activePlan!;
        await h.treatments.assignPlan(
          PatientTreatmentPlan(
            patientPlanId: 'pp1',
            accountId: p.accountId,
            plan: p.plan,
            progressPercentage: 100,
            status: PlanStatus.completed,
            selectedAt: p.selectedAt,
          ),
        );
      });
      expect(
        find.textContaining('You completed Early Knee Recovery'),
        findsOneWidget,
      );
      expect(find.text('Find my next plan'), findsOneWidget);
      expect(find.text('Answer the questions again'), findsOneWidget);
    });

    testWidgets('three tries that did not pass offer gentler plans', (
      tester,
    ) async {
      await pumpTreatment(tester, (h) async {
        h.server.accuracy = 50;
        for (var i = 0; i < 3; i++) {
          await h.recordFirst();
          await h.vm.retry();
        }
      });
      expect(
        find.textContaining('Seated Knee Extension has not passed 3 times'),
        findsOneWidget,
      );
      expect(find.text('See gentler plans'), findsOneWidget);
    });
  });
}
