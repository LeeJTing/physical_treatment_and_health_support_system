import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:physical_treatment_and_health_support_system/core/constants/app_constants.dart';
import 'package:physical_treatment_and_health_support_system/core/themes/design_tokens.dart';
import 'package:physical_treatment_and_health_support_system/core/utils/form_validators.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/lookups.dart';
import 'package:physical_treatment_and_health_support_system/view/profile_view/widgets/profile_widgets.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/profile_view_model/profile_view_model.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/ui_state.dart';

// What the patient changes in each part of the profile (Elwin, 17 Nov): the same four editors
// are used by the page behind each card's Edit (profile_section_view.dart) and by the steps of
// the first-time setup (profile_setup_view.dart). Each fills the space it is given and scrolls
// by itself, so a search box stays in view above its list.

const _pagePadding = EdgeInsets.fromLTRB(AppTokens.gutter, 16, AppTokens.gutter, 24);

/// The title of a part, as its page and its setup step show it.
String sectionTitle(ProfileSection s) => switch (s) {
  ProfileSection.body => 'Body details',
  ProfileSection.conditions => 'Health conditions',
  ProfileSection.limitations => 'Physical limitations',
  ProfileSection.foods => 'Foods I cannot eat',
};

/// The editor of a part.
Widget sectionEditor(ProfileSection s, ProfileViewModel vm, {Widget? leading}) =>
    switch (s) {
      ProfileSection.body => BodyDetailsEditor(vm: vm, leading: leading),
      ProfileSection.conditions => ConditionPicker(vm: vm),
      ProfileSection.limitations => LimitationPicker(vm: vm),
      ProfileSection.foods => FoodPicker(vm: vm),
    };

/// Age, gender, weight and height, checked against the Table 3.3 ranges (FR100_045,
/// FR100_049), with the BMI they give. [leading] is shown above the fields.
class BodyDetailsEditor extends StatefulWidget {
  final ProfileViewModel vm;
  final Widget? leading;
  const BodyDetailsEditor({super.key, required this.vm, this.leading});

  @override
  State<BodyDetailsEditor> createState() => _BodyDetailsEditorState();
}

class _BodyDetailsEditorState extends State<BodyDetailsEditor> {
  static String _num(num? v) =>
      v == null ? '' : (v % 1 == 0 ? v.toInt().toString() : v.toString());

  late final _age = TextEditingController(text: _num(widget.vm.draft?.age));
  late final _weight = TextEditingController(
    text: _num(widget.vm.draft?.weightKg),
  );
  late final _height = TextEditingController(
    text: _num(widget.vm.draft?.heightCm),
  );

  @override
  void dispose() {
    _age.dispose();
    _weight.dispose();
    _height.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = widget.vm;
    final d = vm.draft;
    if (d == null) return const SizedBox.shrink();
    bool bad(String f) => vm.invalidFields.contains(f);
    final decimal = [
      FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,1}')),
    ];
    return ListView(
      padding: _pagePadding,
      children: [
        if (widget.leading case final leading?) ...[
          leading,
          const SizedBox(height: 16),
        ],
        Container(
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
                          style: TextStyle(
                            color: AppTokens.inkMuted,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            for (final g in Gender.values) ...[
                              Expanded(
                                child: ProfileChip(
                                  label: g.db,
                                  selected: d.gender == g,
                                  onTap: () => vm.updateDraft(gender: g),
                                  compact: true,
                                ),
                              ),
                              if (g != Gender.values.last)
                                const SizedBox(width: 6),
                            ],
                          ],
                        ),
                        if (bad('gender'))
                          const Padding(
                            padding: EdgeInsets.only(top: 6),
                            child: Text(
                              'Please choose one.',
                              style: TextStyle(
                                color: AppTokens.cta,
                                fontSize: 13,
                              ),
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
                      formatters: decimal,
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
                      formatters: decimal,
                      onChanged: (v) {
                        final n = double.tryParse(v);
                        vm.updateDraft(heightCm: n, clearHeight: n == null);
                      },
                    ),
                  ),
                ],
              ),
              if (d.calculateBmi() > 0) ...[
                const Divider(height: 28, color: AppTokens.cardBorder),
                BmiRow(bmi: d.calculateBmi()),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// The search box above a long list. It stays in view while the list scrolls.
class ProfileSearchBox extends StatefulWidget {
  final String hint;
  final ValueChanged<String> onChanged;
  const ProfileSearchBox({super.key, required this.hint, required this.onChanged});

  @override
  State<ProfileSearchBox> createState() => _ProfileSearchBoxState();
}

class _ProfileSearchBoxState extends State<ProfileSearchBox> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  static OutlineInputBorder _border(Color c, [double w = 1.5]) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppTokens.radiusField),
        borderSide: BorderSide(color: c, width: w),
      );

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(AppTokens.gutter, 12, AppTokens.gutter, 4),
    child: TextField(
      key: const Key('profile_search'),
      controller: _text,
      textInputAction: TextInputAction.search,
      autocorrect: false,
      onChanged: (v) {
        setState(() {});
        widget.onChanged(v);
      },
      style: const TextStyle(color: AppTokens.ink, fontSize: 17),
      cursorColor: AppTokens.brandDeep,
      decoration: InputDecoration(
        hintText: widget.hint,
        hintStyle: const TextStyle(color: AppTokens.inkMuted, fontSize: 17),
        filled: true,
        fillColor: AppTokens.surface,
        prefixIcon: const Icon(Icons.search, color: AppTokens.inkMuted),
        suffixIcon: _text.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'Clear search',
                icon: const Icon(Icons.close, color: AppTokens.inkMuted),
                onPressed: () {
                  _text.clear();
                  setState(() {});
                  widget.onChanged('');
                },
              ),
        contentPadding: const EdgeInsets.symmetric(vertical: 14),
        enabledBorder: _border(AppTokens.outline),
        focusedBorder: _border(AppTokens.brandDeep, 2),
      ),
    ),
  );
}

/// One choice of a selection page: the whole row is the button, with a tick when chosen.
class PickRow extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const PickRow({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Semantics(
      button: true,
      checked: selected,
      child: Material(
        color: selected ? AppTokens.tint : AppTokens.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusField),
          side: BorderSide(
            color: selected ? AppTokens.brandDeep : AppTokens.cardBorder,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTokens.radiusField),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 52),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      style: const TextStyle(
                        color: AppTokens.ink,
                        fontSize: 17,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Icon(
                    selected ? Icons.check_circle : Icons.radio_button_unchecked,
                    color: selected ? AppTokens.brandDeep : AppTokens.outline,
                    size: 26,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// The line above a list: what to do, and how many are ticked.
class _Intro extends StatelessWidget {
  final String text;
  final int? chosen;
  const _Intro(this.text, {this.chosen});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          text,
          style: const TextStyle(color: AppTokens.inkMuted, fontSize: 15),
        ),
        if (chosen case final n?) ...[
          const SizedBox(height: 6),
          Text(
            n == 0 ? 'None selected' : '$n selected',
            key: const Key('profile_selected_count'),
            style: const TextStyle(
              color: AppTokens.brandDeepAccent,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    ),
  );
}

class _NoMatch extends StatelessWidget {
  final String query;
  const _NoMatch(this.query);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 24),
    child: Text(
      'Nothing matches "${query.trim()}". Check the spelling or try a shorter word.',
      textAlign: TextAlign.center,
      style: const TextStyle(color: AppTokens.inkMuted, fontSize: 16),
    ),
  );
}

/// The health conditions, with a search box. A ticked condition that has a question shows
/// it right under its row (11 Oct); a "No" to one that needs a doctor's OK holds back new
/// exercise plans.
class ConditionPicker extends StatefulWidget {
  final ProfileViewModel vm;
  const ConditionPicker({super.key, required this.vm});

  @override
  State<ConditionPicker> createState() => _ConditionPickerState();
}

class _ConditionPickerState extends State<ConditionPicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final vm = widget.vm;
    final d = vm.draft;
    if (d == null) return const SizedBox.shrink();
    final shown = vm.conditionsMatching(_query);
    // A condition saved before it left the list ("Other"): kept, with its note.
    final unlisted = [
      for (final c in d.conditions)
        if (!vm.conditions.contains(c)) c,
    ];
    return Column(
      children: [
        ProfileSearchBox(
          hint: 'Search conditions',
          onChanged: (v) => setState(() => _query = v),
        ),
        Expanded(
          child: ListView(
            padding: _pagePadding,
            children: [
              _Intro(
                'Tick every condition you have. Leave all unticked if you have none.',
                chosen: d.conditions.length,
              ),
              for (final c in shown) ...[
                PickRow(
                  label: conditionLabel(c),
                  selected: d.conditions.contains(c),
                  onTap: () => vm.toggleCondition(c.conditionId),
                ),
                if (d.conditions.where((x) => x == c).firstOrNull case final mine?
                    when mine.statusQuestion != null)
                  ConditionQuestion(vm: vm, condition: mine),
              ],
              for (final c in unlisted) ConditionQuestion(vm: vm, condition: c),
              if (shown.isEmpty) _NoMatch(_query),
            ],
          ),
        ),
      ],
    );
  }
}

/// The question under a ticked condition, and what "Other" is.
class ConditionQuestion extends StatelessWidget {
  final ProfileViewModel vm;
  final HealthCondition condition;
  const ConditionQuestion({super.key, required this.vm, required this.condition});

  @override
  Widget build(BuildContext context) {
    final c = condition;
    final unanswered = vm.unansweredConditions.contains(c.conditionId);
    // Outlined in red once Next or Save was refused for it.
    final missed = unanswered && vm.saveState is UiError;
    return Container(
      key: ValueKey('condition-answer-${c.conditionId}'),
      margin: const EdgeInsets.only(left: 16, bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTokens.surface,
        borderRadius: BorderRadius.circular(AppTokens.radiusCard),
        border: Border.all(
          color: missed ? AppTokens.cta : AppTokens.cardBorder,
          width: missed ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (c.isOther) ...[
            Text(
              conditionLabel(c),
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: AppTokens.ink,
              ),
            ),
            const SizedBox(height: 6),
            TextFormField(
              key: ValueKey('condition-note-${c.conditionId}'),
              initialValue: c.note,
              maxLength: 100,
              decoration: const InputDecoration(
                hintText: 'What is the condition?',
              ),
              onChanged: (v) => vm.setConditionNote(c.conditionId, v),
            ),
          ],
          if (c.statusQuestion case final question?) ...[
            Text(
              question,
              style: const TextStyle(color: AppTokens.ink, fontSize: 16),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 10,
              children: [
                for (final (text, yes) in const [('Yes', true), ('No', false)])
                  _AnswerChip(
                    text,
                    selected: !unanswered && c.controlled == yes,
                    onTap: () => vm.setConditionControlled(c.conditionId, yes),
                  ),
              ],
            ),
            if (!unanswered && c.blocksPlans)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  plansWaitForDoctor,
                  style: TextStyle(color: AppTokens.onWarn),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// "Yes" or "No" under a condition's question, in the app's colours and large enough to read
/// and to tap.
class _AnswerChip extends StatelessWidget {
  final String text;
  final bool selected;
  final VoidCallback onTap;
  const _AnswerChip(this.text, {required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => ChoiceChip(
    label: Text(text),
    selected: selected,
    showCheckmark: false,
    onSelected: (_) => onTap(),
    labelStyle: TextStyle(
      color: selected ? Colors.white : AppTokens.ink,
      fontSize: 16,
      fontWeight: FontWeight.w600,
    ),
    labelPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
    backgroundColor: AppTokens.surface,
    selectedColor: AppTokens.brandDeep,
    shape: StadiumBorder(
      side: BorderSide(
        color: selected ? AppTokens.brandDeep : AppTokens.outline,
        width: 1.5,
      ),
    ),
  );
}

/// The physical limitations: five choices and "None", so no search box.
class LimitationPicker extends StatelessWidget {
  final ProfileViewModel vm;
  const LimitationPicker({super.key, required this.vm});

  @override
  Widget build(BuildContext context) {
    final d = vm.draft;
    if (d == null) return const SizedBox.shrink();
    return ListView(
      padding: _pagePadding,
      children: [
        const _Intro(
          'Tick each one that applies to you. Exercises for that part of the body are left out '
          'of your plans.',
        ),
        for (final l in vm.limitations)
          PickRow(
            label: limitationLabel(l),
            selected: d.limitations.contains(l),
            onTap: () => vm.toggleLimitation(l.limitationId),
          ),
        PickRow(
          label: 'None',
          selected: d.limitations.isEmpty,
          onTap: vm.clearLimitations,
        ),
      ],
    );
  }
}

/// "Cannot eat" (UI Design, Profile Screen): food names under their headings, with a search
/// box. Each food's recipe lists the names it contains, so the diet suitability rules and
/// plans (M700) leave those dishes out.
class FoodPicker extends StatefulWidget {
  final ProfileViewModel vm;
  const FoodPicker({super.key, required this.vm});

  @override
  State<FoodPicker> createState() => _FoodPickerState();
}

class _FoodPickerState extends State<FoodPicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final vm = widget.vm;
    final d = vm.draft;
    if (d == null) return const SizedBox.shrink();
    final groups = vm.restrictionGroupsMatching(_query);
    return Column(
      children: [
        ProfileSearchBox(
          hint: 'Search foods',
          onChanged: (v) => setState(() => _query = v),
        ),
        Expanded(
          child: ListView(
            padding: _pagePadding,
            children: [
              _Intro(
                'Tick each food you cannot eat. Dishes that contain it are marked Not Suitable '
                'and never planned for you.',
                chosen: d.restrictions.length,
              ),
              for (final (group, items) in groups) ...[
                if (group != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6, bottom: 8),
                    child: Text(
                      group,
                      style: const TextStyle(
                        color: AppTokens.ink,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                for (final r in items)
                  PickRow(
                    label: r.restrictionName,
                    selected: d.restrictions.contains(r),
                    onTap: () => vm.toggleRestriction(r.restrictionId),
                  ),
              ],
              if (groups.isEmpty) _NoMatch(_query),
            ],
          ),
        ),
      ],
    );
  }
}

/// The bar at the bottom of an edit page or setup step. A refused Save or Next says why right
/// above the buttons (audit, 23 Oct): in a long list the message would be out of sight of both
/// the button and the fields it is about.
class ProfileEditBar extends StatelessWidget {
  final ProfileViewModel vm;
  final String primary;
  final VoidCallback onPrimary;
  final String? secondary;
  final VoidCallback? onSecondary;
  final VoidCallback onReviewTerms;
  const ProfileEditBar({
    super.key,
    required this.vm,
    required this.primary,
    required this.onPrimary,
    required this.onReviewTerms,
    this.secondary,
    this.onSecondary,
  });

  @override
  Widget build(BuildContext context) {
    final busy = vm.saveState is Loading;
    const label = TextStyle(fontSize: 17, fontWeight: FontWeight.w600);
    return SafeArea(
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (vm.saveState case UiError(:final message)) ...[
              InfoBanner(message, icon: Icons.error_outline),
              if (vm.ageReviewNeeded)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    key: const Key('review_terms_for_age'),
                    onPressed: onReviewTerms,
                    child: const Text('Review Terms'),
                  ),
                ),
              const SizedBox(height: 10),
            ],
            Row(
              children: [
                if (secondary case final text?) ...[
                  Expanded(
                    child: SizedBox(
                      height: 52,
                      child: OutlinedButton(
                        onPressed: busy ? null : onSecondary,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTokens.ink,
                          side: const BorderSide(
                            color: AppTokens.outline,
                            width: 1.5,
                          ),
                          shape: const StadiumBorder(),
                          textStyle: label,
                        ),
                        child: Text(text),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: SizedBox(
                    height: 52,
                    child: FilledButton(
                      onPressed: busy ? null : onPrimary,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTokens.cta,
                        foregroundColor: Colors.white,
                        shape: const StadiumBorder(),
                        textStyle: label,
                      ),
                      child: busy
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Colors.white,
                              ),
                            )
                          : Text(primary),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
