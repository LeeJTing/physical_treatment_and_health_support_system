import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:physical_treatment_and_health_support_system/core/constants/app_constants.dart';
import 'package:physical_treatment_and_health_support_system/core/themes/design_tokens.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/food_item.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/meal_log.dart';
import 'package:physical_treatment_and_health_support_system/view/diet_view/food_search_sheet.dart';
import 'package:physical_treatment_and_health_support_system/view/diet_view/widgets/diet_widgets.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/meal_log_view_model/meal_log_view_model.dart';

/// Meal Result (UC800 BF-12 to BF-20; Figma "Meal Result"): each identified food with its
/// confidence, portion and nutrients, its verdict coded with a glyph, a word and a colour, the
/// reason in the patient's words and a safer choice; the patient corrects a food, adjusts a portion
/// or adds one, then saves. Returns true when the meal was saved.
class MealResultView extends StatefulWidget {
  const MealResultView({super.key});

  @override
  State<MealResultView> createState() => _MealResultViewState();
}

class _MealResultViewState extends State<MealResultView> {
  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

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
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop && vm.step != MealStep.idle) vm.cancel(); // A7
      },
      child: Scaffold(
        backgroundColor: AppTokens.screenBackground,
        appBar: AppBar(
          title: const Text('Your meal'),
          backgroundColor: AppTokens.brandDeep,
          foregroundColor: Colors.white,
        ),
        body: switch (vm.step) {
          MealStep.recognising => const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Identifying your meal...', style: TextStyle(fontSize: 18)),
              ],
            ),
          ),
          _ when d == null => const Center(child: Text('No meal to review.')),
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
                          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(56), shape: const StadiumBorder()),
                          onPressed: () {
                            vm.cancel();
                            Navigator.of(context).pop(false);
                          },
                          child: const Text('Cancel', style: TextStyle(fontSize: 17)),
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
                              : () async {
                                  final nav = Navigator.of(context);
                                  if (await vm.confirmMeal()) nav.pop(true);
                                },
                          child: vm.step == MealStep.saving
                              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                              : const Text('Save', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
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
              r == null ? Messages.recognitionUnavailable : Messages.lowConfidence, // M7 / M2
              style: const TextStyle(color: AppTokens.onWarn, fontSize: 16),
            ),
          ),
        ],
        if (r != null && !vm.manualEntryPrompt)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              'Identified with ${(r.confidence * 100).round()}% confidence · model ${r.modelVersion}',
              style: const TextStyle(fontSize: 13, color: AppTokens.inkMuted),
            ),
          ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: [
            for (final s in MealSlot.values)
              ChoiceChip(label: Text(s.label), selected: d.mealType == s, onSelected: (_) => vm.setSlot(s)),
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
          label: Text(d.items.isEmpty ? 'Select or enter the food' : 'Add another food', style: const TextStyle(fontSize: 16)),
        ),
        const SizedBox(height: 12),
        if (d.items.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: AppTokens.surface, borderRadius: BorderRadius.circular(18)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('This meal', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                NutrientTable(d.totals),
                const SizedBox(height: 8),
                Text(
                  'After this meal: ${fmtNum(vm.remaining.energyKcal - d.totalEnergyKcal)} kcal, '
                  '${fmtNum(vm.remaining.sodiumMg - d.totalSodiumMg)} mg sodium and '
                  '${(vm.remaining.sugarG - d.totalSugarG).toStringAsFixed(1)} g free sugars left today.',
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

  Future<void> _correct(BuildContext context) async {
    final cands = await vm.candidatesFor(item);
    if (!context.mounted) return;
    final f = await FoodSearchSheet.show(context, search: vm.searchFoods, suggested: cands, title: 'Correct the food');
    if (f != null) vm.correctItem(item, f);
  }

  Future<void> _alternatives(BuildContext context) async {
    final alts = await vm.alternativesFor(item);
    if (!context.mounted) return;
    final chosen = await showModalBottomSheet<FoodItem>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Safer choices', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              if (alts.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('No alternative in the same food group fits your limits.'),
                ),
              for (final a in alts) FoodTile(food: a, onTap: () => Navigator.pop(ctx, a)),
            ],
          ),
        ),
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
                child: Text(item.food.foodName,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppTokens.ink)),
              ),
              VerdictChip(v),
            ],
          ),
          if (item.confidence != null)
            Text('${(item.confidence! * 100).round()}% confidence',
                style: const TextStyle(fontSize: 13, color: AppTokens.inkMuted)),
          const SizedBox(height: 8),
          Row(
            children: [
              const Text('Portion', style: TextStyle(fontSize: 15, color: AppTokens.inkMuted)),
              const Spacer(),
              IconButton.filledTonal(
                tooltip: 'Smaller portion',
                onPressed: item.portionSizeG - step < 10 ? null : () => vm.adjustPortion(item, item.portionSizeG - step),
                icon: const Icon(Icons.remove),
              ),
              SizedBox(
                width: 84,
                child: Text('${item.portionSizeG.round()} g',
                    textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              ),
              IconButton.filledTonal(
                tooltip: 'Bigger portion',
                onPressed: () => vm.adjustPortion(item, item.portionSizeG + step),
                icon: const Icon(Icons.add),
              ),
            ],
          ),
          Text('One serving is ${item.food.baseServingG.round()} g',
              style: const TextStyle(fontSize: 12, color: AppTokens.inkMuted)),
          const SizedBox(height: 8),
          NutrientTable(item.nutrients),
          for (final r in item.verdicts.where((x) => x.verdict != Verdict.suitable))
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(r.reasonText, style: const TextStyle(fontSize: 15, color: AppTokens.ink)),
            ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 4,
            children: [
              TextButton.icon(onPressed: () => _correct(context), icon: const Icon(Icons.edit), label: const Text('Not this food?')),
              if (v != Verdict.suitable)
                TextButton.icon(
                  onPressed: () => _alternatives(context),
                  icon: const Icon(Icons.swap_horiz),
                  label: const Text('Safer choice'),
                ),
              TextButton.icon(
                onPressed: () => vm.removeItem(item),
                icon: const Icon(Icons.delete_outline),
                label: const Text('Remove'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
