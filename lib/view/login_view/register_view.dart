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
import 'package:physical_treatment_and_health_support_system/view/login_view/terms_view.dart';

/// Create an account with email and password (UC100).
class RegisterView extends StatefulWidget {
  const RegisterView({super.key});

  @override
  State<RegisterView> createState() => _RegisterViewState();
}

class _RegisterViewState extends State<RegisterView> {
  final _username = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  /// The Terms of Use and Privacy Notice, read from the link (11 Oct). The
  /// full acceptance, with the health-data consent, is recorded after the
  /// email code, once the account exists.
  bool _agreed = false;

  @override
  void dispose() {
    for (final c in [_username, _email, _password, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  /// The button stays disabled until every field is valid (FR100_006).
  bool get _valid =>
      FormValidators.username(_username.text) == null &&
      FormValidators.email(_email.text) == null &&
      FormValidators.password(_password.text) == null &&
      FormValidators.confirmPassword(_password.text, _confirm.text) == null &&
      _agreed;

  bool get _dirty =>
      [_username, _email, _password, _confirm].any((c) => c.text.isNotEmpty);

  /// Leaving with typed details asks first (FR100_010).
  Future<bool> _confirmDiscard() async {
    if (!_dirty) return true;
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
    return ok ?? false;
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    final vm = context.read<AuthViewModel>();
    final email = _email.text.trim();
    if (await vm.register(_username.text.trim(), email, _password.text) &&
        mounted) {
      Navigator.of(
        context,
      ).pushReplacementNamed(Routes.verifyCode, arguments: email);
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<AuthViewModel>();
    final error = switch (vm.registerState) {
      UiError(:final message) => message,
      _ => null,
    };
    void changed(String _) {
      setState(() {});
      vm.clearErrors();
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmDiscard() && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
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
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
                child: AutofillGroup(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const AuthTitle(
                        'Create account',
                        subtitle: 'Start your personalised recovery plan.',
                      ),
                      const SizedBox(height: 24),
                      LabeledField(
                        label: 'Username',
                        controller: _username,
                        validator: FormValidators.username,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.username],
                        onChanged: changed,
                      ),
                      const SizedBox(height: 18),
                      LabeledField(
                        label: 'Email address',
                        controller: _email,
                        validator: FormValidators.email,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.email],
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
                        textInputAction: TextInputAction.next,
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
                        textInputAction: TextInputAction.done,
                        onChanged: changed,
                        onSubmitted: (_) => _valid ? _submit() : null,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Checkbox(
                            key: const Key('register_agree'),
                            value: _agreed,
                            onChanged: (v) =>
                                setState(() => _agreed = v ?? false),
                          ),
                          const Expanded(
                            child: Text(
                              'I agree to the Terms of Use and Privacy Notice.',
                              style: TextStyle(
                                fontSize: 15,
                                color: AppTokens.ink,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) =>
                                    const TermsView(readOnly: true),
                              ),
                            ),
                            child: const Text(
                              'Read',
                              style: TextStyle(
                                color: AppTokens.brandDeepAccent,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (error != null) ...[
                        AuthErrorBanner(
                          error,
                          action: error == Messages.emailExists
                              ? TextButton(
                                  onPressed: () => Navigator.of(context).pop(),
                                  child: const Text(
                                    'Go to log in',
                                    style: TextStyle(
                                      color: AppTokens.brandDeepAccent,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                )
                              : null,
                        ),
                        const SizedBox(height: 12),
                      ],
                      PillButton(
                        label: 'Create account',
                        busy: vm.registerState is Loading,
                        onPressed: _valid ? _submit : null,
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
