import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:physical_treatment_and_health_support_system/core/constants/app_constants.dart';
import 'package:physical_treatment_and_health_support_system/core/themes/design_tokens.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/diet_plan.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/food_item.dart';
import 'package:physical_treatment_and_health_support_system/view/common/future_sheet.dart';
import 'package:physical_treatment_and_health_support_system/view/common/tidy_text.dart';
import 'package:physical_treatment_and_health_support_system/view/common/user_guide.dart';
import 'package:physical_treatment_and_health_support_system/view/diet_view/food_search_sheet.dart';
import 'package:physical_treatment_and_health_support_system/view/diet_view/manual_diet_plan_view.dart';
import 'package:physical_treatment_and_health_support_system/view/diet_view/widgets/diet_widgets.dart';
import 'package:physical_treatment_and_health_support_system/view/diet_view/widgets/food_picture.dart';
import 'package:physical_treatment_and_health_support_system/view/diet_view/widgets/plan_widgets.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/diet_plan_view_model/diet_plan_view_model.dart';

enum _FoodAction { portion, swap, lock, remove }

/// Today's plan (UC900 A5) or the weekly plan (A6). Each day shows its planned energy, sodium and
/// free sugars against the limits and "Why this plan?" (how it was made, with the healthy plate);
/// each slot shows its foods with a picture of their place on the plate. Tapping a food says why it
/// was chosen and lets the patient change its portion, swap it (A5.1), lock it (A5.2) or remove it;
/// "Add food" adds any suitable food to a slot. Every change is shown with its effect on the day
/// and confirmed first, and one that would break a limit cannot be made (FR700_042). Regenerate
/// (A6.1) and "plan the rest of today" (FR700_034) are confirmed too. When the planner is
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

  // ------------------------------------------------------------------ actions (each confirmed)

  Future<void> _regenerate(DietPlanViewModel vm) async {
    final ok = await confirmEffects(
      context,
      title: 'Make a new plan?',
      icon: Icons.refresh,
      effects: vm.regenerateEffects,
      confirmLabel: 'Make new plan',
    );
    if (ok) await vm.regenerate();
  }

  Future<void> _regenerateRemaining(DietPlanViewModel vm) async {
    final ok = await confirmEffects(
      context,
      title: 'Plan the rest of today?',
      icon: Icons.update,
      effects: vm.regenerateRemainingEffects,
      confirmLabel: 'Plan the rest',
    );
    if (ok) await vm.regenerateRemaining();
  }

  Future<void> _add(DietPlanViewModel vm, DateTime day, MealSlot slot) async {
    final f = await FoodSearchSheet.show(
      context,
      search: vm.searchCatalogue,
      suggestedLater: vm.suggestionsFor(day, slot),
      title: 'Add to your ${slot.label.toLowerCase()}',
    );
    if (f == null || !mounted) return;
    final c = vm.previewAdd(day, slot, f);
    if (c == null) return;
    final ok = await PlanChangeDialog.show(
      context,
      change: c,
      rebuild: (g) => vm.previewAdd(day, slot, f, grams: g),
      servingG: f.baseServingG,
      startG: f.baseServingG.roundToDouble(),
      confirmLabel: 'Add',
      icon: Icons.add_circle,
      role: f.planRole,
    );
    if (ok != null) await vm.applyChange(ok);
  }

  Future<void> _remove(DietPlanViewModel vm, PlannedMeal m) async {
    final c = vm.previewRemove(m);
    if (c == null) return;
    final ok = await PlanChangeDialog.show(
      context,
      change: c,
      confirmLabel: 'Remove',
      icon: Icons.remove_circle,
      destructive: true,
    );
    if (ok != null) await vm.applyChange(ok);
  }

  Future<void> _portion(DietPlanViewModel vm, PlannedMeal m) async {
    final c = vm.previewPortion(m, m.portionSizeG);
    if (c == null) return;
    final ok = await PlanChangeDialog.show(
      context,
      change: c,
      rebuild: (g) => vm.previewPortion(m, g),
      servingG: m.food.baseServingG,
      startG: m.portionSizeG,
      confirmLabel: 'Change',
      icon: Icons.tune,
      role: m.food.planRole,
      needsNewPortion: true,
    );
    if (ok != null) await vm.applyChange(ok);
  }

  /// The sheet opens at once and fills when the alternatives have been found.
  Future<void> _swap(DietPlanViewModel vm, PlannedMeal m) async {
    final f = await showFutureSheet<List<FoodItem>, FoodItem>(
      context: context,
      future: vm.alternativesFor(m),
      title: 'Swap ${m.food.foodName}',
      subtitle: 'Foods of the same kind that keep the day within your limits.',
      loadingText: 'Finding foods that fit...',
      builder: (ctx, alts) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (alts.isEmpty) const Text('No other food fits the same\u00A0limits.'),
          for (final a in alts) FoodTile(food: a, onTap: () => Navigator.pop(ctx, a)),
        ],
      ),
    );
    if (f == null || !mounted) return;
    final c = vm.previewReplace(m, f);
    if (c == null) return;
    final ok = await PlanChangeDialog.show(
      context,
      change: c,
      confirmLabel: 'Swap',
      icon: Icons.swap_horiz,
      role: f.planRole,
    );
    if (ok != null) await vm.applyChange(ok);
  }

  /// A planned food: why it was chosen, its nutrients, and what can be done with it.
  Future<void> _openFood(DietPlanViewModel vm, PlannedMeal m) async {
    final look = FoodLook.of(m.food.planRole);
    final reasons = vm.reasonsFor(m);
    final action = await showModalBottomSheet<_FoodAction>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppTokens.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        builder: (ctx, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: AppTokens.cardBorder, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                FoodRoleAvatar(m.food.planRole, size: 64),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tidy(m.food.foodName),
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppTokens.ink),
                      ),
                      OneLineText(
                        '${look.label} · ${m.mealSlot.label} · ${m.portionSizeG.round()} g',
                        style: const TextStyle(fontSize: 15, color: AppTokens.inkMuted),
                      ),
                      if (m.isLocked)
                        const Padding(
                          padding: EdgeInsets.only(top: 4),
                          child: Row(
                            children: [
                              Icon(Icons.lock, size: 16, color: AppTokens.brandDeep),
                              SizedBox(width: 4),
                              Text(
                                'Locked',
                                style: TextStyle(color: AppTokens.brandDeep, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            NutrientTable(m.nutrients),
            const SizedBox(height: 16),
            const Text(
              'Why this food',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppTokens.ink),
            ),
            const Text(
              'Anything that is too much, too little or not good for your body is shown in\u00A0red.',
              style: TextStyle(fontSize: 13, color: AppTokens.inkMuted),
            ),
            const SizedBox(height: 6),
            EffectList(reasons, bullet: Icons.check_circle),
            const SizedBox(height: 12),
            if (m.isLocked)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text(
                  'Unlock it to change the portion or swap\u00A0it.',
                  style: TextStyle(fontSize: 14, color: AppTokens.inkMuted),
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: _ActionButton(
                    icon: Icons.tune,
                    label: 'Portion',
                    onTap: m.isLocked ? null : () => Navigator.pop(ctx, _FoodAction.portion),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _ActionButton(
                    icon: Icons.swap_horiz,
                    label: 'Swap',
                    onTap: m.isLocked ? null : () => Navigator.pop(ctx, _FoodAction.swap),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _ActionButton(
                    icon: m.isLocked ? Icons.lock_open : Icons.lock,
                    label: m.isLocked ? 'Unlock' : 'Lock',
                    onTap: () => Navigator.pop(ctx, _FoodAction.lock),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _ActionButton(
                    icon: Icons.delete_outline,
                    label: 'Remove',
                    danger: true,
                    onTap: () => Navigator.pop(ctx, _FoodAction.remove),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case _FoodAction.portion:
        await _portion(vm, m);
      case _FoodAction.swap:
        await _swap(vm, m);
      case _FoodAction.lock:
        await vm.toggleLock(m);
      case _FoodAction.remove:
        await _remove(vm, m);
    }
  }

  Future<void> _manual(DietPlanViewModel vm) async {
    final saved = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => ManualDietPlanView(viewModel: vm)));
    if (!mounted) return;
    if (saved == true) {
      await vm.load(widget.type);
      if (mounted) _snack("Today's plan has been saved.");
    }
  }

  Future<void> _editToday(DietPlanViewModel vm) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ChangeNotifierProvider.value(
          value: vm,
          child: const DietPlanView(type: PlanType.daily),
        ),
      ),
    );
    if (mounted) await vm.load(PlanType.weekly);
  }

  // ------------------------------------------------------------------ screen

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
            tooltip: 'Make a new plan',
            onPressed: vm.isLoading ? null : () => _regenerate(vm),
            icon: const Icon(Icons.refresh),
          ),
          const HelpButton(guide: Guides.dietPlan),
        ],
        // A new plan is being made: the current one stays visible under a progress bar.
        bottom: vm.isLoading && p != null
            ? PreferredSize(
                preferredSize: Size.fromHeight(vm.changeInProgress == null ? 4 : 38),
                child: Column(
                  children: [
                    const LinearProgressIndicator(minHeight: 4, color: AppTokens.cta, backgroundColor: AppTokens.tint),
                    if (vm.changeInProgress case final action?)
                      Padding(
                        padding: const EdgeInsets.all(6),
                        child: Text(action, style: const TextStyle(color: Colors.white)),
                      ),
                  ],
                ),
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
                    HealthyPlatePicture(size: 132),
                    SizedBox(height: 20),
                    CircularProgressIndicator(color: AppTokens.brandDeepAccent),
                    SizedBox(height: 14),
                    Text(
                      'Making a plan that fits your\u00A0limits...',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppTokens.ink),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'This can take up to 20\u00A0seconds.',
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
                const SizedBox(height: 12),
                // Not following the plan: what was missed or eaten differently, in red.
                if (vm.followWarnings case final w when w.isNotEmpty) ...[
                  WatchOutBox(
                    w,
                    title: 'Please follow your diet plan',
                    action: widget.type == PlanType.daily
                        ? Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              style: TextButton.styleFrom(foregroundColor: AppTokens.onDanger),
                              onPressed: vm.isLoading ? null : () => _regenerateRemaining(vm),
                              icon: const Icon(Icons.update),
                              label: const OneLineText('Plan the rest of today'),
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(height: 12),
                ],
                if (vm.plannerDown) ...[
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: AppTokens.warnContainer, borderRadius: BorderRadius.circular(16)),
                    child: Text(
                      tidy(Messages.plannerUnavailable),
                      style: const TextStyle(color: AppTokens.onWarn, fontSize: 15),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52), shape: const StadiumBorder()),
                  onPressed: vm.isLoading ? null : () => _manual(vm),
                  icon: const Icon(Icons.edit_note),
                  label: const OneLineText('Build my plan myself'),
                ),
                const SizedBox(height: 12),
                if (p != null) ...[
                  if (widget.type == PlanType.weekly) ...[
                    Text(
                      tidy('This week you followed ${(vm.adherence() * 100).round()}% of your planned meals.'),
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
                  if (days.isNotEmpty) ...[
                    if (!vm.canEditDay(days[_day])) ...[
                      const Text("Today's meals are the same as Today's Plan. Changes made there also appear here."),
                      TextButton.icon(
                        onPressed: vm.isLoading ? null : () => _editToday(vm),
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text("Edit today's plan"),
                      ),
                    ],
                    _overview(vm, days[_day]),
                    const SizedBox(height: 12),
                    for (final slot in MealSlot.values) _slotCard(vm, p, days[_day], slot),
                  ],
                  if (widget.type == PlanType.daily)
                    TextButton.icon(
                      onPressed: vm.isLoading ? null : () => _regenerateRemaining(vm),
                      icon: const Icon(Icons.update),
                      label: const Text("Plan the rest of today from what I've\u00A0eaten"),
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

  /// The day at a glance: planned energy, sodium and free sugars against the limits, and the
  /// explanation of how the plan was made.
  Widget _overview(DietPlanViewModel vm, DateTime day) {
    final t = vm.plannedTotals(day);
    final now = DateTime.now();
    final isToday = day.year == now.year && day.month == now.month && day.day == now.day;
    return Container(
      decoration: BoxDecoration(
        color: AppTokens.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTokens.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                OneLineText(
                  isToday ? 'Your plan for today' : 'Your plan for ${_dayLabel(day)}',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppTokens.ink),
                ),
                PlanBar(
                  label: 'Energy',
                  value: t.energyKcal,
                  limit: vm.ctx.dailyEnergyKcal,
                  unit: 'kcal',
                  isTarget: true,
                ),
                PlanBar(label: 'Sodium', value: t.sodiumMg, limit: vm.ctx.dailySodiumMg, unit: 'mg'),
                PlanBar(label: 'Free sugars', value: t.sugarG, limit: vm.ctx.dailySugarG, unit: 'g', decimals: 1),
                if (vm.unmetNeeds(day) case final unmet when unmet.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      tidy('Too little ${unmet.join(' and ')} today: add vegetables, fruit, milk or tofu if you can.'),
                      style: const TextStyle(fontSize: 14, color: AppTokens.onDanger, fontWeight: FontWeight.w600),
                    ),
                  ),
                const SizedBox(height: 6),
                const Text(
                  'Tap a food to see why it was chosen, or to change, swap, lock or remove\u00A0it.',
                  style: TextStyle(fontSize: 13, color: AppTokens.inkMuted),
                ),
              ],
            ),
          ),
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: const EdgeInsets.symmetric(horizontal: 16),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              leading: const Icon(Icons.lightbulb_outline, color: AppTokens.brandDeep),
              title: const OneLineText(
                'Why this plan?',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppTokens.brandDeep),
              ),
              subtitle: const Text(
                'How it was made and how it fits your\u00A0limits',
                style: TextStyle(fontSize: 13, color: AppTokens.inkMuted),
              ),
              children: [
                const Row(
                  children: [
                    HealthyPlatePicture(size: 112),
                    SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _PlateKey(FoodLook.plateVeg, 'Half: vegetables and fruit'),
                          _PlateKey(FoodLook.plateStarch, 'A quarter: rice, bread or noodles'),
                          _PlateKey(FoodLook.plateProtein, 'A quarter: fish, chicken, egg or tofu'),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                for (final r in vm.summaryFor(day)) PlanReasonTile(r),
                if (vm.profileRules.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  const Text(
                    'Rules from your profile',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppTokens.ink),
                  ),
                  for (final r in vm.profileRules)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(tidy('• $r'), style: const TextStyle(fontSize: 14, color: AppTokens.inkMuted)),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// One meal slot: its picture, energy against its usual share, its foods and "Add food".
  Widget _slotCard(DietPlanViewModel vm, DietPlan p, DateTime day, MealSlot slot) {
    final items = p.mealsFor(day).where((m) => m.mealSlot == slot).toList();
    final kcal = items.fold(0.0, (a, m) => a + m.energyKcal);
    final usual = vm.usualKcal(slot);
    final look = SlotLook.of(slot);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppTokens.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTokens.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [look.back, AppTokens.surface]),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Row(
              children: [
                SlotPicture(slot),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      OneLineText(
                        slot.label,
                        style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: AppTokens.ink),
                      ),
                      OneLineText(
                        '${look.time} · ${fmtNum(kcal)} kcal of about ${fmtNum(usual)}',
                        style: const TextStyle(fontSize: 14, color: AppTokens.inkMuted),
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: usual <= 0 ? 0 : (kcal / usual).clamp(0.0, 1.0),
                          minHeight: 6,
                          color: kcal > usual * 1.3 ? AppTokens.caution : look.fore,
                          backgroundColor: AppTokens.surface,
                        ),
                      ),
                    ],
                  ),
                ),
                if (items.any((m) => m.isLogged))
                  const Padding(
                    padding: EdgeInsets.only(left: 8),
                    child: Column(
                      children: [
                        Icon(Icons.check_circle, color: AppTokens.good, size: 22),
                        Text(
                          'Logged',
                          style: TextStyle(color: AppTokens.good, fontWeight: FontWeight.w600, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Text(
                tidy('Nothing planned for your ${slot.label.toLowerCase()} yet.'),
                style: const TextStyle(fontSize: 15, color: AppTokens.inkMuted),
              ),
            ),
          for (final m in items) _foodRow(vm, m),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 2, 8, 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                style: TextButton.styleFrom(minimumSize: const Size(0, AppTokens.minTarget)),
                onPressed: vm.isLoading || !vm.canEditDay(day) ? null : () => _add(vm, day, slot),
                icon: const Icon(Icons.add_circle_outline),
                label: OneLineText('Add food to ${slot.label.toLowerCase()}'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _foodRow(DietPlanViewModel vm, PlannedMeal m) => InkWell(
    onTap: vm.isLoading
        ? null
        : !vm.canEditDay(m.planDate)
        ? () => _editToday(vm)
        : () => _openFood(vm, m),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 4, 4),
      child: Row(
        children: [
          FoodRoleAvatar(m.food.planRole, size: 46),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        tidy(m.food.foodName),
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppTokens.ink),
                      ),
                    ),
                    if (m.isLocked)
                      const Padding(
                        padding: EdgeInsets.only(left: 6),
                        child: Icon(Icons.lock, size: 16, color: AppTokens.brandDeep, semanticLabel: 'Locked'),
                      ),
                  ],
                ),
                if (vm.reasonsFor(m).where((r) => r.warn).firstOrNull case final w?)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 1, right: 4),
                          child: Icon(Icons.warning_amber_rounded, size: 16, color: AppTokens.danger),
                        ),
                        Expanded(
                          child: Text(
                            tidy(w.text.split(':').first),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppTokens.onDanger,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                OneLineText(
                  '${FoodLook.of(m.food.planRole).label} · ${m.portionSizeG.round()} g · ${fmtNum(m.energyKcal)} kcal',
                  style: const TextStyle(fontSize: 13, color: AppTokens.inkMuted),
                ),
                OneLineText(
                  '${fmtNum(m.sodiumMg)} mg sodium · ${m.sugarG.toStringAsFixed(1)} g sugars',
                  style: const TextStyle(fontSize: 13, color: AppTokens.inkMuted),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Remove ${m.food.foodName}',
            onPressed: vm.isLoading || !vm.canEditDay(m.planDate) ? null : () => _remove(vm, m),
            icon: const Icon(Icons.close, color: AppTokens.inkMuted),
          ),
        ],
      ),
    ),
  );
}

class _PlateKey extends StatelessWidget {
  final Color colour;
  final String text;
  const _PlateKey(this.colour, this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: colour, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(tidy(text), style: const TextStyle(fontSize: 13, color: AppTokens.ink)),
        ),
      ],
    ),
  );
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool danger;
  const _ActionButton({required this.icon, required this.label, this.onTap, this.danger = false});

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    style: OutlinedButton.styleFrom(
      minimumSize: const Size.fromHeight(52),
      foregroundColor: danger ? AppTokens.onDanger : AppTokens.brandDeep,
      side: BorderSide(color: danger ? AppTokens.danger : AppTokens.cardBorder),
      shape: const StadiumBorder(),
    ),
    onPressed: onTap,
    icon: Icon(icon),
    label: OneLineText(label, style: const TextStyle(fontSize: 16)),
  );
}
