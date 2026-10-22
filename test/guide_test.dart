// The exercise guide (Elwin, 23 Oct): the hand-written coaching files agree with the AI server's
// own texts, every exercise gets a guide, the repetition is split into its parts, spoken cues
// follow the switch, and a first-time user is walked through it page by page.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:physical_treatment_and_health_support_system/device_platform/speech/speech_output.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/speech_service/speech_service.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/exercise.dart';
import 'package:physical_treatment_and_health_support_system/view/common/exercise_animation.dart';
import 'package:physical_treatment_and_health_support_system/view/common/exercise_coaching.dart';
import 'package:physical_treatment_and_health_support_system/view/treatment_view/guide/guide_view.dart';
import 'package:physical_treatment_and_health_support_system/view/treatment_view/treatment_view.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/guide_view_model/guide_view_model.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/ui_state.dart';

import 'treatment_test.dart' show Harness;

/// Records what would be said; [fail] makes the phone's speech engine throw.
class FakeSpeech implements SpeechOutput {
  final said = <String>[];
  bool fail = false;
  int stops = 0;

  @override
  Future<void> speak(String text) async {
    if (fail) throw Exception('no engine');
    said.add(text);
  }

  @override
  Future<void> stop() async => stops++;
}

Map<String, dynamic> _json(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

List<Exercise> _catalogue() => [
  for (final e in _json('assets/seed/catalogue.json')['exercises'] as List)
    Exercise.fromJson(e as Map<String, dynamic>),
];

void main() {
  final coachingFiles = Directory('assets/guides/coaching')
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.json'))
      .toList();

  group(
    'coaching files and the AI server (test/fixtures/server_guide_texts.json)',
    () {
      final server = _json('test/fixtures/server_guide_texts.json');

      test('the two pilot exercises have one', () {
        final keys = {
          for (final f in coachingFiles)
            f.uri.pathSegments.last.replaceAll('.json', ''),
        };
        expect(keys, containsAll(['sit_to_stand', 'wall_push_up']));
      });

      test(
        'each mistake quotes the server: its label, meaning and "do this" text',
        () {
          for (final f in coachingFiles) {
            final j = _json(f.path);
            final key = j['pose_key'] as String;
            expect(f.path, endsWith('$key.json'));
            final spec = server[key] as Map<String, dynamic>?;
            expect(spec, isNotNull, reason: '$key is not a server exercise');
            final mistakes = spec!['mistakes'] as Map<String, dynamic>;
            final c = ExerciseCoaching.fromJson(j);
            expect(c.mistakes, isNotEmpty, reason: key);
            for (final m in c.mistakes) {
              final s = mistakes[m.label] as Map<String, dynamic>?;
              expect(s, isNotNull, reason: '$key has no mistake ${m.label}');
              expect(m.right, s!['feedback'], reason: '$key ${m.label}');
              expect(m.wrong, s['meaning'], reason: '$key ${m.label}');
            }
          }
        },
      );

      test(
        'the camera side drawn in the set-up matches the server\'s view',
        () {
          for (final f in coachingFiles) {
            final key = _json(f.path)['pose_key'] as String;
            final guide = _json('assets/guides/$key.json');
            expect(
              guide['view'],
              (server[key] as Map<String, dynamic>)['view'],
              reason: key,
            );
          }
        },
      );

      test(
        'focus, arc and arrow points exist in the animation; steps use known parts',
        () {
          for (final f in coachingFiles) {
            final j = _json(f.path);
            final key = j['pose_key'] as String;
            final d = GuideAnimationData.fromJson(
              _json('assets/guides/$key.json'),
            );
            final c = ExerciseCoaching.fromJson(j);
            for (final n in [c.focusJoint, c.focusFrom, c.focusTo, c.mover]) {
              expect(d.index(n), isNotNull, reason: '$key $n');
            }
            const parts = {'start', 'go', 'top', 'back'};
            expect(parts.containsAll(c.captions.keys), isTrue, reason: key);
            expect(
              c.steps.every((s) => s.phase == null || parts.contains(s.phase)),
              isTrue,
              reason: key,
            );
            expect(c.steps, isNotEmpty);
            expect(c.safety, isNotEmpty);
          }
        },
      );
    },
  );

  test('every catalogue exercise gets steps from its instruction text', () {
    for (final e in _catalogue()) {
      final c = ExerciseCoaching.fromInstruction(e);
      expect(c.steps, isNotEmpty, reason: e.exerciseName);
      expect(c.tailored, isFalse);
      for (final s in [...c.steps.map((s) => s.text), ...c.safety]) {
        expect(s, isNot(contains('Camera:')), reason: e.exerciseName);
        expect(s, isNot(contains('Safety:')), reason: e.exerciseName);
        expect(s[0], s[0].toUpperCase(), reason: s);
        expect(s, endsWith('.'), reason: s);
      }
    }
    final sts = _catalogue().firstWhere((e) => e.poseKey == 'sit_to_stand');
    final c = ExerciseCoaching.fromInstruction(sts);
    expect(c.steps.first.text, startsWith('Sit on a firm chair'));
    expect(c.safety, [
      'Keep a stable chair against a wall.',
      'Stop if you feel dizzy or knee pain.',
    ]);
  });

  test('a repetition is split into start, go, top and back, in that order', () {
    for (final key in ['sit_to_stand', 'wall_push_up']) {
      final d = GuideAnimationData.fromJson(_json('assets/guides/$key.json'));
      final p = d.phases;
      expect(p.first, 'start', reason: key);
      expect(p.last, 'back', reason: key);
      final order = <String>[];
      for (final x in p) {
        if (order.isEmpty || order.last != x) order.add(x);
      }
      expect(order, ['start', 'go', 'top', 'back'], reason: key);
      for (final part in ['start', 'go', 'top', 'back']) {
        expect(p[d.keyFrame(part)], part, reason: '$key $part');
      }
    }
    // Sit-to-Stand: the top is standing, the hip higher (smaller y) than at the start.
    final d = GuideAnimationData.fromJson(
      _json('assets/guides/sit_to_stand.json'),
    );
    final hip = d.index('hip')!;
    expect(
      d.frames[d.keyFrame('top')][hip].dy,
      lessThan(d.frames[0][hip].dy - 0.05),
    );
  });

  group('spoken cues', () {
    test(
      'said only while switched on; a phone without speech stays quiet',
      () async {
        final speech = FakeSpeech();
        final vm = GuideViewModel(SpeechService(speech));
        expect(vm.speechOn, isTrue);
        await vm.say('Stand up.');
        vm.setSpeechOn(false);
        await vm.say('Sit down slowly.');
        expect(speech.said, ['Stand up.']);
        expect(speech.stops, 1); // switching off cuts it short
        vm.setSpeechOn(true);
        speech.fail = true;
        await vm.say('Push back.'); // no exception
        final r = await SpeechService(speech).say('x');
        expect(r.isSuccess, isFalse);
      },
    );
  });

  group('the guide on screen', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('apths'));
    tearDown(() => tmp.deleteSync(recursive: true));

    Future<(Harness, FakeSpeech)> open(WidgetTester tester, String key) async {
      tester.view.physicalSize = const Size(1080, 4000);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final h = Harness();
      final speech = FakeSpeech();
      await tester.runAsync(() async {
        await h.setUp(tmp);
        await h.vm.loadTestExercises();
        final e = (h.vm.testExercises as UiSuccess<List<Exercise>>).data
            .firstWhere((e) => e.poseKey == key);
        h.vm.startTest(e);
        await ExerciseCoaching.forExercise(rootBundle, e);
        await GuideAnimationData.load(rootBundle, key);
      });
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: h.vm),
            ChangeNotifierProvider(
              create: (_) => GuideViewModel(SpeechService(speech)),
            ),
          ],
          child: const MaterialApp(home: GuideView(reps: 10)),
        ),
      );
      for (var i = 0; i < 4; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
      return (h, speech);
    }

    Future<void> next(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('guide_next')));
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 150));
      }
    }

    testWidgets('Sit-to-Stand: watch, four steps, safety, phone set-up', (
      tester,
    ) async {
      final (_, speech) = await open(tester, 'sit_to_stand');
      expect(find.text('Watch how it is done'), findsOneWidget);
      expect(find.byKey(const Key('guide_caption')), findsOneWidget);
      expect(speech.said.last, startsWith('Watch how to do Sit-to-Stand'));
      for (var i = 1; i <= 4; i++) {
        await next(tester);
        expect(find.text('Step $i of 4'), findsOneWidget);
      }
      expect(find.textContaining('Reach back for the chair'), findsOneWidget);
      expect(speech.said.last, startsWith('Step 4.'));
      await next(tester);
      expect(find.text('Stay safe'), findsOneWidget);
      expect(find.text('Common mistakes'), findsOneWidget);
      expect(
        find.textContaining('Do this: Sit down slowly: reach back'),
        findsOneWidget,
      );
      await next(tester);
      expect(find.text('Set up your phone'), findsOneWidget);
      expect(find.textContaining('side-on to the phone'), findsWidgets);
      expect(find.textContaining('you have 10 seconds'), findsOneWidget);
      expect(find.text('Open the camera'), findsOneWidget);
      // Back returns a page.
      await tester.tap(find.text('Back'));
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 150));
      }
      expect(find.text('Stay safe'), findsOneWidget);
    });

    testWidgets('the speaker button turns spoken cues off', (tester) async {
      final (_, speech) = await open(tester, 'wall_push_up');
      final before = speech.said.length;
      await tester.tap(find.byKey(const Key('speech_toggle')));
      await tester.pump();
      expect(find.byTooltip('Turn spoken cues on'), findsOneWidget);
      await next(tester);
      expect(find.text('Step 1 of 4'), findsOneWidget);
      expect(speech.said.length, before); // nothing more said
    });

    testWidgets('an exercise without a written guide still gets one', (
      tester,
    ) async {
      await open(tester, 'heel_raise');
      expect(find.text('Watch how it is done'), findsOneWidget);
      await next(tester);
      expect(find.textContaining('Step 1 of'), findsOneWidget);
    });
  });

  testWidgets('the loop reports each part and counts repetitions', (
    tester,
  ) async {
    late ExerciseCoaching c;
    await tester.runAsync(() async {
      c = (await ExerciseCoaching.load(rootBundle, 'sit_to_stand'))!;
      await GuideAnimationData.load(rootBundle, 'sit_to_stand');
    });
    final seen = <(String, int)>[];
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          height: 300,
          child: ExerciseAnimation(
            poseKey: 'sit_to_stand',
            coaching: c,
            showCaption: true,
            onPhase: (p, r) => seen.add((p, r)),
          ),
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    for (var i = 0; i < 70; i++) {
      await tester.pump(const Duration(milliseconds: 100)); // 7 s: two loops
    }
    final parts = [for (final s in seen) s.$1];
    expect(parts.take(4), ['start', 'go', 'top', 'back']);
    expect(seen.map((s) => s.$2).toSet(), containsAll([1, 2]));
    expect(find.byKey(const Key('guide_caption')), findsOneWidget);
  });

  testWidgets('the exercise sheet lists numbered steps and safety points', (
    tester,
  ) async {
    final tmp = Directory.systemTemp.createTempSync('apths');
    addTearDown(() => tmp.deleteSync(recursive: true));
    tester.view.physicalSize = const Size(1080, 4800);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final h = Harness();
    await tester.runAsync(() => h.setUp(tmp));
    final pe = h.vm.activePlan!.plan.orderedExercises().first;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (ctx) => TextButton(
            onPressed: () => showExerciseDetails(ctx, pe),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(find.text('How to do it'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('Stay safe'), findsOneWidget);
  });
}
