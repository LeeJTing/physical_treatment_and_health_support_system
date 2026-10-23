// RegisterView (UC100) and ResetPasswordView (UC200 reset) on the fake auth repository: the
// button enabled only when every field is valid, the error banners, leaving with typed details,
// and each flow to its next screen. NFR_17 coverage (22 Oct); the rules are in
// auth_view_model_test.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:physical_treatment_and_health_support_system/core/constants/app_constants.dart';
import 'package:physical_treatment_and_health_support_system/core/routes/routes.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/auth_repository/fake_auth_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/profile_repository/fake_profile_repository.dart';
import 'package:physical_treatment_and_health_support_system/view/login_view/account_setup_view.dart';
import 'package:physical_treatment_and_health_support_system/view/login_view/register_view.dart';
import 'package:physical_treatment_and_health_support_system/view/login_view/reset_password_view.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/auth_view_model/auth_view_model.dart';

Widget _stub(BuildContext c, String name) => Scaffold(
  body: Text('route:$name ${ModalRoute.of(c)!.settings.arguments ?? ''}'),
);

/// The screen under test on top of a stand-in login page, so Back and pop have somewhere to go.
Future<FakeAuthRepository> _open(
  WidgetTester tester,
  String route, {
  Object? arguments,
}) async {
  tester.view.physicalSize = const Size(1080, 6000);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final auth = FakeAuthRepository();
  final nav = GlobalKey<NavigatorState>();
  await tester.pumpWidget(
    ChangeNotifierProvider(
      create: (_) => AuthViewModel(auth, FakeProfileRepository()),
      child: MaterialApp(
        navigatorKey: nav,
        routes: {
          Routes.register: (_) => const RegisterView(),
          Routes.accountSetup: (_) => const AccountSetupView(),
          Routes.resetPassword: (_) => const ResetPasswordView(),
          Routes.verifyCode: (c) => _stub(c, 'verify'),
          Routes.loginScreen: (c) => _stub(c, 'login'),
        },
        home: const Scaffold(body: Text('LOGIN PAGE')),
      ),
    ),
  );
  nav.currentState!.pushNamed(route, arguments: arguments);
  await _settle(tester);
  return auth;
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
}

/// Removes the tree so the view model's resend timer is cancelled before the test ends.
Future<void> _close(WidgetTester tester) =>
    tester.pumpWidget(const SizedBox.shrink());

Finder _field(int i) => find.byType(TextFormField).at(i);

void main() {
  group('RegisterView (UC100)', () {
    Future<void> fill(
      WidgetTester tester, {
      String email = 'new@apths.test',
      String confirm = 'secret123',
    }) async {
      await tester.enterText(_field(0), 'newbie');
      await tester.enterText(_field(1), email);
      await tester.enterText(_field(2), 'secret123');
      await tester.enterText(_field(3), confirm);
      await tester.pump();
    }

    testWidgets('Create account waits for every field and the terms box', (
      tester,
    ) async {
      await _open(tester, Routes.register);
      final button = find.ancestor(
        of: find.text('Create account').last,
        matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
      );
      bool enabled() =>
          tester.widget<ButtonStyleButton>(button.first).onPressed != null;
      expect(enabled(), isFalse);
      await fill(tester, confirm: 'different1');
      expect(find.text(Messages.passwordMismatch), findsOneWidget);
      expect(enabled(), isFalse);
      await tester.enterText(_field(3), 'secret123');
      await tester.pump();
      expect(enabled(), isFalse); // the terms box is not ticked
      await tester.tap(find.byKey(const Key('register_agree')));
      await tester.pump();
      expect(enabled(), isTrue);
      await _close(tester);
    });

    testWidgets('a new account goes to the code screen with its email', (
      tester,
    ) async {
      await _open(tester, Routes.register);
      await fill(tester);
      await tester.tap(find.byKey(const Key('register_agree')));
      await tester.pump();
      await tester.tap(find.text('Create account').last);
      await _settle(tester);
      expect(find.text('route:verify new@apths.test'), findsOneWidget);
      await _close(tester);
    });

    testWidgets('an email already registered: the message and Go to log in', (
      tester,
    ) async {
      await _open(tester, Routes.register);
      await fill(tester, email: 'demo@apths.test');
      await tester.tap(find.byKey(const Key('register_agree')));
      await tester.pump();
      await tester.tap(find.text('Create account').last);
      await _settle(tester);
      expect(find.text(Messages.emailExists), findsOneWidget);
      await tester.tap(find.text('Go to log in'));
      await _settle(tester);
      expect(find.text('LOGIN PAGE'), findsOneWidget);
      await _close(tester);
    });

    testWidgets('Back with typed details asks; Keep editing, then Discard', (
      tester,
    ) async {
      await _open(tester, Routes.register);
      await tester.enterText(_field(0), 'newbie');
      await tester.pump();
      await tester.tap(find.byTooltip('Back'));
      await _settle(tester);
      expect(find.text(Messages.discardRegistration), findsOneWidget);
      await tester.tap(find.text('Keep editing'));
      await _settle(tester);
      expect(find.text('LOGIN PAGE'), findsNothing);
      await tester.tap(find.byTooltip('Back'));
      await _settle(tester);
      await tester.tap(find.text('Discard'));
      await _settle(tester);
      expect(find.text('LOGIN PAGE'), findsOneWidget);
      await _close(tester);
    });

    testWidgets('Back with nothing typed leaves at once', (tester) async {
      await _open(tester, Routes.register);
      await tester.tap(find.byTooltip('Back'));
      await _settle(tester);
      expect(find.text(Messages.discardRegistration), findsNothing);
      expect(find.text('LOGIN PAGE'), findsOneWidget);
      await _close(tester);
    });

    testWidgets('Read opens the terms', (tester) async {
      await _open(tester, Routes.register);
      await tester.tap(find.text('Read'));
      await _settle(tester);
      expect(find.text('Create account'), findsNothing);
      await _close(tester);
    });
  });

  group('ResetPasswordView (UC200)', () {
    testWidgets('the email from Login is filled in; Send code shows step 2', (
      tester,
    ) async {
      await _open(tester, Routes.resetPassword, arguments: 'demo@apths.test');
      expect(find.text('demo@apths.test'), findsOneWidget);
      await tester.tap(find.text('Send code'));
      await _settle(tester);
      expect(find.text(Messages.resetCodeSent), findsOneWidget);
      expect(find.text('Reset password'), findsWidgets);
      expect(find.textContaining('Send again in'), findsOneWidget);
      await _close(tester);
    });

    testWidgets('a wrong code is refused and the screen stays', (tester) async {
      await _open(tester, Routes.resetPassword, arguments: 'demo@apths.test');
      await tester.tap(find.text('Send code'));
      await _settle(tester);
      await tester.enterText(_field(1), '000000');
      await tester.enterText(_field(2), 'newpass123');
      await tester.enterText(_field(3), 'newpass123');
      await tester.pump();
      await tester.tap(find.text('Reset password').last);
      await _settle(tester);
      expect(find.textContaining('incorrect'), findsOneWidget);
      expect(find.text('route:login '), findsNothing);
      await _close(tester);
    });

    testWidgets('the right code resets the password, then Log in', (
      tester,
    ) async {
      final auth = await _open(
        tester,
        Routes.resetPassword,
        arguments: 'demo@apths.test',
      );
      await tester.tap(find.text('Send code'));
      await _settle(tester);
      await tester.enterText(_field(1), FakeAuthRepository.devCode);
      await tester.enterText(_field(2), 'newpass123');
      await tester.enterText(_field(3), 'newpass123');
      await tester.pump();
      await tester.tap(find.text('Reset password').last);
      await _settle(tester);
      expect(find.text(Messages.passwordResetDone), findsOneWidget);
      await tester.tap(find.text('Log in'));
      await _settle(tester);
      expect(find.text('route:login '), findsOneWidget);
      final login = await tester.runAsync(
        () => auth.login('demo@apths.test', 'newpass123'),
      );
      expect(login!.isSuccess, isTrue);
      await _close(tester);
    });

    testWidgets('after 60 s the code can be sent again', (tester) async {
      await _open(tester, Routes.resetPassword, arguments: 'demo@apths.test');
      await tester.tap(find.text('Send code'));
      await _settle(tester);
      await tester.pump(const Duration(seconds: 61));
      expect(find.textContaining('Send again in'), findsNothing);
      await _close(tester);
    });
  });

  testWidgets(
    'Google account setup: the back arrow asks before discarding (23 Oct)',
    (tester) async {
      await _open(tester, Routes.accountSetup);
      await tester.tap(find.byTooltip('Back'));
      await _settle(tester);
      expect(find.text(Messages.discardRegistration), findsOneWidget);
      await tester.tap(find.text('Keep editing'));
      await _settle(tester);
      expect(find.text('Complete account setup'), findsOneWidget);
      await _close(tester);
    },
  );
}
