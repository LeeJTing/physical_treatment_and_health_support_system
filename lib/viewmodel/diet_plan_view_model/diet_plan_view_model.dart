import 'package:physical_treatment_and_health_support_system/core/constants/app_constants.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/diet_planner_service/diet_planner_service.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/risk_assessment_service/risk_assessment_service.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/suitability_service/suitability_service.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/diet_plan.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/food_item.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/meal_log.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/safety_limit.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/auth_repository/i_auth_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/food_repository/i_food_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/meal_repository/i_meal_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/result.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/base_view_model.dart';

/// Diet plan generation, locking, replacement and adherence, and the meal recommendations
/// (Table 4.68; UC900 BF-8 to BF-11, A2, A5, A6).
class DietPlanViewModel extends BaseViewModel {
  final DietPlannerService _planner;
  final IMealRepository _mealRepo;
  final IFoodRepository _foods;
  final RiskAssessmentService _risk;
  final IAuthRepository _auth;
  final DateTime Function() _now;

  DietPlanViewModel(
    this._planner,
    this._mealRepo,
    this._foods,
    this._risk,
    this._auth, [
    DateTime Function()? now,
  ]) : _now = now ?? DateTime.now;

  String? _accountId;
  DietContext ctx = DietContext(limit: SafetyLimit.mostRestrictive());

  PlanType type = PlanType.daily;

  /// The plan in force.
  DietPlan? plan;

  /// Meals logged in the plan's period (for adherence and today's allowance).
  List<MealLog> logged = const [];

  /// Allowance left for today (FR700_039).
  Nutrients remaining = Nutrients.zero;

  /// Planner unavailable (E2): the patient can build a plan by hand (FR700_044).
  bool plannerDown = false;

  /// Meal recommendations for the next meal (FR700_021).
  List<FoodItem> recommendations = const [];
  MealSlot nextSlot = MealSlot.lunch;
  int _refresh = 0;

  String? _message;
  String? takeMessage() {
    final m = _message;
    _message = null;
    return m;
  }

  DateTime get _today {
    final n = _now();
    return DateTime(n.year, n.month, n.day);
  }

  Future<void> _context() async {
    _accountId ??= (await _auth.currentAccount()).dataOrNull?.accountId;
    final snap = await _risk.retrieve();
    if (snap case Success(:final data)) {
      ctx = DietContext.from(data);
      if (ctx.failSafe) _message = Messages.dietProfileUnavailable;
    } else {
      ctx = DietContext(limit: SafetyLimit.mostRestrictive(), failSafe: true);
      _message = Messages.dietProfileUnavailable; // E1 M4, C7
    }
  }

  /// Opens today's plan or this week's plan, generating one when none is stored.
  Future<void> load(PlanType t) async {
    type = t;
    setLoading(true);
    try {
      await _context();
      final id = _accountId;
      if (id == null) return;
      plan = (await _mealRepo.planFor(id, t, _today)).dataOrNull;
      if (plan == null) {
        await _generate();
      } else {
        await _markLogged();
      }
    } finally {
      setLoading(false);
    }
  }

  Future<List<MealLog>> _history() async {
    final id = _accountId!;
    return (await _mealRepo.findMeals(id, _today.subtract(const Duration(days: 30)), _now()))
            .dataOrNull ??
        const <MealLog>[];
  }

  /// Daily: breakfast, lunch, dinner and a snack (FR700_029). Weekly: seven days (FR700_030).
  Future<void> _generate({int seed = 0}) async {
    final id = _accountId;
    if (id == null) return;
    final history = await _history();
    final todays = history.where((m) => _sameDay(m.consumedAt, _today)).toList();
    final res = await _planner.generate(
      accountId: id,
      ctx: ctx,
      type: type,
      start: _today,
      consumedToday: Nutrients.sum(todays.map((m) => m.totals)),
      loggedSlots: todays.map((m) => m.mealType).toSet(),
      locked: plan?.meals.where((m) => m.isLocked).toList() ?? const [],
      history: history,
      seed: seed,
    );
    if (res case Success(:final data)) {
      plannerDown = false;
      plan = data;
      await _mealRepo.savePlan(data); // FR700_041, with its model version (FR700_043)
      await _markLogged();
    } else {
      plannerDown = true; // E2
      _message = Messages.plannerUnavailable; // M5
      await _markLogged();
    }
  }

  Future<void> generateDaily() async {
    type = PlanType.daily;
    plan = null;
    setLoading(true);
    await _context();
    await _generate();
    setLoading(false);
  }

  Future<void> generateWeekly() async {
    type = PlanType.weekly;
    plan = null;
    setLoading(true);
    await _context();
    await _generate();
    setLoading(false);
  }

  /// Regenerate on request (FR700_040, A6.1): unlocked meals change, locked ones stay.
  Future<void> regenerate() async {
    setLoading(true);
    await _context();
    await _generate(seed: DateTime.now().millisecond + 1);
    setLoading(false);
  }

  /// Rebuilds the remaining meals of today from what was already logged (FR700_034).
  Future<void> regenerateRemaining() async {
    final p = plan;
    if (p == null) return generateDaily();
    setLoading(true);
    final history = await _history();
    final todays = history.where((m) => _sameDay(m.consumedAt, _today)).toList();
    final res = await _planner.regenerateRemaining(
      plan: p,
      ctx: ctx,
      loggedToday: todays,
      history: history,
      seed: DateTime.now().millisecond,
    );
    if (res case Success(:final data)) {
      plan = data;
      await _mealRepo.savePlan(data);
    } else {
      plannerDown = true;
      _message = Messages.plannerUnavailable;
    }
    await _markLogged();
    setLoading(false);
  }

  /// Records, for each planned meal, whether a matching meal was logged (FR700_037); the adherence
  /// rate (FR700_038) and today's allowance (FR700_039).
  Future<void> _markLogged() async {
    final id = _accountId;
    final p = plan;
    final start = p?.startDate ?? _today;
    final end = p == null ? _now() : p.endDate.add(const Duration(hours: 23, minutes: 59));
    if (id != null) {
      logged = (await _mealRepo.findMeals(id, start, end)).dataOrNull ?? logged;
    }
    final todays = logged.where((m) => _sameDay(m.consumedAt, _today)).toList();
    remaining = ctx.remaining(Nutrients.sum(todays.map((m) => m.totals)));
    if (p != null) {
      final meals = [for (final m in p.meals) m.copyWith(isLogged: logged.any(m.matchLogged))];
      final updated = p.copyWith(meals: meals);
      plan = updated.copyWith(adherenceRate: double.parse(updated.adherence().toStringAsFixed(2)));
      await _mealRepo.updatePlan(plan!);
    }
    _recommend();
    notifyListeners();
  }

  /// Share of planned meals logged this week (FR700_038).
  double adherence() => plan?.adherence() ?? 0;

  /// Protects a slot from regeneration (FR700_036).
  Future<void> lockMeal(String plannedMealId, {bool on = true}) async {
    final p = plan;
    if (p == null) return;
    plan = p.copyWith(
      meals: [for (final m in p.meals) m.plannedMealId == plannedMealId ? m.lock(on) : m],
    );
    await _mealRepo.updatePlan(plan!);
    notifyListeners();
  }

  /// Alternatives that satisfy the same limits (FR700_035, A5.1 step 2).
  Future<List<FoodItem>> alternativesFor(PlannedMeal m) async {
    final p = plan;
    if (p == null) return const [];
    return _planner.alternativesFor(m, p, ctx);
  }

  /// Swaps in the chosen alternative and checks the plan again (A5.1 step 4, FR700_042). False when
  /// the swap would breach a limit (it is then not made).
  Future<bool> replaceMeal(String plannedMealId, FoodItem f) async {
    final p = plan;
    if (p == null) return false;
    final updated = p.copyWith(
      meals: [for (final m in p.meals) m.plannedMealId == plannedMealId ? m.replaceWith(f) : m],
    );
    final todays = logged.where((m) => _sameDay(m.consumedAt, _today));
    final problems = _planner.validate(updated, ctx, consumedToday: _consumedOutsidePlan(todays, updated));
    if (problems.isNotEmpty) {
      _message = 'That swap would go over a daily limit, so the plan was not changed.';
      notifyListeners();
      return false;
    }
    plan = updated;
    await _mealRepo.updatePlan(updated);
    await _markLogged();
    return true;
  }

  /// Logged meals today in slots the plan does not cover (eaten in addition to the plan).
  Nutrients _consumedOutsidePlan(Iterable<MealLog> todays, DietPlan p) {
    final planned = p.mealsFor(_today).map((m) => m.mealSlot).toSet();
    return Nutrients.sum(todays.where((m) => !planned.contains(m.mealType)).map((m) => m.totals));
  }

  /// Builds today's plan from foods the patient picked while the planner is down (FR700_044).
  /// Returns the problems found by the safety gate; empty when it was saved.
  Future<List<String>> saveManualPlan(Map<MealSlot, List<FoodItem>> chosen) async {
    final id = _accountId;
    if (id == null) return const ['session'];
    final p = _planner.buildManually(accountId: id, ctx: ctx, day: _today, chosen: chosen);
    final problems = _planner.validate(p, ctx);
    if (problems.isNotEmpty) return problems;
    plan = p;
    type = PlanType.daily;
    await _mealRepo.savePlan(p);
    await _markLogged();
    return const [];
  }

  /// Catalogue search for the manual plan, without foods the patient cannot eat.
  Future<List<FoodItem>> searchCatalogue(String term) async =>
      ((await _foods.search(term)).dataOrNull ?? const <FoodItem>[])
          .where((f) => !f.breachesAny(ctx.restrictions))
          .toList();

  // ------------------------------------------------------------- recommendations

  /// Meal recommendations from the profile and the running daily totals (FR700_021, C4): suitable
  /// foods for the next meal slot that fit what is left of today's allowance, the least sodium and
  /// free sugar first.
  Future<void> loadRecommendations() async {
    if (_accountId == null) await _context();
    final id = _accountId;
    if (id != null) {
      final todays = (await _mealRepo.findMeals(id, _today, _now())).dataOrNull ?? const <MealLog>[];
      remaining = ctx.remaining(Nutrients.sum(todays.map((m) => m.totals)));
    }
    await _allFoods();
    _recommend();
    notifyListeners();
  }

  /// Refresh (A2): the next few candidates.
  void refreshRecommendations() {
    _refresh++;
    _recommend();
    notifyListeners();
  }

  List<FoodItem> _catalogue = const [];
  Future<void> _allFoods() async {
    if (_catalogue.isEmpty) _catalogue = (await _foods.all()).dataOrNull ?? const [];
  }

  void _recommend() {
    final h = _now().hour;
    nextSlot = h < 10
        ? MealSlot.breakfast
        : h < 15
        ? MealSlot.lunch
        : h < 17
        ? MealSlot.snack
        : MealSlot.dinner;
    final share = switch (nextSlot) {
      MealSlot.breakfast => 0.25,
      MealSlot.lunch => 0.35,
      MealSlot.dinner => 0.30,
      MealSlot.snack => 0.10,
    };
    final energyCap = remaining.energyKcal > 0 ? remaining.energyKcal : ctx.dailyEnergyKcal * share;
    const s = SuitabilityService();
    final cands = _catalogue.where((f) {
      if (!f.mealSlots.contains(nextSlot.db)) return false;
      if (!{'meal', 'staple', 'protein', 'fruit', 'snack'}.contains(f.planRole)) return false;
      if (f.breachesAny(ctx.restrictions)) return false;
      final n = f.nutrientsFor(f.baseServingG);
      if (n.energyKcal > energyCap) return false;
      if (n.sodiumMg > remaining.sodiumMg.clamp(0, double.infinity) ||
          n.sugarG > remaining.sugarG.clamp(0, double.infinity)) {
        return false;
      }
      return s.mostRestrictive([...s.checkNutrients(f, f.baseServingG, ctx)]) == Verdict.suitable;
    }).toList()
      ..sort((a, b) {
        double score(FoodItem f) {
          final n = f.nutrientsFor(f.baseServingG);
          return n.sodiumMg / 100 + n.sugarG * 2 - n.proteinG / 5 + (f.planRole == 'meal' ? -1 : 0);
        }

        return score(a).compareTo(score(b));
      });
    if (cands.isEmpty) {
      recommendations = const [];
      return;
    }
    final start = (_refresh * 5) % cands.length;
    recommendations = [
      for (var i = 0; i < 5 && i < cands.length; i++) cands[(start + i) % cands.length],
    ];
  }

  static bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;
}
