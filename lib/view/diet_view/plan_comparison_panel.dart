import 'dart:math' as math;
import 'package:physical_treatment_and_health_support_system/model/entity/diet_food_guidance.dart';
import 'package:physical_treatment_and_health_support_system/view/common/diet_food_guidance.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:physical_treatment_and_health_support_system/core/themes/design_tokens.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/food_item.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/plan_comparison.dart';

/// All chart values have a text equivalent; missing logs never become zero intake.
class PlanComparisonPanel extends StatefulWidget {
  final PlanComparisonReport report;
  final DietFoodGuidance? foodGuidance;
  final Future<void> Function() onRefresh;
  const PlanComparisonPanel({
    super.key,
    required this.report,
    this.foodGuidance,
    required this.onRefresh,
  });
  @override
  State<PlanComparisonPanel> createState() => _PlanComparisonPanelState();
}

class _PlanComparisonPanelState extends State<PlanComparisonPanel> {
  DateTime? _selected;
  bool _allNutrients = false;
  static const _teal = AppTokens.brandDeep;
  static const _blue = Color(0xFF4775B0);
  static const _amber = Color(0xFF986219);
  String _number(double value) =>
      value.toStringAsFixed(value.abs() < 10 ? 1 : 0);
  String _delta(double value, String unit) =>
      '${value > 0 ? '+' : ''}${_number(value)} $unit';
  Widget _title(String title, String subtitle) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w800,
            color: AppTokens.ink,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          subtitle,
          style: const TextStyle(color: AppTokens.inkMuted, height: 1.4),
        ),
      ],
    ),
  );
  Widget _card(Widget child) => Container(
    margin: const EdgeInsets.only(bottom: AppTokens.gap),
    padding: const EdgeInsets.all(AppTokens.gutter),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: AppTokens.cardBorder),
    ),
    child: child,
  );
  Widget _legend(Color color, String text) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(3),
        ),
      ),
      const SizedBox(width: 6),
      Text(text, style: const TextStyle(fontSize: 12)),
    ],
  );
  Color _statusColor(MealComparisonStatus status) => switch (status) {
    MealComparisonStatus.close => _teal,
    MealComparisonStatus.portions => _blue,
    MealComparisonStatus.foods => _amber,
    _ => AppTokens.inkMuted,
  };
  @override
  void didUpdateWidget(covariant PlanComparisonPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.report.start != widget.report.start) _selected = null;
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.report, compared = widget.report.compared;
    final close = r.count(MealComparisonStatus.close),
        portions = r.count(MealComparisonStatus.portions),
        changed = r.count(MealComparisonStatus.foods);
    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      child: ListView(
        key: PageStorageKey(
          'diet-plan-comparison-${r.start.toIso8601String()}',
        ),
        padding: const EdgeInsets.all(AppTokens.gutter),
        children: [
          Container(
            key: const ValueKey('comparison-summary'),
            padding: const EdgeInsets.all(22),
            margin: const EdgeInsets.only(bottom: 18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [_teal, Color(0xFF157E73)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.restaurant_menu, color: Colors.white),
                    SizedBox(width: 10),
                    Text(
                      'YOUR MEAL STORY',
                      style: TextStyle(
                        color: Colors.white70,
                        letterSpacing: 1.4,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Semantics(
                  container: true,
                  liveRegion: true,
                  identifier: 'comparison-meal-count',
                  child: Text(
                    '${compared.length} meals compared',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 27,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  !r.plansAvailable
                      ? 'Saved plans are unavailable. Pull down to retry.'
                      : compared.isEmpty
                      ? 'A saved plan and a logged meal for the same date and meal time will start your comparison.'
                      : '$close close to plan · ${portions + changed} with changes',
                  style: const TextStyle(color: Colors.white, height: 1.4),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    for (final (icon, text) in [
                      (Icons.event_note, 'Your plan'),
                      (Icons.camera_alt_outlined, 'Your log'),
                      (Icons.insights, 'What changed'),
                    ]) ...[
                      if (text != 'Your plan')
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 6),
                          child: Icon(
                            Icons.arrow_forward,
                            size: 16,
                            color: Colors.white60,
                          ),
                        ),
                      Expanded(
                        child: Column(
                          children: [
                            Icon(
                              icon,
                              color: const Color(0xFFB9ECDD),
                              size: 23,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              text,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          if (compared.isNotEmpty)
            _card(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _title(
                    'How meals matched',
                    'Based on food and grams, not a health score.',
                  ),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      height: 14,
                      child: Row(
                        children: [
                          if (close > 0)
                            Expanded(
                              flex: close,
                              child: Container(color: _teal),
                            ),
                          if (portions > 0)
                            Expanded(
                              flex: portions,
                              child: Container(color: _blue),
                            ),
                          if (changed > 0)
                            Expanded(
                              flex: changed,
                              child: Container(color: _amber),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 14,
                    runSpacing: 8,
                    children: [
                      _legend(_teal, '$close close'),
                      _legend(_blue, '$portions portion changes'),
                      _legend(_amber, '$changed food changes'),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '“Close” means the same foods, each within 10% of planned grams. This is an app comparison rule.',
                  ),
                ],
              ),
            ),
          _card(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _title(
                  'Record coverage',
                  'No log means unknown, not a skipped meal.',
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final status in [
                      MealComparisonStatus.noLog,
                      MealComparisonStatus.upcoming,
                      MealComparisonStatus.unplanned,
                      MealComparisonStatus.reference,
                      MealComparisonStatus.unavailable,
                    ])
                      if (r.count(status) > 0)
                        Chip(
                          label: Text(
                            '${r.count(status)} ${status.label.toLowerCase()}',
                          ),
                          backgroundColor: AppTokens.tint,
                          side: BorderSide.none,
                        ),
                  ],
                ),
                if (r.meals.isEmpty)
                  const Text('No plans or meal logs in this week.'),
                if (r.meals.isNotEmpty && r.meals.every((m) => m.comparable))
                  const Text(
                    'Every recorded meal has a plan available for comparison.',
                  ),
              ],
            ),
          ),
          if (compared.isNotEmpty)
            _card(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _title(
                    'Plan vs log',
                    'Average per compared meal · ${compared.length} meals on both sides',
                  ),
                  Wrap(
                    spacing: 18,
                    children: [
                      _legend(_blue, 'Planned'),
                      _legend(_teal, 'Logged'),
                    ],
                  ),
                  const SizedBox(height: 18),
                  for (final n in _metrics.take(_allNutrients ? 6 : 3))
                    _nutrientBars(n, r.plannedAverage, r.loggedAverage),
                  TextButton(
                    onPressed: () =>
                        setState(() => _allNutrients = !_allNutrients),
                    child: Text(
                      _allNutrients
                          ? 'Show fewer nutrients'
                          : 'Show all 6 nutrients',
                    ),
                  ),
                  const Text(
                    'Energy, sodium and free sugars use saved values. Planned carbohydrate, protein and fat are estimates from the current food catalogue.',
                    style: TextStyle(fontSize: 12, color: AppTokens.inkMuted),
                  ),
                ],
              ),
            ),
          _card(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _title(
                  'Your week at a glance',
                  'Energy (kcal) · tap a day to see its meals',
                ),
                Wrap(
                  spacing: 18,
                  children: [
                    _legend(_blue, 'Full saved plan'),
                    _legend(_teal, 'Recorded food'),
                  ],
                ),
                const SizedBox(height: 18),
                _dailyGraph(r),
                const SizedBox(height: 12),
                const Text(
                  'Recorded food may cover only part of a day. A lower bar does not prove that you ate too little.',
                  style: TextStyle(fontSize: 12, color: AppTokens.inkMuted),
                ),
              ],
            ),
          ),
          if (compared.isNotEmpty) _patterns(r),
          _title(
            'What changed at each meal',
            'Open a meal to compare foods, portions and nutrients.',
          ),
          if (widget.foodGuidance case final guidance?)
            _card(DietFoodGuidanceBody(guidance, selectedDay: _selected)),
          if (_selected != null)
            Row(
              children: [
                Expanded(
                  child: Text(
                    DateFormat('EEEE, d MMM').format(_selected!),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() => _selected = null),
                  child: const Text('Show all days'),
                ),
              ],
            ),
          for (final day in r.days.where(
            (d) => _selected == null || d.date == _selected,
          )) ...[
            if (_selected == null && day.meals.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  DateFormat('EEEE, d MMM').format(day.date),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            for (final meal in day.meals) _meal(meal),
            if (_selected != null && day.meals.isEmpty)
              _card(const Text('No plans or meal logs for this day.')),
          ],
          _card(
            const Text(
              'About this comparison\nUses the currently saved plan contents and recorded meals for each date and meal time. Plans saved after a meal are reference only. Later edits to an existing plan cannot be reconstructed. Check ingredients and amounts in your log before interpreting a difference.',
              style: TextStyle(color: AppTokens.inkMuted, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }

  static final _metrics = <(String, String, double Function(Nutrients))>[
    ('Energy', 'kcal', (n) => n.energyKcal),
    ('Sodium', 'mg', (n) => n.sodiumMg),
    ('Free sugars', 'g', (n) => n.sugarG),
    ('Carbohydrate', 'g', (n) => n.carbG),
    ('Protein', 'g', (n) => n.proteinG),
    ('Fat', 'g', (n) => n.fatG),
  ];
  Widget _nutrientBars(
    (String, String, double Function(Nutrients)) n,
    Nutrients planned,
    Nutrients logged,
  ) {
    final p = n.$3(planned),
        l = n.$3(logged),
        max = math.max(1.0, math.max(p, l));
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  n.$1,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              Text(
                '${_delta(l - p, n.$2)} vs plan',
                style: const TextStyle(fontSize: 12, color: AppTokens.inkMuted),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final (value, color, label) in [
            (p, _blue, 'Planned'),
            (l, _teal, 'Logged'),
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Row(
                children: [
                  Expanded(
                    child: Semantics(
                      label: '$label ${n.$1}: ${_number(value)} ${n.$2}',
                      child: LinearProgressIndicator(
                        value: value / max,
                        minHeight: 9,
                        color: color,
                        backgroundColor: color.withValues(alpha: .08),
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 80,
                    child: Text(
                      '${_number(value)} ${n.$2}',
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _dailyGraph(PlanComparisonReport r) {
    final max = r.days.fold(
      1.0,
      (double v, d) =>
          math.max(v, math.max(d.planned.energyKcal, d.logged.energyKcal)),
    );
    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (final d in r.days)
              Expanded(
                child: Semantics(
                  identifier: 'compare-day-${d.date.weekday}',
                  button: true,
                  label: 'View ${DateFormat('EEEE').format(d.date)} meals',
                  child: InkWell(
                    key: ValueKey('compare-day-${d.date.weekday}'),
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => setState(() => _selected = d.date),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: 10,
                        horizontal: 3,
                      ),
                      decoration: BoxDecoration(
                        color: _selected == d.date
                            ? AppTokens.tint
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        children: [
                          SizedBox(
                            height: 112,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                _bar(
                                  d.hasPlan && r.plansAvailable,
                                  d.planned.energyKcal / max,
                                  _blue,
                                ),
                                const SizedBox(width: 3),
                                _bar(
                                  d.hasLogs && !d.future && d.validTotals,
                                  d.logged.energyKcal / max,
                                  _teal,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            DateFormat('EEEEE').format(d.date),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        if (_selected case final selected?) ...[
          const SizedBox(height: 12),
          for (final d in r.days.where((d) => d.date == selected))
            Semantics(
              identifier: 'comparison-day-values',
              child: Text(
                '${DateFormat('EEE d MMM').format(d.date)} · Plan: ${d.hasPlan && r.plansAvailable ? '${_number(d.planned.energyKcal)} kcal' : 'unavailable'} · Log: ${d.hasLogs && d.validTotals ? '${_number(d.logged.energyKcal)} kcal' : 'unknown'}',
                key: const ValueKey('comparison-day-values'),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12),
              ),
            ),
        ],
      ],
    );
  }

  Widget _bar(bool known, double fraction, Color color) => known
      ? Container(
          width: 10,
          height: math.max(2, fraction * 108),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
          ),
        )
      : const SizedBox(
          width: 10,
          height: 16,
          child: Text(
            '—',
            style: TextStyle(color: AppTokens.inkMuted, fontSize: 10),
          ),
        );

  Widget _patterns(PlanComparisonReport r) {
    final previous = r.previousMeals;
    final previousAvg = PlanComparisonReport.average(previous, planned: false);
    final currentAvg = r.loggedAverage;
    return _card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _title(
            'Patterns worth checking',
            'Small observations to help you review your choices.',
          ),
          if (r.repeatedChanges.isEmpty)
            const Text('Foods and amounts stayed close to the saved plan.'),
          for (final change in r.repeatedChanges.take(3))
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.manage_search, color: _teal),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${change.change}: ${change.name} · ${change.meals} compared ${change.meals == 1 ? 'meal' : 'meals'}.',
                    ),
                  ),
                ],
              ),
            ),
          const Divider(height: 22),
          Text(
            'Compared with the previous week',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            previous.isEmpty
                ? 'No comparable logged meals in the previous week.'
                : 'Per compared meal: energy ${_delta(currentAvg.energyKcal - previousAvg.energyKcal, 'kcal')}, sodium ${_delta(currentAvg.sodiumMg - previousAvg.sodiumMg, 'mg')}, free sugars ${_delta(currentAvg.sugarG - previousAvg.sugarG, 'g')}.\nThis week: ${r.compared.length} meals; previous week: ${previous.length}. Different foods and logging coverage can explain the change.',
          ),
        ],
      ),
    );
  }

  Widget _meal(MealPlanComparison meal) {
    final color = _statusColor(meal.status),
        detail =
            meal.comparable || meal.status == MealComparisonStatus.reference;
    final changes = meal.foods
        .where((f) => f.added || f.absent || f.changedPortion)
        .toList();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: .25)),
      ),
      child: ExpansionTile(
        key: PageStorageKey(
          'comparison-meal-${meal.date.toIso8601String()}-${meal.slot.name}',
        ),
        shape: const Border(),
        collapsedShape: const Border(),
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: .1),
          child: Icon(
            meal.changed ? Icons.compare_arrows : Icons.restaurant_outlined,
            color: color,
          ),
        ),
        title: Text(
          meal.slot.label,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          meal.status.label,
          style: TextStyle(color: color, fontWeight: FontWeight.w600),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
        children: [
          if (meal.note != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(meal.note!),
            ),
          if (meal.status == MealComparisonStatus.noLog ||
              meal.status == MealComparisonStatus.upcoming)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text(
                'No food log yet. The planned foods below do not tell us what you ate.',
              ),
            ),
          const Row(
            children: [
              Expanded(
                child: Text(
                  'FOOD',
                  style: TextStyle(fontSize: 11, color: AppTokens.inkMuted),
                ),
              ),
              SizedBox(
                width: 64,
                child: Text(
                  'PLAN',
                  textAlign: TextAlign.right,
                  style: TextStyle(fontSize: 11, color: _blue),
                ),
              ),
              SizedBox(
                width: 64,
                child: Text(
                  'LOG',
                  textAlign: TextAlign.right,
                  style: TextStyle(fontSize: 11, color: _teal),
                ),
              ),
            ],
          ),
          for (final food in meal.foods)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 9),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: Text(food.name)),
                  SizedBox(
                    width: 64,
                    child: Text(
                      food.plannedG > 0 ? '${_number(food.plannedG)} g' : '—',
                      textAlign: TextAlign.right,
                    ),
                  ),
                  SizedBox(
                    width: 64,
                    child: Text(
                      food.loggedG > 0 ? '${_number(food.loggedG)} g' : '—',
                      textAlign: TextAlign.right,
                    ),
                  ),
                ],
              ),
            ),
          if (detail) ...[
            const Divider(height: 20),
            if (changes.isEmpty)
              const Text(
                'The same foods were logged within 10% of the planned portions.',
              ),
            for (final food in changes)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  food.added
                      ? 'Added ${food.name}: ${_number(food.loggedG)} g.'
                      : food.absent
                      ? '${food.name} was planned but is not in this log.'
                      : '${food.name}: ${_delta(food.loggedG - food.plannedG, 'g')} compared with plan.',
                ),
              ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(top: 6, bottom: 12),
              decoration: BoxDecoration(
                color: AppTokens.tint,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'Logged − planned\nEnergy ${_delta(meal.difference.energyKcal, 'kcal')} · Sodium ${_delta(meal.difference.sodiumMg, 'mg')} · Free sugars ${_delta(meal.difference.sugarG, 'g')}',
                style: const TextStyle(height: 1.5),
              ),
            ),
            Text(
              changes.isEmpty
                  ? 'Keep checking quantities when you log a meal.'
                  : 'Check that every food, drink and amount is recorded correctly. If the log is complete, review the changed foods or portions when planning your next meal.',
            ),
          ],
        ],
      ),
    );
  }
}
