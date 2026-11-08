import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:physical_treatment_and_health_support_system/core/constants/app_constants.dart';
import 'package:physical_treatment_and_health_support_system/core/themes/design_tokens.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/diet_plan.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/food_item.dart';
import 'package:physical_treatment_and_health_support_system/view/common/future_sheet.dart';
import 'package:physical_treatment_and_health_support_system/view/common/user_guide.dart';
import 'package:physical_treatment_and_health_support_system/view/diet_view/food_search_sheet.dart';
import 'package:physical_treatment_and_health_support_system/view/diet_view/widgets/diet_widgets.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/diet_plan_view_model/diet_plan_view_model.dart';

/// Today's plan (UC900 A5) or the weekly plan (A6): each slot's foods with their portions, Lock and
/// Replace for each planned food (A5.1, A5.2), Regenerate (A6.1), the remaining allowance, the
/// adherence rate for the week (FR700_038) and the disclaimer (FR700_045). When the planner is
/// unavailable the patient builds the day's plan by choosing foods (E2, FR700_044).
class DietPlanView extends StatefulWidget {
  final PlanType type;
  const DietPlanView({super.key, required this.type});

  @override
  State<DietPlanView> createState() => _DietPlanViewState();
}

class _DietPlanViewState extends State<DietPlanView> {
  int _day = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await context.read<DietPlanViewModel>().load(widget.type);
      if (mounted) await showGuideOnce(context, Guides.dietPlan); // first visit only
    });
  }

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  /// The sheet opens at once and fills when the alternatives have been found.
  Future<void> _replace(DietPlanViewModel vm, PlannedMeal m) async {
    final f = await showFutureSheet<List<FoodItem>, FoodItem>(
      context: context,
      future: vm.alternativesFor(m),
      title: 'Replace ${m.food.foodName}',
      subtitle: 'These keep the day within your limits.',
      loadingText: 'Finding foods that fit...',
      builder: (ctx, alts) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (alts.isEmpty) const Text('No other food fits the same limits.'),
          for (final a in alts) FoodTile(food: a, onTap: () => Navigator.pop(ctx, a)),
        ],
      ),
    );
    if (f != null) await vm.replaceMeal(m.plannedMealId, f);
  }

  Future<void> _manual(DietPlanViewModel vm) async {
    final chosen = <MealSlot, List<FoodItem>>{};
    for (final s in MealSlot.values) {
      if (!mounted) return;
      final f = await FoodSearchSheet.show(
        context,
        search: (t) async => (await vm.searchCatalogue(t)).where((x) => x.mealSlots.contains(s.db)).toList(),
        title: 'Choose your ${s.label.toLowerCase()}',
      );
      if (f != null) chosen[s] = [f];
    }
    if (chosen.isEmpty) return;
    final problems = await vm.saveManualPlan(chosen);
    if (!mounted) return;
    if (problems.isNotEmpty) {
      _snack('This plan goes over a daily limit (${problems.first}). Choose lighter foods.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<DietPlanViewModel>();
    final m = vm.takeMessage();
    if (m != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _snack(m);
      });
    }
    final p = vm.plan;
    final days = p?.days() ?? const <DateTime>[];
    if (_day >= days.length) _day = 0;
    return Scaffold(
      backgroundColor: AppTokens.screenBackground,
      appBar: AppBar(
        title: Text(widget.type == PlanType.weekly ? 'Weekly Plan' : "Today's Plan"),
        backgroundColor: AppTokens.brandDeep,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Regenerate',
            onPressed: vm.isLoading ? null : vm.regenerate,
            icon: const Icon(Icons.refresh),
          ),
          const HelpButton(guide: Guides.dietPlan),
        ],
        // A new plan is being made: the current one stays visible under a progress bar.
        bottom: vm.isLoading && p != null
            ? const PreferredSize(
                preferredSize: Size.fromHeight(4),
                child: LinearProgressIndicator(minHeight: 4, color: AppTokens.cta, backgroundColor: AppTokens.tint),
              )
            : null,
      ),
      body: vm.isLoading && p == null
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GuideIllustration(Icons.restaurant_menu, badge: Icons.check_circle, size: 120),
                    SizedBox(height: 20),
                    CircularProgressIndicator(color: AppTokens.brandDeepAccent),
                    SizedBox(height: 14),
                    Text(
                      'Making a plan that fits your limits...',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppTokens.ink),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'This can take up to 20 seconds.',
                      style: TextStyle(fontSize: 15, color: AppTokens.inkMuted),
                    ),
                  ],
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                AllowanceCard(
                  consumed: Nutrients(
                    energyKcal: vm.ctx.dailyEnergyKcal - vm.remaining.energyKcal,
                    sodiumMg: vm.ctx.dailySodiumMg - vm.remaining.sodiumMg,
                    sugarG: vm.ctx.dailySugarG - vm.remaining.sugarG,
                  ),
                  energyTarget: vm.ctx.dailyEnergyKcal,
                  sodiumLimit: vm.ctx.dailySodiumMg,
                  sugarLimit: vm.ctx.dailySugarG,
                ),
                if (vm.profileRules.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                    decoration: BoxDecoration(
                      color: AppTokens.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppTokens.cardBorder),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Planned for your profile',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppTokens.ink)),
                        const SizedBox(height: 6),
                        for (final r in vm.profileRules)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text('• $r', style: const TextStyle(fontSize: 14, color: AppTokens.inkMuted)),
                          ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                if (vm.plannerDown) ...[
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: AppTokens.warnContainer, borderRadius: BorderRadius.circular(16)),
                    child: const Text(Messages.plannerUnavailable, style: TextStyle(color: AppTokens.onWarn, fontSize: 15)),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52), shape: const StadiumBorder()),
                    onPressed: () => _manual(vm),
                    icon: const Icon(Icons.edit_note),
                    label: const Text('Build my plan myself'),
                  ),
                  const SizedBox(height: 12),
                ],
                if (p != null) ...[
                  if (widget.type == PlanType.weekly) ...[
                    Text(
                      'This week you followed ${(vm.adherence() * 100).round()}% of your planned meals.',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppTokens.ink),
                    ),
                    const SizedBox(height: 8),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (var i = 0; i < days.length; i++)
                            Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: ChoiceChip(
                                label: Text(_dayLabel(days[i])),
                                selected: _day == i,
                                onSelected: (_) => setState(() => _day = i),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (days.isNotEmpty) ..._dayMeals(vm, p, days[_day]),
                  if (widget.type == PlanType.daily)
                    TextButton.icon(
                      onPressed: vm.regenerateRemaining,
                      icon: const Icon(Icons.update),
                      label: const Text("Plan the rest of today from what I've eaten"),
                    ),
                  Text('Planned by ${p.modelVersion}', style: const TextStyle(fontSize: 12, color: AppTokens.inkMuted)),
                ],
                const DietDisclaimer(),
              ],
            ),
    );
  }

  static String _dayLabel(DateTime d) {
    const w = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return '${w[d.weekday - 1]} ${d.day}/${d.month}';
  }

  List<Widget> _dayMeals(DietPlanViewModel vm, DietPlan p, DateTime day) {
    final meals = p.mealsFor(day);
    final t = p.totalsFor(day);
    return [
      for (final slot in MealSlot.values)
        if (meals.any((m) => m.mealSlot == slot))
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.fromLTRB(14, 12, 6, 8),
            decoration: BoxDecoration(
              color: AppTokens.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppTokens.cardBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(slot.label,
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppTokens.ink)),
                    ),
                    if (meals.where((m) => m.mealSlot == slot).any((m) => m.isLogged))
                      const Padding(
                        padding: EdgeInsets.only(right: 8),
                        child: Row(
                          children: [
                            Icon(Icons.check_circle, color: AppTokens.good, size: 20),
                            SizedBox(width: 4),
                            Text('Logged', style: TextStyle(color: AppTokens.good, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                  ],
                ),
                for (final m in meals.where((m) => m.mealSlot == slot))
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(m.food.foodName, style: const TextStyle(fontSize: 16, color: AppTokens.ink)),
                            Text(
                              '${m.portionSizeG.round()} g · ${fmtNum(m.energyKcal)} kcal · ${fmtNum(m.sodiumMg)} mg sodium · '
                              '${m.sugarG.toStringAsFixed(1)} g sugars',
                              style: const TextStyle(fontSize: 13, color: AppTokens.inkMuted),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: m.isLocked ? 'Unlock' : 'Lock',
                        onPressed: () => vm.lockMeal(m.plannedMealId, on: !m.isLocked),
                        icon: Icon(m.isLocked ? Icons.lock : Icons.lock_open, color: m.isLocked ? AppTokens.brandDeep : null),
                      ),
                      IconButton(
                        tooltip: 'Replace',
                        onPressed: m.isLocked ? null : () => _replace(vm, m),
                        icon: const Icon(Icons.swap_horiz),
                      ),
                    ],
                  ),
              ],
            ),
          ),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(
          'Planned for the day: ${fmtNum(t.energyKcal)} of ${fmtNum(vm.ctx.dailyEnergyKcal)} kcal, '
          '${fmtNum(t.sodiumMg)} of ${fmtNum(vm.ctx.dailySodiumMg)} mg sodium, '
          '${t.sugarG.toStringAsFixed(1)} of ${vm.ctx.dailySugarG.toStringAsFixed(0)} g free sugars.',
          style: const TextStyle(fontSize: 14, color: AppTokens.inkMuted),
        ),
      ),
      if (vm.unmetNeeds(day) case final unmet when unmet.isNotEmpty)
        Text(
          'Low in ${unmet.join(' and ')} today: add a fruit, vegetables, milk or tofu if you can.',
          style: const TextStyle(fontSize: 14, color: AppTokens.onWarn),
        ),
    ];
  }
}
