import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:physical_treatment_and_health_support_system/core/constants/app_constants.dart';
import 'package:physical_treatment_and_health_support_system/core/themes/design_tokens.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/diet_planner_service/plan_change.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/diet_plan.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/food_item.dart';
import 'package:physical_treatment_and_health_support_system/view/common/tidy_text.dart';
import 'package:physical_treatment_and_health_support_system/view/common/user_guide.dart';
import 'package:physical_treatment_and_health_support_system/view/diet_view/food_search_sheet.dart';
import 'package:physical_treatment_and_health_support_system/view/diet_view/manual_diet_plan_view.dart';
import 'package:physical_treatment_and_health_support_system/view/diet_view/widgets/diet_widgets.dart';
import 'package:physical_treatment_and_health_support_system/view/diet_view/widgets/food_picture.dart';
import 'package:physical_treatment_and_health_support_system/view/diet_view/widgets/plan_widgets.dart';
import 'package:physical_treatment_and_health_support_system/view/diet_view/widgets/plan_cards.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/diet_plan_view_model/diet_plan_view_model.dart';

enum _FoodAction { portion, swap, lock, remove, editToday }

enum _FutureDuration {
  day('1 day'),
  week('1 week'),
  month('1 month');

  const _FutureDuration(this.label);
  final String label;

  DateTime endDate(DateTime start) {
    if (this == day) return start;
    if (this == week) return DateTime(start.year, start.month, start.day + 6);
    final daysNextMonth = DateTime(start.year, start.month + 2, 0).day;
    final nextDay = start.day.clamp(1, daysNextMonth);
    return DateTime(start.year, start.month + 1, nextDay - 1);
  }
}

/// Today's plan (UC900 A5) or the weekly plan (A6). Each day shows its planned energy, sodium and
/// free sugars against the limits and "Why this plan?" (how it was made, with the healthy plate);
/// each slot shows its foods with a picture of their place on the plate. Tapping a food says why it
/// was chosen and lets the patient change its portion, swap it (A5.1), lock it (A5.2) or remove it;
/// "Add food" lets the patient choose any catalogue food. Every change is shown with its effect
/// and confirmed first; health conflicts are highlighted in red as warnings. Regenerate
/// (A6.1) and "plan the rest of today" (FR700_034) are confirmed too. When the planner is
/// unavailable the patient builds the day's plan by choosing foods (E2, FR700_044).
class DietPlanView extends StatefulWidget {
  final PlanType type;
  final bool refreshForProfile;
  const DietPlanView({super.key, required this.type, this.refreshForProfile = false});

  @override
  State<DietPlanView> createState() => _DietPlanViewState();
}

class _DietPlanViewState extends State<DietPlanView> {
  final _scroll = ScrollController();
  DateTime? _selectedDay;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final vm = context.read<DietPlanViewModel>();
      if (widget.refreshForProfile) {
        await vm.refreshAfterProfileChange();
      } else {
        await vm.load(widget.type);
      }
      if (mounted) await showGuideOnce(context, Guides.dietPlan); // first visit only
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _focusPlan(DateTime? day) {
    if (_scroll.hasClients) _scroll.jumpTo(0);
    setState(() => _selectedDay = day);
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
    final f = await FoodSearchSheet.show(
      context,
      search: vm.searchCatalogue,
      suggestedLater: vm.alternativesFor(m),
      title: 'Swap ${m.food.foodName}',
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
            if (vm.canEditDay(m.planDate) && m.isLocked)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text(
                  'Unlock it to change the portion or swap\u00A0it.',
                  style: TextStyle(fontSize: 14, color: AppTokens.inkMuted),
                ),
              ),
            if (vm.isPastSavedDay(m.planDate))
              const Text('Previous plan · View only')
            else if (!vm.canEditDay(m.planDate))
              _ActionButton(
                icon: Icons.edit_outlined,
                label: "Edit today's plan",
                onTap: () => Navigator.pop(ctx, _FoodAction.editToday),
              )
            else ...[
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
      case _FoodAction.editToday:
        await _editToday(vm);
    }
  }

  Future<void> _manual(DietPlanViewModel vm, {DateTime? day}) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ManualDietPlanView(viewModel: vm, day: day),
      ),
    );
    if (!mounted) return;
    if (saved == true) {
      if (day == null) {
        await vm.load(widget.type);
        if (mounted) _snack("Today's plan has been saved.");
      } else {
        _focusPlan(day);
        _snack('Future day saved.');
      }
    }
  }

  Future<DateTime?> _pickFutureDate(DietPlanViewModel vm) {
    final today = vm.today;
    final tomorrow = DateTime(today.year, today.month, today.day + 1);
    final current = _selectedDay;
    final latest = DateTime(today.year + 5, today.month, today.day);
    return showDatePicker(
      context: context,
      currentDate: today,
      firstDate: tomorrow,
      initialDate: current != null && current.isAfter(today) && !current.isAfter(latest) ? current : tomorrow,
      lastDate: latest,
      helpText: 'Choose a start date',
    );
  }

  Future<void> _viewSavedPlan(DietPlanViewModel vm) async {
    final today = vm.today;
    final day = await showDatePicker(
      context: context,
      currentDate: today,
      initialDate: _selectedDay ?? today,
      firstDate: DateTime(2000),
      lastDate: DateTime(today.year + 5, today.month, today.day + AppConstants.maxFuturePlanDays - 1),
      helpText: 'Choose a saved plan date',
    );
    if (!mounted || day == null) return;
    if (await vm.openSavedDate(day) && mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      _focusPlan(day);
    }
  }

  Future<void> _addFuture(DietPlanViewModel vm) async {
    final start = await _pickFutureDate(vm);
    if (!mounted || start == null) return;
    var duration = _FutureDuration.day;
    var end = start;
    var custom = false;
    final action = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) {
          final format = MaterialLocalizations.of(context).formatMediumDate;
          return AlertDialog(
            title: const Text('Add future plan'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Start date · ${format(start)}'),
                  Text('End date · ${format(end)}'),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final d in _FutureDuration.values)
                        ChoiceChip(
                          label: Text(d.label),
                          selected: !custom && duration == d,
                          onSelected: (_) => update(() {
                            duration = d;
                            end = d.endDate(start);
                            custom = false;
                          }),
                        ),
                    ],
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.date_range),
                    label: const Text('Choose end date'),
                    onPressed: () async {
                      final date = await showDatePicker(
                        context: context,
                        currentDate: vm.today,
                        initialDate: end,
                        firstDate: start,
                        lastDate: DateTime(start.year, start.month, start.day + AppConstants.maxFuturePlanDays - 1),
                        helpText: 'Choose an end date',
                        errorInvalidText: 'Choose an end date within the ${AppConstants.maxFuturePlanDays}-day range',
                      );
                      if (!context.mounted || date == null) return;
                      update(() {
                        end = date;
                        custom = true;
                      });
                    },
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'A saved one-day plan takes priority on its date. For overlapping longer plans, the later start date takes priority.',
                  ),
                  if (start == end)
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Choose foods myself'),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Generate plan')),
            ],
          );
        },
      ),
    );
    if (!mounted || action == null) return;
    if (!action) {
      await _manual(vm, day: start);
    } else if (await vm.generateFuture(start, end) && mounted) {
      _focusPlan(start);
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
    if (mounted) {
      setState(() => _selectedDay = null);
      await vm.load(PlanType.weekly);
    }
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
    final saved = vm.savedViewDate;
    final days = p?.days() ?? const <DateTime>[];
    final anchor = saved ?? vm.today;
    final day = days.contains(_selectedDay)
        ? _selectedDay
        : days.contains(anchor)
        ? anchor
        : days.firstOrNull;
    final viewDate = day ?? anchor;
    return PopScope(
      canPop: !vm.generatingFuture && (!widget.refreshForProfile || !vm.isLoading),
      child: Scaffold(
        backgroundColor: AppTokens.screenBackground,
        appBar: AppBar(
          title: Text(
            saved != null
                ? viewDate.isBefore(vm.today)
                      ? 'Previous Plan'
                      : viewDate.isAfter(vm.today)
                      ? 'Future Plan'
                      : "Today's Plan"
                : widget.type == PlanType.weekly
                ? 'Weekly Plan'
                : "Today's Plan",
          ),
          backgroundColor: AppTokens.brandDeep,
          foregroundColor: Colors.white,
          actions: [
            if (saved == null)
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
                      const LinearProgressIndicator(
                        minHeight: 4,
                        color: AppTokens.cta,
                        backgroundColor: AppTokens.tint,
                      ),
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
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const HealthyPlatePicture(size: 132),
                      const SizedBox(height: 20),
                      const CircularProgressIndicator(color: AppTokens.brandDeepAccent),
                      const SizedBox(height: 14),
                      Text(
                        vm.changeInProgress ?? 'Making a plan that fits your\u00A0limits...',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppTokens.ink),
                      ),
                    ],
                  ),
                ),
              )
            : ListView(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  if (widget.type == PlanType.weekly) ...[
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.tonalIcon(
                          onPressed: vm.isLoading ? null : () => _addFuture(vm),
                          icon: const Icon(Icons.event_available),
                          label: const Text('Add future plan'),
                        ),
                        OutlinedButton(
                          onPressed: vm.isLoading ? null : () => _viewSavedPlan(vm),
                          child: const Text('View saved plan'),
                        ),
                        if (saved != null)
                          TextButton(
                            onPressed: vm.isLoading
                                ? null
                                : () async {
                                    _focusPlan(null);
                                    await vm.load(PlanType.weekly);
                                  },
                            child: const Text('Back to today'),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (saved == null)
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
                  if (vm.followWarnings case final w when saved == null && w.isNotEmpty) ...[
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
                      decoration: BoxDecoration(
                        color: AppTokens.warnContainer,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        tidy(Messages.plannerUnavailable),
                        style: const TextStyle(color: AppTokens.onWarn, fontSize: 15),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (widget.type == PlanType.weekly && vm.needsDailyReplan) ...[
                    WatchOutBox(
                      const [
                        PlanNote(
                          "Today's saved plan does not meet all nutrition targets and limits. Replan it before making a new week. Your saved weekly plan is kept.",
                          warn: true,
                        ),
                      ],
                      title: "Replan Today's Plan first",
                      action: TextButton.icon(
                        onPressed: vm.isLoading ? null : () => _editToday(vm),
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text("Open Today's Plan"),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (saved == null)
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                        shape: const StadiumBorder(),
                      ),
                      onPressed: vm.isLoading ? null : () => _manual(vm),
                      icon: const Icon(Icons.edit_note),
                      label: const OneLineText('Build my plan myself'),
                    ),
                  const SizedBox(height: 12),
                  if (saved != null && p == null)
                    Text('No saved plan for ${MaterialLocalizations.of(context).formatFullDate(saved)}.'),
                  if (p != null) ...[
                    if (widget.type == PlanType.weekly && saved == null) ...[
                      Text(
                        tidy('This week you followed ${(vm.adherence() * 100).round()}% of your planned meals.'),
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppTokens.ink),
                      ),
                      const SizedBox(height: 8),
                    ],
                    if (days.length > 1 && days.length <= 7) ...[
                      Wrap(
                        spacing: 6,
                        children: [
                          for (final date in days)
                            ChoiceChip(
                              avatar: vm.nutritionWarnings(date).isEmpty
                                  ? null
                                  : const Icon(Icons.warning_amber_rounded, color: AppTokens.danger, size: 18),
                              label: Text(date == vm.today ? 'Today, ${_dayLabel(date)}' : _dayLabel(date)),
                              selected: day == date,
                              onSelected: (_) => setState(() => _selectedDay = date),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                    ],
                    if (days.length > 7 && day != null)
                      OutlinedButton.icon(
                        onPressed: () async {
                          final date = await showDatePicker(
                            context: context,
                            initialDate: day,
                            firstDate: days.first,
                            lastDate: days.last,
                            currentDate: vm.today,
                            helpText: 'Choose a day in this plan',
                          );
                          if (mounted && date != null) setState(() => _selectedDay = date);
                        },
                        icon: const Icon(Icons.date_range),
                        label: Text('Plan day · ${_dayLabel(day)}'),
                      ),
                    if (day != null) ...[
                      if (saved != null && p.startDate != p.endDate)
                        Text('Plan period · ${_dayLabel(p.startDate)} – ${_dayLabel(p.endDate)}'),
                      if (vm.isPastSavedDay(day))
                        const Text('Previous plan · View only')
                      else if (!vm.canEditDay(day)) ...[
                        const Text("Today's meals are the same as Today's Plan. Changes made there also appear here."),
                        TextButton.icon(
                          onPressed: vm.isLoading ? null : () => _editToday(vm),
                          icon: const Icon(Icons.edit_outlined),
                          label: const Text("Edit today's plan"),
                        ),
                      ],
                      _overview(vm, day),
                      const SizedBox(height: 12),
                      for (final slot in MealSlot.values) _slotCard(vm, p, day, slot),
                    ],
                    if (widget.type == PlanType.daily)
                      TextButton.icon(
                        onPressed: vm.isLoading ? null : () => _regenerateRemaining(vm),
                        icon: const Icon(Icons.update),
                        label: const Text("Plan the rest of today from what I've\u00A0eaten"),
                      ),
                    Text(
                      'Planned by ${p.modelVersion}',
                      style: const TextStyle(fontSize: 12, color: AppTokens.inkMuted),
                    ),
                  ],
                  const DietDisclaimer(),
                ],
              ),
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
    final isToday = day == vm.today;
    return PlanTotalsCard(
      title: isToday ? 'Your plan for today' : 'Your plan for ${_dayLabel(day)}',
      totals: t,
      energyLimit: vm.ctx.dailyEnergyKcal,
      sodiumLimit: vm.ctx.dailySodiumMg,
      sugarLimit: vm.ctx.dailySugarG,
      children: [
        if (vm.nutritionWarnings(day) case final alerts when alerts.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: WatchOutBox(alerts, title: 'This day may not provide enough nutrition'),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(
            vm.isPastSavedDay(day)
                ? 'Tap a food to see its details.'
                : 'Tap a food to see its details or change it. You can choose any food. Profile and daily-limit warnings are highlighted in red.',
            style: const TextStyle(fontSize: 13, color: AppTokens.inkMuted),
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
    );
  }

  /// Shared meal and food cards keep draft, daily and weekly plans consistent.
  Widget _slotCard(DietPlanViewModel vm, DietPlan p, DateTime day, MealSlot slot) {
    final items = p.mealsFor(day).where((m) => m.mealSlot == slot).toList();
    return PlanMealCard(
      slot: slot,
      meals: items,
      usualKcal: vm.usualKcal(slot),
      rows: [for (final m in items) _foodRow(vm, m)],
      onAdd: vm.isLoading || !vm.canEditDay(day) ? null : () => _add(vm, day, slot),
    );
  }

  Widget _foodRow(DietPlanViewModel vm, PlannedMeal m) => PlanFoodRow(
    key: ValueKey('saved-food-${m.plannedMealId}'),
    meal: m,
    warnings: vm.savedFoodWarnings(m),
    onTap: vm.isLoading ? null : () => _openFood(vm, m),
    onRemove: vm.isLoading || !vm.canEditDay(m.planDate) ? null : () => _remove(vm, m),
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
