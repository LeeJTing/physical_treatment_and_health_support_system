// ProfileView (UC300) on the fakes: the first-time setup, the page behind each part's Edit,
// saving, the account settings and their confirmations. NFR_17 coverage (22 Oct); the rules
// themselves are in profile_view_model_test. Since 17 Nov each part of the profile has its own
// card, Edit and page, and a new patient is taken through the parts one step at a time.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:physical_treatment_and_health_support_system/core/constants/app_constants.dart';
import 'package:physical_treatment_and_health_support_system/core/routes/routes.dart';
import 'package:physical_treatment_and_health_support_system/core/utils/id_utils.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/risk_assessment_service/risk_assessment_service.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/health_profile.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/lookups.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/safety_limit.dart';
import 'package:physical_treatment_and_health_support_system/model/result.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/auth_repository/fake_auth_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/profile_repository/fake_profile_repository.dart';
import 'package:physical_treatment_and_health_support_system/view/profile_view/profile_view.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/auth_view_model/auth_view_model.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/profile_view_model/profile_view_model.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/test_mode_view_model/test_mode_view_model.dart';

Widget _stub(String name) => Scaffold(body: Text('route:$name'));

class _Setup {
  _Setup({FakeProfileRepository? profileRepo}) : profiles = profileRepo ?? FakeProfileRepository();
  final auth = FakeAuthRepository();
  final FakeProfileRepository profiles;
  final testMode = TestModeViewModel();
  late final vm = ProfileViewModel(
    profiles,
    auth,
    RiskAssessmentService(auth, profiles),
  );

  /// Signs in the demo patient; with [age] a complete profile is saved first.
  Future<void> prepare({
    int? age,
    List<HealthCondition> conditions = const [],
  }) async {
    final a = (await auth.login('demo@apths.test', 'password123')).dataOrNull!;
    if (age != null) {
      final p = HealthProfile(
        profileId: newId(),
        accountId: a.accountId,
        age: age,
        gender: Gender.female,
        weightKg: 62,
        heightCm: 160,
        conditions: conditions,
        updatedAt: DateTime.now(),
      );
      await profiles.saveProfile(p, p.generateSafetyLimit());
    }
  }

  Future<void> pump(WidgetTester tester, {String? route}) async {
    tester.view.physicalSize = const Size(1080, 7200);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.runAsync(vm.loadProfile);
    final app = MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: vm),
        ChangeNotifierProvider.value(value: testMode),
        ChangeNotifierProvider(create: (_) => AuthViewModel(auth, profiles)),
      ],
      child: MaterialApp(
        routes: {
          Routes.home: (_) => _stub('home'),
          Routes.loginScreen: (_) => _stub('login'),
          Routes.changePassword: (_) => _stub('change-password'),
          Routes.terms: (_) => _stub('terms'),
          Routes.refreshDietPlans: (_) => _stub('refresh-diet-plans'),
        },
        // Only the profile route: the default would stack '/' under it, so it could pop.
        initialRoute: route ?? '/profile-tab',
        onGenerateInitialRoutes: (name) => [
          MaterialPageRoute(
            settings: RouteSettings(name: name),
            builder: (_) => const ProfileView(),
          ),
        ],
      ),
    );
    await tester.pumpWidget(app);
    await tester.pump();
  }
}

class _FailProfileSave extends FakeProfileRepository {
  bool refuse = false;
  @override
  Future<Result<void>> saveProfile(HealthProfile p, SafetyLimit limit) async =>
      refuse ? const Failure('offline') : super.saveProfile(p, limit);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
}

Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
}

HealthCondition _condition(String code) =>
    LookupSeed.conditions.firstWhere((c) => c.conditionCode == code);

/// Next or Back of the first-time setup.
Future<void> _press(WidgetTester tester, String button) async {
  await tester.tap(find.text(button));
  await _settle(tester);
}

/// The Edit beside a part of the profile, by its key ('edit_body', 'edit_conditions', ...).
Future<void> _edit(WidgetTester tester, String key) async {
  await _tap(tester, find.byKey(Key(key)));
  await _settle(tester);
}

/// Step 1 of the first-time setup with values that are in order.
Future<void> _fillBody(
  WidgetTester tester, {
  String age = '45',
  String weight = '70.5',
  String height = '172',
  String gender = 'Male',
}) async {
  await tester.enterText(find.byType(TextFormField).at(0), age);
  await tester.enterText(find.byType(TextFormField).at(1), weight);
  await tester.enterText(find.byType(TextFormField).at(2), height);
  await tester.tap(find.text(gender));
  await tester.pump();
}

void main() {
  testWidgets(
    'an out-of-range age shows its whole message in the narrow box (emulator, 29 Oct)',
    (tester) async {
      final s = _Setup();
      await tester.runAsync(s.prepare);
      await s.pump(tester);
      // 600 wide: the test font's square letters make the message about twice as long as on a
      // phone, so this width gives the line count a 360-wide phone needs (more than three).
      tester.view.physicalSize = const Size(1800, 7200);
      tester.view.devicePixelRatio = 3;
      await tester.pump();
      await tester.enterText(find.byType(TextFormField).at(0), '5862158');
      await tester.pump();
      final error = find.text(Messages.valueOutOfRange);
      expect(error, findsOneWidget);
      final paragraph = tester.renderObject<RenderParagraph>(
        find.descendant(of: error, matching: find.byType(RichText)),
      );
      expect(paragraph.didExceedMaxLines, isFalse); // before: cut after three lines
    },
  );

  group('first-time setup, one part at a time (17 Nov)', () {
    testWidgets('a new patient goes through the four steps and saves the profile', (
      tester,
    ) async {
      final s = _Setup();
      await tester.runAsync(s.prepare);
      await s.pump(tester);
      expect(s.vm.isSetup, isTrue);
      expect(find.text('Step 1 of 4: Body details'), findsOneWidget);
      expect(find.text(Messages.profileNotConfigured), findsOneWidget);
      expect(find.text('Back'), findsNothing); // nothing before the first step
      await _fillBody(tester);
      expect(find.text('Body mass index'), findsOneWidget);
      await _press(tester, 'Next');

      expect(find.text('Step 2 of 4: Health conditions'), findsOneWidget);
      expect(s.vm.conditions.any((c) => c.isOther), isFalse);
      expect(find.text('Other condition (not listed)'), findsNothing);
      // Read in the order of the list: high blood pressure first, foot ulcer last.
      expect(
        tester.getTopLeft(find.text('Hypertension')).dy,
        lessThan(tester.getTopLeft(find.text('Foot ulcer or open wound on the foot')).dy),
      );
      await tester.tap(find.text('Hypertension'));
      await tester.pump();
      expect(find.text('Is it under control with treatment?'), findsOneWidget);
      expect(find.text('1 selected'), findsOneWidget);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Yes').first);
      await tester.pump();
      await _press(tester, 'Next');

      expect(find.text('Step 3 of 4: Physical limitations'), findsOneWidget);
      await tester.tap(find.text('Left Leg Mobility'));
      await tester.pump();
      await _press(tester, 'Next');

      expect(find.text('Step 4 of 4: Foods I cannot eat'), findsOneWidget);
      expect(s.vm.profile, isNull); // nothing is saved before the last step
      await _press(tester, 'Save');
      expect(find.text(Messages.profileSaved), findsOneWidget);
      expect(s.vm.isEditing, isFalse);
      expect(s.vm.profile!.age, 45);
      expect(s.vm.profile!.gender, Gender.male);
      expect(
        s.vm.profile!.conditions.map((c) => c.conditionCode),
        ['HYPERTENSION'],
      );
      // The profile screen: what was declared, and nothing else of the lists.
      expect(find.text('Account settings'), findsOneWidget);
      expect(find.text('Edit'), findsNWidgets(4)); // one for each part
      expect(find.text('Hypertension'), findsOneWidget);
      expect(find.text('Left Leg Mobility'), findsOneWidget);
      expect(find.text('Stroke'), findsNothing);
      expect(find.text('Balance Impairment'), findsNothing);
      expect(find.text('Pork'), findsNothing);
      expect(find.text('None declared'), findsOneWidget); // foods
    });

    testWidgets(
      'a refused Next says why just above the button, on a phone-sized screen (audit, 23 Oct)',
      (tester) async {
        final s = _Setup();
        await tester.runAsync(s.prepare);
        await s.pump(tester);
        tester.view.physicalSize = const Size(1080, 2400); // 360 x 800, a phone
        await tester.pump();
        await _fillBody(tester, age: '30', weight: '20', height: '200');
        await _press(tester, 'Next');
        final message = find.text(Messages.weightHeightMismatch);
        expect(message, findsOneWidget);
        expect(find.text('Step 1 of 4: Body details'), findsOneWidget); // not moved on
        final nextTop = tester.getTopLeft(find.text('Next')).dy;
        final messageBottom = tester.getBottomLeft(message).dy;
        expect(messageBottom, lessThan(nextTop)); // above the button
        expect(nextTop - messageBottom, lessThan(120)); // and next to it, not a list away
        expect(tester.getBottomLeft(find.text('Next')).dy, lessThanOrEqualTo(800));
      },
    );

    testWidgets('Next with an empty field shows the required-fields message', (
      tester,
    ) async {
      final s = _Setup();
      await tester.runAsync(s.prepare);
      await s.pump(tester);
      // ProfileModule_SaveHealthProfile_TC003: everything but the gender.
      await tester.enterText(find.byType(TextFormField).at(0), '62');
      await tester.enterText(find.byType(TextFormField).at(1), '70');
      await tester.enterText(find.byType(TextFormField).at(2), '170');
      await _press(tester, 'Next');
      expect(find.text(Messages.requiredFieldsEmpty), findsOneWidget);
      expect(find.text('Please choose one.'), findsOneWidget); // gender
      expect(find.text('Step 1 of 4: Body details'), findsOneWidget);
      // The entered values are kept and nothing is saved.
      expect(find.text('62'), findsOneWidget);
      expect(find.text('70'), findsOneWidget);
      expect(find.text('170'), findsOneWidget);
      expect(s.vm.profile, isNull);
    });

    testWidgets('a ticked condition must be answered before Next; Back keeps what was entered', (
      tester,
    ) async {
      final s = _Setup();
      await tester.runAsync(s.prepare);
      await s.pump(tester);
      await _fillBody(tester);
      await _press(tester, 'Next');
      await tester.tap(find.text('Asthma'));
      await tester.pump();
      await _press(tester, 'Next');
      expect(find.text(Messages.conditionQuestionUnanswered), findsOneWidget);
      expect(find.text('Step 2 of 4: Health conditions'), findsOneWidget);

      await _press(tester, 'Back');
      expect(find.text('Step 1 of 4: Body details'), findsOneWidget);
      expect(find.text(Messages.conditionQuestionUnanswered), findsNothing);
      expect(find.text('45'), findsOneWidget);
      expect(find.text('172'), findsOneWidget);
      await _press(tester, 'Next');
      expect(find.text('1 selected'), findsOneWidget); // asthma is still ticked
      await tester.tap(find.widgetWithText(ChoiceChip, 'No').first);
      await tester.pump();
      expect(find.text('New exercise plans wait until your doctor agrees.'), findsOneWidget);
      await _press(tester, 'Next');
      expect(find.text('Step 3 of 4: Physical limitations'), findsOneWidget);
    });

    testWidgets(
      'opened straight after sign-in: the note, then the last step goes to home',
      (tester) async {
        final s = _Setup();
        await tester.runAsync(s.prepare);
        await s.pump(tester, route: Routes.healthProfile);
        expect(find.text(Messages.profileNotConfigured), findsOneWidget);
        await _fillBody(tester, age: '30', weight: '70', height: '170', gender: 'Female');
        await _press(tester, 'Next');
        await _press(tester, 'Next');
        await _press(tester, 'Next');
        await _press(tester, 'Save');
        expect(find.text('route:home'), findsOneWidget);
        expect(s.vm.profile!.age, 30);
      },
    );
  });

  group('each part has its own Edit and page (17 Nov)', () {
    testWidgets('Edit, change, Cancel asks to discard', (tester) async {
      final s = _Setup();
      await tester.runAsync(() => s.prepare(age: 40));
      await s.pump(tester);
      expect(s.vm.isEditing, isFalse);
      expect(find.text('Account settings'), findsOneWidget);
      await _edit(tester, 'edit_body');
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Account settings'), findsNothing); // its own page
      await tester.enterText(find.byType(TextFormField).at(0), '41');
      await tester.tap(find.text('Cancel'));
      await _settle(tester);
      expect(find.text(Messages.discardChanges), findsOneWidget);
      await tester.tap(find.text('Cancel').last); // keep editing
      await _settle(tester);
      expect(s.vm.isEditing, isTrue);
      await tester.tap(find.text('Cancel'));
      await _settle(tester);
      await tester.tap(find.text('Discard'));
      await _settle(tester);
      expect(s.vm.isEditing, isFalse);
      expect(s.vm.profile!.age, 40);
      expect(find.text('Account settings'), findsOneWidget); // back on the profile
      expect(find.text(Messages.profileSaved), findsNothing);
    });

    testWidgets('the conditions page is searched; the card then shows only what was ticked', (
      tester,
    ) async {
      final s = _Setup();
      await tester.runAsync(() => s.prepare(age: 40));
      await s.pump(tester);
      expect(find.text('None declared'), findsNWidgets(2)); // conditions and foods
      await _edit(tester, 'edit_conditions');
      expect(find.text('None selected'), findsOneWidget);
      expect(find.text('Asthma'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('profile_search')), 'zzz');
      await tester.pump();
      expect(find.textContaining('Nothing matches "zzz"'), findsOneWidget);
      await tester.tap(find.byTooltip('Clear search'));
      await tester.pump();
      expect(find.text('Asthma'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('profile_search')), 'kidney');
      await tester.pump();
      expect(find.text('Chronic kidney disease'), findsOneWidget);
      expect(find.text('Asthma'), findsNothing);
      await tester.tap(find.text('Chronic kidney disease'));
      await tester.pump();
      expect(find.text("Is it stable under your doctor's care?"), findsOneWidget);
      await tester.tap(find.text('Save'));
      await _settle(tester);
      expect(find.text(Messages.conditionQuestionUnanswered), findsOneWidget);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Yes').first);
      await tester.pump();
      await tester.tap(find.text('Save'));
      await _settle(tester);
      await tester.tap(find.text('Not now')); // the diet plans
      await _settle(tester);

      expect(
        s.vm.profile!.conditions.map((c) => c.conditionCode),
        ['KIDNEY_DISEASE'],
      );
      expect(s.vm.profile!.age, 40); // the other parts are as they were
      expect(find.text('Chronic kidney disease'), findsOneWidget);
      expect(find.textContaining("Is it stable under your doctor's care?"), findsOneWidget);
      expect(find.text('Asthma'), findsNothing);
      expect(find.text('Risk level: Medium'), findsOneWidget);
    });

    testWidgets('the foods page is searched under its headings', (tester) async {
      final s = _Setup();
      await tester.runAsync(() => s.prepare(age: 40));
      await s.pump(tester);
      await _edit(tester, 'edit_foods');
      expect(find.text('Meat, fish and seafood'), findsOneWidget);
      expect(find.text('Vegetables, fruit and others'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('profile_search')), 'pork');
      await tester.pump();
      expect(find.text('Pork'), findsOneWidget);
      expect(find.text('Lard (pork fat)'), findsOneWidget);
      expect(find.text('Beef'), findsNothing);
      expect(find.text('Vegetables, fruit and others'), findsNothing);
      await tester.tap(find.text('Pork'));
      await tester.pump();
      expect(find.text('1 selected'), findsOneWidget);
      await tester.tap(find.text('Save'));
      await _settle(tester);
      await tester.tap(find.text('Not now'));
      await _settle(tester);
      expect(s.vm.profile!.restrictionCodes(), ['PORK']);
      expect(find.text('Pork'), findsOneWidget);
      expect(find.text('Lard (pork fat)'), findsNothing);
    });

    testWidgets('limitations: ticked ones are shown; None clears them', (tester) async {
      final s = _Setup();
      await tester.runAsync(() => s.prepare(age: 40));
      await s.pump(tester);
      await _edit(tester, 'edit_limitations');
      expect(find.byKey(const Key('profile_search')), findsNothing); // five choices: no search
      await tester.tap(find.text('Right Arm Mobility'));
      await tester.tap(find.text('Balance Impairment'));
      await tester.pump();
      await tester.tap(find.text('Save'));
      await _settle(tester);
      await tester.tap(find.text('Not now'));
      await _settle(tester);
      expect(find.text('Right Arm Mobility'), findsOneWidget);
      expect(find.text('Balance Impairment'), findsOneWidget);
      expect(find.text('Left Arm Mobility'), findsNothing);
      expect(find.text('Risk level: High'), findsOneWidget); // balance

      await _edit(tester, 'edit_limitations');
      await tester.tap(find.text('None'));
      await tester.pump();
      await tester.tap(find.text('Save'));
      await _settle(tester);
      await tester.tap(find.text('Not now'));
      await _settle(tester);
      expect(s.vm.profile!.limitations, isEmpty);
      expect(find.text('Right Arm Mobility'), findsNothing);
    });

    for (final update in [false, true]) {
      testWidgets('successful profile change asks before updating plans: ${update ? 'Update plans' : 'Not now'}', (tester) async {
        final s = _Setup();
        await tester.runAsync(() => s.prepare(age: 40));
        await s.pump(tester);
        tester.view.physicalSize = const Size(1080, 2400);
        await tester.pump();
        await _edit(tester, 'edit_body');
        await tester.enterText(find.byType(TextFormField).at(0), '41');
        await tester.tap(find.text('Save'));
        await _settle(tester);
        expect(s.vm.profile!.age, 41);
        expect(find.text('Update your diet plan?'), findsOneWidget);
        expect(find.text('route:refresh-diet-plans'), findsNothing);
        await tester.tap(find.text(update ? 'Update plans' : 'Not now'));
        await _settle(tester);
        expect(find.text('route:refresh-diet-plans'), update ? findsOneWidget : findsNothing);
        expect(find.text('Update your diet plan?'), findsNothing);
      });
    }

    testWidgets('an unchanged profile save does not ask to regenerate plans', (tester) async {
      final s = _Setup();
      await tester.runAsync(() => s.prepare(age: 40));
      await s.pump(tester);
      await _edit(tester, 'edit_body');
      await tester.tap(find.text('Save'));
      await _settle(tester);
      expect(find.text('Update your diet plan?'), findsNothing);
      expect(s.vm.isEditing, isFalse);
      expect(find.text('Account settings'), findsOneWidget);
    });

    testWidgets('a failed profile save keeps the draft and never asks to update plans', (tester) async {
      final profiles = _FailProfileSave();
      final s = _Setup(profileRepo: profiles);
      await tester.runAsync(() => s.prepare(age: 40));
      await s.pump(tester);
      profiles.refuse = true;
      await _edit(tester, 'edit_body');
      await tester.enterText(find.byType(TextFormField).at(0), '41');
      await tester.tap(find.text('Save'));
      await _settle(tester);
      expect(find.text('Update your diet plan?'), findsNothing);
      expect(find.text(Messages.profileSaveFailed), findsOneWidget);
      expect(s.vm.isEditing, isTrue);
      expect(s.vm.profile!.age, 40);
    });
  });

  group('Back never leaves an empty screen (emulator, 24 Oct)', () {
    testWidgets(
      'after sign-in, an untouched new profile: Back goes on to Home, no discard question',
      (tester) async {
        final s = _Setup();
        await tester.runAsync(s.prepare);
        await s.pump(tester, route: Routes.healthProfile);
        expect(s.vm.hasUnsavedChanges, isFalse); // before: true for the empty form
        await tester.binding.handlePopRoute();
        await _settle(tester);
        expect(find.text(Messages.discardChanges), findsNothing);
        expect(find.text('route:home'), findsOneWidget);
      },
    );

    testWidgets(
      'after sign-in, something typed: Discard goes on to Home (before: a black screen)',
      (tester) async {
        final s = _Setup();
        await tester.runAsync(s.prepare);
        await s.pump(tester, route: Routes.healthProfile);
        await tester.enterText(find.byType(TextFormField).at(0), '45');
        await tester.pump();
        await tester.binding.handlePopRoute();
        await _settle(tester);
        expect(find.text(Messages.discardChanges), findsOneWidget);
        await tester.tap(find.text('Discard'));
        await _settle(tester);
        expect(find.text('route:home'), findsOneWidget);
      },
    );

    testWidgets(
      'on a later step of the setup, the phone\'s Back shows the step before',
      (tester) async {
        final s = _Setup();
        await tester.runAsync(s.prepare);
        await s.pump(tester, route: Routes.healthProfile);
        await _fillBody(tester);
        await _press(tester, 'Next');
        await tester.binding.handlePopRoute();
        await _settle(tester);
        expect(find.text('Step 1 of 4: Body details'), findsOneWidget);
        expect(find.text(Messages.discardChanges), findsNothing);
        expect(find.text('route:home'), findsNothing);
      },
    );

    testWidgets(
      'a part\'s page with unsaved changes: Discard closes the page and stays on the profile',
      (tester) async {
        final s = _Setup();
        await tester.runAsync(() => s.prepare(age: 40));
        await s.pump(tester); // the shell's tab: the only screen beneath the page
        await _edit(tester, 'edit_body');
        await tester.enterText(find.byType(TextFormField).at(0), '41');
        await tester.pump();
        await tester.binding.handlePopRoute();
        await _settle(tester);
        await tester.tap(find.text('Discard'));
        await _settle(tester);
        expect(find.byType(ProfileView), findsOneWidget);
        expect(s.vm.isEditing, isFalse);
        expect(s.vm.profile!.age, 40);
        expect(find.text('Account settings'), findsOneWidget);
      },
    );
  });

  testWidgets('a high-risk profile shows the advisory right under the risk badge', (
    tester,
  ) async {
    final s = _Setup();
    await tester.runAsync(
      () => s.prepare(
        age: 70,
        conditions: [_condition('HEART_DISEASE'), _condition('HYPERTENSION')],
      ),
    );
    await s.pump(tester);
    expect(find.text(Messages.highRiskAdvisory), findsOneWidget);
    // Above the parts of the profile (17 Nov; it was below the food list).
    expect(
      tester.getTopLeft(find.text(Messages.highRiskAdvisory)).dy,
      lessThan(tester.getTopLeft(find.text('Body details')).dy),
    );
    // Only the declared conditions, not the whole list.
    expect(find.text('Heart Disease'), findsOneWidget);
    expect(find.text('Hypertension'), findsOneWidget);
    expect(find.text('Stroke'), findsNothing);
  });

  testWidgets('account settings: change password, device, testing mode', (
    tester,
  ) async {
    final s = _Setup();
    await tester.runAsync(() => s.prepare(age: 40));
    await s.pump(tester);
    await _tap(tester, find.text('Device connection'));
    await tester.pump();
    expect(find.textContaining('from Health Connect'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await _settle(tester);
    expect(find.text('Not connected'), findsOneWidget);
    expect(s.testMode.enabled, isFalse);
    await _tap(tester, find.byType(Switch));
    await tester.pump();
    expect(s.testMode.enabled, isTrue);
    await _tap(tester, find.text('Testing mode'));
    await tester.pump();
    expect(s.testMode.enabled, isFalse);
    // Leaving and deleting are the last two, below everything else (17 Nov).
    final logOut = tester.getTopLeft(find.text('Log out')).dy;
    expect(logOut, greaterThan(tester.getTopLeft(find.text('Testing mode')).dy));
    expect(logOut, greaterThan(tester.getTopLeft(find.text('AI server')).dy));
    expect(tester.getTopLeft(find.text('Delete my account')).dy, greaterThan(logOut));
    await _tap(tester, find.text('Change password'));
    await _settle(tester);
    expect(find.text('route:change-password'), findsOneWidget);
  });

  testWidgets('log out asks first; Cancel stays, Log out goes to login', (
    tester,
  ) async {
    final s = _Setup();
    await tester.runAsync(() => s.prepare(age: 40));
    await s.pump(tester);
    await _tap(tester, find.text('Log out'));
    await _settle(tester);
    expect(find.text(Messages.confirmLogout), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await _settle(tester);
    expect(find.text('route:login'), findsNothing);
    await _tap(tester, find.text('Log out'));
    await _settle(tester);
    await tester.tap(find.text('Log out').last);
    await _settle(tester);
    expect(find.text('route:login'), findsOneWidget);
  });

  testWidgets('delete my account: confirmed, then back to login', (
    tester,
  ) async {
    final s = _Setup();
    await tester.runAsync(() => s.prepare(age: 40));
    await s.pump(tester);
    await _tap(tester, find.text('Delete my account'));
    await _settle(tester);
    expect(find.text(Messages.confirmDeleteAccount), findsOneWidget);
    await tester.tap(find.text('Delete'));
    await _settle(tester);
    expect(find.text('route:login'), findsOneWidget);
    expect(find.text(Messages.accountDeleted), findsOneWidget);
  });

  testWidgets('the profile cannot load: the message and Try again', (
    tester,
  ) async {
    final s = _Setup();
    await tester.runAsync(s.prepare);
    s.profiles.failNext = true;
    await s.pump(tester);
    expect(find.text('Try again'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    await _settle(tester);
    expect(find.text('Try again'), findsNothing);
    expect(find.text('Step 1 of 4: Body details'), findsOneWidget);
  });
}
