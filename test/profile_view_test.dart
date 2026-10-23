// ProfileView (UC300) on the fakes: the edit form, saving, the account settings and their
// confirmations. NFR_17 coverage (22 Oct); the rules themselves are in profile_view_model_test.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:physical_treatment_and_health_support_system/core/constants/app_constants.dart';
import 'package:physical_treatment_and_health_support_system/core/routes/routes.dart';
import 'package:physical_treatment_and_health_support_system/core/utils/id_utils.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/risk_assessment_service/risk_assessment_service.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/health_profile.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/lookups.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/auth_repository/fake_auth_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/profile_repository/fake_profile_repository.dart';
import 'package:physical_treatment_and_health_support_system/view/profile_view/profile_view.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/auth_view_model/auth_view_model.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/profile_view_model/profile_view_model.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/test_mode_view_model/test_mode_view_model.dart';

Widget _stub(String name) => Scaffold(body: Text('route:$name'));

class _Setup {
  final auth = FakeAuthRepository();
  final profiles = FakeProfileRepository();
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

void main() {
  testWidgets('a new patient fills the form and saves the profile', (
    tester,
  ) async {
    final s = _Setup();
    await tester.runAsync(s.prepare);
    await s.pump(tester);
    expect(s.vm.isEditing, isTrue);
    expect(find.text('Save'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).at(0), '45');
    await tester.enterText(find.byType(TextFormField).at(1), '70.5');
    await tester.enterText(find.byType(TextFormField).at(2), '172');
    await tester.tap(find.text('Male'));
    await tester.pump();
    expect(find.text('Body mass index'), findsOneWidget);
    await tester.tap(find.text('Hypertension'));
    await tester.pump();
    expect(find.text('Is it under control with treatment?'), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Yes').first);
    await tester.pump();
    await tester.tap(find.text('Left Leg Mobility'));
    await tester.pump();
    await tester.tap(find.text('Save'));
    await _settle(tester);
    expect(find.text(Messages.profileSaved), findsOneWidget);
    expect(s.vm.isEditing, isFalse);
    expect(s.vm.profile!.age, 45);
    expect(s.vm.profile!.gender, Gender.male);
    expect(
      s.vm.profile!.conditions.map((c) => c.conditionCode),
      contains('HYPERTENSION'),
    );
    expect(find.text('Account settings'), findsOneWidget);
    expect(find.text('Edit'), findsOneWidget);
  });

  testWidgets(
    'a refused Save says why just above Save, on a phone-sized screen (audit, 23 Oct)',
    (tester) async {
      final s = _Setup();
      await tester.runAsync(s.prepare);
      await s.pump(tester);
      tester.view.physicalSize = const Size(1080, 2400); // 360 x 800, a phone
      await tester.pump();
      await tester.enterText(find.byType(TextFormField).at(0), '30');
      await tester.enterText(find.byType(TextFormField).at(1), '20');
      await tester.enterText(find.byType(TextFormField).at(2), '200');
      await tester.tap(find.text('Male'));
      await tester.pump();
      await tester.tap(find.text('Save'));
      await _settle(tester);
      final message = find.text(Messages.weightHeightMismatch);
      expect(message, findsOneWidget);
      final saveTop = tester.getTopLeft(find.text('Save')).dy;
      final messageBottom = tester.getBottomLeft(message).dy;
      expect(messageBottom, lessThan(saveTop)); // above the button
      expect(saveTop - messageBottom, lessThan(120)); // and next to it, not a list away
      expect(tester.getBottomLeft(find.text('Save')).dy, lessThanOrEqualTo(800));
    },
  );

  testWidgets('saving with an empty field shows the required-fields message', (
    tester,
  ) async {
    final s = _Setup();
    await tester.runAsync(s.prepare);
    await s.pump(tester);
    await tester.enterText(find.byType(TextFormField).at(0), '45');
    await tester.tap(find.text('Save'));
    await _settle(tester);
    expect(find.text(Messages.requiredFieldsEmpty), findsOneWidget);
    expect(find.text('Please choose one.'), findsOneWidget); // gender
    expect(s.vm.isEditing, isTrue);
  });

  testWidgets(
    'opened straight after sign-in: the note, then Save goes to home',
    (tester) async {
      final s = _Setup();
      await tester.runAsync(s.prepare);
      await s.pump(tester, route: Routes.healthProfile);
      expect(find.text(Messages.profileNotConfigured), findsOneWidget);
      await tester.enterText(find.byType(TextFormField).at(0), '30');
      await tester.enterText(find.byType(TextFormField).at(1), '70');
      await tester.enterText(find.byType(TextFormField).at(2), '170');
      await tester.tap(find.text('Female'));
      await tester.pump();
      await tester.tap(find.text('Save'));
      await _settle(tester);
      expect(find.text('route:home'), findsOneWidget);
    },
  );

  testWidgets('an existing profile: Edit, change, Cancel asks to discard', (
    tester,
  ) async {
    final s = _Setup();
    await tester.runAsync(() => s.prepare(age: 40));
    await s.pump(tester);
    expect(s.vm.isEditing, isFalse);
    expect(find.text('Account settings'), findsOneWidget);
    await tester.tap(find.text('Edit'));
    await tester.pump();
    expect(find.text('Cancel'), findsOneWidget);
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
  });

  testWidgets('a high-risk profile shows the advisory and the risk badge', (
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
  });

  testWidgets('account settings: change password, device, testing mode', (
    tester,
  ) async {
    final s = _Setup();
    await tester.runAsync(() => s.prepare(age: 40));
    await s.pump(tester);
    await _tap(tester, find.text('Device connection'));
    await tester.pump();
    expect(find.textContaining('Health Monitoring module'), findsOneWidget);
    expect(find.text('Not connected'), findsOneWidget);
    expect(s.testMode.enabled, isFalse);
    await _tap(tester, find.byType(Switch));
    await tester.pump();
    expect(s.testMode.enabled, isTrue);
    await _tap(tester, find.text('Testing mode'));
    await tester.pump();
    expect(s.testMode.enabled, isFalse);
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
    expect(find.text('Health profile'), findsOneWidget);
  });
}
