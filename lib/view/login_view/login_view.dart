import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:physical_treatment_and_health_support_system/viewmodel/ui_state.dart';
import 'package:physical_treatment_and_health_support_system/core/routes/routes.dart';
import 'package:physical_treatment_and_health_support_system/core/themes/design_tokens.dart';
import 'package:physical_treatment_and_health_support_system/core/utils/form_validators.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/auth_view_model/auth_view_model.dart';
import 'package:physical_treatment_and_health_support_system/view/login_view/widgets/auth_widgets.dart';
import 'package:physical_treatment_and_health_support_system/view/common/status_bar_strip.dart';

/// Log in with email and password or Google (UC200; Figma "Login Screen").
class LoginView extends StatefulWidget {
  const LoginView({super.key});

  @override
  State<LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<LoginView> with WidgetsBindingObserver {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  /// Back from the Google page in the browser: the session may now exist.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    if (state != AppLifecycleState.resumed) return;
    final vm = context.read<AuthViewModel>();
    if (await vm.completeGoogleSignIn() && mounted) _goNext(vm);
  }

  Widget _bannerLink(String label, VoidCallback onTap) => TextButton(
    onPressed: onTap,
    style: TextButton.styleFrom(minimumSize: const Size(48, AppTokens.minTarget)),
    child: Text(
      label,
      style: const TextStyle(
        color: AppTokens.brandDeepAccent,
        fontWeight: FontWeight.w600,
        decoration: TextDecoration.underline,
      ),
    ),
  );

  void _goNext(AuthViewModel vm) {
    // UC100 M12 (Google linked to the existing account) shows on the next screen.
    final notice = vm.notice;
    if (notice != null) {
      vm.notice = null;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(notice)));
    }
    Navigator.of(
      context,
    ).pushNamedAndRemoveUntil(vm.nextRoute ?? Routes.home, (_) => false);
  }

  /// Opens Google; continues at once when the session is already here (offline demo),
  /// otherwise when the app comes back from the browser ([didChangeAppLifecycleState]).
  Future<void> _google() async {
    final vm = context.read<AuthViewModel>();
    await vm.signInWithGoogle();
    if (mounted && vm.googleState is UiSuccess) _goNext(vm);
  }

  Future<void> _login() async {
    FocusScope.of(context).unfocus();
    if (!_form.currentState!.validate()) return;
    final vm = context.read<AuthViewModel>();
    if (await vm.login(_email.text.trim(), _password.text) && mounted) {
      _goNext(vm);
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<AuthViewModel>();
    final busy = vm.loginState is Loading;
    final error = switch (vm.loginState) {
      UiError(:final message) => message,
      _ => switch (vm.googleState) {
        UiError(:final message) => message,
        _ => null,
      },
    };
    return Scaffold(
      appBar: const StatusBarStrip(),
      backgroundColor: AppTokens.screenBackground,
      body: SingleChildScrollView(
        child: Column(
          children: [
            const AuthHeader(),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
              child: AutofillGroup(
                child: Form(
                  key: _form,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const AuthTitle(
                        'Welcome back',
                        subtitle: 'Sign in to continue your recovery plan.',
                      ),
                      const SizedBox(height: 24),
                      LabeledField(
                        label: 'Email address',
                        controller: _email,
                        validator: FormValidators.email,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.email],
                        onChanged: (_) => vm.clearErrors(),
                      ),
                      const SizedBox(height: 20),
                      LabeledField(
                        label: 'Password',
                        controller: _password,
                        // Login only checks that a password was typed; the strength rule is for new passwords.
                        validator: (v) => (v ?? '').isEmpty
                            ? FormValidators.password(v)
                            : null,
                        obscure: true,
                        textInputAction: TextInputAction.done,
                        autofillHints: const [AutofillHints.password],
                        onChanged: (_) => vm.clearErrors(),
                        onSubmitted: (_) => _login(),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          style: TextButton.styleFrom(
                            minimumSize: const Size(48, AppTokens.minTarget),
                          ),
                          onPressed: () => Navigator.of(context).pushNamed(
                            Routes.resetPassword,
                            arguments: _email.text.trim(),
                          ),
                          child: const Text(
                            'Forgot password?',
                            style: TextStyle(
                              color: AppTokens.brandDeepAccent,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      if (error != null) ...[
                        AuthErrorBanner(
                          error,
                          action: switch (vm.lastErrorCode) {
                            'email_not_confirmed' => _bannerLink('Resend code', () {
                              final email = _email.text.trim();
                              vm.resendCode(email);
                              Navigator.of(
                                context,
                              ).pushNamed(Routes.verifyCode, arguments: email);
                            }),
                            // A wrong password or a lockout: offer the reset page directly
                            // (FR100_037), with the email already filled in.
                            'invalid_credentials' || 'locked' => _bannerLink(
                              'Forgot password? Reset it',
                              () => Navigator.of(context).pushNamed(
                                Routes.resetPassword,
                                arguments: _email.text.trim(),
                              ),
                            ),
                            _ => null,
                          },
                        ),
                        const SizedBox(height: 12),
                      ],
                      const SizedBox(height: 8),
                      PillButton(
                        label: 'Log In',
                        busy: busy,
                        onPressed: _login,
                      ),
                      const SizedBox(height: 20),
                      const Row(
                        children: [
                          Expanded(
                            child: Divider(
                              color: AppTokens.cardBorder,
                              thickness: 1,
                            ),
                          ),
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: 16),
                            child: Text(
                              'or',
                              style: TextStyle(
                                color: AppTokens.inkMuted,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Divider(
                              color: AppTokens.cardBorder,
                              thickness: 1,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      OutlinedPillButton(
                        label: 'Continue with Google',
                        icon: const GoogleMark(),
                        busy: vm.googleState is Loading,
                        onPressed: busy ? null : _google,
                      ),
                      const SizedBox(height: 16),
                      // Wrap, not Row: with large text the link drops to its own line.
                      // Full width so WrapAlignment.center actually centres it.
                      SizedBox(
                        width: double.infinity,
                        child: Wrap(
                          alignment: WrapAlignment.center,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            const Text(
                              'New user?',
                              style: TextStyle(
                                color: AppTokens.inkMuted,
                                fontSize: 16,
                              ),
                            ),
                            TextButton(
                              style: TextButton.styleFrom(
                                minimumSize: const Size(
                                  48,
                                  AppTokens.minTarget,
                                ),
                              ),
                              onPressed: () => Navigator.of(
                                context,
                              ).pushNamed(Routes.register),
                              child: const Text(
                                'Create account',
                                style: TextStyle(
                                  color: AppTokens.cta,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
