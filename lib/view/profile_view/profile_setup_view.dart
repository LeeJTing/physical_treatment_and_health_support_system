import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:physical_treatment_and_health_support_system/core/constants/app_constants.dart';
import 'package:physical_treatment_and_health_support_system/core/routes/routes.dart';
import 'package:physical_treatment_and_health_support_system/core/themes/design_tokens.dart';
import 'package:physical_treatment_and_health_support_system/view/common/status_bar_strip.dart';
import 'package:physical_treatment_and_health_support_system/view/profile_view/profile_section_view.dart';
import 'package:physical_treatment_and_health_support_system/view/profile_view/widgets/profile_editors.dart';
import 'package:physical_treatment_and_health_support_system/view/profile_view/widgets/profile_widgets.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/profile_view_model/profile_view_model.dart';

/// The profile of a patient who has none yet (FR100_035), one part at a time (Elwin, 17 Nov):
/// body details, health conditions, physical limitations, foods. Next checks the part before
/// moving on, so the questions about safety cannot be passed by; the last step saves it all.
/// [firstScreen]: opened straight after sign-in with nothing beneath it, so saving and Back
/// both go on to Home.
class ProfileSetupView extends StatefulWidget {
  final bool firstScreen;
  const ProfileSetupView({super.key, required this.firstScreen});

  @override
  State<ProfileSetupView> createState() => _ProfileSetupViewState();
}

class _ProfileSetupViewState extends State<ProfileSetupView> {
  static const _steps = ProfileSection.values;
  int _step = 0;

  ProfileSection get _section => _steps[_step];
  bool get _last => _step == _steps.length - 1;

  Future<void> _next(ProfileViewModel vm) async {
    FocusScope.of(context).unfocus();
    if (!await vm.checkSection(_section) || !mounted) return;
    if (!_last) {
      setState(() => _step++);
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    // Once saved, the profile screen replaces this one: nothing of it is used after that.
    final firstScreen = widget.firstScreen;
    if (!await vm.saveProfile()) return;
    messenger.showSnackBar(
      const SnackBar(content: Text(Messages.profileSaved)),
    );
    // Reached straight after sign-in (nothing to go back to): continue into the app.
    if (firstScreen) {
      nav.pushNamedAndRemoveUntil(Routes.home, (_) => false);
    }
  }

  /// Back on a later step shows the step before. On the first step it leaves the setup:
  /// after asking when something was entered, and on to Home when nothing is beneath this
  /// screen (audit, 24 Oct: Discard closed the only screen and left the app black).
  Future<void> _back(ProfileViewModel vm) async {
    if (_step > 0) {
      vm.clearSaveMessage();
      setState(() => _step--);
      return;
    }
    // Read before the question: while its dialog is open there is a route to pop.
    final firstScreen = widget.firstScreen;
    if (vm.hasUnsavedChanges &&
        !await confirmProfileAction(
          context,
          Messages.discardChanges,
          'Discard',
          danger: true,
        )) {
      return;
    }
    if (!mounted) return;
    vm.cancelEdit();
    final nav = Navigator.of(context);
    if (firstScreen) {
      nav.pushNamedAndRemoveUntil(Routes.home, (_) => false);
    } else if (nav.canPop()) {
      nav.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ProfileViewModel>();
    return PopScope(
      canPop: _step == 0 && !vm.hasUnsavedChanges && !widget.firstScreen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back(vm);
      },
      child: Scaffold(
        appBar: const StatusBarStrip(),
        backgroundColor: AppTokens.screenBackground,
        bottomNavigationBar: ProfileEditBar(
          vm: vm,
          secondary: _step == 0 ? null : 'Back',
          onSecondary: () => _back(vm),
          primary: _last ? 'Save' : 'Next',
          onPrimary: () => _next(vm),
          onReviewTerms: () async {
            if (await reviewTermsForAge(context, vm) && mounted) await _next(vm);
          },
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              color: AppTokens.brandDeep,
              // The strip above already covers the status bar.
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'My Profile',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 30,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Step ${_step + 1} of ${_steps.length}: ${sectionTitle(_section)}',
                    key: const Key('profile_setup_step'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: (_step + 1) / _steps.length,
                      minHeight: 6,
                      backgroundColor: AppTokens.onBrandMuted.withValues(
                        alpha: 0.35,
                      ),
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              // A key for each step, so its editor starts with its own state; and for the
              // draft, so Discard (a new, empty draft) also empties the fields.
              child: KeyedSubtree(
                key: ValueKey((_section, vm.draft?.profileId)),
                child: sectionEditor(
                  _section,
                  vm,
                  leading: const InfoBanner(
                    Messages.profileNotConfigured,
                    icon: Icons.info_outline,
                    tone: BannerTone.info,
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
