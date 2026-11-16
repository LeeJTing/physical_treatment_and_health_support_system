import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:provider/provider.dart';
import 'package:physical_treatment_and_health_support_system/core/themes/design_tokens.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/diet_insights.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/diet_insights_view_model/diet_insights_view_model.dart';

class DietInsightsView extends StatefulWidget {
  const DietInsightsView({super.key});
  @override
  State<DietInsightsView> createState() => _DietInsightsViewState();
}

class _DietInsightsViewState extends State<DietInsightsView> {
  String _contributor = 'sodium_mg';
  String _date(DateTime d) => DateFormat('d MMM').format(d);
  @override
  Widget build(BuildContext context) {
    final vm = context.watch<DietInsightsViewModel>();
    final data = vm.insights;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: AppTokens.screenBackground,
        appBar: AppBar(
          title: const Text('Diet review'),
          backgroundColor: AppTokens.brandDeep,
          foregroundColor: Colors.white,
          bottom: const TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.white,
            tabs: [
              Tab(text: 'Weekly review'),
              Tab(text: 'Meal & readings'),
            ],
          ),
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Previous week',
                    onPressed: vm.isLoading ? null : vm.previousWeek,
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Expanded(
                    child: Text(
                      '${_date(vm.selectedWeek)} – ${_date(DateTime(vm.selectedWeek.year, vm.selectedWeek.month, vm.selectedWeek.day + 6))}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Next week',
                    onPressed: vm.isLoading || !vm.canGoForward
                        ? null
                        : vm.nextWeek,
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
            ),
            if (vm.isLoading)
              const LinearProgressIndicator(
                semanticsLabel: 'Loading diet review',
              ),
            if (vm.errorMessage case final error?)
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Text(error),
                    TextButton(
                      onPressed: () => vm.load(),
                      child: const Text('Try again'),
                    ),
                  ],
                ),
              ),
            if (data != null)
              Expanded(
                child: TabBarView(
                  children: [
                    RefreshIndicator(
                      onRefresh: () => vm.load(),
                      child: ListView(
                        key: const PageStorageKey('diet-weekly-review'),
                        padding: const EdgeInsets.all(20),
                        children: [
                          _heading(
                            'Your recorded week',
                            '${data.week.loggedDays} of ${data.week.elapsedDays} elapsed days have meal records. ${data.week.threeMealDays} ${data.week.threeMealDays == 1 ? 'day has' : 'days have'} all three main meals logged.',
                          ),
                          for (final notice in vm.notices)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Text(
                                notice,
                                style: const TextStyle(
                                  color: AppTokens.inkMuted,
                                ),
                              ),
                            ),
                          _card(
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Energy by day',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                for (final day in data.week.days)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: Row(
                                      children: [
                                        SizedBox(
                                          width: 42,
                                          child: Text(
                                            DateFormat('EEE').format(day.date),
                                          ),
                                        ),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              LinearProgressIndicator(
                                                minHeight: 8,
                                                borderRadius:
                                                    BorderRadius.circular(5),
                                                value: day.hasLogs
                                                    ? (day.totals.energyKcal /
                                                              math.max(
                                                                1,
                                                                data
                                                                    .week
                                                                    .nutrients
                                                                    .first
                                                                    .maximum!,
                                                              ))
                                                          .clamp(0.0, 1.0)
                                                    : 0,
                                                color:
                                                    day.totals.energyKcal >
                                                        data
                                                            .week
                                                            .nutrients
                                                            .first
                                                            .maximum!
                                                    ? AppTokens.danger
                                                    : AppTokens.brandDeep,
                                              ),
                                              Text(
                                                day.future
                                                    ? 'Upcoming'
                                                    : day.hasLogs
                                                    ? '${day.mainMeals}/3 main meals logged'
                                                    : 'No meal records',
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  color: AppTokens.inkMuted,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        SizedBox(
                                          width: 84,
                                          child: Text(
                                            day.hasLogs
                                                ? '${day.totals.energyKcal.round()} kcal'
                                                : '—',
                                            textAlign: TextAlign.right,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          _heading(
                            'Average on recorded days',
                            data.week.loggedDays == 0
                                ? 'Log a meal to begin your review.'
                                : 'Averages use ${data.week.loggedDays} ${data.week.loggedDays == 1 ? 'day' : 'days'} with logs. Missing days are excluded.',
                          ),
                          for (final n in data.week.nutrients)
                            _nutrient(n, data.week.loggedDays),
                          _card(
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Following your stored plans',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  !data.week.plansAvailable
                                      ? 'Plan matching is unavailable.'
                                      : data.week.dueSlots == 0
                                      ? 'No stored planned meals are due in this period.'
                                      : '${data.week.followedSlots} of ${data.week.dueSlots} due planned meals matched your logs (${(data.week.followedSlots / data.week.dueSlots * 100).round()}%).',
                                  style: const TextStyle(fontSize: 16),
                                ),
                                const SizedBox(height: 6),
                                const Text(
                                  'Uses the same food-matching rule as your plan screen. A missing log does not prove that a meal was skipped.',
                                  style: TextStyle(color: AppTokens.inkMuted),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          _card(
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Foods contributing most',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                DropdownButton<String>(
                                  value: _contributor,
                                  isExpanded: true,
                                  items: const [
                                    DropdownMenuItem(
                                      value: 'sodium_mg',
                                      child: Text('Sodium'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'sugar_g',
                                      child: Text('Free sugars'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'energy_kcal',
                                      child: Text('Energy'),
                                    ),
                                  ],
                                  onChanged: (v) {
                                    if (v != null) {
                                      setState(() => _contributor = v);
                                    }
                                  },
                                ),
                                if ((data.week.contributors[_contributor] ??
                                        const [])
                                    .isEmpty)
                                  const Text(
                                    'No contributions recorded for this nutrient.',
                                  ),
                                for (final food
                                    in (data.week.contributors[_contributor] ??
                                            const <FoodContribution>[])
                                        .take(5))
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 7,
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          food.foodName,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        Text(
                                          '${food.amount.toStringAsFixed(_contributor == 'sugar_g' ? 1 : 0)} ${_contributor == 'sodium_mg'
                                              ? 'mg'
                                              : _contributor == 'energy_kcal'
                                              ? 'kcal'
                                              : 'g'} · ${(food.share * 100).round()}% of the recorded total',
                                        ),
                                      ],
                                    ),
                                  ),
                                const SizedBox(height: 6),
                                const Text(
                                  'Review the largest contributors when choosing portions or alternatives. These totals include only your logged foods.',
                                  style: TextStyle(color: AppTokens.inkMuted),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    RefreshIndicator(
                      onRefresh: () => vm.load(),
                      child: ListView(
                        key: const PageStorageKey('diet-health-patterns'),
                        padding: const EdgeInsets.all(20),
                        children: [
                          _heading(
                            'Patterns in your records',
                            '${_date(data.patternFrom)} – ${_date(data.patternTo)} · 28-day observation window',
                          ),
                          const Text(
                            'These are exploratory associations, not proof that a food caused a health change. Medicines, activity, sleep, timing and unlogged food may affect the readings. Do not change treatment based on this screen.',
                          ),
                          const SizedBox(height: 16),
                          for (final p in data.patterns) _pattern(p),
                          const Text(
                            'The app requires at least 12 pairs across 7 days and variation in both measurements. These checks reduce misleading displays; they do not establish clinical validity.',
                            style: TextStyle(color: AppTokens.inkMuted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              )
            else if (vm.errorMessage == null)
              const Expanded(
                child: Center(child: Text('Loading your records…')),
              ),
          ],
        ),
      ),
    );
  }

  Widget _heading(String title, String body) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text(body),
      ],
    ),
  );
  Widget _card(Widget child) => Material(
    color: AppTokens.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
      side: const BorderSide(color: AppTokens.cardBorder),
    ),
    child: Padding(padding: const EdgeInsets.all(16), child: child),
  );
  Widget _nutrient(ReviewNutrient n, int days) {
    final over = days > 0 && n.maximum != null && n.average > n.maximum!;
    final below = days > 0 && n.minimum != null && n.average < n.minimum!;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: _card(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    n.label,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  days == 0
                      ? '—'
                      : '${n.average.toStringAsFixed(n.unit == 'g' ? 1 : 0)} ${n.unit}',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: over ? AppTokens.danger : AppTokens.ink,
                  ),
                ),
              ],
            ),
            if (n.minimum != null || n.maximum != null)
              Text(
                'Current daily guidance: ${n.minimum != null ? 'at least ${n.minimum!.round()} ${n.unit}' : ''}${n.minimum != null && n.maximum != null ? ' · ' : ''}${n.maximum != null ? 'at most ${n.maximum!.round()} ${n.unit}' : ''}',
                style: const TextStyle(color: AppTokens.inkMuted),
              ),
            if (over)
              const Text(
                'Recorded average exceeds this limit.',
                style: TextStyle(color: AppTokens.danger),
              ),
            if (below)
              const Text(
                'Recorded average is below this target. Check whether all meals were logged.',
                style: TextStyle(color: AppTokens.inkMuted),
              ),
            if (n.catalogueEstimate)
              const Text(
                'Estimated using current catalogue composition.',
                style: TextStyle(fontSize: 12, color: AppTokens.inkMuted),
              ),
          ],
        ),
      ),
    );
  }

  Widget _pattern(MealHealthPattern p) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: _card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            p.title,
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text('${p.points.length} paired records · ${p.distinctDays} days'),
          const SizedBox(height: 8),
          if (!p.available) ...[
            Text(p.withheldReason ?? 'No pattern can be calculated.'),
            const SizedBox(height: 10),
            LinearProgressIndicator(
              value: (p.points.length / 12).clamp(0.0, 1.0),
              semanticsLabel: 'Paired records collected',
            ),
          ] else ...[
            Text(
              p.correlation!.abs() < .2
                  ? 'No clear rank pattern appears in these records.'
                  : p.correlation! > 0
                  ? 'Higher recorded amounts tended to occur with higher readings in these pairs.'
                  : 'Higher recorded amounts tended to occur with lower readings in these pairs.',
            ),
            const SizedBox(height: 8),
            Text(
              'Rank association: ${p.correlation! >= 0 ? '+' : ''}${p.correlation!.toStringAsFixed(2)} (Spearman)',
            ),
            const SizedBox(height: 12),
            Text(p.readingLabel, style: const TextStyle(fontSize: 12)),
            Semantics(
              label: 'Scatter plot of ${p.points.length} paired records',
              child: SizedBox(
                height: 190,
                width: double.infinity,
                child: CustomPaint(painter: _PatternPlot(p.points)),
              ),
            ),
            Text(p.foodLabel, style: const TextStyle(fontSize: 12)),
          ],
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('How records are paired'),
            children: [
              Align(alignment: Alignment.centerLeft, child: Text(p.method)),
              const SizedBox(height: 8),
              for (final point in p.points.take(28))
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '${_date(point.at)} · ${point.foodValue.toStringAsFixed(1)} → ${point.readingValue.toStringAsFixed(1)}\n${point.description}',
                      style: const TextStyle(fontSize: 13),
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

class _PatternPlot extends CustomPainter {
  final List<MealHealthPoint> points;
  _PatternPlot(this.points);
  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    final xs = points.map((p) => p.foodValue),
        ys = points.map((p) => p.readingValue);
    final minX = xs.reduce(math.min),
        maxX = xs.reduce(math.max),
        minY = ys.reduce(math.min),
        maxY = ys.reduce(math.max);
    final rect = Rect.fromLTWH(
      42,
      12,
      math.max(1, size.width - 54),
      size.height - 38,
    );
    final line = Paint()
      ..color = AppTokens.cardBorder
      ..strokeWidth = 1;
    void label(String s, Offset at) {
      final text = TextPainter(
        text: TextSpan(
          text: s,
          style: const TextStyle(
            color: AppTokens.inkMuted,
            fontSize: 11,
            fontFamily: 'Roboto',
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      text.paint(canvas, at);
    }

    for (var i = 0; i < 4; i++) {
      final y = rect.top + rect.height * i / 3;
      canvas.drawLine(Offset(rect.left, y), Offset(rect.right, y), line);
      label(
        (maxY - (maxY - minY) * i / 3).toStringAsFixed(1),
        Offset(0, y - 6),
      );
    }
    label(minX.toStringAsFixed(0), Offset(rect.left, rect.bottom + 7));
    label(maxX.toStringAsFixed(0), Offset(rect.right - 25, rect.bottom + 7));
    final dot = Paint()..color = AppTokens.brandDeep.withValues(alpha: .7);
    for (final p in points) {
      final x =
          rect.left +
          (p.foodValue - minX) / math.max(.001, maxX - minX) * rect.width;
      final y =
          rect.bottom -
          (p.readingValue - minY) / math.max(.001, maxY - minY) * rect.height;
      canvas.drawCircle(Offset(x, y), 4, dot);
    }
  }

  @override
  bool shouldRepaint(covariant _PatternPlot oldDelegate) =>
      oldDelegate.points != points;
}
