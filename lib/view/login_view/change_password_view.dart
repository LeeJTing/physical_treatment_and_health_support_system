import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:physical_treatment_and_health_support_system/viewmodel/ui_state.dart';
import 'package:physical_treatment_and_health_support_system/core/constants/app_constants.dart';
import 'package:physical_treatment_and_health_support_system/core/routes/routes.dart';
import 'package:physical_treatment_and_health_support_system/core/themes/design_tokens.dart';
import 'package:physical_treatment_and_health_support_system/core/utils/form_validators.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/auth_view_model/auth_view_model.dart';
import 'package:physical_treatment_and_health_support_system/view/login_view/widgets/auth_widgets.dart';
import 'package:physical_treatment_and_health_support_system/view/common/status_bar_strip.dart';

/// Profile > Change password (FR100_061): the current password is re-entered, and the new one
/// follows the registration rule. A forgotten current password goes to the emailed reset code
/// (FR100_037 to FR100_042). Lives with the other account screens so it shares their widgets.
class ChangePasswordView extends StatefulWidget {
  const ChangePasswordView({super.key});

  @override
  State<ChangePasswordView> createState() => _ChangePasswordViewState();
}

class _ChangePasswordViewState extends State<ChangePasswordView> {
  final _current = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  @override
  void dispose() {
    for (final c in [_current, _password, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _valid =>
      _current.text.isNotEmpty &&
      FormValidators.password(_password.text) == null &&
      FormValidators.confirmPassword(_password.text, _confirm.text) == null;

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    final vm = context.read<AuthViewModel>();
    if (!await vm.changePassword(_current.text, _password.text, _confirm.text) ||
        !mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text(Messages.passwordChanged)));
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<AuthViewModel>();
    final error = switch (vm.changePasswordState) {
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
                    'Change password',
                    subtitle: 'Enter your current password, then the new one.',
                  ),
                  const SizedBox(height: 24),
                  LabeledField(
                    label: 'Current password',
                    controller: _current,
                    obscure: true,
                    autofillHints: const [AutofillHints.password],
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
                    label: 'Update password',
                    busy: vm.changePasswordState is Loading,
                    onPressed: _valid ? _submit : null,
                  ),
                  Center(
                    child: TextButton(
                      style: TextButton.styleFrom(
                        minimumSize: const Size(48, AppTokens.minTarget),
                      ),
                      onPressed: () => Navigator.of(
                        context,
                      ).pushNamed(Routes.resetPassword),
                      child: const Text(
                        'Forgot your current password? Reset it by email',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: AppTokens.brandDeepAccent,
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
