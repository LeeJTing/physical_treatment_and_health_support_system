import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:physical_treatment_and_health_support_system/viewmodel/ui_state.dart';
import 'package:physical_treatment_and_health_support_system/core/constants/app_constants.dart';
import 'package:physical_treatment_and_health_support_system/core/routes/routes.dart';
import 'package:physical_treatment_and_health_support_system/core/themes/design_tokens.dart';
import 'package:physical_treatment_and_health_support_system/core/utils/form_validators.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/auth_view_model/auth_view_model.dart';
import 'package:physical_treatment_and_health_support_system/view/login_view/widgets/auth_widgets.dart';
import 'package:physical_treatment_and_health_support_system/view/common/status_bar_strip.dart';

/// Reset a forgotten password in two steps (UC200 alternative flow, FR100_037 to FR100_042):
/// 1. email -> a reset code is sent; 2. code + new password.
/// Also opened from Profile > Change password. Route argument: an optional email to prefill.
class ResetPasswordView extends StatefulWidget {
  const ResetPasswordView({super.key});

  @override
  State<ResetPasswordView> createState() => _ResetPasswordViewState();
}

class _ResetPasswordViewState extends State<ResetPasswordView> {
  final _email = TextEditingController();
  final _code = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _codeSent = false;
  bool _prefilled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_prefilled) {
      _prefilled = true;
      _email.text =
          (ModalRoute.of(context)?.settings.arguments as String?) ?? '';
    }
  }

  @override
  void dispose() {
    for (final c in [_email, _code, _password, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _stepTwoValid =>
      FormValidators.otp(_code.text) == null &&
      FormValidators.password(_password.text) == null &&
      FormValidators.confirmPassword(_password.text, _confirm.text) == null;

  Future<void> _sendCode() async {
    FocusScope.of(context).unfocus();
    if (await context.read<AuthViewModel>().requestReset(_email.text.trim()) &&
        mounted) {
      setState(() => _codeSent = true);
    }
  }

  Future<void> _confirmReset() async {
    FocusScope.of(context).unfocus();
    final vm = context.read<AuthViewModel>();
    if (!await vm.confirmReset(
          _email.text.trim(),
          _code.text.trim(),
          _password.text,
        ) ||
        !mounted) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        content: const Text(
          Messages.passwordResetDone,
          style: TextStyle(fontSize: 17),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Log in'),
          ),
        ],
      ),
    );
    // Every session has ended (FR100_041), so the patient logs in again (FR100_042).
    if (mounted) {
      Navigator.of(
        context,
      ).pushNamedAndRemoveUntil(Routes.loginScreen, (_) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<AuthViewModel>();
    final error = switch (_codeSent
        ? vm.resetConfirmState
        : vm.resetRequestState) {
      UiError(:final message) => message,
      _ => null,
    };
    void changed(String _) {
      setState(() {});
      vm.clearErrors();
    }

    return Scaffold(
      appBar: const StatusBarStrip(),
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
                  const AuthTitle(
                    'Reset password',
                    subtitle: 'We will email you a 6-digit reset code.',
                  ),
                  const SizedBox(height: 24),
                  LabeledField(
                    label: 'Email address',
                    controller: _email,
                    validator: FormValidators.email,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    onChanged: changed,
                  ),
                  const SizedBox(height: 20),
                  if (!_codeSent) ...[
                    if (error != null) ...[
                      AuthErrorBanner(error),
                      const SizedBox(height: 12),
                    ],
                    PillButton(
                      label: 'Send code',
                      busy: vm.resetRequestState is Loading,
                      onPressed: FormValidators.email(_email.text) == null
                          ? _sendCode
                          : null,
                    ),
                  ] else ...[
                    // The same reply whether or not the address has an account (FR100_038).
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppTokens.tint,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Text(
                        Messages.resetCodeSent,
                        style: TextStyle(color: AppTokens.ink, fontSize: 15),
                      ),
                    ),
                    const SizedBox(height: 20),
                    LabeledField(
                      label: 'Reset code',
                      controller: _code,
                      keyboardType: TextInputType.number,
                      autofillHints: const [AutofillHints.oneTimeCode],
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      maxLength: AppConstants.otpLength,
                      onChanged: changed,
                    ),
                    const SizedBox(height: 18),
                    LabeledField(
                      label: 'New password',
                      controller: _password,
                      validator: FormValidators.password,
                      obscure: true,
                      helper:
                          'At least 8 characters, with at least one letter and one number.',
                      autofillHints: const [AutofillHints.newPassword],
                      onChanged: changed,
                    ),
                    const SizedBox(height: 18),
                    LabeledField(
                      label: 'Confirm new password',
                      controller: _confirm,
                      validator: (v) =>
                          FormValidators.confirmPassword(_password.text, v),
                      obscure: true,
                      onChanged: changed,
                    ),
                    const SizedBox(height: 20),
                    if (error != null) ...[
                      AuthErrorBanner(error),
                      const SizedBox(height: 12),
                    ],
                    PillButton(
                      label: 'Reset password',
                      busy: vm.resetConfirmState is Loading,
                      onPressed: _stepTwoValid ? _confirmReset : null,
                    ),
                    Center(
                      child: TextButton(
                        style: TextButton.styleFrom(
                          minimumSize: const Size(48, AppTokens.minTarget),
                        ),
                        onPressed: vm.canResend ? _sendCode : null,
                        child: Text(
                          vm.canResend
                              ? 'Send a new code'
                              : 'Send again in ${vm.secondsUntilResend} s',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: vm.canResend
                                ? AppTokens.brandDeepAccent
                                : AppTokens.inkMuted,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
