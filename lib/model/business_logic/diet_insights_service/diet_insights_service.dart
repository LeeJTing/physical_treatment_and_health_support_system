import 'dart:math' as math;
import 'package:physical_treatment_and_health_support_system/model/business_logic/diet_planner_service/diet_planner_service.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/suitability_service/suitability_service.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/biometric_reading.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/diet_insights.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/diet_plan.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/food_item.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/meal_log.dart';

/// Fixed, inspectable summaries. Correlation never changes a target, verdict or treatment.
class DietInsightsService {
  static const minimumPairs = 12;
  static const minimumDays = 7;
  const DietInsightsService();
  static DateTime day(DateTime d) {
    final l = d.toLocal();
    return DateTime(l.year, l.month, l.day);
  }

  static DateTime monday(DateTime d) =>
      day(d).subtract(Duration(days: d.toLocal().weekday - 1));

  DietInsights build({
    required String accountId,
    required DateTime weekStart,
    required DateTime now,
    required List<MealLog> meals,
    required List<BiometricReading> readings,
    required DietContext context,
    Map<DateTime, DietPlan> plans = const {},
    bool plansAvailable = true,
    String? readingError,
  }) {
    final start = monday(weekStart);
    final weekEnd = start
        .add(const Duration(days: 7))
        .subtract(const Duration(microseconds: 1));
    final end = now.isBefore(weekEnd) ? now : weekEnd;
    final patternStart = day(end).subtract(const Duration(days: 27));
    final uniqueMeals = <String, MealLog>{};
    for (final m in meals) {
      if (m.accountId != accountId ||
          m.consumedAt.isBefore(patternStart) ||
          m.consumedAt.isAfter(end) ||
          m.items.isEmpty) {
        continue;
      }
      if (m.items.any(
        (i) =>
            !i.portionSizeG.isFinite ||
            i.portionSizeG <= 0 ||
            i.nutrients.toJson().values.any(
              (n) => n is! num || !n.isFinite || n < 0,
            ),
      )) {
        continue;
      }
      uniqueMeals[m.mealId] = m;
    }
    final valid = uniqueMeals.values.toList()
      ..sort((a, b) => a.consumedAt.compareTo(b.consumedAt));
    final days = [
      for (var i = 0; i < 7; i++)
        DietReviewDay(
          start.add(Duration(days: i)),
          valid
              .where((m) => day(m.consumedAt) == start.add(Duration(days: i)))
              .toList(),
          future: start.add(Duration(days: i)).isAfter(day(now)),
        ),
    ];
    final logged = days.where((d) => d.hasLogs).toList();
    final count = logged.length;
    final totals = Nutrients.sum(logged.map((d) => d.totals));
    double avg(double v) => count == 0 ? 0 : v / count;
    final limits = context.targets.limits, needs = context.targets.needs;
    final extras = valid
        .where((m) => !m.consumedAt.isBefore(start))
        .expand((m) => m.items)
        .fold(FoodExtras.zero, (a, i) => a + i.food.extrasFor(i.portionSizeG));
    final nutrients = [
      ReviewNutrient(
        'energy_kcal',
        'Energy',
        'kcal',
        avg(totals.energyKcal),
        minimum: context.dailyEnergyKcal * .75,
        maximum: context.dailyEnergyKcal,
      ),
      ReviewNutrient(
        'sodium_mg',
        'Sodium',
        'mg',
        avg(totals.sodiumMg),
        maximum: context.dailySodiumMg,
      ),
      ReviewNutrient(
        'sugar_g',
        'Free sugars',
        'g',
        avg(totals.sugarG),
        maximum: context.dailySugarG,
      ),
      ReviewNutrient('carb_g', 'Carbohydrate', 'g', avg(totals.carbG)),
      ReviewNutrient(
        'protein_g',
        'Protein',
        'g',
        avg(totals.proteinG),
        minimum: needs['protein_g_min'],
        maximum: limits['protein_g'],
      ),
      ReviewNutrient('fat_g', 'Fat', 'g', avg(totals.fatG)),
      if (needs['fibre_g_min'] case final n?)
        ReviewNutrient(
          'fibre_g',
          'Fibre',
          'g',
          avg(extras.fibreG),
          minimum: n,
          catalogueEstimate: true,
        ),
      if (needs['calcium_mg_min'] case final n?)
        ReviewNutrient(
          'calcium_mg',
          'Calcium',
          'mg',
          avg(extras.calciumMg),
          minimum: n,
          catalogueEstimate: true,
        ),
      if (limits['sat_fat_g'] case final n?)
        ReviewNutrient(
          'sat_fat_g',
          'Saturated fat',
          'g',
          avg(extras.satFatG),
          maximum: n,
          catalogueEstimate: true,
        ),
    ];
    var due = 0, followed = 0;
    for (final d in days.where((d) => !d.future)) {
      final p = plans[d.date];
      if (p == null || p.accountId != accountId) continue;
      for (final slot in MealSlot.values) {
        final planned = p
            .mealsFor(d.date)
            .where((m) => m.mealSlot == slot)
            .toList();
        if (planned.isEmpty) continue;
        final eaten = d.meals.where((m) => m.mealType == slot).toList();
        final deadline = DietPlannerService.deadlineOf(slot, d.date);
        if (eaten.isEmpty && (deadline == null || deadline.isAfter(now))) {
          continue;
        }
        due++;
        if (DietPlannerService.follows(planned, eaten)) followed++;
      }
    }
    final weeklyItems = [
      for (final d in logged)
        for (final m in d.meals) ...m.items,
    ];
    final contributions = <String, List<FoodContribution>>{};
    for (final key in ['energy_kcal', 'sodium_mg', 'sugar_g']) {
      final grouped = <String, ({String name, double amount})>{};
      for (final i in weeklyItems) {
        final amount = (i.nutrients.toJson()[key] as num).toDouble();
        final old = grouped[i.food.foodKey];
        grouped[i.food.foodKey] = (
          name: i.food.foodName,
          amount: (old?.amount ?? 0) + amount,
        );
      }
      final sum = grouped.values.fold(0.0, (a, b) => a + b.amount);
      contributions[key] = [
        for (final e in grouped.entries)
          if (e.value.amount > 0)
            FoodContribution(
              e.key,
              e.value.name,
              e.value.amount,
              sum > 0 ? e.value.amount / sum : 0,
            ),
      ]..sort((a, b) => b.amount.compareTo(a.amount));
    }
    final uniqueReadings = <String, BiometricReading>{};
    for (final r in readings) {
      if (r.accountId == accountId &&
          !r.recordedAt.isAfter(end) &&
          !r.recordedAt.isBefore(patternStart) &&
          r.primaryValue.isFinite &&
          r.isPlausible() &&
          r.isValidBloodPressure()) {
        uniqueReadings[r.duplicateKey()] = r;
      }
    }
    final rs = uniqueReadings.values.toList()
      ..sort((a, b) => a.recordedAt.compareTo(b.recordedAt));
    final glucose = <MealHealthPoint>[];
    final used = <String>{};
    for (final m in valid) {
      final matches =
          rs
              .where(
                (r) =>
                    r.metricType == MetricType.bloodGlucose &&
                    r.measurementContext == MeasurementContext.postMeal &&
                    !used.contains(r.duplicateKey()) &&
                    r.recordedAt.difference(m.consumedAt).inSeconds >=
                        90 * 60 &&
                    r.recordedAt.difference(m.consumedAt).inSeconds <=
                        150 * 60 &&
                    !valid.any(
                      (other) =>
                          other.mealId != m.mealId &&
                          other.consumedAt.isAfter(m.consumedAt) &&
                          !other.consumedAt.isAfter(r.recordedAt),
                    ),
              )
              .toList()
            ..sort(
              (a, b) => (a.recordedAt.difference(m.consumedAt).inSeconds - 7200)
                  .abs()
                  .compareTo(
                    (b.recordedAt.difference(m.consumedAt).inSeconds - 7200)
                        .abs(),
                  ),
            );
      if (matches.isEmpty) continue;
      final r = matches.first;
      used.add(r.duplicateKey());
      glucose.add(
        MealHealthPoint(
          m.consumedAt,
          m.totals.carbG,
          r.primaryValue,
          '${m.mealType.label}: ${r.recordedAt.difference(m.consumedAt).inMinutes} minutes later',
        ),
      );
    }
    final pressure = <MealHealthPoint>[];
    for (
      var d = patternStart;
      d.isBefore(day(end));
      d = d.add(const Duration(days: 1))
    ) {
      final daily = valid.where((m) => day(m.consumedAt) == d).toList();
      if (daily
              .where((m) => m.mealType != MealSlot.snack)
              .map((m) => m.mealType)
              .toSet()
              .length !=
          3) {
        continue;
      }
      final next = d.add(const Duration(days: 1));
      final morning = rs
          .where(
            (r) =>
                r.metricType == MetricType.bloodPressure &&
                day(r.recordedAt) == next &&
                r.recordedAt.toLocal().hour >= 6 &&
                r.recordedAt.toLocal().hour < 12,
          )
          .toList();
      if (morning.isEmpty) continue;
      pressure.add(
        MealHealthPoint(
          d,
          Nutrients.sum(daily.map((m) => m.totals)).sodiumMg,
          morning.fold(0.0, (a, b) => a + b.primaryValue) / morning.length,
          '3 main meals logged; next morning 06:00–12:00',
        ),
      );
    }
    return DietInsights(
      WeeklyDietReview(
        start: start,
        end: weekEnd,
        days: days,
        nutrients: nutrients,
        contributors: contributions,
        followedSlots: followed,
        dueSlots: due,
        plansAvailable: plansAvailable,
      ),
      patternStart,
      end,
      [
        _pattern(
          'Meal carbohydrates and later glucose',
          'Meal carbohydrate (g)',
          'After-meal glucose (mmol/L)',
          'Pairs one meal with one reading marked After a meal, 90–150 minutes later. Meals with another food log before the reading are excluded.',
          glucose,
          readingError,
        ),
        _pattern(
          'Recorded sodium and next-morning pressure',
          'Recorded daily sodium (mg)',
          'Next-morning systolic pressure (mmHg)',
          'Uses days with breakfast, lunch and dinner logged, paired with average systolic readings the next morning (06:00–12:00). Unlogged snacks or ingredients may still be missing.',
          pressure,
          readingError,
        ),
      ],
    );
  }

  MealHealthPattern _pattern(
    String title,
    String x,
    String y,
    String method,
    List<MealHealthPoint> points,
    String? error,
  ) {
    final days = points.map((p) => day(p.at)).toSet().length;
    String? reason = error;
    if (reason == null &&
        (points.length < minimumPairs || days < minimumDays)) {
      reason =
          'Not enough paired records: ${points.length}/$minimumPairs pairs across $days/$minimumDays days. These are minimum app checks, not clinical validation.';
    }
    if (reason == null &&
        (points.map((p) => p.foodValue).toSet().length < 4 ||
            points.map((p) => p.readingValue).toSet().length < 4)) {
      reason =
          'There is too little variation in these records to describe a pattern.';
    }
    return MealHealthPattern(
      title: title,
      foodLabel: x,
      readingLabel: y,
      method: method,
      points: points,
      distinctDays: days,
      correlation: reason == null
          ? spearman(
              points.map((p) => p.foodValue).toList(),
              points.map((p) => p.readingValue).toList(),
            )
          : null,
      withheldReason: reason,
    );
  }

  /// Average ranks for ties; zero variance is withheld rather than interpreted as no relation.
  static double? spearman(List<double> a, List<double> b) {
    if (a.length != b.length ||
        a.length < 2 ||
        [...a, ...b].any((v) => !v.isFinite)) {
      return null;
    }
    List<double> ranks(List<double> values) {
      final order = List.generate(values.length, (i) => i)
        ..sort((i, j) => values[i].compareTo(values[j]));
      final out = List<double>.filled(values.length, 0);
      var i = 0;
      while (i < order.length) {
        var j = i + 1;
        while (j < order.length && values[order[j]] == values[order[i]]) {
          j++;
        }
        final rank = (i + j + 1) / 2;
        for (var k = i; k < j; k++) {
          out[order[k]] = rank;
        }
        i = j;
      }
      return out;
    }

    final x = ranks(a), y = ranks(b);
    final mean = (a.length + 1) / 2;
    var xy = 0.0, xx = 0.0, yy = 0.0;
    for (var i = 0; i < a.length; i++) {
      final dx = x[i] - mean, dy = y[i] - mean;
      xy += dx * dy;
      xx += dx * dx;
      yy += dy * dy;
    }
    return xx == 0 || yy == 0
        ? null
        : (xy / math.sqrt(xx * yy)).clamp(-1.0, 1.0);
  }
}
