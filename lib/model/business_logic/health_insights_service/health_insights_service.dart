import 'package:physical_treatment_and_health_support_system/model/business_logic/diet_insights_service/plan_comparison_service.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/biometric_reading.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/diet_plan.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/food_item.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/health_insights.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/meal_log.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/patient_treatment_plan.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/plan_comparison.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/recovery_check_in.dart';

class HealthInsightsService {
  const HealthInsightsService();
  static DateTime day(DateTime d) => DateTime(d.year, d.month, d.day);
  static DateTime monday(DateTime d) =>
      day(d).subtract(Duration(days: d.weekday - 1));
  static bool demoMeal(MealLog m) =>
      (m.modelVersion ?? '').startsWith('presentation-demo');
  static bool demoReading(BiometricReading r) =>
      (r.sourceDevice ?? '').toLowerCase().contains('presentation demo') ||
      (r.sourceDevice ?? '').toLowerCase().contains('synthetic');
  static String stamp(DateTime d) =>
      '${d.day}/${d.month} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  HealthInsights build({
    required String accountId,
    required DateTime start,
    required DateTime now,
    required List<MealLog> meals,
    required List<BiometricReading> readings,
    required List<DietPlan> plans,
    required List<PatientTreatmentPlan> treatments,
    required List<ExerciseEvidence> sessions,
    required List<RecoveryCheckIn> checkIns,
    bool includeDemo = true,
    bool plansAvailable = true,
    List<String> notices = const [],
    DateTime? lastSync,
  }) {
    final beginning = monday(start),
        end = monday(start).add(const Duration(days: 7));
    final asOf = now.isBefore(end)
        ? now
        : end.subtract(const Duration(microseconds: 1));
    final recoveryFrom = beginning.subtract(const Duration(days: 27));
    bool inWeek(DateTime at) =>
        !at.isBefore(beginning) && at.isBefore(end) && !at.isAfter(asOf);
    final ownedMeals = {
      for (final m in meals)
        if (m.accountId == accountId && !m.consumedAt.isAfter(asOf))
          m.mealId: m,
    }.values.toList();
    final ownedReadings = {
      for (final r in readings)
        if (r.accountId == accountId &&
            !r.recordedAt.isAfter(asOf) &&
            !r.recordedAt.isBefore(asOf.subtract(const Duration(days: 120))))
          r.duplicateKey(): r,
    }.values.toList();
    final ownPlans = treatments.where((p) => p.accountId == accountId).toList();
    final planIds = ownPlans.map((p) => p.patientPlanId).toSet();
    final ownedSessions = {
      for (final s in sessions)
        if (s.session.accountId == accountId &&
            s.session.isCompleted() &&
            s.session.completedAt != null &&
            !s.session.completedAt!.isBefore(recoveryFrom) &&
            !s.session.completedAt!.isAfter(asOf))
          s.session.sessionId: s,
    }.values.toList();
    final ownedChecks = checkIns
        .where(
          (r) =>
              r.accountId == accountId &&
              planIds.contains(r.patientPlanId) &&
              !r.date.isBefore(recoveryFrom) &&
              !r.date.isAfter(day(asOf)),
        )
        .toList();
    final demoCount =
        ownedMeals.where(demoMeal).length +
        ownedReadings.where(demoReading).length +
        ownedSessions.where((s) => s.isDemo).length +
        ownedChecks.where((r) => r.isDemo).length;
    final usableMeals = ownedMeals
        .where((m) => includeDemo || !demoMeal(m))
        .toList();
    final invalid = ownedReadings
        .where(
          (r) =>
              !r.primaryValue.isFinite ||
              !(r.secondaryValue?.isFinite ?? true) ||
              !r.isPlausible() ||
              !r.isValidBloodPressure(),
        )
        .length;
    final usableReadings =
        ownedReadings
            .where(
              (r) =>
                  (includeDemo || !demoReading(r)) &&
                  r.primaryValue.isFinite &&
                  (r.secondaryValue?.isFinite ?? true) &&
                  r.isPlausible() &&
                  r.isValidBloodPressure(),
            )
            .toList()
          ..sort((a, b) => a.recordedAt.compareTo(b.recordedAt));
    final usableSessions = ownedSessions
        .where((s) => includeDemo || !s.isDemo)
        .toList();
    final usableChecks =
        ownedChecks.where((r) => includeDemo || !r.isDemo).toList()
          ..sort((a, b) => a.date.compareTo(b.date));
    final periodMeals = usableMeals.where((m) => inWeek(m.consumedAt)).toList();
    final periodSessions = usableSessions
        .where((s) => inWeek(s.session.completedAt!))
        .toList();
    final map = <DateTime, DietPlan>{};
    final availablePlans = plans
        .where(
          (p) => includeDemo || !p.modelVersion.startsWith('presentation-demo'),
        )
        .toList();
    for (var i = -7; i < 7; i++) {
      final date = beginning.add(Duration(days: i));
      final p = PlanComparisonService.selectPlan(
        availablePlans,
        accountId,
        date,
      );
      if (p != null) map[date] = p;
    }
    final comparison = const PlanComparisonService().build(
      accountId: accountId,
      start: beginning,
      now: asOf,
      meals: usableMeals,
      plans: map,
      plansAvailable: plansAvailable,
    );
    final events = <HealthTimelineEvent>[];
    for (final m in periodMeals) {
      events.add(
        HealthTimelineEvent(
          m.mealId,
          m.consumedAt,
          TimelineKind.meal,
          '${m.mealType.label} logged',
          '${m.items.map((i) => '${i.food.foodName} ${i.portionSizeG.round()} g').join(', ')}\n${m.totalEnergyKcal.round()} kcal · ${m.totalSodiumMg.round()} mg sodium · ${m.totalSugarG.toStringAsFixed(1)} g free sugars',
          isDemo: demoMeal(m),
        ),
      );
    }
    for (final r in usableReadings.where((r) => inWeek(r.recordedAt))) {
      events.add(
        HealthTimelineEvent(
          r.readingId,
          r.recordedAt,
          TimelineKind.reading,
          r.metricType.label,
          '${r.display()}\n${r.measurementContext?.label ?? 'Context not supplied'} · ${r.sourceDevice ?? r.source.db}\nRecorded ${stamp(r.recordedAt)}${r.importedAt == null ? '' : ' · Imported ${stamp(r.importedAt!)}'}',
          isDemo: demoReading(r),
        ),
      );
    }
    for (final s in periodSessions) {
      events.add(
        HealthTimelineEvent(
          s.session.sessionId,
          s.session.completedAt!,
          TimelineKind.exercise,
          s.exerciseName,
          '${s.planName}\n${s.session.durationMinutes().toStringAsFixed(1)} minutes${s.session.postureAccuracy == null ? '' : ' · ${s.session.postureAccuracy!.toStringAsFixed(0)}% posture result'}',
          isDemo: s.isDemo,
        ),
      );
    }
    for (final r in usableChecks.where((r) => inWeek(r.date))) {
      events.add(
        HealthTimelineEvent(
          r.checkInId,
          r.date.add(const Duration(hours: 12)),
          TimelineKind.recovery,
          'Recovery check-in',
          'Daily diary; noon marker is a layout position, not a measurement time.\nPain ${r.pain}/10 · stiffness ${r.stiffness}/10 · difficulty ${r.difficulty}/5\n${r.notes}',
          isDemo: r.isDemo,
        ),
      );
    }
    for (var i = 0; i < 7; i++) {
      final date = beginning.add(Duration(days: i)),
          plan = map[beginning.add(Duration(days: i))];
      if (plan == null) continue;
      for (final slot in MealSlot.values) {
        final items = plan.meals
            .where((m) => day(m.planDate) == date && m.mealSlot == slot)
            .toList();
        if (items.isEmpty) continue;
        final hour = switch (slot) {
          MealSlot.breakfast => 8,
          MealSlot.lunch => 13,
          MealSlot.dinner => 19,
          MealSlot.snack => 16,
        };
        events.add(
          HealthTimelineEvent(
            'planned-${date.toIso8601String()}-${slot.db}',
            date.add(Duration(hours: hour)),
            TimelineKind.planned,
            '${slot.label} planned',
            'Suggested time for display only.\n${items.map((i) => '${i.food.foodName} ${i.portionSizeG.round()} g').join(', ')}',
            isDemo: plan.modelVersion.startsWith('presentation-demo'),
          ),
        );
      }
    }
    events.sort(
      (a, b) => a.at == b.at ? a.id.compareTo(b.id) : a.at.compareTo(b.at),
    );
    final loggedDays = periodMeals.map((m) => day(m.consumedAt)).toSet();
    final complete = loggedDays
        .where(
          (d) =>
              periodMeals
                  .where(
                    (m) =>
                        day(m.consumedAt) == d && m.mealType != MealSlot.snack,
                  )
                  .map((m) => m.mealType)
                  .toSet()
                  .length ==
              3,
        )
        .length;
    final elapsed = (day(asOf).difference(beginning).inDays + 1).clamp(0, 7);
    final facts = <InsightFact>[];
    final compared = comparison.compared,
        close = comparison.count(MealComparisonStatus.close);
    facts.add(
      InsightFact(
        'Diet plan follow-through',
        compared.isEmpty
            ? 'No comparable saved meals in this period. Unlogged meals remain unknown.'
            : '$close of ${compared.length} compared meals were close to plan (${(100 * close / compared.length).round()}%). ${compared.length - close} had food or portion changes. Missing logs are excluded.',
        compared.map((m) => m.date).toSet().toList(),
      ),
    );
    final prior = comparison.previousMeals
        .where(
          (m) => m.date.isBefore(
            beginning
                .subtract(const Duration(days: 7))
                .add(Duration(days: elapsed)),
          ),
        )
        .toList();
    if (compared.isNotEmpty && prior.isNotEmpty) {
      final previousClose = prior
          .where((m) => m.status == MealComparisonStatus.close)
          .length;
      final delta =
          100 * close / compared.length - 100 * previousClose / prior.length;
      facts.add(
        InsightFact(
          'Previous period comparison',
          'Close-to-plan share changed by ${delta >= 0 ? '+' : ''}${delta.toStringAsFixed(0)} percentage points. Previous period: $previousClose/${prior.length}; selected period: $close/${compared.length}. Both cover $elapsed elapsed calendar days; recorded-meal coverage may differ.',
          compared.map((m) => m.date).toSet().toList(),
        ),
      );
    }
    if (periodMeals.isNotEmpty) {
      final n = Nutrients.sum(
        periodMeals.map((m) => m.totals),
      ).scale(1 / loggedDays.length);
      facts.add(
        InsightFact(
          'Recorded nutrition',
          'On ${loggedDays.length} logged days, recorded intake averaged ${n.energyKcal.round()} kcal, ${n.sodiumMg.round()} mg sodium and ${n.sugarG.toStringAsFixed(1)} g free sugars per logged day. $complete days had all three main meals recorded. Partial logs can understate intake.',
          loggedDays.toList(),
        ),
      );
    }
    final changed = compared.where((m) => m.changed).toList();
    if (changed.isNotEmpty) {
      final counts = <MealSlot, int>{};
      for (final m in changed) {
        counts[m.slot] = (counts[m.slot] ?? 0) + 1;
      }
      final ranked = counts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      facts.add(
        InsightFact(
          'A useful next step',
          '${ranked.first.key.label} had ${ranked.first.value} changed meals. Review those records, then use What if I change this meal? when logging your next meal to compare suitable foods and portions.',
          changed
              .where((m) => m.slot == ranked.first.key)
              .map((m) => m.date)
              .toSet()
              .toList(),
        ),
      );
    } else if (compared.isNotEmpty) {
      facts.add(
        InsightFact(
          'Keep the useful habit',
          'Your compared meals were close to plan. Keep checking food amounts and logging what you actually eat.',
          compared.map((m) => m.date).toSet().toList(),
        ),
      );
    }
    facts.add(
      InsightFact(
        'Treatment activity',
        '${periodSessions.length} completed exercise sessions across ${periodSessions.map((s) => day(s.session.completedAt!)).toSet().length} days; ${periodSessions.fold<double>(0, (a, s) => a + s.session.durationMinutes()).toStringAsFixed(1)} minutes recorded. This describes recorded activity, not recovery effectiveness.',
        periodSessions.map((s) => day(s.session.completedAt!)).toSet().toList(),
      ),
    );
    final sources = <String, int>{};
    // Compare averages of daily means, so a burst of watch readings cannot dominate a week.
    // Glucose contexts stay separate; temporal differences are descriptive observations only.
    final previousStart = beginning.subtract(const Duration(days: 7));
    for (final metric in MetricType.values) {
      final contexts = metric == MetricType.bloodGlucose
          ? MeasurementContext.values.cast<MeasurementContext?>()
          : <MeasurementContext?>[null];
      for (final context in contexts) {
        final relevant = usableReadings
            .where(
              (r) =>
                  r.metricType == metric &&
                  (metric != MetricType.bloodGlucose ||
                      r.measurementContext == context),
            )
            .toList();
        Map<DateTime, List<double>> daily(DateTime from, DateTime to) {
          final values = <DateTime, List<double>>{};
          for (final r in relevant.where(
            (r) => !r.recordedAt.isBefore(from) && r.recordedAt.isBefore(to),
          )) {
            (values[day(r.recordedAt)] ??= []).add(r.primaryValue);
          }
          return values;
        }

        final current = daily(
          beginning,
          asOf.add(const Duration(microseconds: 1)),
        );
        final previous = daily(
          previousStart,
          asOf
              .subtract(const Duration(days: 7))
              .add(const Duration(microseconds: 1)),
        );
        if (current.length < 2 || previous.length < 2) continue;
        double mean(Map<DateTime, List<double>> values) =>
            values.values
                .map((v) => v.reduce((a, b) => a + b) / v.length)
                .reduce((a, b) => a + b) /
            values.length;
        final first = mean(previous),
            last = mean(current),
            delta = last - first;
        final name = metric == MetricType.bloodPressure
            ? 'Systolic blood pressure'
            : metric.label;
        facts.add(
          InsightFact(
            '$name${context == null ? '' : ' · ${context.label}'}',
            'Average of daily means: ${first.toStringAsFixed(1)} → ${last.toStringAsFixed(1)} ${metric.unit} (${delta >= 0 ? '+' : ''}${delta.toStringAsFixed(1)}). Previous period has ${previous.length} recorded days; selected period has ${current.length}. Unequal coverage and source differences can affect the comparison. This does not show that diet or exercise caused the change.',
            current.keys.toList(),
          ),
        );
      }
    }
    for (final r in usableReadings) {
      final label =
          r.sourceDevice ??
          (r.source == ReadingSource.manual
              ? 'Manual entry'
              : 'Imported source not named');
      sources[label] = (sources[label] ?? 0) + 1;
    }
    final recovery = [
      for (final p in ownPlans)
        RecoveryProgress(
          p.patientPlanId,
          p.plan.planName,
          usableChecks
              .where((r) => r.patientPlanId == p.patientPlanId)
              .toList(),
          usableSessions
              .where((s) => s.session.patientPlanId == p.patientPlanId)
              .toList(),
        ),
    ];
    return HealthInsights(
      accountId: accountId,
      start: beginning,
      end: end.subtract(const Duration(days: 1)),
      asOf: asOf,
      includesDemo: includeDemo,
      meals: periodMeals,
      readings: usableReadings,
      sessions: periodSessions,
      timeline: events,
      facts: facts,
      recovery: recovery,
      comparison: comparison,
      sourceCounts: sources,
      notices: notices,
      demoCount: demoCount,
      loggedDays: loggedDays.length,
      completeMealDays: complete,
      elapsedDays: elapsed,
      invalidReadings: invalid,
      lastSync: lastSync,
    );
  }
}
