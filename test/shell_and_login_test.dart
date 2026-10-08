import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:physical_treatment_and_health_support_system/core/constants/app_constants.dart';
import 'package:physical_treatment_and_health_support_system/core/routes/routes.dart';
import 'package:physical_treatment_and_health_support_system/core/utils/id_utils.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/health_profile.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/auth_repository/fake_auth_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/profile_repository/fake_profile_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/auth_repository/i_auth_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/profile_repository/i_profile_repository.dart';
import 'package:physical_treatment_and_health_support_system/view/login_view/login_view.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/auth_view_model/auth_view_model.dart';
import 'package:physical_treatment_and_health_support_system/view/login_view/startup_view.dart';

/// A labelled stand-in for each destination screen.
Widget _stub(String name) => Scaffold(body: Text('route:$name'));

final Map<String, WidgetBuilder> _routes = {
  Routes.init: (_) => const StartupView(),
  Routes.loginScreen: (_) => const LoginView(),
  Routes.home: (_) => _stub('home'),
  Routes.healthProfile: (_) => _stub('profile'),
  Routes.register: (_) => _stub('register'),
  Routes.resetPassword: (_) => _stub('reset'),
  Routes.verifyCode: (_) => _stub('verify'),
};

Widget _app(
  FakeAuthRepository auth,
  FakeProfileRepository profiles, {
  required String initial,
}) => MultiProvider(
  providers: [
    Provider<IAuthRepository>.value(value: auth),
    Provider<IProfileRepository>.value(value: profiles),
    ChangeNotifierProvider(create: (c) => AuthViewModel(c.read(), c.read())),
  ],
  child: MaterialApp(
    initialRoute: initial,
    routes: _routes,
    // Push only the requested screen. The default would stack '/' (StartupView)
    // under '/login', and StartupView would then push a second LoginView.
    onGenerateInitialRoutes: (name) => [
      MaterialPageRoute(
        settings: RouteSettings(name: name),
        builder: _routes[name]!,
      ),
    ],
  ),
);

Future<void> _completeProfile(
  FakeAuthRepository auth,
  FakeProfileRepository profiles,
) async {
  final a = (await auth.login('demo@apths.test', 'password123')).dataOrNull!;
  final p = HealthProfile(
    profileId: newId(),
    accountId: a.accountId,
    age: 60,
    gender: Gender.male,
    weightKg: 70,
    heightCm: 170,
    updatedAt: DateTime.now(),
  );
  await profiles.saveProfile(p, p.generateSafetyLimit());
}

void main() {
  group('AuthViewModel.decideStartRoute (FR100_024, FR100_025, FR100_035)', () {
    test('no stored session -> login', () async {
      final vm = AuthViewModel(FakeAuthRepository(), FakeProfileRepository());
      expect(await vm.decideStartRoute(), Routes.loginScreen);
    });

    test('signed in without a profile -> profile', () async {
      final auth = FakeAuthRepository();
      await auth.login('demo@apths.test', 'password123');
      expect(
        await AuthViewModel(auth, FakeProfileRepository()).decideStartRoute(),
        Routes.healthProfile,
      );
    });

    test('signed in with a complete profile -> home', () async {
      final auth = FakeAuthRepository();
      final profiles = FakeProfileRepository();
      await _completeProfile(auth, profiles);
      expect(
        await AuthViewModel(auth, profiles).decideStartRoute(),
        Routes.home,
      );
    });

    test(
      'profile cannot be read -> home (fail-safe limits apply there)',
      () async {
        final auth = FakeAuthRepository();
        final profiles = FakeProfileRepository()..failNext = true;
        await auth.login('demo@apths.test', 'password123');
        expect(
          await AuthViewModel(auth, profiles).decideStartRoute(),
          Routes.home,
        );
      },
    );
  });

  testWidgets('StartupView goes to the login screen when nobody is signed in', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(FakeAuthRepository(), FakeProfileRepository(), initial: Routes.init),
    );
    await tester.pumpAndSettle();
    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Log In'), findsOneWidget);
  });

  testWidgets('Login: empty fields show errors under the fields (FR100_028)', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _app(
        FakeAuthRepository(),
        FakeProfileRepository(),
        initial: Routes.loginScreen,
      ),
    );
    await tester.tap(find.text('Log In'));
    await tester.pump();
    expect(find.text(Messages.emailEmpty), findsOneWidget);
    expect(find.text(Messages.passwordEmpty), findsOneWidget);
  });

  testWidgets('Login: a wrong password shows the report message', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _app(
        FakeAuthRepository(),
        FakeProfileRepository(),
        initial: Routes.loginScreen,
      ),
    );
    await tester.enterText(find.byType(TextFormField).at(0), 'demo@apths.test');
    await tester.enterText(find.byType(TextFormField).at(1), 'wrongpass1');
    await tester.tap(find.text('Log In'));
    await tester.pumpAndSettle();
    expect(find.text(Messages.incorrectCredentials), findsOneWidget);
  });

  testWidgets('Login: correct details for a patient with a profile open home', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.reset);
    final auth = FakeAuthRepository();
    final profiles = FakeProfileRepository();
    await _completeProfile(auth, profiles);
    await auth.signOut();
    await tester.pumpWidget(_app(auth, profiles, initial: Routes.loginScreen));
    await tester.enterText(find.byType(TextFormField).at(0), 'demo@apths.test');
    await tester.enterText(find.byType(TextFormField).at(1), 'password123');
    await tester.tap(find.text('Log In'));
    await tester.pumpAndSettle();
    expect(find.text('route:home'), findsOneWidget);
  });

  // Older users are told to raise the phone's font size (chatbot text_size answer).
  testWidgets('Login: no overflow with 2x phone text on a 360x800 screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      _app(
        FakeAuthRepository(),
        FakeProfileRepository(),
        initial: Routes.loginScreen,
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    // The page's own scroll view (each text field has a Scrollable too).
    await tester.scrollUntilVisible(
      find.text('Create account'),
      300,
      scrollable: find
          .descendant(
            of: find.byType(SingleChildScrollView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
