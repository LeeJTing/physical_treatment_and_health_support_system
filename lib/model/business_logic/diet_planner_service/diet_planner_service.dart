import 'package:physical_treatment_and_health_support_system/core/constants/app_constants.dart';
import 'package:physical_treatment_and_health_support_system/core/utils/id_utils.dart';
import 'package:physical_treatment_and_health_support_system/model/result.dart';
import 'package:physical_treatment_and_health_support_system/shared_client/api_client/api_client.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/suitability_service/suitability_service.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/diet_plan.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/food_item.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/meal_log.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/food_repository/i_food_repository.dart';

/// Generates daily and weekly plans inside the safety limits, excluding anything the patient cannot
/// eat (Table 4.93; UC900 A5, A6). The plan comes from /plan on the AI server (condition-aware
/// planner with a learned preference ranker, DC700_07); the safety gate is applied again here, on
/// this side of the connection (C11, C12): a plan that breaches a daily limit, or holds a food that
/// would be Not Suitable, is rejected and requested again.
class DietPlannerService {
  final ApiClient _api;
  final IFoodRepository _foods;
  final SuitabilityService suitability;

  /// Recorded with every generated plan (FR700_043).
  String modelVersion = '';

  DietPlannerService(this._api, this._foods, [this.suitability = const SuitabilityService()]);

  static const _maxAttempts = 3;

  /// Builds a plan within the daily limits (FR700_029 to FR700_033). [consumedToday] and
  /// [loggedSlots] let the rest of today be planned around what was already eaten (FR700_034);
  /// [locked] meals are kept as they are (FR700_036); [history] feeds the preference ranker (C4).
  Future<Result<DietPlan>> generate({
    required String accountId,
    required DietContext ctx,
    required PlanType type,
    required DateTime start,
    Nutrients consumedToday = Nutrients.zero,
    Set<MealSlot> loggedSlots = const {},
    List<PlannedMeal> locked = const [],
    List<MealLog> history = const [],
    List<String> exclude = const [],
    int seed = 0,
  }) async {
    final counts = <String, int>{};
    for (final m in history) {
      for (final i in m.items) {
        counts[i.food.foodKey] = (counts[i.food.foodKey] ?? 0) + 1;
      }
    }
    final day0 = DateTime(start.year, start.month, start.day);
    final today = DateTime.now();
    for (var attempt = 0; attempt < _maxAttempts; attempt++) {
      final res = await _api.post(
        AppConstants.planPath,
        {
          'plan_type': type.db,
          'start_date': _d(day0),
          'today': _d(today),
          'conditions': ctx.failSafe ? const ['HYPERTENSION', 'DIABETES'] : ctx.conditionCodes,
          'restrictions': ctx.restrictionCodes,
          'risk_level': ctx.riskLevel.db,
          'limits': {
            'daily_calorie_target': ctx.dailyEnergyKcal,
            'daily_sodium_limit_mg': ctx.dailySodiumMg,
            'daily_sugar_limit_g': ctx.dailySugarG,
          },
          'consumed_today': {
            'energy_kcal': consumedToday.energyKcal,
            'sodium_mg': consumedToday.sodiumMg,
            'sugar_g': consumedToday.sugarG,
          },
          'logged_slots_today': loggedSlots.map((s) => s.db).toList(),
          'locked': [
            for (final m in locked)
              {
                'plan_date': _d(m.planDate),
                'meal_slot': m.mealSlot.db,
                'food_key': m.food.foodKey,
                'portion_g': m.portionSizeG,
              },
          ],
          'history': [
            for (final e in counts.entries) {'food_key': e.key, 'count': e.value},
          ],
          'exclude': exclude,
          'seed': seed + attempt * 101,
        },
        timeout: AppConstants.planTimeout,
      );
      if (res case Failure(:final code, :final cause)) {
        return Failure(Messages.plannerUnavailable, code: code, cause: cause); // E2
      }
      final body = res.dataOrNull!;
      modelVersion = (body['model_version'] ?? '') as String;
      final meals = <PlannedMeal>[];
      for (final day in (body['days'] as List? ?? const [])) {
        final dm = Map<String, dynamic>.from(day as Map);
        final date = DateTime.parse(dm['plan_date'] as String);
        for (final slot in (dm['meals'] as List? ?? const [])) {
          final sm = Map<String, dynamic>.from(slot as Map);
          final ms = MealSlot.fromDb(sm['meal_slot'] as String?);
          final wasLocked = locked.where((l) => _same(l.planDate, date) && l.mealSlot == ms).toList();
          if (wasLocked.isNotEmpty) {
            meals.addAll(wasLocked.map((l) => l.carriedOver()));
            continue;
          }
          for (final it in (sm['items'] as List? ?? const [])) {
            final im = Map<String, dynamic>.from(it as Map);
            final food = (await _foods.byKey(im['food_key'] as String)).dataOrNull;
            if (food == null) continue;
            meals.add(PlannedMeal.of(food, date, ms, ((im['portion_g'] ?? food.baseServingG) as num).toDouble()));
          }
        }
      }
      // Locked or already-eaten slots the server skipped stay in the plan as they were.
      for (final l in locked) {
        final kept = meals.any(
          (m) => _same(m.planDate, l.planDate) && m.mealSlot == l.mealSlot && m.food.foodId == l.food.foodId,
        );
        if (!kept) meals.add(l.carriedOver());
      }
      final plan = DietPlan(
        dietPlanId: newId(),
        accountId: accountId,
        safetyLimitId: ctx.limit.safetyLimitId,
        planType: type,
        startDate: day0,
        endDate: type == PlanType.weekly ? day0.add(const Duration(days: 6)) : day0,
        modelVersion: modelVersion,
        generatedAt: DateTime.now(),
        meals: meals,
      );
      if (validate(plan, ctx, consumedToday: consumedToday).isEmpty) {
        return Success(plan);
      }
    }
    return const Failure(Messages.plannerUnavailable, code: 'plan_breaches_limits');
  }

  /// Rebuilds the rest of the day from what was eaten (FR700_034): the slots already logged and
  /// the locked meals stay; the others are planned again within what is left of the allowance.
  Future<Result<DietPlan>> regenerateRemaining({
    required DietPlan plan,
    required DietContext ctx,
    required List<MealLog> loggedToday,
    List<MealLog> history = const [],
    int seed = 1,
  }) async {
    final today = DateTime.now();
    final consumed = Nutrients.sum(loggedToday.map((m) => m.totals));
    final res = await generate(
      accountId: plan.accountId,
      ctx: ctx,
      type: plan.planType,
      start: plan.startDate,
      consumedToday: consumed,
      loggedSlots: loggedToday.map((m) => m.mealType).toSet(),
      locked: [
        ...plan.meals.where((m) => m.isLocked),
        // Slots already eaten today stay as planned (they are marked logged).
        ...plan.meals.where(
          (m) => _same(m.planDate, today) && loggedToday.any((l) => l.mealType == m.mealSlot) && !m.isLocked,
        ),
      ],
      history: history,
      seed: seed,
    );
    return res;
  }

  /// The safety gate (FR700_042, C11): every day within the calorie target and the sodium and free
  /// sugar limits, and no food that would be Not Suitable. Returns the problems; empty = valid.
  List<String> validate(DietPlan p, DietContext ctx, {Nutrients consumedToday = Nutrients.zero}) {
    final problems = <String>[];
    final today = DateTime.now();
    for (final day in p.days()) {
      var t = p.totalsFor(day);
      if (_same(day, today)) t = t + consumedToday;
      if (t.energyKcal > ctx.dailyEnergyKcal + 0.5) problems.add('${_d(day)} energy');
      if (t.sodiumMg > ctx.dailySodiumMg + 0.5) problems.add('${_d(day)} sodium');
      if (t.sugarG > ctx.dailySugarG + 0.05) problems.add('${_d(day)} free sugars');
    }
    for (final m in p.meals) {
      if (suitability.isExcludedFromPlans(m.food, ctx, m.portionSizeG)) {
        problems.add('${m.food.foodName} is not suitable');
      }
    }
    return problems;
  }

  /// Alternatives for a planned meal that keep its day within the same limits (FR700_035), best
  /// fitting first: same plan role and slot, suitable, and the day's totals stay under the limits.
  Future<List<FoodItem>> alternativesFor(PlannedMeal m, DietPlan p, DietContext ctx) async {
    final all = (await _foods.all()).dataOrNull ?? const <FoodItem>[];
    final dayWithout = p.totalsFor(m.planDate) - m.nutrients;
    final out = <(double, FoodItem)>[];
    for (final f in all) {
      if (f.foodId == m.food.foodId || f.planRole != m.food.planRole) continue;
      if (!f.mealSlots.contains(m.mealSlot.db)) continue;
      if (f.breachesAny(ctx.restrictions)) continue;
      final repl = m.replaceWith(f);
      if (suitability.isExcludedFromPlans(f, ctx, repl.portionSizeG)) continue;
      final t = dayWithout + repl.nutrients;
      if (t.energyKcal > ctx.dailyEnergyKcal || t.sodiumMg > ctx.dailySodiumMg || t.sugarG > ctx.dailySugarG) {
        continue;
      }
      out.add(((repl.energyKcal - m.energyKcal).abs() + repl.sodiumMg / 20 + repl.sugarG * 5, f));
    }
    out.sort((a, b) => a.$1.compareTo(b.$1));
    return out.map((e) => e.$2).take(8).toList();
  }

  /// Fall-back while the planner is unavailable (FR700_044): a one-day plan from the foods the
  /// patient chose for each slot, one serving each. The caller checks it with [validate].
  DietPlan buildManually({
    required String accountId,
    required DietContext ctx,
    required DateTime day,
    required Map<MealSlot, List<FoodItem>> chosen,
  }) {
    final d = DateTime(day.year, day.month, day.day);
    return DietPlan(
      dietPlanId: newId(),
      accountId: accountId,
      safetyLimitId: ctx.limit.safetyLimitId,
      planType: PlanType.daily,
      startDate: d,
      endDate: d,
      modelVersion: 'manual',
      generatedAt: DateTime.now(),
      meals: [
        for (final e in chosen.entries)
          for (final f in e.value) PlannedMeal.of(f, d, e.key, f.baseServingG),
      ],
    );
  }

  static String _d(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  static bool _same(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;
}
