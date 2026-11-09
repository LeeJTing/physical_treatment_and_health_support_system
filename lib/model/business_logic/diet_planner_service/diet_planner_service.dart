import 'package:physical_treatment_and_health_support_system/core/constants/app_constants.dart';
import 'package:physical_treatment_and_health_support_system/core/utils/id_utils.dart';
import 'package:physical_treatment_and_health_support_system/model/result.dart';
import 'package:physical_treatment_and_health_support_system/shared_client/api_client/api_client.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/diet_planner_service/plan_change.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/suitability_service/suitability_service.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/diet_plan.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/food_item.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/meal_log.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/food_repository/i_food_repository.dart';

/// Generates daily and weekly plans inside the safety limits, excluding anything the patient cannot
/// eat (Table 4.93; UC900 A5, A6). The plan comes from /plan on the AI server (condition-aware
/// planner with a learned preference ranker, DC700_07), which gets the conditions, the food names the
/// patient cannot eat, the physical limitations and the body measurements (no name or id). The
/// safety gate is applied again here, on this side of the connection (C11, C12): a plan that
/// breaches a daily limit (energy, sodium, free sugars and the condition limits of [DietTargets]),
/// or holds a food that would be Not Suitable or needs two hands for a patient with an arm
/// limitation, is rejected and requested again.
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
    final dayEnd = type == PlanType.weekly ? day0.add(const Duration(days: 6)) : day0;
    final safeLocked = locked.where((m) => suitability.suitsPatient(m.food, ctx, m.portionSizeG)).toList();
    final rejectedFoods = <String>{...exclude};
    for (var attempt = 0; attempt < _maxAttempts; attempt++) {
      final res = await _api.post(AppConstants.planPath, {
        'plan_type': type.db,
        'start_date': _d(day0),
        'today': _d(today),
        'conditions': ctx.failSafe ? const ['HYPERTENSION', 'DIABETES'] : ctx.conditionCodes,
        'restrictions': ctx.restrictionCodes,
        'limitations': ctx.limitationCodes,
        'profile': ctx.profileForPlanner,
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
          for (final m in safeLocked)
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
        'exclude': rejectedFoods.toList(),
        'seed': seed + attempt * 101,
      }, timeout: AppConstants.planTimeout);
      if (res case Failure(:final code, :final cause)) {
        if (code == 'no_suitable_plan') continue;
        return Failure(Messages.plannerUnavailable, code: code, cause: cause); // E2
      }
      final body = res.dataOrNull!;
      modelVersion = (body['model_version'] ?? '') as String;
      final meals = <PlannedMeal>[];
      var rejectedResponse = false;
      for (final day in (body['days'] as List? ?? const [])) {
        final dm = Map<String, dynamic>.from(day as Map);
        final date = DateTime.tryParse(dm['plan_date'] as String? ?? '');
        if (date == null) {
          rejectedResponse = true;
          continue;
        }
        if (date.isBefore(day0) || date.isAfter(dayEnd)) rejectedResponse = true;
        for (final slot in (dm['meals'] as List? ?? const [])) {
          final sm = Map<String, dynamic>.from(slot as Map);
          final ms = MealSlot.fromDb(sm['meal_slot'] as String?);
          final fromServer = <PlannedMeal>[];
          for (final it in (sm['items'] as List? ?? const [])) {
            final im = Map<String, dynamic>.from(it as Map);
            final key = im['food_key'];
            if (key is! String) {
              rejectedResponse = true;
              continue;
            }
            final food = (await _foods.byKey(key)).dataOrNull;
            final portion = im['portion_g'];
            final grams = portion is num ? portion.toDouble() : null;
            if (food == null || grams == null || !suitability.suitsPatient(food, ctx, grams)) {
              rejectedResponse = true;
              rejectedFoods.add(key);
              continue;
            }
            fromServer.add(PlannedMeal.of(food, date, ms, grams));
          }
          final wasLocked = safeLocked.where((l) => _same(l.planDate, date) && l.mealSlot == ms).toList();
          meals.addAll(wasLocked.isEmpty ? fromServer : wasLocked.map((l) => l.carriedOver()));
        }
      }
      // Locked or already-eaten slots the server skipped stay in the plan as they were.
      for (final l in safeLocked) {
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
        meals: PlannedMeal.mergeDuplicates(meals),
      );
      // A slot already eaten today counts once: what was eaten, not also what was planned for it.
      final eatenPlanned = Nutrients.sum(
        plan.meals.where((m) => _same(m.planDate, today) && loggedSlots.contains(m.mealSlot)).map((m) => m.nutrients),
      );
      if (!rejectedResponse &&
          meals.isNotEmpty &&
          validate(plan, ctx, consumedToday: consumedToday - eatenPlanned, strict: true).isEmpty) {
        return Success(plan);
      }
    }
    return const Failure(
      'We could not make a plan with suitable foods after 3 attempts. No new plan was saved. Try again or build your plan yourself.',
      code: 'plan_breaches_limits',
    );
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

  /// The safety gate (FR700_042, C11): every day within the calorie target, the sodium and free
  /// sugar limits and the condition limits (saturated fat, protein for kidney disease, caffeine in
  /// pregnancy), and no food that would be Not Suitable or that needs two hands when the patient
  /// has an arm limitation. Returns the problems; empty = valid.
  ///
  /// [strict] (a plan from the planner): every food the planner chose must also suit the patient
  /// ([SuitabilityService.suitsPatient]: no Caution, at most 30 % of a day's sodium or free sugars);
  /// locks and logged flags never exempt a food from the current profile's rules.
  List<String> validate(DietPlan p, DietContext ctx, {Nutrients consumedToday = Nutrients.zero, bool strict = true}) {
    p = p.copyWith(meals: PlannedMeal.mergeDuplicates(p.meals));
    final problems = <String>[];
    final today = DateTime.now();
    final limits = ctx.targets.limits;
    for (final day in p.days()) {
      var t = p.totalsFor(day);
      if (_same(day, today)) t = t + consumedToday;
      if (t.energyKcal > ctx.dailyEnergyKcal + 0.5) problems.add('${_d(day)} energy');
      if (t.sodiumMg > ctx.dailySodiumMg + 0.5) problems.add('${_d(day)} sodium');
      if (t.sugarG > ctx.dailySugarG + 0.05) problems.add('${_d(day)} free sugars');
      final x = extrasFor(p, day);
      if (limits['sat_fat_g'] case final l? when x.satFatG > l + 0.05) problems.add('${_d(day)} saturated fat');
      if (limits['protein_g'] case final l? when t.proteinG > l + 0.05) problems.add('${_d(day)} protein');
      if (limits['caffeine_mg'] case final l? when x.caffeineMg > l + 0.5) problems.add('${_d(day)} caffeine');
    }
    for (final m in p.meals) {
      if (suitability.isExcludedFromPlans(m.food, ctx, m.portionSizeG) ||
          (strict && !suitability.suitsPatient(m.food, ctx, m.portionSizeG))) {
        problems.add('${m.food.foodName} is not suitable');
      }
    }
    return problems;
  }

  /// User choices may exceed health limits, but malformed portions or dates cannot be stored.
  List<String> editingProblems(DietPlan p) => [
    for (final m in p.meals)
      if (!m.portionSizeG.isFinite || m.portionSizeG <= 0)
        '${m.food.foodName}: choose a positive portion in grams.'
      else if (m.planDate.isBefore(p.startDate) || m.planDate.isAfter(p.endDate))
        '${m.food.foodName}: choose a date within this plan.',
  ];

  /// Saturated fat, fibre, potassium, phosphorus, calcium and caffeine of one day's planned meals.
  static FoodExtras extrasFor(DietPlan p, DateTime day) => p.meals
      .where((m) => _same(m.planDate, day))
      .fold(FoodExtras.zero, (a, m) => a + m.food.extrasFor(m.portionSizeG));

  /// The needs a day of the plan does not reach (protein, calcium, fibre), for the plan screen.
  static List<String> unmetNeeds(DietPlan p, DateTime day, DietContext ctx) {
    final needs = ctx.targets.needs;
    final t = p.totalsFor(day);
    final x = extrasFor(p, day);
    return [
      if (needs['protein_g_min'] case final n? when t.proteinG < n) 'protein',
      if (needs['calcium_mg_min'] case final n? when x.calciumMg < n) 'calcium',
      if (needs['fibre_g_min'] case final n? when x.fibreG < n) 'fibre',
    ];
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
      if (f.needsTwoHands && ctx.oneHandOnly) continue;
      final repl = m.replaceWith(f);
      if (!suitability.suitsPatient(f, ctx, repl.portionSizeG)) continue; // only foods that suit the patient
      final t = dayWithout + repl.nutrients;
      if (t.energyKcal > ctx.dailyEnergyKcal || t.sodiumMg > ctx.dailySodiumMg || t.sugarG > ctx.dailySugarG) {
        continue;
      }
      out.add(((repl.energyKcal - m.energyKcal).abs() + repl.sodiumMg / 20 + repl.sugarG * 5, f));
    }
    out.sort((a, b) => a.$1.compareTo(b.$1));
    return out.map((e) => e.$2).take(8).toList();
  }

  // ------------------------------------------------------------- changes and explanations

  /// Each slot's share of the day's energy target, as the planner shares it out.
  static const slotShare = {
    MealSlot.breakfast: 0.25,
    MealSlot.lunch: 0.35,
    MealSlot.dinner: 0.30,
    MealSlot.snack: 0.10,
  };

  /// Works out a change before it is made, so the patient can see its effect and confirm it
  /// (A5.1 step 3). [after] is the plan with the change; [eatenOutside] is what was logged today in
  /// slots the plan does not cover. Only limits the change itself would break count as problems.
  PlanChange previewChange({
    required PlanChangeKind kind,
    required DietPlan before,
    required DietPlan after,
    required DateTime day,
    required MealSlot slot,
    required DietContext ctx,
    required String title,
    required String doneMessage,
    Nutrients eatenOutside = Nutrients.zero,
    List<String> notes = const [],
  }) {
    final extra = _same(day, DateTime.now()) ? eatenOutside : Nutrients.zero;
    final b = before.totalsFor(day) + extra;
    final a = after.totalsFor(day) + extra;
    final healthWarnings = [
      for (final p in validate(after, ctx, consumedToday: eatenOutside)) _problemWords(p, a, after, day, ctx),
    ];
    final slotKcal = _slotKcal(after, day, slot);
    final usual = ctx.dailyEnergyKcal * slotShare[slot]!;
    final lostNeeds = unmetNeeds(after, day, ctx).toSet().difference(unmetNeeds(before, day, ctx).toSet());
    final metNeeds = unmetNeeds(before, day, ctx).toSet().difference(unmetNeeds(after, day, ctx).toSet());
    final slotEmpty = after.mealsFor(day).every((m) => m.mealSlot != slot);
    final effects = <PlanNote>[
      for (final n in notes) PlanNote(n),
      PlanNote(
        'Energy for ${_dayWords(day)}: ${_n(b.energyKcal)} → ${_n(a.energyKcal)} of ${_n(ctx.dailyEnergyKcal)} kcal '
        '(${_signed(a.energyKcal - b.energyKcal)} kcal).',
      ),
      PlanNote('Sodium: ${_n(b.sodiumMg)} → ${_n(a.sodiumMg)} of ${_n(ctx.dailySodiumMg)} mg.'),
      PlanNote(
        'Free sugars: ${b.sugarG.toStringAsFixed(1)} → ${a.sugarG.toStringAsFixed(1)} of '
        '${ctx.dailySugarG.toStringAsFixed(0)} g.',
      ),
      if (slotEmpty && slot != MealSlot.snack)
        PlanNote(
          'Your ${slot.label.toLowerCase()} will have no food planned. ${_body['skip']} '
          'You can add a food at any time.',
          warn: true,
        )
      else if (slotEmpty)
        PlanNote('Your snack will have no food planned. You can add one at any time.')
      else if (slotKcal > usual * 1.5)
        PlanNote(
          'Too much for one ${slot.label.toLowerCase()}: ${_n(slotKcal)} kcal, against its usual share of about '
          '${_n(usual)} kcal. ${_body['heavy']}',
          warn: true,
        )
      else
        PlanNote(
          'Your ${slot.label.toLowerCase()} will have ${_n(slotKcal)} kcal; its usual share is about '
          '${_n(usual)} kcal.',
        ),
      ..._limitWarnings(before, after, b, a, day, ctx),
      for (final warning in healthWarnings) PlanNote(warning, warn: true),
      for (final n in lostNeeds)
        PlanNote(
          'Too little $n: the day would no longer reach your need (${_needWords(n, after, day, ctx)}). '
          '${_body['${n}_low']}',
          warn: true,
        ),
      for (final n in metNeeds) PlanNote('The day now reaches your $n need (${_needWords(n, after, day, ctx)}).'),
      if (a.energyKcal < 0.75 * ctx.dailyEnergyKcal && a.energyKcal < b.energyKcal)
        PlanNote(
          'Too little energy: that leaves ${_n(a.energyKcal)} of your ${_n(ctx.dailyEnergyKcal)} kcal target for '
          'the day. ${_body['energy_low']} You can add another food later.',
          warn: true,
        ),
    ];
    return PlanChange(
      kind: kind,
      day: day,
      slot: slot,
      title: title,
      effects: effects,
      before: b,
      after: a,
      problems: editingProblems(after),
      basePlan: before,
      plan: after,
      doneMessage: doneMessage,
    );
  }

  /// Why a planned food was chosen, in plain words (DC700_06): its place on the plate, its portion
  /// against the slot's share of the day, its sodium and free sugars against the patient's limits,
  /// the needs it helps with, and the profile rules it keeps. Lines about too much, too little or
  /// something not good for the body are marked as warnings, with what it does to the body.
  List<PlanNote> reasonsFor(PlannedMeal m, DietPlan p, DietContext ctx) {
    final f = m.food;
    final slot = m.mealSlot.label.toLowerCase();
    final n = m.nutrients;
    final x = f.extrasFor(m.portionSizeG);
    final share = slotShare[m.mealSlot]!;
    final usual = ctx.dailyEnergyKcal * share;
    final slotKcal = _slotKcal(p, m.planDate, m.mealSlot);
    final servings = f.baseServingG > 0 ? m.portionSizeG / f.baseServingG : 1.0;
    final out = <PlanNote>[
      for (final issue in suitability.planProblems(f, ctx, m.portionSizeG)) PlanNote(issue, warn: true),
      PlanNote(_roleWords(f.planRole, slot)),
      PlanNote(
        '${m.portionSizeG.round()} g (${_servingWords(servings)}) gives ${_n(n.energyKcal)} kcal. Your $slot has '
        '${_n(slotKcal)} kcal planned; its usual share is about ${_n(usual)} kcal '
        '(${(share * 100).round()}% of your ${_n(ctx.dailyEnergyKcal)} kcal a day).',
      ),
      if (slotKcal > usual * 1.5)
        PlanNote(
          'Your $slot is heavier than its share (${_n(slotKcal)} of about ${_n(usual)} kcal). ${_body['heavy']}',
          warn: true,
        ),
    ];
    final vs = suitability.checkNutrients(f, m.portionSizeG, ctx);
    for (final v in vs) {
      final bad = v.verdict != Verdict.suitable;
      out.add(PlanNote(bad ? '${v.reasonText} ${_bodyOf(v.nutrient)}'.trim() : v.reasonText, warn: bad));
    }
    if (!vs.any((v) => v.nutrient == 'sodium_mg')) {
      final pc = _pct(n.sodiumMg, ctx.dailySodiumMg);
      out.add(
        pc >= 30
            ? PlanNote(
                'High in sodium for one food: ${_n(n.sodiumMg)} mg, $pc% of your daily limit. ${_body['sodium']} '
                'Keep the rest of the day low in salt.',
                warn: true,
              )
            : PlanNote('${_n(n.sodiumMg)} mg sodium: $pc% of your daily limit.'),
      );
    }
    if (!vs.any((v) => v.nutrient == 'sugar_g')) {
      final pc = _pct(n.sugarG, ctx.dailySugarG);
      out.add(
        pc >= 30
            ? PlanNote(
                'High in free sugars for one food: ${n.sugarG.toStringAsFixed(1)} g, $pc% of your daily limit. '
                '${_body['sugar']} Keep the rest of the day low in sugar.',
                warn: true,
              )
            : PlanNote('${n.sugarG.toStringAsFixed(1)} g free sugars: $pc% of your daily limit.'),
      );
    }
    final needs = ctx.targets.needs;
    if (needs['protein_g_min'] case final v? when n.proteinG >= 8) {
      out.add(PlanNote('Adds ${n.proteinG.round()} g protein towards the ${_n(v)} g you need a day.'));
    }
    if (needs['calcium_mg_min'] case final v? when x.calciumMg >= 80) {
      out.add(PlanNote('Adds ${_n(x.calciumMg)} mg calcium towards the ${_n(v)} mg you need a day.'));
    }
    if (needs['fibre_g_min'] case final v? when x.fibreG >= 2) {
      out.add(PlanNote('Adds ${x.fibreG.toStringAsFixed(1)} g fibre towards the ${_n(v)} g you need a day.'));
    }
    if (ctx.restrictions.isNotEmpty && !f.breachesAny(ctx.restrictions)) {
      out.add(
        PlanNote('Has none of the foods you avoid (${ctx.restrictions.map((r) => r.restrictionName).join(', ')}).'),
      );
    }
    if (ctx.oneHandOnly && !f.needsTwoHands) {
      out.add(const PlanNote('Can be eaten with one hand: no bones, shells or whole fish.'));
    }
    if (ctx.targets.pregnant && !suitability.isExcludedFromPlans(f, ctx, m.portionSizeG)) {
      out.add(const PlanNote('No pregnancy exclusion was found for this food.'));
    }
    if (m.isLocked) out.add(const PlanNote('Locked: a new plan keeps it.'));
    if (m.isLogged) out.add(PlanNote('You have logged your $slot.'));
    out.add(
      PlanNote(
        f.dataSource == 'lab'
            ? 'Nutrient values from a Malaysian laboratory analysis of the food.'
            : 'Nutrient values from a standard recipe of the food (USDA ingredients).',
      ),
    );
    return out;
  }

  /// What too much or too little of something does to the body, in plain words.
  static const _body = {
    'energy_over': 'Eating more energy than you use is stored as body fat, so your weight goes up.',
    'energy_low': 'Too little food can make you tired, weak or dizzy and makes you lose muscle.',
    'sodium': 'Too much salt raises blood pressure and strains the heart and kidneys.',
    'sugar': 'Too much sugar raises blood sugar and adds weight.',
    'sat_fat': 'Too much saturated fat raises cholesterol and the risk of heart disease and stroke.',
    'protein_over': 'Too much protein makes damaged kidneys work harder.',
    'caffeine': 'Too much caffeine in pregnancy can harm the baby.',
    'potassium': 'With kidney disease, too much potassium can upset the heartbeat.',
    'phosphorus': 'With kidney disease, too much phosphorus weakens the bones.',
    'protein_low': 'Too little protein slows healing and weakens your muscles.',
    'calcium_low': 'Too little calcium weakens your bones.',
    'fibre_low': 'Too little fibre can cause constipation and makes blood sugar rise faster.',
    'heavy': 'A large meal raises blood sugar after eating and leaves less room for the rest of the day.',
    'skip': 'Skipping a meal can make you weak and hungry, and you may eat too much later.',
  };

  static String _bodyOf(String? nutrient) => switch (nutrient) {
    'sodium_mg' => _body['sodium']!,
    'sugar_g' => _body['sugar']!,
    'sat_fat_g' => _body['sat_fat']!,
    'potassium_mg' => _body['potassium']!,
    'phosphorus_mg' => _body['phosphorus']!,
    'caffeine_mg' => _body['caffeine']!,
    _ => '',
  };

  /// Too much, or close to too much, of a daily limit after a change, with what it does to the
  /// body. A limit counts as close from 80 % (the Caution band) when the change adds to it.
  static List<PlanNote> _limitWarnings(
    DietPlan before,
    DietPlan after,
    Nutrients b,
    Nutrients a,
    DateTime day,
    DietContext ctx,
  ) {
    final xb = extrasFor(before, day);
    final xa = extrasFor(after, day);
    final lim = ctx.targets.limits;
    final out = <PlanNote>[];
    void check(String name, double was, double now, double? limit, String unit, String body, {int dp = 0}) {
      if (limit == null || limit <= 0 || now <= was + 1e-6) return;
      String f(double v) => dp == 0 ? _n(v) : v.toStringAsFixed(dp);
      if (now > limit) {
        out.add(PlanNote('Too much $name: ${f(now)} of ${f(limit)} $unit, over your daily limit. $body', warn: true));
      } else if (now >= 0.8 * limit) {
        out.add(
          PlanNote(
            'Close to your $name limit: ${f(now)} of ${f(limit)} $unit (${_pct(now, limit)}%). $body '
            'Keep the rest of the day low in $name.',
            warn: true,
          ),
        );
      }
    }

    if (a.energyKcal > ctx.dailyEnergyKcal && a.energyKcal > b.energyKcal) {
      out.add(
        PlanNote(
          'Too much energy: ${_n(a.energyKcal)} of ${_n(ctx.dailyEnergyKcal)} kcal, over your target. '
          '${_body['energy_over']}',
          warn: true,
        ),
      );
    }
    check('sodium', b.sodiumMg, a.sodiumMg, ctx.dailySodiumMg, 'mg', _body['sodium']!);
    check('free sugars', b.sugarG, a.sugarG, ctx.dailySugarG, 'g', _body['sugar']!, dp: 1);
    check('saturated fat', xb.satFatG, xa.satFatG, lim['sat_fat_g'], 'g', _body['sat_fat']!, dp: 1);
    check('protein', b.proteinG, a.proteinG, lim['protein_g'], 'g', _body['protein_over']!);
    check('caffeine', xb.caffeineMg, xa.caffeineMg, lim['caffeine_mg'], 'mg', _body['caffeine']!);
    return out;
  }

  /// How a day of the plan was made and how it fits the patient's limits (DC700_06).
  List<PlanReason> summaryFor(DietPlan p, DateTime day, DietContext ctx, {Nutrients eatenOutside = Nutrients.zero}) {
    final t = p.totalsFor(day) + (_same(day, DateTime.now()) ? eatenOutside : Nutrients.zero);
    final basis = ctx.targets.basis['energy_kcal'] ?? 'your safety limit';
    final conds = ctx.conditions.map((c) => c.conditionName.toLowerCase()).toList();
    final (sodiumItem, sodiumCond, _) = suitability.itemLimit('sodium_mg', ctx);
    final (sugarItem, sugarCond, _) = suitability.itemLimit('sugar_g', ctx);
    final unmet = unmetNeeds(p, day, ctx);
    final needs = ctx.targets.needs;
    final locked = p.mealsFor(day).where((m) => m.isLocked).length;
    String pctWord(double v, double l) => '${_pct(v, l)}%';
    final saltHigh = t.sodiumMg >= 0.8 * ctx.dailySodiumMg;
    final sugarHigh = t.sugarG >= 0.8 * ctx.dailySugarG;
    final choicesFit = p.mealsFor(day).every((m) => suitability.suitsPatient(m.food, ctx, m.portionSizeG));
    return [
      PlanReason(
        'energy',
        t.energyKcal > ctx.dailyEnergyKcal
            ? 'Too much energy for the day'
            : t.energyKcal < 0.75 * ctx.dailyEnergyKcal
            ? 'Too little energy for the day'
            : 'Energy shared through the day',
        'Your target is ${_n(ctx.dailyEnergyKcal)} kcal a day ($basis). Breakfast gets about 25%, lunch 35%, '
            'dinner 30% and a snack 10%, so no meal is too heavy. This day has ${_n(t.energyKcal)} kcal '
            '(${pctWord(t.energyKcal, ctx.dailyEnergyKcal)} of the target).'
            '${t.energyKcal > ctx.dailyEnergyKcal
                ? ' ${_body['energy_over']}'
                : t.energyKcal < 0.75 * ctx.dailyEnergyKcal
                ? ' ${_body['energy_low']} Add a food to a meal.'
                : ''}',
        ok: t.energyKcal <= ctx.dailyEnergyKcal && t.energyKcal >= 0.75 * ctx.dailyEnergyKcal,
      ),
      const PlanReason(
        'plate',
        'A balanced plate',
        'Lunch and dinner follow the Malaysian Healthy Plate (quarter, quarter, half): a quarter rice, '
            'bread or noodles, a quarter fish, chicken, egg or tofu, and half vegetables, or a complete '
            'dish with vegetables on the side. Snacks are fruit or a light snack rather than sweets.',
      ),
      PlanReason(
        'limits',
        saltHigh || sugarHigh
            ? 'Close to your ${saltHigh && sugarHigh
                  ? 'salt and sugar limits'
                  : saltHigh
                  ? 'salt limit'
                  : 'sugar limit'}'
            : 'Within your salt and sugar limits',
        'Planned: ${_n(t.sodiumMg)} of ${_n(ctx.dailySodiumMg)} mg sodium (${pctWord(t.sodiumMg, ctx.dailySodiumMg)}) '
            'and ${t.sugarG.toStringAsFixed(1)} of ${ctx.dailySugarG.toStringAsFixed(0)} g free sugars '
            '(${pctWord(t.sugarG, ctx.dailySugarG)}). '
            '${choicesFit ? 'The selected foods fit your profile at these portions.' : 'Some choices do not fit your profile. Review the foods highlighted in red; you can still save your choices.'}'
            '${saltHigh ? ' ${_body['sodium']} Avoid extra salt, soy sauce and salty snacks today.' : ''}'
            '${sugarHigh ? ' ${_body['sugar']} Avoid sweet drinks and kuih today.' : ''}',
        ok: !saltHigh && !sugarHigh && choicesFit,
      ),
      if (ctx.failSafe)
        const PlanReason(
          'profile',
          'Careful limits for now',
          'Your health profile could not be read, so the stricter limits for high blood pressure and '
              'diabetes are used until it can.',
        )
      else if (conds.isNotEmpty)
        PlanReason(
          'profile',
          choicesFit ? 'Fits your conditions' : 'Review your conditions',
          'Because you have declared ${_join(conds)}, the guidance for each food is '
              '${sodiumCond != null ? 'at most ${_n(sodiumItem)} mg sodium' : 'a modest amount of sodium'}'
              '${sugarCond != null ? ' and ${sugarItem.toStringAsFixed(1)} g free sugars' : ''}, and the condition '
              'rules below. Choices outside this guidance are highlighted in red.',
          ok: choicesFit,
        ),
      PlanReason(
        'preference',
        p.modelVersion == 'manual' ? 'Foods you chose' : 'Foods you like, healthier first',
        p.modelVersion == 'manual'
            ? 'You chose these foods yourself. Profile and daily-limit conflicts are shown in red as warnings.'
            : 'Foods like the meals you log are ranked higher, and among them those with less salt and '
                  'sugar and more protein come first. Asking for a new plan gives other choices of the '
                  'same quality.',
      ),
      if (needs.isNotEmpty)
        PlanReason(
          'needs',
          unmet.isEmpty ? 'Your needs are reached' : 'Low in ${_join(unmet)}',
          [
            for (final k in const ['protein', 'calcium', 'fibre'])
              if (needs.containsKey('${k == 'calcium' ? 'calcium_mg' : '${k}_g'}_min'))
                '${k[0].toUpperCase()}${k.substring(1)}: ${_needWords(k, p, day, ctx)}.',
            for (final u in unmet) _body['${u}_low']!,
            if (unmet.isNotEmpty) 'Add vegetables, fruit, milk or tofu if you can.',
          ].join(' '),
          ok: unmet.isEmpty,
        ),
      if (locked > 0)
        PlanReason(
          'lock',
          'Locked foods stay',
          '$locked locked ${locked == 1 ? 'food is' : 'foods are'} kept when you ask for a new plan.',
        ),
    ];
  }

  static String _roleWords(String role, String slot) => switch (role) {
    'meal' => 'A complete dish: it brings its own rice or noodles and protein, so it can be the whole $slot.',
    'staple' => 'The rice, bread or other starch of your $slot: about a quarter of the plate, for energy.',
    'protein' =>
      'The protein of your $slot: about a quarter of the plate, to keep your muscles strong and you full for longer.',
    'veg' => 'Vegetables: half of a healthy plate, for fibre and vitamins with few calories.',
    'soup' => 'A soup with the meal: it adds fluid and vegetables.',
    'fruit' => 'Fruit: fibre and vitamins without added sugar.',
    'drink' => 'A drink to go with your $slot.',
    'snack' => 'A light snack to keep you going between meals.',
    'dessert' => 'A small sweet treat that still fits your sugar limit for the day.',
    _ => 'Part of your $slot.',
  };

  static double _slotKcal(DietPlan p, DateTime day, MealSlot slot) =>
      p.mealsFor(day).where((m) => m.mealSlot == slot).fold(0.0, (a, m) => a + m.energyKcal);

  /// "64 of at least 70 g" for a need word (protein, calcium, fibre).
  static String _needWords(String need, DietPlan p, DateTime day, DietContext ctx) {
    final t = p.totalsFor(day);
    final x = extrasFor(p, day);
    return switch (need) {
      'protein' => '${t.proteinG.round()} of at least ${_n(ctx.targets.needs['protein_g_min'] ?? 0)} g',
      'calcium' => '${_n(x.calciumMg)} of at least ${_n(ctx.targets.needs['calcium_mg_min'] ?? 0)} mg',
      _ => '${x.fibreG.toStringAsFixed(1)} of at least ${_n(ctx.targets.needs['fibre_g_min'] ?? 0)} g',
    };
  }

  /// A problem of [validate] in words, with the amount: "sodium 2,150 of 2,000 mg".
  static String _problemWords(String p, Nutrients a, DietPlan after, DateTime day, DietContext ctx) {
    final x = extrasFor(after, day);
    final lim = ctx.targets.limits;
    if (p.endsWith(' energy')) return 'energy ${_n(a.energyKcal)} of ${_n(ctx.dailyEnergyKcal)} kcal';
    if (p.endsWith(' sodium')) return 'sodium ${_n(a.sodiumMg)} of ${_n(ctx.dailySodiumMg)} mg';
    if (p.endsWith(' free sugars')) {
      return 'free sugars ${a.sugarG.toStringAsFixed(1)} of ${ctx.dailySugarG.toStringAsFixed(0)} g';
    }
    if (p.endsWith(' saturated fat')) {
      return 'saturated fat ${x.satFatG.toStringAsFixed(1)} of ${(lim['sat_fat_g'] ?? 0).toStringAsFixed(1)} g';
    }
    if (p.endsWith(' protein')) return 'protein ${a.proteinG.round()} of at most ${_n(lim['protein_g'] ?? 0)} g';
    if (p.endsWith(' caffeine')) return 'caffeine ${_n(x.caffeineMg)} of ${_n(lim['caffeine_mg'] ?? 0)} mg';
    if (p.endsWith(' is not suitable')) {
      return '${p.substring(0, p.length - 16)} does not suit your profile at this portion';
    }
    return p;
  }

  static String _dayWords(DateTime d) {
    final now = DateTime.now();
    if (_same(d, now)) return 'today';
    if (_same(d, now.add(const Duration(days: 1)))) return 'tomorrow';
    const w = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    return '${w[d.weekday - 1]} ${d.day}/${d.month}';
  }

  static String _servingWords(double s) {
    final r = (s * 4).round() / 4;
    final t = r == r.roundToDouble()
        ? r.round().toString()
        : r.toStringAsFixed(r * 2 == (r * 2).roundToDouble() ? 1 : 2);
    return '$t ${r == 1 ? 'serving' : 'servings'}';
  }

  static int _pct(double v, double limit) => limit <= 0 ? 0 : (v / limit * 100).round();
  static String _n(num v) => v.round().toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
  static String _signed(double v) => v >= 0 ? '+${_n(v)}' : '-${_n(-v)}';
  static String _join(List<String> xs) =>
      xs.length <= 1 ? xs.join() : '${xs.sublist(0, xs.length - 1).join(', ')} and ${xs.last}';

  // ------------------------------------------------------------- following the plan (alerts)

  /// The time by which a planned main meal is expected to be logged; the "follow your plan" alert
  /// rings then when it has not been (snacks have none).
  static const mealDeadline = {MealSlot.breakfast: (10, 30), MealSlot.lunch: (14, 30), MealSlot.dinner: (20, 30)};

  static DateTime? deadlineOf(MealSlot s, DateTime day) {
    final t = mealDeadline[s];
    return t == null ? null : DateTime(day.year, day.month, day.day, t.$1, t.$2);
  }

  /// Whether the meals logged for a slot follow its plan: logged from the plan, or at least half of
  /// the planned foods were eaten.
  static bool follows(List<PlannedMeal> planned, List<MealLog> eaten) {
    if (planned.isEmpty || eaten.isEmpty) return false;
    if (eaten.any((m) => planned.any((p) => p.plannedMealId == m.plannedMealId))) return true;
    final keys = {
      for (final m in eaten)
        for (final i in m.items) i.food.foodKey,
    };
    return planned.where((p) => keys.contains(p.food.foodKey)).length * 2 >= planned.length;
  }

  /// How the plan has been followed up to [now]: every planned slot that was logged or whose time
  /// has passed, eaten as planned, eaten differently or missed.
  PlanFollow followOf(DietPlan p, List<MealLog> logged, DateTime now) {
    var due = 0, followed = 0, different = 0, missed = 0;
    for (final day in p.days()) {
      if (day.isAfter(now)) break;
      for (final slot in MealSlot.values) {
        final planned = p.mealsFor(day).where((m) => m.mealSlot == slot).toList();
        if (planned.isEmpty) continue;
        final eaten = logged.where((m) => m.mealType == slot && _same(m.consumedAt, day)).toList();
        final deadline = deadlineOf(slot, day);
        if (eaten.isEmpty && (deadline == null || now.isBefore(deadline))) continue; // not due yet
        due++;
        if (eaten.isEmpty) {
          missed++;
        } else if (follows(planned, eaten)) {
          followed++;
        } else {
          different++;
        }
      }
    }
    return PlanFollow(due: due, followed: followed, different: different, missed: missed);
  }

  /// Today's planned main meals not logged yet whose time is still to come: one alert each, rung at
  /// the meal's time if it has not been logged by then.
  List<PlanAlert> missedMealAlerts(DietPlan p, List<MealLog> loggedToday, DateTime now) {
    final day = DateTime(now.year, now.month, now.day);
    if (!p.days().any((d) => _same(d, day))) return const [];
    final out = <PlanAlert>[];
    for (final slot in mealDeadline.keys) {
      final planned = p.mealsFor(day).where((m) => m.mealSlot == slot).toList();
      if (planned.isEmpty || loggedToday.any((m) => m.mealType == slot && _same(m.consumedAt, day))) continue;
      final at = deadlineOf(slot, day)!;
      if (!at.isAfter(now)) continue;
      final s = slot.label.toLowerCase();
      final kcal = planned.fold(0.0, (a, m) => a + m.energyKcal);
      out.add(
        PlanAlert(
          slot: slot,
          at: at,
          title: 'Follow your diet plan: $s',
          body:
              'You have not logged your $s yet. Your plan has ${_foodWords(planned.map((m) => m.food.foodName))} '
              '(${_n(kcal)} kcal). Eat it to stay within your salt and sugar limits; if you ate something '
              'else, log it so the rest of today can be planned again.',
        ),
      );
    }
    return out;
  }

  /// A meal just logged, checked against the plan: null when it follows the plan (or nothing is
  /// planned for that day). Otherwise the alert says what was different, the difference in energy,
  /// sodium and free sugars, and what the day reaches if the rest of the plan is eaten; it is red
  /// ([PlanAlert.overLimit]) when that goes over a limit, with what it does to the body.
  PlanAlert? offPlanAlertFor(MealLog meal, DietPlan p, DietContext ctx, List<MealLog> loggedToday, DateTime now) {
    final day = DateTime(meal.consumedAt.year, meal.consumedAt.month, meal.consumedAt.day);
    if (!_same(day, now) || !p.days().any((d) => _same(d, day))) return null;
    final slot = meal.mealType;
    final s = slot.label.toLowerCase();
    final planned = p.mealsFor(day).where((m) => m.mealSlot == slot).toList();
    final eatenToday = {
      for (final m in [...loggedToday, meal]) m.mealId: m,
    }.values.toList();
    if (follows(planned, eatenToday.where((m) => m.mealType == slot).toList())) return null;
    final ate = meal.totals;
    final plannedT = Nutrients.sum(planned.map((m) => m.nutrients));
    final eatenSlots = eatenToday.map((m) => m.mealType).toSet();
    final projected =
        Nutrients.sum(eatenToday.map((m) => m.totals)) +
        Nutrients.sum(p.mealsFor(day).where((m) => !eatenSlots.contains(m.mealSlot)).map((m) => m.nutrients));
    final over = <(String, String)>[
      if (projected.sodiumMg > ctx.dailySodiumMg)
        ('sodium ${_n(projected.sodiumMg)} of ${_n(ctx.dailySodiumMg)} mg', _body['sodium']!),
      if (projected.sugarG > ctx.dailySugarG)
        (
          'free sugars ${projected.sugarG.toStringAsFixed(1)} of ${ctx.dailySugarG.toStringAsFixed(0)} g',
          _body['sugar']!,
        ),
      if (projected.energyKcal > ctx.dailyEnergyKcal)
        ('energy ${_n(projected.energyKcal)} of ${_n(ctx.dailyEnergyKcal)} kcal', _body['energy_over']!),
    ];
    if (planned.isEmpty && over.isEmpty) return null; // an extra meal that still fits
    final ateWords = _foodWords(meal.items.map((i) => i.food.foodName));
    final b = StringBuffer(
      planned.isEmpty
          ? 'Your plan has no $s today, so $ateWords ${meal.items.length == 1 ? 'is' : 'are'} extra. '
          : 'Your $s was not the planned one: you had $ateWords instead of '
                '${_foodWords(planned.map((m) => m.food.foodName))}. Compared with the plan it had '
                '${_signed(ate.energyKcal - plannedT.energyKcal)} kcal, ${_signed(ate.sodiumMg - plannedT.sodiumMg)} mg '
                'sodium and ${(ate.sugarG - plannedT.sugarG) >= 0 ? '+' : ''}${(ate.sugarG - plannedT.sugarG).toStringAsFixed(1)} g '
                'free sugars. ',
    );
    if (over.isNotEmpty) {
      b.write(
        'If you eat the rest of today\'s plan, the day will go over your limit: ${over.map((o) => o.$1).join(', ')}. '
        '${over.map((o) => o.$2).toSet().join(' ')} Open your plan and tap "Plan the rest of today" so the other '
        'meals make up for it.',
      );
    } else {
      b.write('Please follow the rest of today\'s plan to stay within your limits.');
    }
    return PlanAlert(
      slot: slot,
      at: now,
      title: over.isEmpty ? 'This meal was not in your diet plan' : 'Not following your diet plan: over your limit',
      body: b.toString(),
      overLimit: over.isNotEmpty,
    );
  }

  /// "A, B and C".
  static String _foodWords(Iterable<String> names) => _join(names.toList());

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
