import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:physical_treatment_and_health_support_system/viewmodel/ui_state.dart';
import 'package:physical_treatment_and_health_support_system/core/constants/app_constants.dart';
import 'package:physical_treatment_and_health_support_system/core/routes/routes.dart';
import 'package:physical_treatment_and_health_support_system/view/login_view/terms_view.dart';
import 'package:physical_treatment_and_health_support_system/core/themes/design_tokens.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/lookups.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/profile_view_model/profile_view_model.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/test_mode_view_model/test_mode_view_model.dart';
import 'package:physical_treatment_and_health_support_system/view/profile_view/profile_section_view.dart';
import 'package:physical_treatment_and_health_support_system/view/profile_view/profile_setup_view.dart';
import 'package:physical_treatment_and_health_support_system/view/profile_view/widgets/profile_widgets.dart';
import 'package:physical_treatment_and_health_support_system/view/common/status_bar_strip.dart';
import 'package:physical_treatment_and_health_support_system/view/common/user_guide.dart';

/// My Profile (UC300; Figma "Profile Screen"). Used as the Profile tab and, for a
/// patient without a complete profile, as a standalone route after sign-in (FR100_035).
///
/// Since 17 Nov (Elwin) the screen shows only what the patient declared, one card for each
/// part of the profile, and each card has its own Edit that opens a page for that part
/// (profile_section_view.dart); the long lists are searched there. A patient without a
/// profile is taken through the parts one at a time (profile_setup_view.dart).
class ProfileView extends StatefulWidget {
  const ProfileView({super.key});

  @override
  State<ProfileView> createState() => _ProfileViewState();
}

class _ProfileViewState extends State<ProfileView> {
  /// Opened on its own after sign-in rather than as a tab of the shell.
  bool get _standalone =>
      ModalRoute.of(context)?.settings.name == Routes.healthProfile;

  /// Opens the page of one part. A saved change is confirmed here, on the screen the patient
  /// comes back to, and may change the diet plans (M700), so that is asked.
  Future<void> _edit(ProfileViewModel vm, ProfileSection section) async {
    vm.startEdit();
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ChangeNotifierProvider.value(
          value: vm,
          child: ProfileSectionView(section: section),
        ),
      ),
    );
    if (changed == null) {
      vm.cancelEdit(); // left without saving (FR100_052)
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text(Messages.profileSaved)),
    );
    if (changed && await _askDietPlanUpdate() && mounted) {
      await Navigator.of(context).pushNamed(Routes.refreshDietPlans);
    }
  }

  Future<bool> _askDietPlanUpdate() async =>
      await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('Update your diet plan?'),
          content: const SingleChildScrollView(child: Text(
            'Your profile has been saved. Update your daily plan and saved weekly plan using the new profile? '
            'Foods may change. Your logged meal history stays. Choose Not now to keep your plans.',
          )),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Not now')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Update plans')),
          ],
        ),
      ) ?? false;

  Future<void> _logout(ProfileViewModel vm) async {
    if (!await confirmProfileAction(
      context,
      Messages.confirmLogout,
      'Log out',
      danger: true,
    )) {
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
    if (!await confirmProfileAction(
      context,
      Messages.confirmDeleteAccount,
      'Delete',
      danger: true,
    )) {
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
    final firstLoad =
        vm.loadState is Loading && vm.profile == null && vm.draft == null;
    // Straight after sign-in nothing is beneath this screen: Back goes on to Home (the profile
    // can be completed later; Home asks for it) instead of closing the app.
    final firstScreen = _standalone && !Navigator.of(context).canPop();
    if (!firstLoad && vm.isSetup) {
      return ProfileSetupView(firstScreen: firstScreen);
    }
    return PopScope(
      canPop: !firstScreen,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        Navigator.of(context).pushNamedAndRemoveUntil(Routes.home, (_) => false);
      },
      child: Scaffold(
        appBar: const StatusBarStrip(),
        backgroundColor: AppTokens.screenBackground,
        body: switch (vm.loadState) {
          _ when firstLoad => const Center(
            child: CircularProgressIndicator(color: AppTokens.brandDeep),
          ),
          UiError(:final message) when vm.profile == null =>
            _LoadError(message, vm.loadProfile),
          _ => _body(vm),
        },
      ),
    );
  }

  /// Device connection (FR100_062 to FR100_065): connect to Health Connect, or revoke it.
  Future<void> _healthSource(ProfileViewModel vm) async {
    final last = vm.healthLastSync;
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Health Connect'),
        content: Text(
          vm.healthConnected
              ? 'Connected. ${last == null ? 'No import yet.' : 'Last import ${last.day}/${last.month} '
                    '${last.hour.toString().padLeft(2, '0')}:${last.minute.toString().padLeft(2, '0')}.'}\n\n'
                    'Disconnect to stop importing blood pressure, glucose and weight readings.'
              : 'Allow HealthGuide to read your blood pressure, blood glucose and weight readings '
                    'from Health Connect. Nothing is written to Health Connect.',
          style: const TextStyle(fontSize: 16),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(vm.healthConnected ? 'Disconnect' : 'Connect'),
          ),
        ],
      ),
    );
    if (yes != true) return;
    vm.healthConnected ? await vm.disconnectHealthSource() : await vm.connectHealthSource();
    final m = vm.healthMessage;
    if (m != null && mounted) {
      final fix = !vm.healthConnected && vm.healthFix != null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(m),
          duration: Duration(seconds: fix ? 10 : 4),
          action: fix ? SnackBarAction(label: 'Fix', onPressed: vm.fixHealthSource) : null,
        ),
      );
    }
  }

  Widget _body(ProfileViewModel vm) {
    final p = vm.profile;
    final risk = p?.assignRiskLevel();
    final top = MediaQuery.paddingOf(context).top;
    const gap = SizedBox(height: 24);
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
              // Right under the risk level it explains (17 Nov; it was below the food list).
              if (risk == RiskLevel.medium || risk == RiskLevel.high) ...[
                InfoBanner(
                  risk == RiskLevel.high
                      ? Messages
                            .highRiskAdvisory // FR100_058
                      : 'Consult a healthcare professional before starting any exercise programme.',
                ),
                gap,
              ],
              SectionHeader(
                'Body details',
                what: 'body details',
                editKey: const Key('edit_body'),
                onEdit: () => _edit(vm, ProfileSection.body),
              ),
              const SizedBox(height: 8),
              StatsCard(profile: p),
              gap,
              SectionHeader(
                'Pre-existing health conditions',
                what: 'health conditions',
                editKey: const Key('edit_conditions'),
                onEdit: () => _edit(vm, ProfileSection.conditions),
              ),
              const SizedBox(height: 8),
              _DeclaredConditions(p?.conditions ?? const []),
              gap,
              SectionHeader(
                'Physical limitations',
                what: 'physical limitations',
                editKey: const Key('edit_limitations'),
                onEdit: () => _edit(vm, ProfileSection.limitations),
              ),
              const SizedBox(height: 8),
              _DeclaredTags(
                key: const Key('declared_limitations'),
                [for (final l in p?.limitations ?? const <PhysicalLimitation>[]) limitationLabel(l)],
                none: 'None',
              ),
              gap,
              // "Cannot eat" (UI Design, Profile Screen): food names, whatever the reason
              // (allergy, religion, dislike). Dishes that contain one are left out (M700).
              SectionHeader(
                'Foods I cannot eat',
                what: 'foods I cannot eat',
                editKey: const Key('edit_foods'),
                onEdit: () => _edit(vm, ProfileSection.foods),
              ),
              const SizedBox(height: 8),
              _DeclaredTags(
                key: const Key('declared_foods'),
                [for (final r in p?.restrictions ?? const <DietaryRestriction>[]) r.restrictionName],
                none: 'None declared',
                note: 'Dishes with these are marked Not Suitable and never planned for you.',
              ),
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
                  vm.healthConnected ? 'Connected' : 'Not connected',
                  good: vm.healthConnected,
                ),
                onTap: () => _healthSource(vm),
              ),
              const SizedBox(height: 10),
              SettingsCard(
                title: 'Picture guides',
                subtitle: 'Show the how-to guides again on each screen',
                onTap: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  if (await showAllGuidesAgain(context)) {
                    messenger.showSnackBar(
                      const SnackBar(content: Text('The guides will show again when you open each screen.')),
                    );
                  }
                },
              ),
              const SizedBox(height: 10),
              SettingsCard(
                title: 'Terms of Use and Privacy Notice',
                subtitle: 'Read what you agreed to',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const TermsView(readOnly: true),
                  ),
                ),
              ),
              // For the team, not for everyday use: kept apart from the patient's own settings.
              const SizedBox(height: 28),
              const SectionTitle('Advanced'),
              const SizedBox(height: 12),
              SettingsCard(
                title: 'AI server',
                subtitle: 'Address of the AI server',
                onTap: () =>
                    Navigator.of(context).pushNamed(Routes.serverSettings),
              ),
              if (TestModeViewModel.available) ...[
                const SizedBox(height: 10),
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
                        activeTrackColor: AppTokens.brandDeep,
                        inactiveTrackColor: AppTokens.tint,
                        inactiveThumbColor: AppTokens.outline,
                        trackOutlineColor: const WidgetStatePropertyAll(
                          AppTokens.outline,
                        ),
                      ),
                      onTap: () => tm.setEnabled(!tm.enabled),
                    );
                  },
                ),
              ],
              // Leaving and deleting come last.
              const SizedBox(height: 28),
              SettingsCard(
                title: 'Log out',
                subtitle: 'End this session',
                danger: true,
                onTap: () => _logout(vm),
              ),
              const SizedBox(height: 10),
              SettingsCard(
                title: 'Delete my account',
                subtitle: 'Delete your account and all your data',
                danger: true,
                onTap: () => _deleteAccount(vm),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The conditions the patient declared, each with the answer to its question (11 Oct); a
/// "No" to one that needs a doctor's OK holds back new exercise plans, and says so.
class _DeclaredConditions extends StatelessWidget {
  final List<HealthCondition> conditions;
  const _DeclaredConditions(this.conditions);

  @override
  Widget build(BuildContext context) => DeclaredCard(
    key: const Key('declared_conditions'),
    child: conditions.isEmpty
        ? const NoneDeclared('None declared')
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final (i, c) in conditions.indexed) ...[
                if (i > 0)
                  const Divider(height: 24, color: AppTokens.cardBorder),
                _condition(c),
              ],
            ],
          ),
  );

  Widget _condition(HealthCondition c) => Column(
    key: ValueKey('condition-answer-${c.conditionId}'),
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        conditionLabel(c),
        style: const TextStyle(
          color: AppTokens.ink,
          fontSize: 17,
          fontWeight: FontWeight.w600,
        ),
      ),
      if (c.isOther && (c.note ?? '').isNotEmpty) ...[
        const SizedBox(height: 2),
        Text(
          c.note!,
          style: const TextStyle(color: AppTokens.inkMuted, fontSize: 15),
        ),
      ],
      if (c.statusQuestion case final question?) ...[
        const SizedBox(height: 4),
        Text.rich(
          TextSpan(
            text: '$question ',
            children: [
              TextSpan(
                text: c.controlled ? 'Yes' : 'No',
                style: const TextStyle(
                  color: AppTokens.ink,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          style: const TextStyle(color: AppTokens.inkMuted, fontSize: 15),
        ),
        if (c.blocksPlans)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text(
              plansWaitForDoctor,
              style: TextStyle(color: AppTokens.onWarn, fontSize: 15),
            ),
          ),
      ],
    ],
  );
}

/// What the patient declared in a part, as labels; [none] when nothing was.
class _DeclaredTags extends StatelessWidget {
  final List<String> labels;
  final String none;
  final String? note;
  const _DeclaredTags(this.labels, {super.key, required this.none, this.note});

  @override
  Widget build(BuildContext context) => DeclaredCard(
    child: labels.isEmpty
        ? NoneDeclared(none)
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [for (final l in labels) ProfileTag(l)],
              ),
              if (note case final text?) ...[
                const SizedBox(height: 10),
                Text(
                  text,
                  style: const TextStyle(
                    color: AppTokens.inkMuted,
                    fontSize: 14,
                  ),
                ),
              ],
            ],
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
