import 'package:flutter/material.dart';

import 'package:physical_treatment_and_health_support_system/core/themes/design_tokens.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/diet_plan.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/food_item.dart';
import 'package:physical_treatment_and_health_support_system/model/result.dart';
import 'package:physical_treatment_and_health_support_system/view/common/tidy_text.dart';
import 'package:physical_treatment_and_health_support_system/view/diet_view/food_search_sheet.dart';
import 'package:physical_treatment_and_health_support_system/view/diet_view/widgets/plan_cards.dart';
import 'package:physical_treatment_and_health_support_system/view/diet_view/widgets/plan_widgets.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/diet_plan_view_model/diet_plan_view_model.dart';

/// A local draft: food picks stay visible until the whole day is reviewed and saved.
class ManualDietPlanView extends StatefulWidget {
  final DietPlanViewModel viewModel;
  const ManualDietPlanView({super.key, required this.viewModel});

  @override
  State<ManualDietPlanView> createState() => _ManualDietPlanViewState();
}

class _ManualDietPlanViewState extends State<ManualDietPlanView> {
  final List<PlannedMeal> _meals = [];
  bool _loading = true, _saving = false, _dirty = false, _allowPop = false, _loadFailed = false, _choosing = false;
  String? _error;
  DietPlanViewModel get vm => widget.viewModel;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final result = await vm.manualMeals();
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (result case Success(:final data)) {
        _meals.addAll(data);
      } else {
        _loadFailed = true;
        _error = 'Your saved foods could not be loaded. Close this screen and try again.';
      }
    });
  }

  Future<void> _close() async {
    if (_saving) return;
    if (_dirty) {
      final discard = await confirmEffects(
        context,
        title: 'Leave without saving?',
        icon: Icons.close,
        effects: const ['Your draft changes will be discarded. Your saved plan stays as it is.'],
        confirmLabel: 'Discard changes',
      );
      if (!discard || !mounted) return;
    }
    setState(() => _allowPop = true);
    if (mounted) {
      Navigator.pop(context, false);
    }
  }

  Future<void> _pick(MealSlot slot, {PlannedMeal? replacing}) async {
    if (_saving || _choosing) return;
    setState(() => _choosing = true);
    try {
      final f = await FoodSearchSheet.show(
        context,
        search: vm.searchCatalogue,
        title: '${replacing == null ? 'Add to' : 'Change food for'} ${slot.label.toLowerCase()}',
      );
      if (!mounted || f == null) return;
      await _portion(f, slot, replacing: replacing);
    } finally {
      if (mounted) setState(() => _choosing = false);
    }
  }

  Future<void> _portion(FoodItem food, MealSlot slot, {PlannedMeal? replacing}) async {
    final now = DateTime.now();
    final day = replacing?.planDate ?? DateTime(now.year, now.month, now.day);
    final existing = _meals
        .where((m) => m.mealSlot == slot && m.food.foodId == food.foodId && m.plannedMealId != replacing?.plannedMealId)
        .fold<double>(0, (sum, meal) => sum + meal.portionSizeG);
    var grams = replacing?.food.foodId == food.foodId ? replacing!.portionSizeG : food.baseServingG;
    final selected = await showDialog<double>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: Text(tidy(food.foodName)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Choose a portion'),
                Wrap(
                  spacing: 6,
                  children: [
                    for (final share in [0.5, 0.75, 1.0, 1.25, 1.5])
                      ChoiceChip(
                        label: Text('${(food.baseServingG * share).round()} g'),
                        selected: (grams - food.baseServingG * share).abs() < 1,
                        onSelected: (_) => setDialog(() => grams = (food.baseServingG * share).roundToDouble()),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                if (existing > 0)
                  Text(
                    tidy(
                      '${food.foodName} is already in this meal (${existing.round()} g). '
                      'The extra ${grams.round()} g will be combined into one ${(existing + grams).round()} g portion.',
                    ),
                  ),
                Text(
                  tidy(
                    '${replacing == null ? 'Add' : 'Replace ${replacing.food.foodName} with'} '
                    '${food.foodName}, ${grams.round()} g, in your ${slot.label.toLowerCase()}. '
                    'This changes your draft only; save the day when you are ready.',
                  ),
                ),
                if (vm.foodProblemsForPlan(PlannedMeal.of(food, day, slot, grams + existing)) case final issues
                    when issues.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(top: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTokens.dangerContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      tidy('Review this choice before saving. You can still include it. ${issues.join(' ')}'),
                      style: const TextStyle(color: AppTokens.onDanger, fontWeight: FontWeight.w600),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, grams),
              child: Text(replacing == null ? 'Add to draft' : 'Update draft'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || selected == null) return;
    final meal = PlannedMeal.of(food, day, slot, selected, locked: replacing?.isLocked ?? false);
    final merged = vm.mergeManualChoice(_meals, meal, replacing: replacing);
    setState(() {
      _meals
        ..clear()
        ..addAll(merged);
      _dirty = true;
      _error = null;
    });
    final combined = _meals.firstWhere((m) => m.mealSlot == slot && m.food.foodId == food.foodId);
    final issues = vm.manualFoodProblems(combined, _meals);
    if (issues.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppTokens.danger,
          content: Text(tidy('${food.foodName} does not fit your plan. ${issues.first}')),
        ),
      );
    }
  }

  Future<void> _remove(PlannedMeal meal) async {
    final ok = await confirmEffects(
      context,
      title: 'Remove ${meal.food.foodName}?',
      icon: Icons.remove_circle_outline,
      effects: ['${meal.food.foodName} will be removed from your draft ${meal.mealSlot.label.toLowerCase()}.'],
      confirmLabel: 'Remove',
    );
    if (ok && mounted) {
      setState(() {
        _meals.remove(meal);
        _dirty = true;
        _error = null;
      });
    }
  }

  Future<void> _save() async {
    final totals = Nutrients.sum(_meals.map((m) => m.nutrients));
    final empty = MealSlot.values.where((s) => !_meals.any((m) => m.mealSlot == s));
    final ok = await confirmEffects(
      context,
      title: "Save today's plan?",
      icon: Icons.save_outlined,
      effects: [
        "Today's saved plan will be replaced by these ${_meals.length} foods. Your logged meals stay in your history.",
        '${totals.energyKcal.round()} kcal, ${totals.sodiumMg.round()} mg sodium and ${totals.sugarG.toStringAsFixed(1)} g free sugars.',
        if (empty.isNotEmpty) 'No food is planned for ${empty.map((s) => s.label.toLowerCase()).join(', ')}.',
        "The weekly view will use this same plan for today.",
      ],
      confirmLabel: 'Save plan',
    );
    if (!ok || !mounted) return;
    setState(() => _saving = true);
    final problems = await vm.saveManualMeals(_meals);
    if (!mounted) return;
    if (problems.isEmpty) {
      setState(() {
        _saving = false;
        _allowPop = true;
      });
      Navigator.pop(context, true);
    } else {
      setState(() {
        _saving = false;
        _error = problems.join('\n');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Nutrients.sum(_meals.map((m) => m.nutrients));
    final problems = _loading ? const <String>[] : vm.manualProblems(_meals);
    final warnings = _loading || _meals.isEmpty ? null : vm.manualWarnings(_meals);
    return PopScope(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: Scaffold(
        backgroundColor: AppTokens.screenBackground,
        appBar: AppBar(
          title: const OneLineText("Build today's plan"),
          backgroundColor: AppTokens.brandDeep,
          foregroundColor: Colors.white,
          leading: IconButton(
            tooltip: 'Close plan builder',
            onPressed: _saving ? null : _close,
            icon: const Icon(Icons.close),
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const Text('Choose foods for each meal, then review and save the day.'),
                  const SizedBox(height: 12),
                  PlanTotalsCard(
                    title: 'Your draft for today',
                    totals: t,
                    energyLimit: vm.ctx.dailyEnergyKcal,
                    sodiumLimit: vm.ctx.dailySodiumMg,
                    sugarLimit: vm.ctx.dailySugarG,
                    children: [
                      if (vm.manualNutritionWarnings(_meals) case final alerts when alerts.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                          child: WatchOutBox(alerts, title: 'This day may not provide enough nutrition'),
                        ),
                      const Padding(
                        padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: Text(
                          'Red highlights show profile or daily-limit warnings. You can still save your choices.',
                          style: TextStyle(fontSize: 14, color: AppTokens.inkMuted),
                        ),
                      ),
                      if (warnings != null && warnings.isNotEmpty)
                        ExpansionTile(
                          title: Text(
                            'Review warnings (${warnings.length})',
                            style: const TextStyle(color: AppTokens.onDanger),
                          ),
                          leading: const Icon(Icons.warning_amber, color: AppTokens.danger),
                          children: [Padding(padding: const EdgeInsets.all(12), child: WatchOutBox(warnings))],
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        tidy(_error!),
                        style: const TextStyle(color: AppTokens.onDanger, fontWeight: FontWeight.w600),
                      ),
                    ),
                  for (final slot in MealSlot.values)
                    PlanMealCard(
                      slot: slot,
                      meals: _meals.where((m) => m.mealSlot == slot).toList(),
                      usualKcal: vm.usualKcal(slot),
                      rows: [
                        for (final meal in _meals.where((m) => m.mealSlot == slot))
                          _foodRow(meal, vm.manualFoodProblems(meal, _meals)),
                      ],
                      onAdd: _saving || _choosing || _loadFailed ? null : () => _pick(slot),
                    ),
                ],
              ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                backgroundColor: AppTokens.brandDeep,
              ),
              onPressed: _loading || _saving || _choosing || problems.isNotEmpty || _loadFailed ? null : _save,
              icon: _saving
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.save_outlined),
              label: Text(_saving ? 'Saving...' : 'Save plan'),
            ),
          ),
        ),
      ),
    );
  }

  Widget _foodRow(PlannedMeal meal, List<String> problems) => PlanFoodRow(
    key: ValueKey('manual-food-${meal.plannedMealId}'),
    meal: meal,
    warnings: problems,
    onTap: _saving || _choosing ? null : () => _portion(meal.food, meal.mealSlot, replacing: meal),
    onRemove: _saving || _choosing ? null : () => _remove(meal),
    actions: Wrap(
      spacing: 4,
      children: [
        TextButton.icon(
          onPressed: _saving || _choosing ? null : () => _pick(meal.mealSlot, replacing: meal),
          icon: const Icon(Icons.swap_horiz, size: 18),
          label: const Text('Change food'),
        ),
        TextButton.icon(
          onPressed: _saving || _choosing ? null : () => _portion(meal.food, meal.mealSlot, replacing: meal),
          icon: const Icon(Icons.tune, size: 18),
          label: const Text('Portion'),
        ),
      ],
    ),
  );
}
