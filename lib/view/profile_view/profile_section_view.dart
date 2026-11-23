import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:physical_treatment_and_health_support_system/core/constants/app_constants.dart';
import 'package:physical_treatment_and_health_support_system/core/routes/routes.dart';
import 'package:physical_treatment_and_health_support_system/core/themes/design_tokens.dart';
import 'package:physical_treatment_and_health_support_system/view/profile_view/widgets/profile_editors.dart';
import 'package:physical_treatment_and_health_support_system/view/profile_view/widgets/profile_widgets.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/auth_view_model/auth_view_model.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/profile_view_model/profile_view_model.dart';

/// The Terms were accepted for another age group (14 Oct): they are shown again for the age
/// typed. True when the patient accepted them.
Future<bool> reviewTermsForAge(BuildContext context, ProfileViewModel vm) async {
  final age = vm.draft?.age;
  if (age == null) return false;
  context.read<AuthViewModel>().startAgeReview(age);
  return await Navigator.of(context).pushNamed<bool>(Routes.terms) == true;
}

/// The page behind a card's Edit on the profile screen (Elwin, 17 Nov): one part of the
/// profile, with its own Cancel and Save. The profile screen starts the edit before opening
/// it. Closes with true when a change was saved, false when Save changed nothing, and without
/// a value when the patient left without saving.
class ProfileSectionView extends StatefulWidget {
  final ProfileSection section;
  const ProfileSectionView({super.key, required this.section});

  @override
  State<ProfileSectionView> createState() => _ProfileSectionViewState();
}

class _ProfileSectionViewState extends State<ProfileSectionView> {
  Future<void> _save(ProfileViewModel vm) async {
    FocusScope.of(context).unfocus();
    final changed = vm.hasUnsavedChanges;
    final ok = await vm.saveProfile();
    if (ok && mounted) Navigator.of(context).pop(changed);
  }

  /// Cancel, the arrow and the phone's Back: asks first when something was changed.
  Future<void> _leave(ProfileViewModel vm) async {
    if (vm.hasUnsavedChanges &&
        !await confirmProfileAction(
          context,
          Messages.discardChanges,
          'Discard',
          danger: true,
        )) {
      return;
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ProfileViewModel>();
    return PopScope(
      canPop: !vm.hasUnsavedChanges,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave(vm);
      },
      child: Scaffold(
        backgroundColor: AppTokens.screenBackground,
        appBar: AppBar(
          backgroundColor: AppTokens.brandDeep,
          foregroundColor: Colors.white,
          surfaceTintColor: AppTokens.brandDeep,
          systemOverlayStyle: SystemUiOverlayStyle.light,
          elevation: 0,
          scrolledUnderElevation: 0,
          leading: IconButton(
            tooltip: 'Back',
            icon: const Icon(Icons.arrow_back),
            onPressed: () => _leave(vm),
          ),
          title: Text(
            sectionTitle(widget.section),
            style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
          ),
        ),
        bottomNavigationBar: ProfileEditBar(
          vm: vm,
          secondary: 'Cancel',
          onSecondary: () => _leave(vm),
          primary: 'Save',
          onPrimary: () => _save(vm),
          onReviewTerms: () async {
            if (await reviewTermsForAge(context, vm) && mounted) await _save(vm);
          },
        ),
        body: sectionEditor(widget.section, vm),
      ),
    );
  }
}
