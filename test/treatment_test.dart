import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import 'package:physical_treatment_and_health_support_system/viewmodel/ui_state.dart';
import 'package:physical_treatment_and_health_support_system/core/constants/app_constants.dart';
import 'package:physical_treatment_and_health_support_system/shared_client/api_client/api_client.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/pose_estimation_service/pose_estimation_service.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/exercise_session.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/patient_treatment_plan.dart';
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
  String? fallMessage; // set: the clip looked like a fall (safety_alert)
  int calls = 0;
  late final client = MockClient((req) async {
    calls++;
    if (errorCode != null) {
      return http.Response(
        jsonEncode({
          'error': {'code': errorCode, 'message': 'x'},
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

    test('below 80% waits for Continue, then saves and advances', () async {
      final h = Harness();
      await h.setUp(tmp);
      h.server.accuracy = 60;
      await h.recordFirst();
      expect(h.vm.activePlan!.completedStages, 0);
      expect(h.treatments.sessions, isEmpty);
      expect(await h.vm.acceptResult(), isTrue);
      expect(h.vm.activePlan!.completedStages, 1);
      expect(h.treatments.sessions.single.postureAccuracy, 60);
    });

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
    });

    testWidgets('result screen shows the score, guidance and both buttons', (
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
  });
}
