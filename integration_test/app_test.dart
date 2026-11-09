// Chapter 5 functional test cases that stay inside the app, run on a device or emulator with the
// whole app (Flutter integration_test; 9 Nov). The cases that pass through Android's own screens
// (notification permission, gallery picker, exact-alarm setting) are Maestro flows in maestro/.
//
// Run on the Android 15 emulator with integration_test/run_android.sh, which also grants the
// notification permission (an Android dialog, tested by Maestro), with the AI server on the
// computer (DEV_AUTH_BYPASS for the test token) and the app on its in-memory test repositories:
//   bash integration_test/run_android.sh
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:physical_treatment_and_health_support_system/core/utils/body_regions.dart';
import 'package:physical_treatment_and_health_support_system/main.dart' as app;
import 'package:physical_treatment_and_health_support_system/view/planning_view/widgets/body_map.dart';

/// The guide animations and progress rings never settle, so wait for a widget instead.
Future<void> waitFor(
  WidgetTester t,
  Finder f, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await t.pump(const Duration(milliseconds: 200));
    if (f.evaluate().isNotEmpty) return;
  }
  throw TestFailure('Timed out waiting for $f. On screen: ${visibleTexts()}');
}

/// The texts on screen, for a failure message that says where the app was.
String visibleTexts() => find
    .byType(Text)
    .evaluate()
    .map(
      (e) =>
          (e.widget as Text).data ??
          (e.widget as Text).textSpan?.toPlainText() ??
          '',
    )
    .where((x) => x.trim().isNotEmpty)
    .take(25)
    .join(' | ');

Future<void> settle(WidgetTester t, [int ms = 800]) async {
  for (var i = 0; i < ms ~/ 100; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

/// Taps [f]: scrolls to it when it is further down a lazily built list, and takes the first
/// match a finger could reach when a label appears more than once.
Future<void> tap(WidgetTester t, Finder f) async {
  if (f.evaluate().isEmpty) await scrollTo(t, f);
  var target = f.hitTestable();
  if (target.evaluate().isEmpty) {
    await t.ensureVisible(f.first);
    await t.pump(const Duration(milliseconds: 300));
    target = f.hitTestable();
  }
  if (target.evaluate().isEmpty) {
    throw TestFailure('Cannot tap $f. On screen: ${visibleTexts()}');
  }
  await t.tap(target.first);
  await settle(t);
}

Future<void> tapText(WidgetTester t, String text) => tap(t, find.text(text));

Future<void> enter(WidgetTester t, Finder field, String text) async {
  if (field.evaluate().isEmpty) await scrollTo(t, field);
  await t.ensureVisible(field);
  // Tap the field first, as a person would: after a button press the field has lost focus and
  // typing would not reach it (UserModule_UserRegistration_TC004 kept sending the first code).
  await t.tap(field, warnIfMissed: false);
  await t.pump(const Duration(milliseconds: 300));
  await t.enterText(field, text);
  await settle(t, 300);
}

Finder fields() => find.byType(TextFormField);

/// Scrolls the screen's list until [f] is built and visible (long screens build lazily).
Future<void> scrollTo(WidgetTester t, Finder f) async {
  await t.scrollUntilVisible(
    f,
    400,
    scrollable: find.byType(Scrollable).first,
    maxScrolls: 60,
  );
  await settle(t, 300);
}

/// A debug-only Flutter warning from the Diet tab (Jun Ting's FoodTile: a tappable ListTile in a
/// coloured box hides its ripple). The Diet tab is built behind Home, so it would fail every test
/// here; it is logged instead and reported (PROJECT_STATE, 9 Nov). Nothing else is ignored.
const knownForeignWarning =
    'ListTile background color or ink splashes may be invisible';

/// Starts the app afresh (new in-memory test repositories) at the login screen.
Future<void> start(WidgetTester t) async {
  final report = FlutterError.onError;
  FlutterError.onError = (details) {
    if (details.toString().contains(knownForeignWarning)) {
      debugPrint('KNOWN WARNING (diet FoodTile): $knownForeignWarning');
      return;
    }
    report?.call(details);
  };
  addTearDown(() => FlutterError.onError = report);
  app.main();
  await waitFor(t, find.text('Welcome back'));
}

/// UserModule_UserRegistration_TC001 data: a new patient up to the code screen.
Future<void> register(
  WidgetTester t, {
  String email = 'maria@apths.test',
}) async {
  await tapText(t, 'Create account');
  await waitFor(t, find.text('Start your personalised recovery plan.'));
  await enter(t, fields().at(0), 'maria');
  await enter(t, fields().at(1), email);
  await enter(t, fields().at(2), 'abcd1234');
  await enter(t, fields().at(3), 'abcd1234');
  await tap(t, find.byKey(const Key('register_agree')));
  await tap(t, find.widgetWithText(FilledButton, 'Create account').last);
}

Future<void> verifyWith(WidgetTester t, String code) async {
  await enter(t, fields().first, code);
  await tapText(t, 'Verify');
}

/// The Terms at the first sign-in, as an adult.
Future<void> acceptTerms(WidgetTester t) async {
  await waitFor(t, find.text('Terms of Use and Privacy Notice'));
  await scrollTo(t, find.text('18 or older'));
  await tap(t, find.text('18 or older'));
  await scrollTo(t, find.byKey(const Key('agree_terms')));
  await tap(t, find.byKey(const Key('agree_terms')));
  await scrollTo(t, find.byKey(const Key('consent_health')));
  await tap(t, find.byKey(const Key('consent_health')));
  await scrollTo(t, find.text('Agree and continue'));
  await tapText(t, 'Agree and continue');
}

/// The ProfileModule_SaveHealthProfile_TC001 patient: 58, female, 62 kg, 158 cm, controlled high blood pressure.
Future<void> fillProfile(WidgetTester t, {String age = '58'}) async {
  await waitFor(
    t,
    find.text(
      'Please complete your health profile to receive personalised guidance.',
    ),
  );
  await enter(t, fields().at(0), age);
  await tap(t, find.text('Female'));
  await enter(t, fields().at(1), '62');
  await enter(t, fields().at(2), '158');
  await tap(t, find.text('Hypertension'));
  await tap(t, find.text('Yes'));
  await tapText(t, 'Save');
}

/// A signed-in patient with the ProfileModule_SaveHealthProfile_TC001 profile, on Home.
Future<void> patientOnHome(WidgetTester t) async {
  await start(t);
  await register(t);
  await waitFor(t, find.text('Enter your code'));
  await verifyWith(t, '123456');
  await acceptTerms(t);
  await fillProfile(t);
  await waitFor(t, find.textContaining('High risk'));
}

Future<void> openPlanning(WidgetTester t) async {
  await tapText(t, 'Treatment');
  await waitFor(t, find.text('AI-assisted treatment planning'));
  await tapText(t, 'AI-assisted treatment planning');
  await waitFor(t, find.text('Chat bot'));
}

/// PlanModule_RecommendPlans_TC001 answers: both knees, early stage, low mobility, move more freely.
/// Taps the centre of a body-map region. The regions are painted, so they are found by their
/// place on the canvas, as in test/body_map_test.dart.
Future<void> tapRegion(WidgetTester t, String id) async {
  final canvas = find.byKey(BodyMap.canvasKey);
  await waitFor(t, canvas);
  await t.ensureVisible(canvas);
  await t.pump(const Duration(milliseconds: 300));
  final layout = BodyMapLayout(t.getSize(canvas));
  await t.tapAt(
    t.getTopLeft(canvas) +
        layout.toScreen(BodyShapes.centreOf(BodyRegions.byId[id]!)),
  );
  await settle(t, 400);
}

Future<void> recommendKnees(WidgetTester t) async {
  await openPlanning(t);
  await tapText(t, 'Retrieve physical treatment');
  await waitFor(t, find.text('Which area needs rehabilitation?'));
  await tapRegion(t, 'front_right_knee');
  await tapRegion(t, 'front_left_knee');
  await waitFor(t, find.text('Right knee'));
  await waitFor(t, find.text('Left knee'));
  await tap(t, find.textContaining('Just started recovering'));
  await tap(t, find.textContaining('Need support to move'));
  await tap(t, find.text('Move more freely'));
  await tapText(t, 'Find my plans');
  await waitFor(t, find.text('Recommended plans'));
}

Future<void> askChat(WidgetTester t, String question) async {
  await enter(t, find.byType(TextField).last, question);
  await tap(t, find.byTooltip('Send'));
  await settle(t, 2500);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Registration and login', () {
    testWidgets(
      'UserModule_UserRegistration_TC001 sign up with valid details opens the code screen',
      (t) async {
        await start(t);
        await register(t);
        await waitFor(t, find.text('Enter your code'));
        expect(find.textContaining('maria@apths.test'), findsWidgets);
        expect(
          find.textContaining('Resend in'),
          findsOneWidget,
        ); // 60 s cooldown
      },
    );

    testWidgets(
      'UserModule_UserRegistration_TC002 a 7-character password breaks the rule',
      (t) async {
        await start(t);
        await tapText(t, 'Create account');
        await waitFor(t, find.text('Start your personalised recovery plan.'));
        await enter(t, fields().at(0), 'maria');
        await enter(t, fields().at(1), 'maria@apths.test');
        await enter(t, fields().at(2), 'abc1234');
        await enter(t, fields().at(3), 'abc1234');
        expect(
          find.text(
            'Password must be at least 8 characters and contain at least one letter and one number.',
          ),
          findsOneWidget,
        );
        final button = t.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Create account').last,
        );
        expect(button.onPressed, isNull); // stays disabled
      },
    );

    testWidgets(
      'UserModule_UserRegistration_TC003 a confirmation that does not match',
      (t) async {
        await start(t);
        await tapText(t, 'Create account');
        await waitFor(t, find.text('Start your personalised recovery plan.'));
        await enter(t, fields().at(2), 'abc1234');
        await enter(t, fields().at(3), 'abc1235');
        expect(
          find.text(
            'Confirm password does not match your password. Please check both fields.',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'UserModule_UserRegistration_TC004 five wrong codes invalidate the code; a new one works',
      (t) async {
        await start(t);
        await register(t);
        await waitFor(t, find.text('Enter your code'));
        for (final code in ['000000', '111111', '222222', '333333', '444444']) {
          await verifyWith(t, code);
        }
        await verifyWith(
          t,
          '123456',
        ); // the right code, but the code is dead now
        expect(
          find.text(
            'The verification code has expired. Please request a new code.',
          ),
          findsOneWidget,
        );
        // Resend appears once its 60-second cooldown is over (FR100_015).
        await waitFor(
          t,
          find.text('Resend code'),
          timeout: const Duration(seconds: 75),
        );
        await tapText(t, 'Resend code');
        await waitFor(t, find.text('A new code has been sent.'));
        await verifyWith(t, '123456');
        await waitFor(t, find.text('Terms of Use and Privacy Notice'));
      },
    );

    testWidgets('UserModule_UserLogin_TC001 log in with the right password', (
      t,
    ) async {
      await start(t);
      await enter(t, fields().at(0), 'demo@apths.test');
      await enter(t, fields().at(1), 'password123');
      await tapText(t, 'Log In');
      await acceptTerms(t);
      await waitFor(
        t,
        find.text(
          'Please complete your health profile to receive personalised guidance.',
        ),
      );
    });

    testWidgets('UserModule_UserLogin_TC002 a wrong password is refused', (
      t,
    ) async {
      await start(t);
      await enter(t, fields().at(0), 'demo@apths.test');
      await enter(t, fields().at(1), 'wrongpass1');
      await tapText(t, 'Log In');
      await waitFor(
        t,
        find.text('The email or password you entered is incorrect.'),
      );
      expect(find.text('Welcome back'), findsOneWidget);
    });
  });

  group('Health profile', () {
    testWidgets(
      'ProfileModule_SaveHealthProfile_TC001 a complete profile gives BMI 24.8, High risk and the advice',
      (t) async {
        await patientOnHome(t);
        await tapText(t, 'Profile');
        await waitFor(t, find.text('Risk level: High'));
        expect(find.text('24.8'), findsOneWidget);
        await t.scrollUntilVisible(
          find.textContaining('please consult a healthcare professional'),
          400,
          scrollable: find.byType(Scrollable).first,
        );
        expect(
          find.textContaining('please consult a healthcare professional'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'ProfileModule_SaveHealthProfile_TC002 age 12 is outside the range; values are kept',
      (t) async {
        await start(t);
        await register(t);
        await waitFor(t, find.text('Enter your code'));
        await verifyWith(t, '123456');
        await acceptTerms(t);
        await waitFor(
          t,
          find.text(
            'Please complete your health profile to receive personalised guidance.',
          ),
        );
        await enter(t, fields().at(0), '12');
        await tap(t, find.text('Female'));
        await enter(t, fields().at(1), '62');
        await enter(t, fields().at(2), '158');
        await tapText(t, 'Save');
        expect(
          find.text(
            'The value entered is outside the accepted range. Please check your entry.',
          ),
          findsWidgets,
        );
        expect(find.text('62'), findsOneWidget);
        expect(find.text('158'), findsOneWidget);
      },
    );

    testWidgets(
      'ProfileModule_EditHealthProfile_TC001 removing the condition makes the risk Low',
      (t) async {
        await patientOnHome(t);
        await tapText(t, 'Profile');
        await waitFor(t, find.text('Risk level: High'));
        await tapText(t, 'Edit');
        await tap(t, find.text('Hypertension'));
        await tapText(t, 'Save');
        // The risk level is at the top of the page; the condition chips are further down.
        await t.fling(
          find.byType(Scrollable).first,
          const Offset(0, 3000),
          3000,
        );
        await waitFor(t, find.text('Risk level: Low'));
      },
    );
  });

  group('Plan generation', () {
    testWidgets(
      'PlanModule_RecommendPlans_TC001 the questionnaire gives ranked plans within the limits',
      (t) async {
        await patientOnHome(t);
        await recommendKnees(t);
        expect(find.text('Early Knee Recovery'), findsOneWidget);
        expect(find.textContaining('% match'), findsWidgets);
        await tap(t, find.text('Why this plan').first);
        expect(
          find.textContaining('your limit: 20'),
          findsOneWidget,
        ); // High risk: 20 minutes
      },
    );

    testWidgets(
      'PlanModule_SelectPlan_TC001 selecting a plan saves it and makes its reminder',
      (t) async {
        await patientOnHome(t);
        await recommendKnees(t);
        await tap(t, find.text('Select').first);
        await waitFor(t, find.text('The Plan has been saved successfully.'));
        await tapText(t, 'Home');
        await tap(t, find.byTooltip('Reminders'));
        await waitFor(t, find.text('Time for Early Knee Recovery'));
        expect(find.text('9:00 AM'), findsOneWidget);
      },
    );
  });

  group('AI chat assistant', () {
    Future<void> chatWithPlan(WidgetTester t) async {
      await patientOnHome(t);
      await recommendKnees(t);
      await tap(t, find.text('Select').first);
      await waitFor(t, find.text('The Plan has been saved successfully.'));
      await openPlanning(t);
      await tapText(t, 'Chat bot');
      await waitFor(t, find.text('What is in my plan'));
    }

    testWidgets(
      'ChatModule_NoPlanQuestion_TC001 a plan question without a plan points to planning',
      (t) async {
        await patientOnHome(t);
        await openPlanning(t);
        await tapText(t, 'Chat bot');
        await waitFor(t, find.textContaining('Hello!'));
        await askChat(t, 'what is my plan');
        await waitFor(
          t,
          find.textContaining('You do not have a treatment plan yet'),
        );
        expect(find.text('Open treatment planning'), findsOneWidget);
      },
    );

    testWidgets(
      'ChatModule_AnswerQuestions_TC001 to TC003 and ChatModule_UrgentMessages_TC001 to TC002',
      (t) async {
        await chatWithPlan(t);
        // ChatModule_AnswerQuestions_TC001: the plan's topics
        expect(find.text('Progress and results'), findsOneWidget);
        // ChatModule_AnswerQuestions_TC002: a question with a spelling mistake
        await askChat(t, 'how many reps for seated knee extnsion');
        await waitFor(
          t,
          find.textContaining('In your plan this is exercise 1'),
        );
        expect(find.textContaining('high blood pressure'), findsWidgets);
        // ChatModule_UrgentMessages_TC001: an urgent symptom
        await askChat(t, 'I have chest pain when I exercise');
        await waitFor(t, find.textContaining('Stop exercising now.'));
        // ChatModule_UrgentMessages_TC002: a crisis message
        await askChat(t, 'i want to end it all');
        await waitFor(t, find.textContaining('Befrienders KL'));
        // ChatModule_AnswerQuestions_TC003: nonsense
        await askChat(t, 'asdf jkl qwerty');
        await waitFor(t, find.textContaining('Question not recognised'));
      },
    );
  });
}
