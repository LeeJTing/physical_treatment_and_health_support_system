import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:physical_treatment_and_health_support_system/core/constants/app_constants.dart';
import 'package:physical_treatment_and_health_support_system/core/themes/design_tokens.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/food_item.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/meal_log.dart';
import 'package:physical_treatment_and_health_support_system/view/common/future_sheet.dart';
import 'package:physical_treatment_and_health_support_system/view/common/user_guide.dart';
import 'package:physical_treatment_and_health_support_system/view/diet_view/food_search_sheet.dart';
import 'package:physical_treatment_and_health_support_system/view/diet_view/widgets/diet_widgets.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/meal_log_view_model/meal_log_view_model.dart';
import 'package:physical_treatment_and_health_support_system/view/common/tidy_text.dart';

/// Meal Result (UC800 BF-12 to BF-20; Figma "Meal Result"): each identified food with its
/// confidence, portion and nutrients, its verdict coded with a glyph, a word and a colour, the
/// reason in the patient's words and a safer choice; the patient corrects a food, adjusts a portion
/// or adds one, then saves. While the photo is identified it shows the photo with the progress
/// and photo tips. Save closes the screen at once and returns the save still in progress (a
/// `Future<bool>`); Cancel returns false.
class MealResultView extends StatefulWidget {
  const MealResultView({super.key});

  @override
  State<MealResultView> createState() => _MealResultViewState();
}

class _MealResultViewState extends State<MealResultView> {
  void _snack(String m) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(backgroundColor: m.startsWith('Not suitable:') ? AppTokens.danger : null, content: Text(m)));

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<MealLogViewModel>();
    final msg = vm.takeMessage();
    if (msg != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _snack(msg);
      });
    }
    final d = vm.draft;
    // The photo could not be used (A1): back to Diet, where the message is shown.
    if (vm.step == MealStep.idle && d == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && ModalRoute.of(context)?.isCurrent == true) Navigator.of(context).pop(false);
      });
    }
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        // Leaving without saving discards the photo and the draft (A7); a save already started
        // carries on.
        if (didPop && (vm.step == MealStep.review || vm.step == MealStep.recognising)) vm.cancel();
      },
      child: Scaffold(
        backgroundColor: AppTokens.screenBackground,
        appBar: AppBar(
          title: const OneLineText('Your meal'),
          backgroundColor: AppTokens.brandDeep,
          foregroundColor: Colors.white,
          actions: const [HelpButton(guide: Guides.diet)],
        ),
        body: switch (vm.step) {
          MealStep.recognising => _RecognisingView(photo: vm.draftImage ?? vm.pendingPhoto, onManual: vm.enterManually),
          _ when d == null => const Center(child: Text('No meal to\u00A0review.')),
          _ => _review(vm, d),
        },
        bottomNavigationBar: d == null || vm.step == MealStep.recognising
            ? null
            : SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(56),
                            shape: const StadiumBorder(),
                          ),
                          onPressed: () {
                            vm.cancel();
                            Navigator.of(context).pop(false);
                          },
                          child: const OneLineText(
                            'Cancel',
                            alignment: Alignment.center,
                            style: TextStyle(fontSize: 17),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(56),
                            backgroundColor: AppTokens.cta,
                            shape: const StadiumBorder(),
                          ),
                          onPressed: d.items.isEmpty || vm.step == MealStep.saving
                              ? null
                              : () {
                                  // UI first: the meal appears on Diet at once while it is saved.
                                  final pending = vm.confirmMeal();
                                  Navigator.of(context).pop(pending);
                                },
                          child: vm.step == MealStep.saving
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(strokeWidth: 2.5),
                                )
                              : const OneLineText(
                                  'Save',
                                  alignment: Alignment.center,
                                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _review(MealLogViewModel vm, MealLog d) {
    final r = vm.lastResult;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        const DietPlanReminder(),
        if (vm.draftImage != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Image.memory(vm.draftImage!, height: 200, fit: BoxFit.cover),
          ),
        if (vm.manualEntryPrompt) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: AppTokens.warnContainer, borderRadius: BorderRadius.circular(16)),
            child: Text(
              tidy(r == null ? Messages.recognitionUnavailable : Messages.lowConfidence), // M7 / M2
              style: const TextStyle(color: AppTokens.onWarn, fontSize: 16),
            ),
          ),
        ],
        if (r != null && !vm.manualEntryPrompt)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              keepGroups('Identified with ${(r.confidence * 100).round()}% confidence · model ${r.modelVersion}'),
              style: const TextStyle(fontSize: 13, color: AppTokens.inkMuted),
            ),
          ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: [
            for (final s in MealSlot.values)
              ChoiceChip(label: OneLineText(s.label), selected: d.mealType == s, onSelected: (_) => vm.setSlot(s)),
          ],
        ),
        const SizedBox(height: 8),
        for (final i in d.items) _ItemCard(vm: vm, item: i),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52), shape: const StadiumBorder()),
          onPressed: () async {
            final f = await FoodSearchSheet.show(context, search: vm.searchFoods, title: 'Add a food');
            if (f != null) vm.addFood(f);
          },
          icon: const Icon(Icons.add),
          label: OneLineText(
            d.items.isEmpty ? 'Select or enter the food' : 'Add another food',
            style: const TextStyle(fontSize: 16),
          ),
        ),
        const SizedBox(height: 12),
        if (d.items.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: AppTokens.surface, borderRadius: BorderRadius.circular(18)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const OneLineText('This meal', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                NutrientTable(d.totals),
                const SizedBox(height: 8),
                Text(
                  tidy(
                    'After this meal: ${fmtNum(vm.remaining.energyKcal - d.totalEnergyKcal)} kcal, '
                    '${fmtNum(vm.remaining.sodiumMg - d.totalSodiumMg)} mg sodium and '
                    '${(vm.remaining.sugarG - d.totalSugarG).toStringAsFixed(1)} g free sugars left today.',
                  ),
                  style: const TextStyle(fontSize: 14, color: AppTokens.inkMuted),
                ),
              ],
            ),
          ),
        const DietDisclaimer(),
      ],
    );
  }
}

class _ItemCard extends StatelessWidget {
  final MealLogViewModel vm;
  final MealItem item;
  const _ItemCard({required this.vm, required this.item});

  /// The search sheet opens at once; the recogniser's other likely foods appear when found.
  Future<void> _correct(BuildContext context) async {
    final f = await FoodSearchSheet.show(
      context,
      search: vm.searchFoods,
      suggestedLater: vm.candidatesFor(item),
      title: 'Correct the food',
    );
    if (f != null) vm.correctItem(item, f);
  }

  Future<void> _alternatives(BuildContext context) async {
    final chosen = await showFutureSheet<List<FoodItem>, FoodItem>(
      context: context,
      future: vm.alternativesFor(item),
      title: 'Safer choices',
      loadingText: 'Finding safer choices...',
      builder: (ctx, alts) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (alts.isEmpty)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('No alternative in the same food group fits your\u00A0limits.'),
            ),
          for (final a in alts) FoodTile(food: a, onTap: () => Navigator.pop(ctx, a)),
        ],
      ),
    );
    if (chosen != null) vm.correctItem(item, chosen);
  }

  @override
  Widget build(BuildContext context) {
    final v = item.worstVerdict();
    final (bg, _, _) = VerdictChip.colours(v);
    final step = (item.food.baseServingG / 4).roundToDouble().clamp(10, 200).toDouble();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: v == Verdict.suitable ? AppTokens.surface : bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTokens.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  tidy(item.food.foodName),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppTokens.ink),
                ),
              ),
              VerdictChip(v),
            ],
          ),
          if (item.confidence != null)
            OneLineText(
              '${(item.confidence! * 100).round()}% confidence',
              style: const TextStyle(fontSize: 13, color: AppTokens.inkMuted),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              const OneLineText('Portion', style: TextStyle(fontSize: 15, color: AppTokens.inkMuted)),
              const Spacer(),
              IconButton.filledTonal(
                tooltip: 'Smaller portion',
                onPressed: item.portionSizeG - step < AppConstants.portionMinG
                    ? null
                    : () => vm.adjustPortion(item, item.portionSizeG - step),
                icon: const Icon(Icons.remove),
              ),
              // The weight itself: tap it to type the grams (FR700_007).
              SizedBox(
                width: 104,
                child: TextButton(
                  onPressed: () => _typeGrams(context, vm, item),
                  style: TextButton.styleFrom(foregroundColor: AppTokens.ink, padding: EdgeInsets.zero),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                        child: OneLineText(
                          '${item.portionSizeG.round()} g',
                          semanticsLabel: '${item.portionSizeG.round()} grams, tap to type the weight',
                          alignment: Alignment.center,
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.edit, size: 16, color: AppTokens.brandDeepAccent),
                    ],
                  ),
                ),
              ),
              IconButton.filledTonal(
                tooltip: 'Bigger portion',
                onPressed: item.portionSizeG + step > AppConstants.portionMaxG
                    ? null
                    : () => vm.adjustPortion(item, item.portionSizeG + step),
                icon: const Icon(Icons.add),
              ),
            ],
          ),
          OneLineText(
            'One serving is ${item.food.baseServingG.round()} g · tap the weight to type it',
            style: const TextStyle(fontSize: 12, color: AppTokens.inkMuted),
          ),
          const SizedBox(height: 8),
          NutrientTable(item.nutrients),
          for (final r in item.verdicts.where((x) => x.verdict != Verdict.suitable))
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                tidy(r.reasonText),
                style: TextStyle(
                  fontSize: 15,
                  color: r.verdict == Verdict.notSuitable ? AppTokens.onDanger : AppTokens.onWarn,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 4,
            children: [
              TextButton.icon(
                onPressed: () => _correct(context),
                icon: const Icon(Icons.edit),
                label: const OneLineText('Not this food?'),
              ),
              if (v != Verdict.suitable)
                TextButton.icon(
                  onPressed: () => _alternatives(context),
                  icon: const Icon(Icons.swap_horiz),
                  label: const OneLineText('Safer choice'),
                ),
              TextButton.icon(
                onPressed: () => vm.removeItem(item),
                icon: const Icon(Icons.delete_outline),
                label: const OneLineText('Remove'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The waiting screen while a photo is checked and identified (up to 15 s): the photo itself, what
/// is happening now, and tips for a better photo next time. The patient can switch to entering the
/// food by hand at any time (FR700_050).
class _RecognisingView extends StatefulWidget {
  final Uint8List? photo;
  final VoidCallback onManual;
  const _RecognisingView({required this.photo, required this.onManual});

  @override
  State<_RecognisingView> createState() => _RecognisingViewState();
}

class _RecognisingViewState extends State<_RecognisingView> {
  static const _stages = [
    'Checking the photo...',
    'Identifying the foods...',
    'Estimating the nutrients...',
    'Checking them against your limits...',
  ];
  static const _tips = [
    'Take the photo from above so the whole plate is in the picture.',
    'Daylight or a bright room gives the best result.',
    'Keep fingers, cutlery and packaging out of the photo.',
    'One plate per photo works best.',
  ];
  Timer? _timer;
  int _tick = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 2500), (_) {
      if (mounted) setState(() => _tick++);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stage = _stages[_tick < _stages.length ? _tick : _stages.length - 1];
    final tip = _tips[_tick % _tips.length];
    final photo = widget.photo;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: SizedBox(
            height: 240,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (photo != null)
                  Image.memory(photo, fit: BoxFit.cover, cacheWidth: 800, gaplessPlayback: true)
                else
                  const ColoredBox(color: AppTokens.tint),
                const ColoredBox(color: Color(0x66000000)),
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 56,
                        height: 56,
                        child: CircularProgressIndicator(strokeWidth: 5, color: Colors.white),
                      ),
                      const SizedBox(height: 14),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        child: Text(
                          tidy(stage),
                          key: ValueKey(stage),
                          style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        const ClipRRect(
          borderRadius: BorderRadius.all(Radius.circular(6)),
          child: LinearProgressIndicator(
            minHeight: 8,
            color: AppTokens.brandDeepAccent,
            backgroundColor: AppTokens.tint,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'This usually takes a few\u00A0seconds.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: AppTokens.inkMuted),
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTokens.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppTokens.cardBorder),
          ),
          child: Row(
            children: [
              const GuideIllustration(Icons.lightbulb_outline, size: 64),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const OneLineText(
                      'Photo tip',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppTokens.ink),
                    ),
                    const SizedBox(height: 4),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: Text(
                        tidy(tip),
                        key: ValueKey(tip),
                        style: const TextStyle(fontSize: 15, height: 1.35, color: AppTokens.ink),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        TextButton.icon(
          onPressed: widget.onManual,
          icon: const Icon(Icons.edit_note),
          label: const OneLineText('Enter the food myself instead', style: TextStyle(fontSize: 16)),
        ),
      ],
    );
  }
}

/// Lets the patient type the weight of a food in grams (FR700_007), from
/// [AppConstants.portionMinG] to [AppConstants.portionMaxG]. The reason shows under the box while
/// the weight is not accepted, and Set stays off until it is.
Future<void> _typeGrams(BuildContext context, MealLogViewModel vm, MealItem item) async {
  final grams = await showDialog<String>(context: context, builder: (_) => _GramsDialog(item));
  if (grams != null) vm.enterPortion(item, grams);
}

/// Asks for the weight of one food in grams; Set stays off until the weight is in range.
class _GramsDialog extends StatefulWidget {
  final MealItem item;
  const _GramsDialog(this.item);

  @override
  State<_GramsDialog> createState() => _GramsDialogState();
}

class _GramsDialogState extends State<_GramsDialog> {
  late final TextEditingController text = TextEditingController(text: widget.item.portionSizeG.round().toString());

  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final problem = MealLogViewModel.checkPortion(text.text);
    return AlertDialog(
      backgroundColor: AppTokens.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Text(
        tidy('How much ${item.food.foodName}?'),
        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
      ),
      content: TextField(
        controller: text,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')), LengthLimitingTextInputFormatter(6)],
        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
        decoration: InputDecoration(
          labelText: 'Weight',
          suffixText: 'g',
          helperText: tidy(
            'From ${AppConstants.portionMinG} to ${AppConstants.portionMaxG} g. '
            'One serving is ${item.food.baseServingG.round()} g.',
          ),
          helperMaxLines: 2,
          errorText: text.text.isEmpty ? null : problem,
          errorMaxLines: 2,
        ),
        onChanged: (_) => setState(() {}),
        onSubmitted: (v) {
          if (MealLogViewModel.checkPortion(v) == null) Navigator.pop(context, v);
        },
      ),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const OneLineText('Cancel', alignment: Alignment.center),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: AppTokens.brandDeep,
            minimumSize: const Size(120, AppTokens.minTarget),
          ),
          onPressed: problem == null ? () => Navigator.pop(context, text.text) : null,
          child: const OneLineText('Set', alignment: Alignment.center),
        ),
      ],
    );
  }
}
