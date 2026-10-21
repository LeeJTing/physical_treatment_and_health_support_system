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

  Future<Harness> open(WidgetTester tester, {String? errorCode}) async {
    // 720 wide: the step labels have no Flexible and overflow 360 dp in the wide test font
    // (reported to the PC, 22 Oct; no behaviour change here).
    tester.view.physicalSize = const Size(2160, 4800);
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

  testWidgets('Exit while checking asks first; Keep going stays', (
    tester,
  ) async {
    final h = await open(tester);
    await tester.tap(find.text('Exit'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('Leave this exercise?'), findsOneWidget);
    await tester.tap(find.text('Keep going'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Analysing your posture'), findsOneWidget);
    await finishUpload(tester, h);
  });

  testWidgets('Exit after an error goes home without asking', (tester) async {
    final h = await open(tester, errorCode: 'no_repetitions');
    await finishUpload(tester, h);
    await tester.tap(find.text('Exit'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('HOME'), findsOneWidget);
    expect(h.vm.current, isNull);
  });
}
