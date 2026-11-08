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

/// Complete Account Setup (UC100 A1 / UC200 A2.2, FR100_022): after the first Google sign-in the
/// patient chooses a username and a password, with the same rules as manual registration.
/// Cancelling asks first (M11), then signs out and removes the unfinished account (FR100_023).
class AccountSetupView extends StatefulWidget {
  const AccountSetupView({super.key});

  @override
  State<AccountSetupView> createState() => _AccountSetupViewState();
}

class _AccountSetupViewState extends State<AccountSetupView> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  @override
  void dispose() {
    for (final c in [_username, _password, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _valid =>
      FormValidators.username(_username.text) == null &&
      FormValidators.password(_password.text) == null &&
      FormValidators.confirmPassword(_password.text, _confirm.text) == null;

  void _go(AuthViewModel vm) => Navigator.of(
    context,
  ).pushNamedAndRemoveUntil(vm.nextRoute ?? Routes.home, (_) => false);

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    final vm = context.read<AuthViewModel>();
    if (await vm.completeAccountSetup(
          _username.text,
          _password.text,
          _confirm.text,
        ) &&
        mounted) {
      _go(vm);
    }
  }

  /// M11, then FR100_023: the unfinished account is removed and the login screen returns.
  Future<void> _cancel() async {
    final vm = context.read<AuthViewModel>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        content: const Text(
          Messages.discardRegistration,
          style: TextStyle(fontSize: 17),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text(
              'Discard',
              style: TextStyle(color: AppTokens.cta),
            ),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await vm.cancelAccountSetup();
    if (mounted) _go(vm);
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<AuthViewModel>();
    final busy = vm.setupState is Loading;
    final error = switch (vm.setupState) {
      UiError(:final message) => message,
      _ => null,
    };
    void changed(String _) {
      setState(() {});
      vm.clearErrors();
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !busy) _cancel();
      },
      child: Scaffold(
        appBar: const StatusBarStrip(),
        backgroundColor: AppTokens.screenBackground,
        body: SingleChildScrollView(
          child: Column(
            children: [
              // A back arrow like Register's (audit, 23 Oct); it asks before discarding, as
              // the phone's Back and Cancel do.
              AuthHeader(
                heightFactor: 0.22,
                showSubtitle: false,
                leading: IconButton(
                  tooltip: 'Back',
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: busy ? null : () => Navigator.of(context).maybePop(),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(24),
                child: AutofillGroup(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const AuthTitle(
                        'Complete account setup',
                        subtitle:
                            'You signed in with Google. Choose a username and a '
                            'password so you can also log in with your email.',
                      ),
                      const SizedBox(height: 24),
                      LabeledField(
                        label: 'Username',
                        controller: _username,
                        validator: FormValidators.username,
                        autofillHints: const [AutofillHints.username],
                        onChanged: changed,
                      ),
                      const SizedBox(height: 18),
                      LabeledField(
                        label: 'Password',
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
                        label: 'Confirm password',
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
                        label: 'Finish setup',
                        busy: busy,
                        onPressed: _valid && !busy ? _submit : null,
                      ),
                      Center(
                        child: TextButton(
                          style: TextButton.styleFrom(
                            minimumSize: const Size(48, AppTokens.minTarget),
                          ),
                          onPressed: busy ? null : _cancel,
                          child: const Text(
                            'Cancel',
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
              ),
            ],
          ),
        ),
      ),
    );
  }
}
