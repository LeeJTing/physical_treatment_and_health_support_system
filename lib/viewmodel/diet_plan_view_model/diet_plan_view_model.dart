import 'package:physical_treatment_and_health_support_system/core/constants/app_constants.dart';
import 'package:physical_treatment_and_health_support_system/core/utils/id_utils.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/diet_planner_service/diet_planner_service.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/diet_planner_service/plan_change.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/local_notification_service/local_notification_service.dart';
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

  /// Rings the "follow your diet plan" alerts of today's planned meals not logged yet.
  final LocalNotificationService? _alerts;

  DietPlanViewModel(
    this._planner,
    this._mealRepo,
    this._foods,
    this._risk,
    this._auth, [
    DateTime Function()? now,
    this._alerts,
  ]) : _now = now ?? DateTime.now;

  String? _accountId;
  DietContext ctx = DietContext(limit: SafetyLimit.mostRestrictive());

  PlanType type = PlanType.daily;

  /// The plan in force.
  DietPlan? plan;
  String? changeInProgress;

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

  /// Today's foods are edited in the daily plan, also when viewed as part of a week.
  bool canEditDay(DateTime day) => type == PlanType.daily || !_sameDay(day, _today);

  DietPlan _dailyPart(DietPlan weekly) => DietPlan(
    dietPlanId: newId(),
    accountId: weekly.accountId,
    safetyLimitId: weekly.safetyLimitId,
    planType: PlanType.daily,
    startDate: _today,
    endDate: _today,
    modelVersion: weekly.modelVersion,
    generatedAt: _now(),
    meals: weekly.mealsFor(_today).map((m) => m.carriedOver()).toList(),
  );

  /// Copy today's daily foods without sharing planned-meal ids between the two stored plans.
  DietPlan _withToday(DietPlan weekly, DietPlan daily) {
    final original = weekly.mealsFor(_today);
    final used = <String>{};
    final today = <PlannedMeal>[];
    for (final m in PlannedMeal.mergeDuplicates(daily.mealsFor(_today))) {
      final same = original
          .where(
            (w) =>
                !used.contains(w.plannedMealId) &&
                w.mealSlot == m.mealSlot &&
                w.food.foodId == m.food.foodId &&
                w.portionSizeG == m.portionSizeG,
          )
          .firstOrNull;
      if (same != null) used.add(same.plannedMealId);
      today.add(
        (same ?? m.carriedOver()).copyWith(dietPlanId: weekly.dietPlanId, isLocked: m.isLocked, isLogged: m.isLogged),
      );
    }
    return weekly.copyWith(
      meals: PlannedMeal.mergeDuplicates([...weekly.meals.where((m) => !_sameDay(m.planDate, _today)), ...today]),
    );
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
      final stored = await _mealRepo.planFor(id, t, _today);
      if (stored is Failure) {
        _message = Messages.dbUnavailable;
        plan = null;
        return;
      }
      plan = stored.dataOrNull;
      if (plan != null) plan = plan!.copyWith(meals: PlannedMeal.mergeDuplicates(plan!.meals));
      if (t == PlanType.daily && plan == null) {
        final week = await _mealRepo.planFor(id, PlanType.weekly, _today);
        if (week is Failure) {
          _message = Messages.dbUnavailable;
          return;
        }
        if (week.dataOrNull case final weekly?) {
          final daily = _dailyPart(weekly);
          if (await _mealRepo.savePlan(daily) is Success) {
            plan = daily;
          } else {
            _message = Messages.dbUnavailable;
            return;
          }
        }
      }
      if (t == PlanType.weekly && plan != null) {
        final daily = await _mealRepo.planFor(id, PlanType.daily, _today);
        if (daily is Failure) {
          _message = Messages.dbUnavailable;
          return;
        }
        if (daily.dataOrNull case final saved?) plan = _withToday(plan!, saved);
      }
      if (plan != null && _planner.validate(plan!, ctx).isNotEmpty) {
        _message = 'Some saved choices do not fit your profile or daily limits. Review the foods highlighted in red.';
      }
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
    return (await _mealRepo.findMeals(id, _today.subtract(const Duration(days: 30)), _now())).dataOrNull ??
        const <MealLog>[];
  }

  /// Daily: breakfast, lunch, dinner and a snack (FR700_029). Weekly: seven days (FR700_030).
  Future<void> _generate({int seed = 0}) async {
    final id = _accountId;
    if (id == null) return;
    final history = await _history();
    final todays = history.where((m) => _sameDay(m.consumedAt, _today)).toList();
    DietPlan? daily;
    if (type == PlanType.weekly) {
      final saved = await _mealRepo.planFor(id, PlanType.daily, _today);
      if (saved is Failure) {
        _message = Messages.dbUnavailable;
        return;
      }
      daily = saved.dataOrNull;
    }
    final res = await _planner.generate(
      accountId: id,
      ctx: ctx,
      type: type,
      start: _today,
      consumedToday: Nutrients.sum(todays.map((m) => m.totals)),
      loggedSlots: todays.map((m) => m.mealType).toSet(),
      // Locked foods stay, and so do the slots already eaten today (they are marked logged).
      locked: [
        // Keep all of today's choices, including hand-picked foods; restore their real locks below.
        ...?daily?.mealsFor(_today).map((m) => m.lock()),
        ...?plan?.meals.where(
          (m) =>
              !(daily != null && _sameDay(m.planDate, _today)) &&
              (m.isLocked || (_sameDay(m.planDate, _today) && todays.any((l) => l.mealType == m.mealSlot))),
        ),
      ],
      history: history,
      seed: seed,
    );
    if (res case Success(:final data)) {
      plannerDown = false;
      final next = daily == null ? data : _withToday(data, daily);
      // The AI reply passed its strict gate before restoring the patient's saved choices.
      if (_planner.editingProblems(next).isNotEmpty) {
        _message = 'This plan contains foods that do not suit your profile. No new plan was saved.';
        return;
      }
      if (await _mealRepo.savePlan(next) is Failure) {
        _message = Messages.dbUnavailable;
        return;
      }
      plan = next;
      await _markLogged();
    } else {
      plannerDown = true; // E2
      _message = switch (res) {
        Failure(:final message) => message,
        _ => Messages.plannerUnavailable,
      };
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
      // Today's planned meals not logged yet ring at their time if they are still not logged.
      try {
        await _alerts?.schedulePlanAlerts(_planner.missedMealAlerts(plan!, todays, _now()));
      } catch (_) {
        // The alerts are a help; the plan works without them.
      }
    }
    _recommend();
    notifyListeners();
  }

  // ------------------------------------------------------------- following the plan

  /// How the plan has been followed so far (planned meals due, eaten as planned, differently, missed).
  PlanFollow get follow {
    final p = plan;
    return p == null ? const PlanFollow() : _planner.followOf(p, logged, _now());
  }

  /// Warnings when the patient is not following the plan, in plain words (shown in red): planned
  /// meals of today that were missed or eaten differently, and a plan followed less than 60 %.
  List<PlanNote> get followWarnings {
    final p = plan;
    if (p == null) return const [];
    final now = _now();
    final out = <PlanNote>[];
    for (final slot in DietPlannerService.mealDeadline.keys) {
      final planned = p.mealsFor(_today).where((m) => m.mealSlot == slot).toList();
      final deadline = DietPlannerService.deadlineOf(slot, _today)!;
      if (planned.isEmpty) continue;
      final eaten = logged.where((m) => m.mealType == slot && _sameDay(m.consumedAt, now)).toList();
      final s = slot.label.toLowerCase();
      final names = planned.map((m) => m.food.foodName).join(', ');
      if (eaten.isEmpty && now.isAfter(deadline)) {
        out.add(
          PlanNote('You have not logged your $s. Your plan had $names. If you ate something else, log it.', warn: true),
        );
      } else if (eaten.isNotEmpty && !DietPlannerService.follows(planned, eaten)) {
        out.add(
          PlanNote(
            'Your $s was not the planned one (planned: $names). Follow the rest of today\'s plan, or plan the '
            'rest of today again so it stays within your limits.',
            warn: true,
          ),
        );
      }
    }
    final f = follow;
    if (f.notFollowing) {
      out.add(
        PlanNote(
          'You are not following your diet plan: ${f.followed} of ${f.due} planned meals so far were eaten as '
          'planned (${f.different} different, ${f.missed} missed). Meals off the plan can take you over your salt '
          'and sugar limits, which your health needs. Follow the plan, or change it so it suits you.',
          warn: true,
        ),
      );
    }
    return out;
  }

  /// Share of planned meals logged this week (FR700_038).
  double adherence() => plan?.adherence() ?? 0;

  /// Protects a slot from regeneration (FR700_036). UI first: the lock changes at once and is
  /// undone if the plan could not be saved.
  Future<void> lockMeal(String plannedMealId, {bool on = true}) async {
    if (isLoading) return;
    final p = plan;
    if (p == null) return;
    final meal = p.meals.where((m) => m.plannedMealId == plannedMealId).firstOrNull;
    if (meal == null || !canEditDay(meal.planDate)) return;
    final locked = p.copyWith(meals: [for (final m in p.meals) m.plannedMealId == plannedMealId ? m.lock(on) : m]);
    changeInProgress = on ? 'Locking food...' : 'Unlocking food...';
    setLoading(true);
    try {
      plan = locked;
      notifyListeners();
      final res = await _mealRepo.updatePlan(locked);
      if (res is Failure && identical(plan, locked)) {
        plan = p;
        _message = Messages.dbUnavailable;
        notifyListeners();
      }
    } finally {
      changeInProgress = null;
      setLoading(false);
    }
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
    final m = plan?.meals.where((x) => x.plannedMealId == plannedMealId).firstOrNull;
    if (m == null) return false;
    return applyChange(previewReplace(m, f)!);
  }

  // ------------------------------------------------------------- flexible changes (A5.1, A5.3)

  /// Meals logged today in slots the plan does not cover, for the day's totals.
  Nutrients get _eatenOutside {
    final p = plan;
    if (p == null) return Nutrients.zero;
    return _consumedOutsidePlan(logged.where((m) => _sameDay(m.consumedAt, _today)), p);
  }

  PlanChange _preview(
    PlanChangeKind kind,
    DietPlan after,
    DateTime day,
    MealSlot slot,
    String title,
    String done, {
    List<String> notes = const [],
  }) => _planner.previewChange(
    kind: kind,
    before: plan!,
    after: after.copyWith(meals: PlannedMeal.mergeDuplicates(after.meals)),
    day: day,
    slot: slot,
    ctx: ctx,
    title: title,
    doneMessage: done,
    eatenOutside: _eatenOutside,
    notes: notes,
  );

  /// Adding [f] to a slot of [day], [grams] defaulting to one serving, worked out before it is made.
  PlanChange? previewAdd(DateTime day, MealSlot slot, FoodItem f, {double? grams}) {
    final p = plan;
    if (p == null || !canEditDay(day)) return null;
    final g = (grams ?? f.baseServingG).roundToDouble();
    final s = slot.label.toLowerCase();
    final added = PlannedMeal.of(f, day, slot, g).copyWith(dietPlanId: p.dietPlanId);
    return _preview(
      PlanChangeKind.add,
      p.copyWith(meals: [...p.meals, added]),
      day,
      slot,
      'Add ${f.foodName} to your $s?',
      '${f.foodName} added to your $s.',
      notes: [
        '${f.foodName}, ${g.round()} g, will be added to your $s.',
        if (p.mealsFor(day).any((m) => m.mealSlot == slot && m.food.foodId == f.foodId))
          'It is already in this meal. Its portions will be combined into one row and checked together.',
      ],
    );
  }

  /// Taking [m] out of the plan, worked out before it is made.
  PlanChange? previewRemove(PlannedMeal m) {
    final p = plan;
    if (p == null || !canEditDay(m.planDate)) return null;
    final s = m.mealSlot.label.toLowerCase();
    return _preview(
      PlanChangeKind.remove,
      p.copyWith(
        meals: [
          for (final x in p.meals)
            if (x.plannedMealId != m.plannedMealId) x,
        ],
      ),
      m.planDate,
      m.mealSlot,
      'Remove ${m.food.foodName} from your $s?',
      '${m.food.foodName} removed from your $s.',
      notes: [
        '${m.food.foodName} (${m.portionSizeG.round()} g, ${m.energyKcal.round()} kcal) will be taken out of your $s.',
        if (m.isLocked) 'It is locked; removing it also removes the lock.',
        if (m.isLogged) 'Your logged meal stays in your meal history.',
      ],
    );
  }

  /// Swapping [m] for [f] at about the same energy (FR700_035), worked out before it is made.
  PlanChange? previewReplace(PlannedMeal m, FoodItem f) {
    final p = plan;
    if (p == null || !canEditDay(m.planDate)) return null;
    final r = m.replaceWith(f);
    final s = m.mealSlot.label.toLowerCase();
    return _preview(
      PlanChangeKind.replace,
      p.copyWith(meals: [for (final x in p.meals) x.plannedMealId == m.plannedMealId ? r : x]),
      m.planDate,
      m.mealSlot,
      'Swap ${m.food.foodName} for ${f.foodName}?',
      '${m.food.foodName} swapped for ${f.foodName}.',
      notes: [
        '${m.food.foodName} (${m.portionSizeG.round()} g) will be replaced by ${f.foodName} '
            '(${r.portionSizeG.round()} g) in your $s.',
      ],
    );
  }

  /// Changing the portion of [m] to [grams], worked out before it is made.
  PlanChange? previewPortion(PlannedMeal m, double grams) {
    final p = plan;
    if (p == null || !canEditDay(m.planDate)) return null;
    final g = grams.roundToDouble();
    final r = PlannedMeal.of(
      m.food,
      m.planDate,
      m.mealSlot,
      g,
      locked: m.isLocked,
    ).copyWith(dietPlanId: m.dietPlanId, isLogged: m.isLogged);
    final s = m.mealSlot.label.toLowerCase();
    return _preview(
      PlanChangeKind.portion,
      p.copyWith(meals: [for (final x in p.meals) x.plannedMealId == m.plannedMealId ? r : x]),
      m.planDate,
      m.mealSlot,
      'Change ${m.food.foodName} to ${g.round()} g?',
      '${m.food.foodName} is now ${g.round()} g.',
      notes: ['${m.food.foodName} in your $s: ${m.portionSizeG.round()} g → ${g.round()} g.'],
    );
  }

  /// Makes a change the patient confirmed. UI first: the plan changes at once and is put back if
  /// it could not be saved. A change the safety gate rejects is not made (FR700_042).
  Future<bool> applyChange(PlanChange c) async {
    if (isLoading) return false;
    final p = plan;
    if (p == null || !canEditDay(c.day)) return false;
    if (!c.allowed) {
      _message = 'Not changed: ${c.problems.first}.';
      notifyListeners();
      return false;
    }
    if (!identical(p, c.basePlan)) {
      _message = 'Your plan changed in the meantime. Please try again.';
      notifyListeners();
      return false;
    }
    changeInProgress = switch (c.kind) {
      PlanChangeKind.add => 'Adding food...',
      PlanChangeKind.remove => 'Removing food...',
      PlanChangeKind.replace => 'Changing food...',
      PlanChangeKind.portion => 'Updating portion...',
    };
    setLoading(true);
    try {
      await _context();
      if (!identical(plan, p)) {
        _message = 'Your plan changed in the meantime. Please try again.';
        notifyListeners();
        return false;
      }
      if (_planner.editingProblems(c.plan).isNotEmpty) {
        _message = 'Choose a valid portion and date before saving.';
        notifyListeners();
        return false;
      }
      plan = c.plan;
      notifyListeners();
      final res = await _mealRepo.updatePlan(c.plan);
      if (res is Failure) {
        if (identical(plan, c.plan)) {
          plan = p;
          _message = Messages.dbUnavailable;
          notifyListeners();
        }
        return false;
      }
      _message = _planner.validate(c.plan, ctx, consumedToday: _eatenOutside).isEmpty
          ? c.doneMessage
          : '${c.doneMessage} Review the foods highlighted in red; some choices do not fit your profile or daily limits.';
      await _markLogged();
      return true;
    } finally {
      changeInProgress = null;
      setLoading(false);
    }
  }

  /// Why a planned food was chosen, in plain words; warnings (too much, too little, not good for
  /// the body) are marked.
  List<PlanNote> reasonsFor(PlannedMeal m) {
    final p = plan;
    return p == null ? const [] : _planner.reasonsFor(m, p, ctx);
  }

  /// How a day of the plan was made and how it fits the limits.
  List<PlanReason> summaryFor(DateTime day) {
    final p = plan;
    return p == null ? const [] : _planner.summaryFor(p, day, ctx, eatenOutside: _eatenOutside);
  }

  /// A slot's usual share of the day's energy target (breakfast 25 %, lunch 35 %, dinner 30 %,
  /// snack 10 %).
  double usualKcal(MealSlot s) => ctx.dailyEnergyKcal * DietPlannerService.slotShare[s]!;

  /// The planned totals of a day with what was eaten outside the plan today.
  Nutrients plannedTotals(DateTime day) {
    final p = plan;
    if (p == null) return Nutrients.zero;
    return p.totalsFor(day) + (_sameDay(day, _today) ? _eatenOutside : Nutrients.zero);
  }

  /// What a new plan will do, for its confirmation (A6.1).
  List<String> get regenerateEffects {
    final p = plan;
    if (p == null) return const ['A new plan will be made for you within your limits.'];
    final eaten = p.meals
        .where((m) => canEditDay(m.planDate) && _sameDay(m.planDate, _today) && m.isLogged && !m.isLocked)
        .length;
    final changing = p.meals.where((m) => canEditDay(m.planDate) && !m.isLocked).length - eaten;
    final locked = p.meals.where((m) => m.isLocked).length;
    return [
      if (type == PlanType.weekly)
        "Today's meals stay the same as Today's Plan, including empty slots. Edit them there.",
      '$changing ${changing == 1 ? 'food' : 'foods'} that ${changing == 1 ? 'is' : 'are'} not locked will be '
          'replaced with new choices, including foods you added or changed yourself.',
      if (locked > 0)
        '$locked locked ${locked == 1 ? 'food stays' : 'foods stay'} as ${locked == 1 ? 'it is' : 'they are'}.'
      else
        'Nothing is locked. To keep a food, open it and tap Lock first.',
      if (eaten > 0) 'Meals you have already logged today stay.',
      'The new plan keeps within your energy, sodium and sugar limits.',
      'This needs the AI server and can take up to 20 seconds.',
    ];
  }

  /// What planning the rest of today will do, for its confirmation (FR700_034).
  List<String> get regenerateRemainingEffects => [
    'Meals you have already logged today stay as they are.',
    'The other meals of today are planned again from what is left of your allowance: '
        '${remaining.energyKcal.clamp(0, double.infinity).round()} kcal, '
        '${remaining.sodiumMg.clamp(0, double.infinity).round()} mg sodium and '
        '${remaining.sugarG.clamp(0, double.infinity).toStringAsFixed(1)} g free sugars.',
    'Locked foods stay.',
    'This needs the AI server and can take up to 20 seconds.',
  ];

  /// Lock or unlock with a message saying what it means.
  Future<void> toggleLock(PlannedMeal m) async {
    final on = !m.isLocked;
    await lockMeal(m.plannedMealId, on: on);
    _message ??= on
        ? '${m.food.foodName} is locked: a new plan keeps it.'
        : '${m.food.foodName} is unlocked: a new plan may change it.';
    notifyListeners();
  }

  /// Foods to suggest for a slot of [day]: suitable for the patient, planned for that slot, and a
  /// serving keeps the day within the limits. What the slot is missing comes first (vegetables at
  /// lunch and dinner, a protein next to rice), then the least sodium and free sugars.
  Future<List<FoodItem>> suggestionsFor(DateTime day, MealSlot slot) async {
    await _allFoods();
    final p = plan;
    if (p == null) return const [];
    const s = SuitabilityService();
    final t = plannedTotals(day);
    final inSlot = p.mealsFor(day).where((m) => m.mealSlot == slot).map((m) => m.food).toList();
    final roles = inSlot.map((f) => f.planRole).toSet();
    final want = <String>{
      if (slot == MealSlot.lunch || slot == MealSlot.dinner) ...[
        if (!roles.contains('veg')) 'veg',
        if (roles.contains('staple') && !roles.contains('protein')) 'protein',
        if (roles.contains('protein') && !roles.contains('staple')) 'staple',
        if (roles.isEmpty) 'meal',
      ],
      if (slot == MealSlot.breakfast && roles.isEmpty) 'meal',
      if (slot == MealSlot.snack && roles.isEmpty) 'fruit',
    };
    final cands = _catalogue.where((f) {
      if (!f.mealSlots.contains(slot.db) || inSlot.any((x) => x.foodId == f.foodId)) return false;
      if (!s.suitsPatient(f, ctx)) return false; // only foods that suit the patient
      final n = f.nutrientsFor(f.baseServingG);
      return t.energyKcal + n.energyKcal <= ctx.dailyEnergyKcal &&
          t.sodiumMg + n.sodiumMg <= ctx.dailySodiumMg &&
          t.sugarG + n.sugarG <= ctx.dailySugarG;
    }).toList();
    double score(FoodItem f) {
      final n = f.nutrientsFor(f.baseServingG);
      return (want.contains(f.planRole) ? -10 : 0) + n.sodiumMg / 200 + n.sugarG / 2 - n.proteinG / 10;
    }

    cands.sort((a, b) => score(a).compareTo(score(b)));
    return cands.take(8).toList();
  }

  /// Logged meals today in slots the plan does not cover (eaten in addition to the plan).
  Nutrients _consumedOutsidePlan(Iterable<MealLog> todays, DietPlan p) {
    final planned = p.mealsFor(_today).map((m) => m.mealSlot).toSet();
    return Nutrients.sum(todays.where((m) => !planned.contains(m.mealType)).map((m) => m.totals));
  }

  /// Builds today's plan from foods the patient picked while the planner is down (FR700_044).
  /// Returns the problems found by the safety gate; empty when it was saved.
  Future<List<String>> saveManualPlan(Map<MealSlot, List<FoodItem>> chosen) async {
    return saveManualMeals([
      for (final e in chosen.entries)
        for (final f in e.value) PlannedMeal.of(f, _today, e.key, f.baseServingG),
    ]);
  }

  Future<Result<List<PlannedMeal>>> manualMeals() async {
    final id = _accountId;
    if (id == null) return const Failure('Please sign in again.');
    final daily = await _mealRepo.planFor(id, PlanType.daily, _today);
    if (daily is Failure) return const Failure(Messages.dbUnavailable);
    final source = daily.dataOrNull ?? plan;
    return Success(PlannedMeal.mergeDuplicates(source?.mealsFor(_today).map((m) => m.carriedOver()) ?? []));
  }

  DietPlan _manualDraft(List<PlannedMeal> meals) => _planner
      .buildManually(accountId: _accountId ?? '', ctx: ctx, day: _today, chosen: const {})
      .copyWith(meals: PlannedMeal.mergeDuplicates(meals));

  List<PlannedMeal> mergeManualChoice(List<PlannedMeal> meals, PlannedMeal incoming, {PlannedMeal? replacing}) =>
      PlannedMeal.mergeDuplicates([
        for (final meal in meals) meal.plannedMealId == replacing?.plannedMealId ? incoming : meal,
        if (replacing == null) incoming,
      ]);

  List<String> manualProblems(List<PlannedMeal> meals) {
    if (meals.isEmpty) return const ['Choose at least one food.'];
    final p = _manualDraft(meals);
    return _planner.editingProblems(p);
  }

  List<String> foodProblemsForPlan(PlannedMeal meal) =>
      _planner.suitability.planProblems(meal.food, ctx, meal.portionSizeG);

  /// Mark the offending portion, and every food contributing to an excessive daily nutrient.
  List<String> manualFoodProblems(PlannedMeal meal, List<PlannedMeal> meals) {
    final draft = _manualDraft(meals);
    return _foodWarnings(meal, draft);
  }

  List<String> savedFoodWarnings(PlannedMeal meal) => plan == null ? const [] : _foodWarnings(meal, plan!);

  List<String> _foodWarnings(PlannedMeal meal, DietPlan draft) {
    final day = meal.planDate;
    final t =
        draft.totalsFor(day) +
        (_sameDay(day, _today)
            ? _consumedOutsidePlan(logged.where((m) => _sameDay(m.consumedAt, day)), draft)
            : Nutrients.zero);
    final x = DietPlannerService.extrasFor(draft, day);
    final one = meal.nutrients;
    final extras = meal.food.extrasFor(meal.portionSizeG);
    final totals = {
      'energy_kcal': t.energyKcal,
      'sodium_mg': t.sodiumMg,
      'sugar_g': t.sugarG,
      'protein_g': t.proteinG,
      'sat_fat_g': x.satFatG,
      'caffeine_mg': x.caffeineMg,
    };
    final amounts = {
      'energy_kcal': one.energyKcal,
      'sodium_mg': one.sodiumMg,
      'sugar_g': one.sugarG,
      'protein_g': one.proteinG,
      'sat_fat_g': extras.satFatG,
      'caffeine_mg': extras.caffeineMg,
    };
    const names = {
      'energy_kcal': 'energy',
      'sodium_mg': 'sodium',
      'sugar_g': 'free sugars',
      'protein_g': 'protein',
      'sat_fat_g': 'saturated fat',
      'caffeine_mg': 'caffeine',
    };
    return [
      ...foodProblemsForPlan(meal),
      for (final entry in ctx.targets.limits.entries)
        if ((totals[entry.key] ?? 0) > entry.value + (entry.key.endsWith('_g') ? 0.05 : 0.5) &&
            (amounts[entry.key] ?? 0) > 0)
          'Together with your other choices${_sameDay(day, _today) ? ' and logged meals' : ''}, this portion contributes to too much ${names[entry.key]} for this day. You can reduce the portion or choose another food.',
    ];
  }

  List<PlanNote> manualWarnings(List<PlannedMeal> meals) {
    final draft = _manualDraft(meals);
    return [
      for (final m in meals) ..._planner.reasonsFor(m, draft, ctx).where((n) => n.warn),
      for (final reason in _planner.summaryFor(draft, _today, ctx))
        if (!reason.ok) PlanNote(reason.text, warn: true),
    ];
  }

  Future<List<String>> saveManualMeals(List<PlannedMeal> meals) async {
    await _context();
    final id = _accountId;
    if (id == null) return const ['session'];
    final problems = manualProblems(meals);
    if (problems.isNotEmpty) return problems;
    final p = _manualDraft(meals.map((m) => m.carriedOver()).toList());
    if (await _mealRepo.savePlan(p) is Failure) return const [Messages.dbUnavailable];
    plan = p;
    type = PlanType.daily;
    await _markLogged();
    return const [];
  }

  /// All catalogue foods are available for user choice; health conflicts are shown as warnings.
  Future<List<FoodItem>> searchCatalogue(String term) async =>
      (await _foods.search(term)).dataOrNull ?? const <FoodItem>[];

  /// What the profile adds to the day's plan, in words (for the plan screen): the condition limits,
  /// the needs, and the one-hand and pregnancy rules.
  List<String> get profileRules {
    final t = ctx.targets;
    String g(double x) => x.toStringAsFixed(x == x.roundToDouble() ? 0 : 1);
    return [
      if (t.limits['sat_fat_g'] case final v?) 'Saturated fat under ${g(v)} g (${t.basis['sat_fat_g']})',
      if (t.limits['protein_g'] case final v?) 'Protein at most ${g(v)} g (${t.basis['protein_g']})',
      if (t.limits['caffeine_mg'] case final v?)
        'Caffeine at most ${g(v)} mg; no raw fish, half-boiled eggs or alcohol',
      if (t.needs['protein_g_min'] case final v?) 'Protein at least ${g(v)} g (${t.basis['protein_g_min']})',
      if (t.needs['calcium_mg_min'] case final v?) 'Calcium at least ${g(v)} mg (${t.basis['calcium_mg_min']})',
      if (t.needs['fibre_g_min'] case final v?) 'Fibre at least ${g(v)} g (${t.basis['fibre_g_min']})',
      if (t.watchPotassium) 'Lower potassium and phosphorus foods first (kidney disease)',
      if (t.oneHandOnly) 'Only foods you can eat with one hand: no bones, shells or whole fish',
      if (ctx.restrictions.isNotEmpty) 'Without: ${ctx.restrictions.map((r) => r.restrictionName).join(', ')}',
    ];
  }

  /// The needs a day of the plan does not reach (protein, calcium, fibre).
  List<String> unmetNeeds(DateTime day) {
    final p = plan;
    return p == null ? const [] : DietPlannerService.unmetNeeds(p, day, ctx);
  }

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
    final cands =
        _catalogue.where((f) {
          if (!f.mealSlots.contains(nextSlot.db)) return false;
          if (!{'meal', 'staple', 'protein', 'fruit', 'snack'}.contains(f.planRole)) return false;
          if (s.isExcludedFromPlans(f, ctx)) return false; // food names, pregnancy, two hands
          final n = f.nutrientsFor(f.baseServingG);
          if (n.energyKcal > energyCap) return false;
          if (n.sodiumMg > remaining.sodiumMg.clamp(0, double.infinity) ||
              n.sugarG > remaining.sugarG.clamp(0, double.infinity)) {
            return false;
          }
          return s.suitsPatient(f, ctx);
        }).toList()..sort((a, b) {
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
    recommendations = [for (var i = 0; i < 5 && i < cands.length; i++) cands[(start + i) % cands.length]];
  }

  static bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;
}
