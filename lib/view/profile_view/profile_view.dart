import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:physical_treatment_and_health_support_system/viewmodel/ui_state.dart';
import 'package:physical_treatment_and_health_support_system/core/constants/app_constants.dart';
import 'package:physical_treatment_and_health_support_system/core/routes/routes.dart';
import 'package:physical_treatment_and_health_support_system/view/login_view/terms_view.dart';
import 'package:physical_treatment_and_health_support_system/core/themes/design_tokens.dart';
import 'package:physical_treatment_and_health_support_system/core/utils/form_validators.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/health_profile.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/lookups.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/auth_view_model/auth_view_model.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/profile_view_model/profile_view_model.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/test_mode_view_model/test_mode_view_model.dart';
import 'package:physical_treatment_and_health_support_system/view/profile_view/widgets/profile_widgets.dart';
import 'package:physical_treatment_and_health_support_system/view/common/status_bar_strip.dart';

/// My Profile (UC300; Figma "Profile Screen"). Used as the Profile tab and, for a
/// patient without a complete profile, as a standalone route after sign-in (FR100_035).
class ProfileView extends StatefulWidget {
  const ProfileView({super.key});

  @override
  State<ProfileView> createState() => _ProfileViewState();
}

class _ProfileViewState extends State<ProfileView> {
  final _age = TextEditingController();
  final _weight = TextEditingController();
  final _height = TextEditingController();
  bool _fieldsFilled = false;

  @override
  void dispose() {
    _age.dispose();
    _weight.dispose();
    _height.dispose();
    super.dispose();
  }

  /// Opened on its own after sign-in rather than as a tab of the shell.
  bool get _standalone =>
      ModalRoute.of(context)?.settings.name == Routes.healthProfile;

  static String _num(num? v) =>
      v == null ? '' : (v % 1 == 0 ? v.toInt().toString() : v.toString());

  void _fillFields(HealthProfile? d) {
    _age.text = _num(d?.age);
    _weight.text = _num(d?.weightKg);
    _height.text = _num(d?.heightCm);
  }

  void _startEdit(ProfileViewModel vm) {
    vm.startEdit();
    _fillFields(vm.draft);
    _fieldsFilled = true;
  }

  Future<void> _save(ProfileViewModel vm) async {
    FocusScope.of(context).unfocus();
    final ok = await vm.saveProfile();
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    if (ok) {
      _fieldsFilled = false;
      messenger.showSnackBar(
        const SnackBar(content: Text(Messages.profileSaved)),
      );
      // Reached straight after sign-in (nothing to go back to): continue into the app.
      if (_standalone && !Navigator.of(context).canPop()) {
        Navigator.of(
          context,
        ).pushNamedAndRemoveUntil(Routes.home, (_) => false);
      }
    }
  }

  /// The age does not match the age group accepted in the Terms (14 Oct):
  /// accept them again for the new age, then save.
  Future<void> _reviewTerms(ProfileViewModel vm) async {
    final age = vm.draft?.age;
    if (age == null) return;
    context.read<AuthViewModel>().startAgeReview(age);
    final accepted = await Navigator.of(context).pushNamed<bool>(Routes.terms);
    if (accepted == true && mounted) await _save(vm);
  }

  Future<bool> _ask(String message, String yes, {bool danger = false}) async =>
      await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          content: Text(message, style: const TextStyle(fontSize: 17)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text(
                yes,
                style: TextStyle(
                  color: danger ? AppTokens.cta : AppTokens.brandDeepAccent,
                ),
              ),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _cancel(ProfileViewModel vm) async {
    if (vm.hasUnsavedChanges &&
        !await _ask(Messages.discardChanges, 'Discard', danger: true)) {
      return;
    }
    vm.cancelEdit();
    _fieldsFilled = false;
  }

  Future<void> _logout(ProfileViewModel vm) async {
    if (!await _ask(Messages.confirmLogout, 'Log out', danger: true)) {
      return; // FR100_060
    }
    await vm.logout();
    if (mounted) {
      Navigator.of(
        context,
      ).pushNamedAndRemoveUntil(Routes.loginScreen, (_) => false); // FR100_059
    }
  }

  /// Privacy Notice section 5: the patient can delete the account and all its
  /// data. Asked twice: the first answer explains, the second confirms.
  Future<void> _deleteAccount(ProfileViewModel vm) async {
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    if (!await _ask(Messages.confirmDeleteAccount, 'Delete', danger: true)) {
      return;
    }
    if (await vm.deleteAccount()) {
      nav.pushNamedAndRemoveUntil(Routes.loginScreen, (_) => false);
      messenger.showSnackBar(
        const SnackBar(content: Text(Messages.accountDeleted)),
      );
    } else {
      messenger.showSnackBar(
        const SnackBar(content: Text(Messages.accountDeleteFailed)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ProfileViewModel>();
    if (vm.isEditing && !_fieldsFilled && vm.draft != null) {
      _fillFields(vm.draft);
      _fieldsFilled = true;
    }
    final firstLoad =
        vm.loadState is Loading && vm.profile == null && vm.draft == null;
    return PopScope(
      canPop: !vm.hasUnsavedChanges,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _ask(Messages.discardChanges, 'Discard', danger: true) &&
            context.mounted) {
          vm.cancelEdit();
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: const StatusBarStrip(),
        backgroundColor: AppTokens.screenBackground,
        bottomNavigationBar: vm.isEditing
            ? _EditBar(
                vm: vm,
                onCancel: () => _cancel(vm),
                onSave: () => _save(vm),
              )
            : null,
        body: switch (vm.loadState) {
          _ when firstLoad => const Center(
            child: CircularProgressIndicator(color: AppTokens.brandDeep),
          ),
          UiError(:final message) when vm.profile == null && vm.draft == null =>
            _LoadError(message, vm.loadProfile),
          _ => _body(vm),
        },
      ),
    );
  }

  Widget _body(ProfileViewModel vm) {
    final p = vm.shown;
    final risk = p?.assignRiskLevel();
    final top = MediaQuery.paddingOf(context).top;
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        Stack(
          children: [
            Container(
              height: top + 112,
              width: double.infinity,
              color: AppTokens.brandDeep,
              padding: EdgeInsets.fromLTRB(24, top + 20, 24, 0),
              child: const Text(
                'My Profile',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                AppTokens.gutter,
                top + 70,
                AppTokens.gutter,
                0,
              ),
              child: IdentityCard(
                username: vm.account?.username ?? '',
                email: vm.account?.email ?? '',
                risk: p != null && p.isComplete ? risk : null,
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppTokens.gutter,
            20,
            AppTokens.gutter,
            32,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_standalone && vm.isEditing) ...[
                InfoBanner(
                  Messages.profileNotConfigured,
                  icon: Icons.info_outline,
                  tone: BannerTone.info,
                ),
                const SizedBox(height: 16),
              ],
              Row(
                children: [
                  const Expanded(child: SectionTitle('Health profile')),
                  if (!vm.isEditing)
                    TextButton(
                      style: TextButton.styleFrom(
                        minimumSize: const Size(48, AppTokens.minTarget),
                      ),
                      onPressed: () => _startEdit(vm),
                      child: const Text(
                        'Edit',
                        style: TextStyle(
                          color: AppTokens.brandDeepAccent,
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              vm.isEditing ? _editStats(vm) : StatsCard(profile: p),
              const SizedBox(height: 24),
              const SectionTitle('Pre-existing health conditions'),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final c in vm.conditions)
                    ProfileChip(
                      label: conditionLabel(c),
                      selected: p?.conditions.contains(c) ?? false,
                      onTap: vm.isEditing
                          ? () => vm.toggleCondition(c.conditionId)
                          : null,
                    ),
                ],
              ),
              _ConditionAnswers(vm: vm, profile: p),
              const SizedBox(height: 24),
              const SectionTitle('Physical limitations'),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final l in vm.limitations)
                    ProfileChip(
                      label: limitationLabel(l),
                      selected: p?.limitations.contains(l) ?? false,
                      onTap: vm.isEditing
                          ? () => vm.toggleLimitation(l.limitationId)
                          : null,
                    ),
                  ProfileChip(
                    label: 'None',
                    selected: p != null && p.limitations.isEmpty,
                    onTap: vm.isEditing ? vm.clearLimitations : null,
                  ),
                ],
              ),
              if (risk == RiskLevel.medium || risk == RiskLevel.high) ...[
                const SizedBox(height: 20),
                InfoBanner(
                  risk == RiskLevel.high
                      ? Messages
                            .highRiskAdvisory // FR100_058
                      : 'Consult a healthcare professional before starting any exercise programme.',
                ),
              ],
              if (vm.saveState case UiError(:final message)) ...[
                const SizedBox(height: 16),
                InfoBanner(message, icon: Icons.error_outline),
                if (vm.ageReviewNeeded)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      key: const Key('review_terms_for_age'),
                      onPressed: () => _reviewTerms(vm),
                      child: const Text('Review Terms'),
                    ),
                  ),
              ],
              if (!vm.isEditing) ...[
                const SizedBox(height: 28),
                const SectionTitle('Account settings'),
                const SizedBox(height: 12),
                SettingsCard(
                  title: 'Change password',
                  subtitle: 'Update your password',
                  onTap: () =>
                      Navigator.of(context).pushNamed(Routes.changePassword),
                ),
                const SizedBox(height: 10),
                SettingsCard(
                  title: 'Device connection',
                  subtitle: 'Health Connect',
                  trailing: StatusPill(
                    vm.account?.healthSourceConnected == true
                        ? 'Connected'
                        : 'Not connected',
                    good: vm.account?.healthSourceConnected == true,
                  ),
                  onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Connecting Health Connect is part of the Health Monitoring module.',
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SettingsCard(
                  title: 'Log out',
                  subtitle: 'End this session',
                  danger: true,
                  onTap: () => _logout(vm),
                ),
                const SizedBox(height: 10),
                if (TestModeViewModel.available) ...[
                  Builder(
                    builder: (context) {
                      final tm = context.watch<TestModeViewModel>();
                      return SettingsCard(
                        key: const Key('test_mode_switch'),
                        title: 'Testing mode',
                        subtitle: 'Try any exercise now; nothing is saved',
                        trailing: Switch(
                          value: tm.enabled,
                          onChanged: tm.setEnabled,
                        ),
                        onTap: () => tm.setEnabled(!tm.enabled),
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                ],
                SettingsCard(
                  title: 'Terms of Use and Privacy Notice',
                  subtitle: 'Read what you agreed to',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const TermsView(readOnly: true),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SettingsCard(
                  title: 'Delete my account',
                  subtitle: 'Delete your account and all your data',
                  danger: true,
                  onTap: () => _deleteAccount(vm),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// The stats card in edit mode: text fields and a Male/Female choice, validated
  /// against the Table 3.3 ranges (FR100_045, FR100_049).
  Widget _editStats(ProfileViewModel vm) {
    final d = vm.draft;
    bool bad(String f) => vm.invalidFields.contains(f);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTokens.tint,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: NumberField(
                  label: 'Age (yrs)',
                  controller: _age,
                  forceError: bad('age'),
                  validator: (v) => FormValidators.intInRange(
                    v,
                    AppConstants.ageMin,
                    AppConstants.ageMax,
                    'Age',
                  ),
                  formatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: (v) {
                    final n = int.tryParse(v);
                    vm.updateDraft(age: n, clearAge: n == null);
                  },
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Gender',
                      style: TextStyle(color: AppTokens.inkMuted, fontSize: 15),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        for (final g in Gender.values) ...[
                          Expanded(
                            child: ProfileChip(
                              label: g.db,
                              selected: d?.gender == g,
                              onTap: () => vm.updateDraft(gender: g),
                              compact: true,
                            ),
                          ),
                          if (g != Gender.values.last) const SizedBox(width: 6),
                        ],
                      ],
                    ),
                    if (bad('gender'))
                      const Padding(
                        padding: EdgeInsets.only(top: 6),
                        child: Text(
                          'Please choose one.',
                          style: TextStyle(color: AppTokens.cta, fontSize: 13),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: NumberField(
                  label: 'Weight (kg)',
                  controller: _weight,
                  forceError: bad('weight'),
                  validator: (v) => FormValidators.doubleInRange(
                    v,
                    AppConstants.weightMin,
                    AppConstants.weightMax,
                    'Weight',
                  ),
                  formatters: [
                    FilteringTextInputFormatter.allow(
                      RegExp(r'^\d*\.?\d{0,1}'),
                    ),
                  ],
                  onChanged: (v) {
                    final n = double.tryParse(v);
                    vm.updateDraft(weightKg: n, clearWeight: n == null);
                  },
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: NumberField(
                  label: 'Height (cm)',
                  controller: _height,
                  forceError: bad('height'),
                  validator: (v) => FormValidators.doubleInRange(
                    v,
                    AppConstants.heightMin,
                    AppConstants.heightMax,
                    'Height',
                  ),
                  formatters: [
                    FilteringTextInputFormatter.allow(
                      RegExp(r'^\d*\.?\d{0,1}'),
                    ),
                  ],
                  onChanged: (v) {
                    final n = double.tryParse(v);
                    vm.updateDraft(heightCm: n, clearHeight: n == null);
                  },
                ),
              ),
            ],
          ),
          if (d != null && d.calculateBmi() > 0) ...[
            const Divider(height: 28, color: AppTokens.cardBorder),
            BmiRow(bmi: d.calculateBmi()),
          ],
        ],
      ),
    );
  }
}

class _EditBar extends StatelessWidget {
  final ProfileViewModel vm;
  final VoidCallback onCancel;
  final VoidCallback onSave;
  const _EditBar({
    required this.vm,
    required this.onCancel,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Container(
      padding: const EdgeInsets.fromLTRB(
        AppTokens.gutter,
        12,
        AppTokens.gutter,
        12,
      ),
      decoration: const BoxDecoration(
        color: AppTokens.surface,
        border: Border(top: BorderSide(color: AppTokens.cardBorder)),
      ),
      child: Row(
        children: [
          if (vm.profile != null) ...[
            Expanded(
              child: SizedBox(
                height: 52,
                child: OutlinedButton(
                  onPressed: vm.saveState is Loading ? null : onCancel,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTokens.ink,
                    side: const BorderSide(
                      color: AppTokens.outline,
                      width: 1.5,
                    ),
                    shape: const StadiumBorder(),
                    textStyle: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  child: const Text('Cancel'),
                ),
              ),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: SizedBox(
              height: 52,
              child: FilledButton(
                onPressed: vm.saveState is Loading ? null : onSave,
                style: FilledButton.styleFrom(
                  backgroundColor: AppTokens.cta,
                  foregroundColor: Colors.white,
                  shape: const StadiumBorder(),
                  textStyle: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                child: vm.saveState is Loading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Save'),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _LoadError extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _LoadError(this.message, this.onRetry);

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppTokens.ink, fontSize: 17),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: onRetry,
            style: FilledButton.styleFrom(
              backgroundColor: AppTokens.brandDeep,
              minimumSize: const Size(160, 52),
            ),
            child: const Text('Try again'),
          ),
        ],
      ),
    ),
  );
}

/// Short chip names from the Figma ("Left Leg Mobility", "Hypertension").
String conditionLabel(HealthCondition c) =>
    c.conditionCode == 'HYPERTENSION' ? 'Hypertension' : c.conditionName;

String limitationLabel(PhysicalLimitation l) =>
    l.limitationName.replaceAll(' Limitation', '');

/// The question under each selected condition, and what "Other" is (11 Oct).
/// A condition that needs a doctor's OK and is answered "No" holds back new
/// exercise plans.
class _ConditionAnswers extends StatelessWidget {
  final ProfileViewModel vm;
  final HealthProfile? profile;
  const _ConditionAnswers({required this.vm, required this.profile});

  @override
  Widget build(BuildContext context) {
    final asked = [
      for (final c in profile?.conditions ?? const <HealthCondition>[])
        if (c.statusQuestion != null || c.isOther) c,
    ];
    if (asked.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [for (final c in asked) _answer(c)],
      ),
    );
  }

  Widget _answer(HealthCondition c) {
    final unanswered =
        vm.isEditing && vm.unansweredConditions.contains(c.conditionId);
    return Container(
      key: ValueKey('condition-answer-${c.conditionId}'),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTokens.surface,
        borderRadius: BorderRadius.circular(AppTokens.radiusCard),
        border: Border.all(
          color: unanswered ? AppTokens.cta : AppTokens.cardBorder,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            conditionLabel(c),
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: AppTokens.ink,
            ),
          ),
          if (c.isOther) ...[
            const SizedBox(height: 6),
            if (vm.isEditing)
              TextFormField(
                key: ValueKey('condition-note-${c.conditionId}'),
                initialValue: c.note,
                maxLength: 100,
                decoration: const InputDecoration(
                  hintText: 'What is the condition?',
                ),
                onChanged: (v) => vm.setConditionNote(c.conditionId, v),
              )
            else
              Text(
                c.note ?? '',
                style: const TextStyle(color: AppTokens.inkMuted),
              ),
          ],
          if (c.statusQuestion case final question?) ...[
            const SizedBox(height: 6),
            Text(question, style: const TextStyle(color: AppTokens.ink)),
            const SizedBox(height: 6),
            if (vm.isEditing)
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('Yes'),
                    selected: !unanswered && c.controlled,
                    onSelected: (_) =>
                        vm.setConditionControlled(c.conditionId, true),
                  ),
                  ChoiceChip(
                    label: const Text('No'),
                    selected: !unanswered && !c.controlled,
                    onSelected: (_) =>
                        vm.setConditionControlled(c.conditionId, false),
                  ),
                ],
              )
            else
              Text(
                c.controlled ? 'Yes' : 'No',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: AppTokens.ink,
                ),
              ),
            if (!unanswered && c.blocksPlans)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  'New exercise plans wait until your doctor agrees.',
                  style: TextStyle(color: AppTokens.onWarn),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
