import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:physical_treatment_and_health_support_system/core/base/ui_state.dart';
import 'package:physical_treatment_and_health_support_system/core/constants/app_constants.dart';
import 'package:physical_treatment_and_health_support_system/core/routes/routes.dart';
import 'package:physical_treatment_and_health_support_system/core/themes/design_tokens.dart';
import 'package:physical_treatment_and_health_support_system/core/utils/form_validators.dart';
import 'package:physical_treatment_and_health_support_system/features/auth/viewmodel/auth_view_model.dart';
import 'package:physical_treatment_and_health_support_system/features/auth/widgets/auth_widgets.dart';

/// Enter the 6-digit code emailed at sign-up (FR100_012 to FR100_015).
/// The email address arrives as the route argument.
class VerifyCodeView extends StatefulWidget {
  const VerifyCodeView({super.key});

  @override
  State<VerifyCodeView> createState() => _VerifyCodeViewState();
}

class _VerifyCodeViewState extends State<VerifyCodeView> {
  final _code = TextEditingController();

  String get _email =>
      (ModalRoute.of(context)?.settings.arguments as String?) ?? '';

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    FocusScope.of(context).unfocus();
    final vm = context.read<AuthViewModel>();
    if (await vm.verify(_email, _code.text.trim()) && mounted) {
      // The auth screens are removed so Back does not return to them.
      Navigator.of(
        context,
      ).pushNamedAndRemoveUntil(vm.nextRoute ?? Routes.home, (_) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<AuthViewModel>();
    final error = switch (vm.verifyState) {
      UiError(:final message) => message,
      _ => switch (vm.resendState) {
        UiError(:final message) => message,
        _ => null,
      },
    };
    final ready = FormValidators.otp(_code.text) == null;
    return Scaffold(
      backgroundColor: AppTokens.screenBackground,
      body: SingleChildScrollView(
        child: Column(
          children: [
            AuthHeader(
              heightFactor: 0.22,
              showSubtitle: false,
              leading: IconButton(
                tooltip: 'Back',
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AuthTitle(
                    'Enter your code',
                    subtitle: 'We sent a 6-digit code to $_email.',
                  ),
                  const SizedBox(height: 24),
                  LabeledField(
                    label: 'Verification code',
                    controller: _code,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.done,
                    autofillHints: const [AutofillHints.oneTimeCode],
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    maxLength: AppConstants.otpLength,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppTokens.ink,
                      fontSize: 28,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 12,
                    ),
                    onChanged: (_) {
                      setState(() {});
                      vm.clearErrors();
                    },
                    onSubmitted: (_) => ready ? _verify() : null,
                  ),
                  const SizedBox(height: 20),
                  if (error != null) ...[
                    AuthErrorBanner(error),
                    const SizedBox(height: 12),
                  ],
                  if (vm.resendState is UiSuccess && !vm.canResend) ...[
                    const Text(
                      'A new code has been sent.',
                      style: TextStyle(color: AppTokens.good, fontSize: 15),
                    ),
                    const SizedBox(height: 12),
                  ],
                  PillButton(
                    label: 'Verify',
                    busy: vm.verifyState is Loading,
                    onPressed: ready ? _verify : null,
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: TextButton(
                      style: TextButton.styleFrom(
                        minimumSize: const Size(48, AppTokens.minTarget),
                      ),
                      onPressed: vm.canResend && vm.resendState is! Loading
                          ? () => vm.resendCode(_email)
                          : null,
                      child: Text(
                        vm.canResend
                            ? 'Resend code'
                            : 'Resend in ${vm.secondsUntilResend} s',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: vm.canResend
                              ? AppTokens.brandDeepAccent
                              : AppTokens.inkMuted,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
