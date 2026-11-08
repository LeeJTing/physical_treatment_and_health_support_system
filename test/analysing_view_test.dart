// AnalysingView (Posture Analyse Loading Page) on the fake /pose server: the steps while the
// clip is checked, the result screen on success, the error with Record again, and Exit asking
// first while checking. NFR_17 coverage (22 Oct).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:physical_treatment_and_health_support_system/core/constants/app_constants.dart';
import 'package:physical_treatment_and_health_support_system/core/routes/routes.dart';
import 'package:physical_treatment_and_health_support_system/view/treatment_view/analysing_view.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/ui_state.dart';

import 'treatment_test.dart' show Harness;

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('apths'));
  tearDown(() => tmp.deleteSync(recursive: true));

  Future<Harness> open(
    WidgetTester tester, {
    String? errorCode,
    double textScale = 1,
  }) async {
    tester.view.physicalSize = const Size(1080, 4800); // 360 dp wide
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final h = Harness();
    await tester.runAsync(() async {
      await h.setUp(tmp);
      await h.vm.startExercise(h.vm.pathway.first.item.exercise);
    });
    h.server.errorCode = errorCode;
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: h.vm,
        child: MaterialApp(
          navigatorKey: nav,
          builder: (c, child) => MediaQuery(
            data: MediaQuery.of(
              c,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          routes: {Routes.home: (_) => const Scaffold(body: Text('HOME'))},
          home: const Scaffold(body: Text('RECORDER')),
        ),
      ),
    );
    nav.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => ChangeNotifierProvider.value(
          value: h.vm,
          child: AnalysingView(file: h.clip, clipSeconds: 15),
        ),
      ),
    );
    await tester.pump(); // the route
    await tester.pump(); // the post-frame start
    await tester.pump(const Duration(milliseconds: 400)); // the page transition
    return h;
  }

  /// Lets the upload (real file reads, fake server) finish, then the screen catch up.
  Future<void> finishUpload(WidgetTester tester, Harness h) async {
    for (var i = 0; i < 20 && h.vm.analysis is Loading; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
  }

  testWidgets('the steps while checking, then the posture result', (
    tester,
  ) async {
    final h = await open(tester);
    expect(find.text('Analysing your posture'), findsOneWidget);
    expect(find.text('Video received'), findsOneWidget);
    expect(find.text('This usually takes a few seconds'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3)); // a step advances
    await finishUpload(tester, h);
    expect(h.vm.analysis, isA<UiSuccess>());
    expect(find.text('Posture result'), findsOneWidget);
    expect(find.text('90%'), findsOneWidget);
  });

  testWidgets('no repetitions found: the message and Record again', (
    tester,
  ) async {
    final h = await open(tester, errorCode: 'no_repetitions');
    await finishUpload(tester, h);
    expect(find.text(Messages.postureAnalyseFailed), findsOneWidget);
    expect(find.text('Video received'), findsNothing);
    await tester.tap(find.text('Record again'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('RECORDER'), findsOneWidget);
    expect(h.vm.analysis, isA<Idle>());
  });

  // The back arrow replaced Exit (Elwin, 9 Nov) and does what the phone's Back does.
  testWidgets('the back arrow asks first; Keep checking stays', (tester) async {
    final h = await open(tester);
    expect(find.text('Exit'), findsNothing);
    await tester.tap(find.byTooltip('Back'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.text('Stop checking this video? This attempt will not be saved.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Keep checking'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Analysing your posture'), findsOneWidget);
    await finishUpload(tester, h);
  });

  // The phone's Back (23 Oct) left silently while the clip was still checked, and it was saved.
  Future<void> back(WidgetTester tester) async {
    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets(
    'Back while checking asks; Stop returns to the recorder, nothing saved',
    (tester) async {
      final h = await open(tester);
      await back(tester);
      expect(
        find.text('Stop checking this video? This attempt will not be saved.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Keep checking'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Analysing your posture'), findsOneWidget);
      await back(tester);
      await tester.tap(find.text('Stop'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('RECORDER'), findsOneWidget);
      expect(h.vm.current, isNotNull); // still on the same exercise
      // The server's reply arrives after the patient left: dropped, not saved.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pump();
      expect(h.vm.analysis, isA<Idle>());
      expect(h.treatments.sessions, isEmpty);
    },
  );

  testWidgets('Back after an error is Record again', (tester) async {
    final h = await open(tester, errorCode: 'no_repetitions');
    await finishUpload(tester, h);
    await back(tester);
    expect(find.text('RECORDER'), findsOneWidget);
    expect(h.vm.analysis, isA<Idle>());
  });

  testWidgets('Back on a result that did not pass is Retry exercise', (
    tester,
  ) async {
    final h = await open(tester);
    h.server.accuracy = 50;
    await finishUpload(tester, h);
    expect(find.text('Posture result'), findsOneWidget);
    await back(tester);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('RECORDER'), findsOneWidget);
    expect(h.vm.analysis, isA<Idle>());
    expect(
      h.treatments.sessions.map((s) => s.completionStatus.db),
      contains('RETRIED'),
    );
  });

  testWidgets('the back arrow after an error goes back to the recorder', (
    tester,
  ) async {
    final h = await open(tester, errorCode: 'no_repetitions');
    await finishUpload(tester, h);
    await tester.tap(find.byTooltip('Back'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('RECORDER'), findsOneWidget);
    expect(h.vm.current, isNotNull); // still on the same exercise
  });

  // The step labels overflowed with large phone text (laptop test, 22 Oct): they now wrap.
  for (final scale in [1.5, 2.0]) {
    testWidgets('at ${scale}x text on 360 dp every step shows, no overflow', (
      tester,
    ) async {
      final h = await open(tester, textScale: scale);
      expect(tester.takeException(), isNull);
      for (final step in [
        'Video received',
        'Body landmarks extracted',
        'Analysing posture',
        'Calculating accuracy score',
      ]) {
        expect(find.text(step), findsOneWidget);
      }
      await finishUpload(tester, h);
    });
  }
}
