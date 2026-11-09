import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;

import 'package:physical_treatment_and_health_support_system/core/constants/app_constants.dart';
import 'package:physical_treatment_and_health_support_system/core/utils/id_utils.dart';
import 'package:physical_treatment_and_health_support_system/device_platform/camera_gallery/meal_image_picker.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/diet_planner_service/diet_planner_service.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/diet_planner_service/plan_change.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/food_recognition_service/food_recognition_service.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/risk_assessment_service/risk_assessment_service.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/suitability_service/suitability_service.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/diet_plan.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/food_item.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/health_profile.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/lookups.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/meal_log.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/safety_limit.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/auth_repository/fake_auth_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/food_repository/fake_food_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/meal_repository/fake_meal_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/profile_repository/fake_profile_repository.dart';
import 'package:physical_treatment_and_health_support_system/shared_client/api_client/api_client.dart';
import 'package:physical_treatment_and_health_support_system/device_platform/notification_scheduler/notification_scheduler.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/local_notification_service/local_notification_service.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/notification_repository/fake_notification_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/treatment_repository/fake_treatment_repository.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/diet_plan_view_model/diet_plan_view_model.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/meal_log_view_model/meal_log_view_model.dart';

final foods = FakeFoodRepository.fromJson(File('assets/seed/food_catalogue.json').readAsStringSync());
FoodItem food(String key) => foods.foods.firstWhere((f) => f.foodKey == key);

HealthCondition cond(String code) => LookupSeed.conditions.firstWhere((c) => c.conditionCode == code);
DietaryRestriction restr(String code) => LookupSeed.restrictions.firstWhere((r) => r.restrictionCode == code);

DietContext ctx({List<String> conds = const [], List<String> rs = const [], bool failSafe = false}) => DietContext(
  conditions: conds.map(cond).toList(),
  restrictions: rs.map(restr).toList(),
  limit: const SafetyLimit(
    safetyLimitId: 'sl',
    maxExerciseIntensity: ExerciseIntensity.moderate,
    maxSessionDurationMin: 30,
    dailyCalorieTarget: 1800,
    dailySodiumLimitMg: 2000,
    dailySugarLimitG: 25,
  ),
  failSafe: failSafe,
);

class _NoCamera implements MealImageSource {
  Uint8List? next;
  @override
  Future<Uint8List?> capture() async => next;
  @override
  Future<Uint8List?> pickFromGallery() async => next;
}

/// Records the "follow your diet plan" notifications.
class _PlanScheduler implements NotificationScheduler {
  final Map<int, (DateTime, String, String)> pending = {};
  @override
  Future<void> init() async {}
  @override
  Future<bool> requestPermission() async => true;
  @override
  Future<bool> isPermitted() async => true;
  @override
  Future<bool> openSettings() async => true;
  @override
  Future<void> scheduleOnce(int id, String title, String body, DateTime at, {String? payload}) async =>
      pending[id] = (at, title, body);
  @override
  Future<void> cancel(int id) async => pending.remove(id);
  @override
  Future<void> cancelAll() async => pending.clear();
  @override
  Stream<String> get taps => const Stream.empty();
  @override
  Future<String?> launchPayload() async => null;
  @override
  Future<bool> canRingOnTime() async => true;
  @override
  Future<void> openExactAlarmSettings() async {}
}

Uint8List jpeg(int w, int h) => Uint8List.fromList(img.encodeJpg(img.Image(width: w, height: h)));

void main() {
  const s = SuitabilityService();

  group('food catalogue', () {
    test('holds the Malaysian and healthcare foods the server recognises', () {
      expect(foods.foods.length, greaterThanOrEqualTo(200));
      for (final k in [
        'nasi_lemak',
        'roti_canai',
        'char_kway_teow',
        'asam_laksa',
        'teh_tarik',
        'oats',
        'steamed_fish',
      ]) {
        expect(foods.foods.any((f) => f.foodKey == k), isTrue, reason: k);
      }
    });

    test('nutrients scale with the portion (FR700_010, FR700_011)', () {
      final f = food('nasi_lemak');
      final a = f.nutrientsFor(100), b = f.nutrientsFor(250);
      expect(b.energyKcal, closeTo(a.energyKcal * 2.5, 0.2));
      final item = MealItem.of(f);
      expect(item.portionSizeG, f.baseServingG); // one standard serving (C8)
      expect(item.scaleTo(125).sodiumMg, closeTo(item.sodiumMg / 2, 0.2));
    });

    test('search finds Malay and English names', () async {
      expect((await foods.search('lemak')).dataOrNull!.map((f) => f.foodKey), contains('nasi_lemak'));
      expect((await foods.search('fried chicken')).dataOrNull!.map((f) => f.foodKey), contains('ayam_goreng'));
    });
  });

  group('suitability (UC900 C2, C6, C8; same cases as the server tests)', () {
    // Grams of nasi lemak that hold a given amount of sodium (its value comes from laboratory data).
    double gramsFor(double sodiumMg) => sodiumMg / food('nasi_lemak').sodiumMgPer100g * 100;

    test('hypertension: one item over 600 mg sodium is Not Suitable, with the excess', () {
      final vs = s.assess(MealItem.of(food('nasi_lemak'), grams: gramsFor(750)), ctx(conds: ['HYPERTENSION']));
      final v = vs.firstWhere((v) => v.nutrient == 'sodium_mg');
      expect(v.verdict, Verdict.notSuitable);
      expect(v.limit, 600);
      expect(v.excessAmount(), closeTo(150, 0.5));
      expect(v.reasonText, contains('exceeds your limit by 150 mg'));
      expect(v.conditionId, 1); // stored against the condition
    });

    test('80-100 % of the limit is Caution', () {
      final vs = s.assess(MealItem.of(food('nasi_lemak'), grams: gramsFor(510)), ctx(conds: ['HYPERTENSION']));
      expect(vs.firstWhere((v) => v.nutrient == 'sodium_mg').verdict, Verdict.caution);
    });

    test('diabetes: 7.5 g free sugars per item, most restrictive verdict shown (FR700_028)', () {
      final item = MealItem.of(
        food('teh_tarik'),
      ).withVerdicts(s.assess(MealItem.of(food('teh_tarik')), ctx(conds: ['DIABETES', 'HYPERTENSION'])));
      expect(item.worstVerdict(), Verdict.notSuitable);
      expect(item.verdicts.any((v) => v.nutrient == 'sugar_g' && v.limit == 7.5), isTrue);
    });

    test('no condition: the general daily limits (C6)', () {
      expect(s.mostRestrictive(s.assess(MealItem.of(food('nasi_lemak'), grams: 250), ctx())), Verdict.suitable);
      expect(s.mostRestrictive(s.assess(MealItem.of(food('ikan_masin'), grams: 40), ctx())), Verdict.notSuitable);
    });

    test('a declared restriction is always Not Suitable and excluded from plans (FR700_033)', () {
      final c = ctx(rs: ['PEANUT']);
      final vs = s.assess(MealItem.of(food('nasi_lemak'), grams: 50), c);
      expect(vs.single.verdict, Verdict.notSuitable);
      expect(vs.single.restrictionId, 1);
      expect(s.isExcludedFromPlans(food('nasi_lemak'), c), isTrue);
    });

    test('profile unavailable: conservative limits (FR700_022)', () {
      final vs = s.assess(MealItem.of(food('nasi_lemak'), grams: 250), ctx(failSafe: true));
      expect(s.mostRestrictive(vs), Verdict.notSuitable);
    });

    test('alternatives: same group, within the limits, closest first (C3)', () async {
      final item = MealItem.of(food('nasi_lemak'), grams: 250);
      final c = ctx(conds: ['HYPERTENSION']);
      final same = (await foods.alternativesTo(item.food, c.restrictionCodes)).dataOrNull!;
      final ranked = s.rankAlternatives(item, same, c);
      expect(ranked, isNotEmpty);
      expect(ranked.every((f) => f.foodCategory == 'Rice'), isTrue);
      expect(ranked.every((f) => f.nutrientsFor(f.baseServingG).sodiumMg < 600), isTrue);
    });
  });

  group('diet plan', () {
    DietPlan plan(List<PlannedMeal> meals) => DietPlan(
      dietPlanId: 'p',
      accountId: 'a',
      safetyLimitId: 'sl',
      planType: PlanType.daily,
      startDate: DateTime(2026, 10, 26),
      endDate: DateTime(2026, 10, 26),
      modelVersion: 'test',
      generatedAt: DateTime(2026, 10, 26),
      meals: meals,
    );
    final day = DateTime(2026, 10, 26);

    test('the safety gate rejects a day over a limit or with an unsuitable food (FR700_042)', () {
      final planner = DietPlannerService(ApiClient(baseUrl: 'x', tokenProvider: () => null), foods);
      final ok = plan([
        PlannedMeal.of(food('oats'), day, MealSlot.breakfast, 250),
        PlannedMeal.of(food('grilled_chicken_breast'), day, MealSlot.dinner, 100),
      ]);
      expect(planner.validate(ok, ctx(conds: ['HYPERTENSION'])), isEmpty);
      final salty = plan([PlannedMeal.of(food('ikan_masin'), day, MealSlot.lunch, 40)]);
      expect(planner.validate(salty, ctx()), isNotEmpty);
      final peanut = plan([PlannedMeal.of(food('satay_ayam'), day, MealSlot.dinner, 100)]);
      expect(planner.validate(peanut, ctx(rs: ['PEANUT'])), isNotEmpty);
    });

    test('a fail-safe plan is stored without a safety limit link (UC900 E1)', () {
      final failSafe = DietPlan(
        dietPlanId: 'p',
        accountId: 'a',
        safetyLimitId: SafetyLimit.mostRestrictive().safetyLimitId,
        planType: PlanType.daily,
        startDate: day,
        endDate: day,
        modelVersion: 'test',
        generatedAt: day,
        meals: const [],
      );
      final row = failSafe.toJson();
      expect(row['safety_limit_id'], isNull);
      expect(DietPlan.fromJson(row, const <PlannedMeal>[]).safetyLimitId, SafetyLimit.failSafeId);
      expect(plan(const []).toJson()['safety_limit_id'], 'sl');
    });

    test('adherence counts slots that were logged (FR700_037, FR700_038)', () {
      final p = plan([
        PlannedMeal.of(food('oats'), day, MealSlot.breakfast, 250),
        PlannedMeal.of(food('nasi_putih'), day, MealSlot.lunch, 160),
        PlannedMeal.of(food('steamed_fish'), day, MealSlot.lunch, 150),
      ]);
      final logged = MealLog(
        mealId: 'm',
        accountId: 'a',
        mealType: MealSlot.breakfast,
        entryMethod: EntryMethod.manual,
        consumedAt: DateTime(2026, 10, 26, 8),
      );
      final marked = p.copyWith(meals: [for (final m in p.meals) m.copyWith(isLogged: m.matchLogged(logged))]);
      expect(marked.adherence(), 0.5); // breakfast of breakfast + lunch
    });

    test('lock and replace keep the slot (FR700_035, FR700_036)', () {
      final m = PlannedMeal.of(food('nasi_lemak'), day, MealSlot.lunch, 250);
      expect(m.lock().isLocked, isTrue);
      final r = m.replaceWith(food('nasi_putih'));
      expect(r.mealSlot, MealSlot.lunch);
      expect(r.food.foodKey, 'nasi_putih');
      expect(r.portionSizeG, inInclusiveRange(80, 240));
    });

    test('a plan from the server is checked again on the phone and stored', () async {
      final auth = FakeAuthRepository();
      final accountId = (await auth.login('demo@apths.test', 'password123')).dataOrNull!.accountId;
      final profiles = FakeProfileRepository();
      final p = HealthProfile(
        profileId: newId(),
        accountId: accountId,
        age: 60,
        gender: Gender.female,
        weightKg: 62,
        heightCm: 158,
        conditions: [cond('HYPERTENSION')],
        restrictions: [restr('PEANUT')],
        updatedAt: DateTime.now(),
      );
      await profiles.saveProfile(p, p.generateSafetyLimit());
      Map<String, dynamic>? sent;
      final api = ApiClient(
        baseUrl: 'http://ai',
        tokenProvider: () => 'dev-token',
        httpClient: MockClient((req) async {
          sent = jsonDecode(req.body) as Map<String, dynamic>;
          final today = DateTime.now().toIso8601String().substring(0, 10);
          return http.Response(
            jsonEncode({
              'model_version': 'diet-planner-1.0+pref-logreg-1',
              'days': [
                {
                  'plan_date': today,
                  'meals': [
                    {
                      'meal_slot': 'BREAKFAST',
                      'items': [
                        {'food_key': 'oats', 'portion_g': 250},
                      ],
                    },
                    {
                      'meal_slot': 'LUNCH',
                      'items': [
                        {'food_key': 'nasi_putih', 'portion_g': 160},
                        {'food_key': 'telur_rebus', 'portion_g': 50},
                      ],
                    },
                    {
                      'meal_slot': 'DINNER',
                      'items': [
                        {'food_key': 'nasi_beras_perang', 'portion_g': 160},
                        {'food_key': 'grilled_chicken_breast', 'portion_g': 100},
                      ],
                    },
                    {
                      'meal_slot': 'SNACK',
                      'items': [
                        {'food_key': 'epal', 'portion_g': 150},
                      ],
                    },
                  ],
                },
              ],
            }),
            200,
          );
        }),
      );
      final meals = FakeMealRepository();
      final vm = DietPlanViewModel(
        DietPlannerService(api, foods),
        meals,
        foods,
        RiskAssessmentService(auth, profiles),
        auth,
      );
      await vm.load(PlanType.daily);
      expect(vm.plannerDown, isFalse);
      expect(vm.plan!.meals.length, 6);
      expect(vm.plan!.modelVersion, startsWith('diet-planner')); // FR700_043
      expect(meals.plans, hasLength(1)); // FR700_041
      expect(sent!['conditions'], ['HYPERTENSION']);
      expect(sent!['restrictions'], ['PEANUT']);
      expect(sent!.containsKey('account_id'), isFalse); // no identifier (FR700_046)
    });

    test('planner down: the patient can build the plan by hand (E2, FR700_044)', () async {
      final auth = FakeAuthRepository();
      await auth.login('demo@apths.test', 'password123');
      final api = ApiClient(
        baseUrl: 'http://ai',
        tokenProvider: () => 't',
        httpClient: MockClient((_) async => http.Response('{"error":{"code":"error","message":"down"}}', 503)),
      );
      final vm = DietPlanViewModel(
        DietPlannerService(api, foods),
        FakeMealRepository(),
        foods,
        RiskAssessmentService(auth, FakeProfileRepository()),
        auth,
      );
      await vm.load(PlanType.daily);
      expect(vm.plannerDown, isTrue);
      final problems = await vm.saveManualPlan({
        MealSlot.breakfast: [food('oats')],
        MealSlot.lunch: [food('nasi_putih')],
      });
      expect(problems, isEmpty);
      expect(vm.plan!.modelVersion, 'manual');
    });
  });

  group('flexible plan changes and explanations (A5.1, A5.3, DC700_06)', () {
    final day = DateTime(2026, 10, 26);
    DietPlan plan(List<PlannedMeal> meals) => DietPlan(
      dietPlanId: 'p',
      accountId: 'a',
      safetyLimitId: 'sl',
      planType: PlanType.daily,
      startDate: day,
      endDate: day,
      modelVersion: 'diet-planner-2.1+pref-logreg-1',
      generatedAt: day,
      meals: meals,
    );
    final planner = DietPlannerService(ApiClient(baseUrl: 'x', tokenProvider: () => null), foods);
    PlanChange preview(DietPlan before, DietPlan after, MealSlot slot, DietContext c) => planner.previewChange(
      kind: PlanChangeKind.add,
      before: before,
      after: after,
      day: day,
      slot: slot,
      ctx: c,
      title: 't',
      doneMessage: 'd',
    );

    test('only foods that suit the patient are suggested; a planner choice that does not is rejected', () {
      const s = SuitabilityService();
      expect(s.suitsPatient(food('oats'), ctx(conds: ['HYPERTENSION'])), isTrue);
      expect(s.suitsPatient(food('nasi_lemak'), ctx(conds: ['HYPERTENSION'])), isFalse); // 695 mg sodium
      expect(s.suitsPatient(food('nasi_lemak'), ctx()), isFalse); // more than 30 % of a day's sodium
      final lunch = PlannedMeal.of(food('nasi_lemak'), day, MealSlot.lunch, 250);
      expect(planner.validate(plan([lunch]), ctx()), isNotEmpty); // manual plans must suit the patient too
      expect(planner.validate(plan([lunch]), ctx(), strict: true), isNotEmpty); // the planner may not
      expect(
        planner.validate(plan([lunch.lock()]), ctx(), strict: true),
        isNotEmpty,
      ); // a lock never bypasses the rules
    });

    test('alternatives and suggestions are all suitable foods', () async {
      final c = ctx(conds: ['HYPERTENSION', 'DIABETES']);
      final m = PlannedMeal.of(food('nasi_putih'), day, MealSlot.lunch, 160);
      final alts = await planner.alternativesFor(m, plan([m]), c);
      expect(alts, isNotEmpty);
      const s = SuitabilityService();
      expect(alts.every((f) => s.suitsPatient(f, c, m.replaceWith(f).portionSizeG)), isTrue);
    });

    test('adding a food shows its effect on the day before it is made', () {
      final before = plan([PlannedMeal.of(food('oats'), day, MealSlot.breakfast, 250)]);
      final after = before.copyWith(meals: [...before.meals, PlannedMeal.of(food('epal'), day, MealSlot.snack, 150)]);
      final c = preview(before, after, MealSlot.snack, ctx(conds: ['DIABETES']));
      expect(c.allowed, isTrue);
      expect(c.after.energyKcal, greaterThan(c.before.energyKcal));
      expect(c.delta.energyKcal, closeTo(food('epal').nutrientsFor(150).energyKcal, 1));
      expect(c.effects.any((e) => e.text.startsWith('Energy for') && e.text.contains('→')), isTrue);
      expect(c.effects.any((e) => e.text.startsWith('Your snack will have')), isTrue);
    });

    test('a user change over a limit stays allowed with the amount shown as a red warning', () {
      final before = plan([PlannedMeal.of(food('oats'), day, MealSlot.breakfast, 250)]);
      final after = before.copyWith(
        meals: [...before.meals, PlannedMeal.of(food('ikan_masin'), day, MealSlot.lunch, 300)],
      );
      final c = preview(before, after, MealSlot.lunch, ctx());
      expect(c.allowed, isTrue);
      expect(c.problems, isEmpty);
      expect(c.warnings.join(' '), contains('of 2,000 mg'));
      // Too much is said in red, with what it does to the body.
      final w = c.warnings.map((e) => e.text).join(' ');
      expect(w, contains('Too much sodium'));
      expect(w, contains('blood pressure'));
    });

    test('a food that is high for the patient is explained as a warning; a fine one is not', () {
      final c = ctx(conds: ['HYPERTENSION']);
      final salty = PlannedMeal.of(food('ikan_masin'), day, MealSlot.lunch, 20);
      final r = planner.reasonsFor(salty, plan([salty]), c);
      expect(r.where((n) => n.warn).map((n) => n.text).join(' '), contains('blood pressure'));
      final oats = PlannedMeal.of(food('oats'), day, MealSlot.breakfast, 250);
      expect(planner.reasonsFor(oats, plan([oats]), c).where((n) => n.warn), isEmpty);
      // A day far under its energy target says so.
      final low = planner.summaryFor(plan([oats]), day, c).firstWhere((x) => x.kind == 'energy');
      expect(low.ok, isFalse);
      expect(low.title, 'Too little energy for the day');
    });

    test('removing the last food of a slot says the slot will be empty', () {
      final before = plan([
        PlannedMeal.of(food('oats'), day, MealSlot.breakfast, 250),
        PlannedMeal.of(food('epal'), day, MealSlot.snack, 150),
      ]);
      final after = before.copyWith(meals: [before.meals.first]);
      final c = preview(before, after, MealSlot.snack, ctx());
      expect(c.allowed, isTrue);
      expect(c.effects.any((e) => e.text.contains('will have no food planned')), isTrue);
      expect(c.after.energyKcal, lessThan(c.before.energyKcal));
    });

    test('each planned food and each day of the plan are explained', () {
      final m = PlannedMeal.of(food('oats'), day, MealSlot.breakfast, 250);
      final p = plan([m]);
      final c = ctx(conds: ['HYPERTENSION'], rs: ['PEANUT']);
      final reasons = planner.reasonsFor(m, p, c);
      expect(reasons.first.text, contains('starch')); // its place on the plate
      expect(reasons.any((r) => r.text.contains('because you have declared')), isTrue); // its sodium limit
      expect(reasons.any((r) => r.text.contains('Peanut')), isTrue); // the foods avoided
      final kinds = planner.summaryFor(p, day, c).map((r) => r.kind).toList();
      expect(kinds, containsAll(['energy', 'plate', 'limits', 'profile', 'preference']));
    });

    test('the patient adds and removes foods; a rejected or stale change is not made', () async {
      final auth = FakeAuthRepository();
      await auth.login('demo@apths.test', 'password123');
      final api = ApiClient(
        baseUrl: 'http://ai',
        tokenProvider: () => 't',
        httpClient: MockClient((_) async => http.Response('{"error":{"code":"error","message":"down"}}', 503)),
      );
      final meals = FakeMealRepository();
      final vm = DietPlanViewModel(
        DietPlannerService(api, foods),
        meals,
        foods,
        RiskAssessmentService(auth, FakeProfileRepository()),
        auth,
      );
      await vm.load(PlanType.daily);
      expect(
        await vm.saveManualPlan({
          MealSlot.breakfast: [food('oats')],
        }),
        isEmpty,
      );
      final today = vm.plan!.startDate;

      final add = vm.previewAdd(today, MealSlot.snack, food('epal'))!;
      expect(add.allowed, isTrue);
      expect(add.effects.first.text, contains('will be added to your snack'));
      expect(await vm.applyChange(add), isTrue);
      expect(vm.plan!.mealsFor(today).map((m) => m.food.foodKey), containsAll(['oats', 'epal']));
      expect(meals.plans.single.meals, hasLength(2)); // saved

      final rm = vm.previewRemove(vm.plan!.meals.firstWhere((m) => m.food.foodKey == 'oats'))!;
      expect(await vm.applyChange(rm), isTrue);
      expect(vm.plan!.meals.map((m) => m.food.foodKey), ['epal']);

      final salty = vm.previewAdd(today, MealSlot.lunch, food('ikan_masin'), grams: 300)!;
      expect(salty.allowed, isTrue);
      expect(await vm.applyChange(salty), isTrue);
      expect(vm.plan!.meals, hasLength(2));
      expect(vm.savedFoodWarnings(vm.plan!.meals.last), isNotEmpty);

      final stale = vm.previewAdd(today, MealSlot.lunch, food('nasi_putih'))!;
      expect(await vm.applyChange(vm.previewAdd(today, MealSlot.breakfast, food('oats'))!), isTrue);
      expect(await vm.applyChange(stale), isFalse); // worked out from an older plan
      expect(vm.plan!.meals, hasLength(3));

      final portion = vm.previewPortion(vm.plan!.meals.firstWhere((m) => m.food.foodKey == 'oats'), 125)!;
      expect(await vm.applyChange(portion), isTrue);
      expect(vm.plan!.meals.firstWhere((m) => m.food.foodKey == 'oats').portionSizeG, 125);
      expect(vm.regenerateEffects.first, contains('not locked'));
    });

    test('suggestions for a slot fill what it is missing and fit the limits', () async {
      final auth = FakeAuthRepository();
      await auth.login('demo@apths.test', 'password123');
      final api = ApiClient(
        baseUrl: 'http://ai',
        tokenProvider: () => 't',
        httpClient: MockClient((_) async => http.Response('{"error":{"code":"error","message":"down"}}', 503)),
      );
      final vm = DietPlanViewModel(
        DietPlannerService(api, foods),
        FakeMealRepository(),
        foods,
        RiskAssessmentService(auth, FakeProfileRepository()),
        auth,
      );
      await vm.load(PlanType.daily);
      await vm.saveManualPlan({
        MealSlot.lunch: [food('nasi_putih')],
      });
      final s = await vm.suggestionsFor(vm.plan!.startDate, MealSlot.lunch);
      expect(s, isNotEmpty);
      expect(s.first.planRole, anyOf('veg', 'protein')); // rice is there: vegetables or a protein next
      expect(s.every((f) => f.mealSlots.contains('LUNCH')), isTrue);
    });
  });

  group('following the diet plan: alerts (UC900 with M600)', () {
    final day = DateTime(2026, 10, 26);
    final planner = DietPlannerService(ApiClient(baseUrl: 'x', tokenProvider: () => null), foods);
    DietPlan dayPlan({String accountId = 'a'}) => DietPlan(
      dietPlanId: 'p',
      accountId: accountId,
      safetyLimitId: 'sl',
      planType: PlanType.daily,
      startDate: day,
      endDate: day,
      modelVersion: 'diet-planner-2.1',
      generatedAt: day,
      meals: [
        PlannedMeal.of(food('oats'), day, MealSlot.breakfast, 250),
        PlannedMeal.of(food('nasi_putih'), day, MealSlot.lunch, 160),
        PlannedMeal.of(food('grilled_chicken_breast'), day, MealSlot.lunch, 100),
        PlannedMeal.of(food('nasi_beras_perang'), day, MealSlot.dinner, 160),
        PlannedMeal.of(food('epal'), day, MealSlot.snack, 150),
      ],
    );
    MealLog eaten(MealSlot slot, List<(String, double)> items, DateTime at) => MealLog(
      mealId: newId(),
      accountId: 'a',
      mealType: slot,
      entryMethod: EntryMethod.manual,
      consumedAt: at,
      items: [for (final (k, g) in items) MealItem.of(food(k), grams: g)],
    );

    test('planned meals not logged ring at their time; logged or past ones do not', () {
      final p = dayPlan();
      final morning = planner.missedMealAlerts(p, const [], DateTime(2026, 10, 26, 8));
      expect(morning.map((a) => a.slot), [MealSlot.breakfast, MealSlot.lunch, MealSlot.dinner]); // no snack
      expect(morning[1].at, DateTime(2026, 10, 26, 14, 30));
      expect(morning[1].body, contains('Plain white rice'));
      final noon = planner.missedMealAlerts(p, [
        eaten(MealSlot.breakfast, [('oats', 250)], DateTime(2026, 10, 26, 8)),
      ], DateTime(2026, 10, 26, 12));
      expect(noon.map((a) => a.slot), [MealSlot.lunch, MealSlot.dinner]);
      expect(planner.missedMealAlerts(p, const [], DateTime(2026, 10, 27, 8)), isEmpty); // not a plan day
    });

    test('how the plan was followed: as planned, differently, missed', () {
      final p = dayPlan();
      final logged = [
        eaten(MealSlot.breakfast, [('oats', 250)], DateTime(2026, 10, 26, 8)), // as planned
        eaten(MealSlot.dinner, [('nasi_lemak', 250)], DateTime(2026, 10, 26, 19)), // different
      ];
      final f = planner.followOf(p, logged, DateTime(2026, 10, 26, 21)); // lunch missed
      expect((f.due, f.followed, f.different, f.missed), (3, 1, 1, 1));
      expect(f.notFollowing, isTrue);
      final early = planner.followOf(p, logged.take(1).toList(), DateTime(2026, 10, 26, 9));
      expect((early.due, early.followed), (1, 1));
      expect(early.notFollowing, isFalse);
    });

    test('a meal off the plan is explained; over a limit it is red with what it does to the body', () {
      final p = dayPlan();
      final at = DateTime(2026, 10, 26, 13);
      final asPlanned = eaten(MealSlot.lunch, [('nasi_putih', 160), ('grilled_chicken_breast', 100)], at);
      expect(planner.offPlanAlertFor(asPlanned, p, ctx(), [asPlanned], at), isNull);
      final other = eaten(MealSlot.lunch, [('nasi_lemak', 250)], at);
      final a = planner.offPlanAlertFor(other, p, ctx(), [other], at)!;
      expect(a.overLimit, isFalse);
      expect(a.body, contains('instead of Plain white rice'));
      final salty = eaten(MealSlot.lunch, [('ikan_masin', 100)], at);
      final r = planner.offPlanAlertFor(salty, p, ctx(), [salty], at)!;
      expect(r.overLimit, isTrue);
      expect(r.body, contains('over your limit'));
      expect(r.body, contains('blood pressure'));
    });

    test(
      'alerts are scheduled, cancelled when the meal is logged, and an off-plan meal is logged in the history',
      () async {
        final repo = FakeNotificationRepository();
        final device = _PlanScheduler();
        final now = DateTime(2026, 10, 26, 8);
        final alerts = LocalNotificationService(
          repo,
          FakeTreatmentRepository(const []),
          scheduler: device,
          now: () => now,
        );
        final p = dayPlan();
        expect(await alerts.schedulePlanAlerts(planner.missedMealAlerts(p, const [], now)), 3);
        expect(device.pending.keys, containsAll([700000000, 700000001, 700000002]));
        final breakfast = eaten(MealSlot.breakfast, [('oats', 250)], DateTime(2026, 10, 26, 9));
        await alerts.schedulePlanAlerts(planner.missedMealAlerts(p, [breakfast], now));
        expect(device.pending.containsKey(700000000), isFalse); // breakfast logged: no alert
        final other = eaten(MealSlot.lunch, [('ikan_masin', 100)], DateTime(2026, 10, 26, 8));
        final entry = await alerts.planAlert('a', planner.offPlanAlertFor(other, p, ctx(), [other], now)!);
        expect(repo.log.single.messageBody, entry.messageBody);
        expect(entry.messageBody, contains('Not following your diet plan'));
        expect(device.pending.containsKey(LocalNotificationService.offPlanAlertId(MealSlot.lunch)), isTrue);
      },
    );

    test('logging a meal that is not the planned one alerts the patient on the Diet tab', () async {
      final auth = FakeAuthRepository();
      final accountId = (await auth.login('demo@apths.test', 'password123')).dataOrNull!.accountId;
      final meals = FakeMealRepository();
      await meals.savePlan(dayPlan(accountId: accountId));
      final repo = FakeNotificationRepository();
      final device = _PlanScheduler();
      final at = DateTime(2026, 10, 26, 13);
      final vm = MealLogViewModel(
        meals,
        FoodRecognitionService(ApiClient(baseUrl: 'x', tokenProvider: () => null), foods),
        foods,
        RiskAssessmentService(auth, FakeProfileRepository()),
        auth,
        _NoCamera(),
        const SuitabilityService(),
        () => at,
        planner,
        LocalNotificationService(repo, FakeTreatmentRepository(const []), scheduler: device, now: () => at),
      );
      await vm.load();
      expect(vm.planAlert, isNull);
      expect(device.pending.containsKey(700000000), isFalse); // breakfast time has passed
      expect(device.pending.containsKey(700000001), isTrue); // lunch rings at 14:30 unless logged
      vm.startManual();
      vm.addFood(food('nasi_lemak'));
      expect(await vm.confirmMeal(), isTrue);
      expect(vm.planAlert, isNotNull); // lunch was not the planned one
      expect(repo.log, hasLength(1));
      expect(device.pending.containsKey(700000001), isFalse); // lunch is logged
      vm.dismissPlanAlert();
      expect(vm.planAlert, isNull);
    });
  });

  group('meal logging (UC800)', () {
    late FakeAuthRepository auth;
    late FakeMealRepository meals;
    late _NoCamera camera;

    MealLogViewModel build(http.Client client) => MealLogViewModel(
      meals,
      FoodRecognitionService(ApiClient(baseUrl: 'http://ai', tokenProvider: () => 't', httpClient: client), foods),
      foods,
      RiskAssessmentService(auth, FakeProfileRepository()),
      auth,
      camera,
    );

    setUp(() async {
      auth = FakeAuthRepository();
      await auth.login('demo@apths.test', 'password123');
      meals = FakeMealRepository();
      camera = _NoCamera();
    });

    test('adding papaya twice combines the grams and nutrients in one row before saving', () async {
      final vm = build(MockClient((_) async => http.Response('{}', 503)));
      await vm.load();
      vm.startManual();
      final papaya = food('betik');
      vm.addFood(papaya, grams: 100);
      final id = vm.draft!.items.single.mealItemId;
      vm.addFood(papaya, grams: 150);
      final row = vm.draft!.items.single;
      expect(row.mealItemId, id);
      expect(row.portionSizeG, 250);
      expect(row.energyKcal, papaya.nutrientsFor(250).energyKcal);
      expect(row.sugarG, papaya.nutrientsFor(250).sugarG);
      expect(vm.takeMessage(), contains('250 g'));
      expect(await vm.confirmMeal(), isTrue);
      expect(meals.meals.single.items, hasLength(1));
    });

    test('correcting another food to papaya merges and preserves the correction flag', () async {
      final vm = build(MockClient((_) async => http.Response('{}', 503)));
      await vm.load();
      vm.startManual();
      vm.addFood(food('betik'), grams: 100);
      vm.addFood(food('oats'), grams: 125);
      vm.correctItem(vm.draft!.items.last, food('betik'));
      expect(vm.draft!.items, hasLength(1));
      expect(vm.draft!.items.single.portionSizeG, 100 + food('betik').baseServingG);
      expect(vm.draft!.items.single.isUserCorrected, isTrue);
    });

    test('merged quantities are reassessed and an excessive combined quantity leaves the draft unchanged', () async {
      final vm = build(MockClient((_) async => http.Response('{}', 503)));
      await vm.load();
      vm.startManual();
      vm.addFood(food('ikan_masin'), grams: 10);
      vm.takeMessage();
      vm.addFood(food('ikan_masin'), grams: 30);
      expect(vm.draft!.items.single.portionSizeG, 40);
      expect(vm.takeMessage(), contains('Not suitable:'));
      vm.startManual();
      vm.addFood(food('betik'), grams: 900);
      vm.addFood(food('betik'), grams: 150);
      expect(vm.draft!.items.single.portionSizeG, 900);
      expect(vm.takeMessage(), contains('combined portion'));
    });

    test('a photo is checked (C3) and reduced to 384 px JPEG before upload (C4)', () async {
      final svc = FoodRecognitionService(ApiClient(baseUrl: 'x', tokenProvider: () => null), foods);
      expect((await svc.prepare(jpeg(100, 100))).isSuccess, isFalse);
      expect((await svc.prepare(Uint8List.fromList([1, 2, 3]))).isSuccess, isFalse);
      final ok = (await svc.prepare(jpeg(1200, 900))).dataOrNull!;
      expect(ok.width, 384);
      expect(ok.height, 288);
    });

    test('choosing or resizing an unsuitable logged food alerts with the reason; correction clears it', () async {
      final vm = build(MockClient((_) async => http.Response('{}', 503)));
      await vm.load();
      vm.startManual();
      vm.addFood(food('ikan_masin'), grams: 40);
      expect(vm.takeMessage(), contains('Not suitable:'));
      vm.correctItem(vm.draft!.items.single, food('oats'));
      expect(vm.takeMessage(), isNull);
      vm.correctItem(vm.draft!.items.single, food('ikan_masin'));
      vm.adjustPortion(vm.draft!.items.single, 40);
      expect(vm.takeMessage(), contains('sodium'));
      // A diary can record what was eaten; this is separate from saving a suitable diet plan.
      expect(await vm.confirmMeal(), isTrue);
    });

    test('recognised meal: items with verdicts; saved with its photo and model version', () async {
      final vm = build(
        MockClient((req) async {
          expect(req.headers['authorization'], 'Bearer t'); // FR700_047
          return http.Response(
            jsonEncode({
              'model_version': 'food-clip-vitb16-head-1',
              'is_food': true,
              'confidence': 0.86,
              'items': [
                {
                  'food_key': 'nasi_lemak',
                  'confidence': 0.86,
                  'primary': true,
                  'candidates': [
                    {'food_key': 'nasi_kerabu'},
                  ],
                },
                {'food_key': 'teh_tarik', 'confidence': 0.7, 'primary': false, 'candidates': []},
              ],
            }),
            200,
          );
        }),
      );
      await vm.load();
      camera.next = jpeg(800, 600);
      await vm.captureImage();
      expect(vm.step, MealStep.review);
      expect(vm.manualEntryPrompt, isFalse);
      expect(vm.draft!.items.map((i) => i.food.foodKey), ['nasi_lemak', 'teh_tarik']);
      expect(meals.images, isEmpty); // not stored before confirmation (FR700_009)
      vm.adjustPortion(vm.draft!.items.first, 125); // FR700_007
      expect(vm.draft!.items.first.portionSizeG, 125);
      // The weight can also be typed, from 10 g to 1000 g; anything else is refused with the reason.
      final first = vm.draft!.items.first;
      expect(vm.enterPortion(first, '5'), Messages.portionOutOfRange);
      expect(vm.enterPortion(first, '1200'), Messages.portionOutOfRange);
      expect(vm.enterPortion(first, 'abc'), Messages.portionNotNumber);
      expect(vm.enterPortion(first, ''), Messages.portionNotNumber);
      expect(vm.draft!.items.first.portionSizeG, 125); // unchanged
      expect(vm.enterPortion(vm.draft!.items.first, '180,4'), isNull); // a comma is a decimal point
      expect(vm.draft!.items.first.portionSizeG, 180);
      final kcal180 = vm.draft!.items.first.energyKcal;
      expect(vm.enterPortion(vm.draft!.items.first, '1000'), isNull); // the top of the range
      expect(vm.draft!.items.first.energyKcal, closeTo(kcal180 * 1000 / 180, 1)); // nutrients follow
      expect(vm.enterPortion(vm.draft!.items.first, '10'), isNull); // the bottom of the range
      vm.adjustPortion(vm.draft!.items.first, 125);
      expect(await vm.confirmMeal(), isTrue);
      expect(meals.meals.single.modelVersion, 'food-clip-vitb16-head-1'); // FR700_008
      expect(meals.images, hasLength(1));
      expect(vm.dailyTotals.energyKcal, greaterThan(0)); // FR700_013
      await vm.deleteMeal(meals.meals.single); // FR700_015, FR700_016
      expect(meals.meals, isEmpty);
      expect(meals.images, isEmpty);
    });

    test('below 60 % confidence the patient enters the food (A2, FR700_005)', () async {
      final vm = build(
        MockClient(
          (_) async => http.Response(
            jsonEncode({
              'model_version': 'v',
              'is_food': true,
              'confidence': 0.41,
              'items': [
                {'food_key': 'mee_goreng', 'confidence': 0.41},
              ],
            }),
            200,
          ),
        ),
      );
      await vm.load();
      camera.next = jpeg(640, 480);
      await vm.pickFromGallery();
      expect(vm.manualEntryPrompt, isTrue);
      expect(vm.draft!.items, isEmpty);
      vm.addFood(food('mee_goreng_mamak'));
      expect(await vm.confirmMeal(), isTrue);
    });

    test('service down: manual entry still logs the meal (E1, FR700_050)', () async {
      final vm = build(MockClient((_) async => throw const SocketException('down')));
      await vm.load();
      camera.next = jpeg(640, 480);
      await vm.captureImage();
      expect(vm.manualEntryPrompt, isTrue);
      expect(vm.lastResult, isNull);
      vm.addFood(food('roti_canai'));
      expect(await vm.confirmMeal(), isTrue);
      expect(meals.meals.single.entryMethod, EntryMethod.manual);
      expect(meals.images, hasLength(1)); // the photo is kept although the foods were entered by hand
    });

    String nasiLemak() => jsonEncode({
      'model_version': 'food-clip-vitb16-head-2',
      'is_food': true,
      'confidence': 0.9,
      'items': [
        {'food_key': 'nasi_lemak', 'confidence': 0.9, 'primary': true, 'candidates': []},
      ],
    });

    test(
      'UI first: the meal is on today\'s list before the database answers; its photo comes back in the history',
      () async {
        final vm = build(MockClient((_) async => http.Response(nasiLemak(), 200)));
        await vm.load();
        camera.next = jpeg(800, 600);
        await vm.captureImage();
        final saving = vm.confirmMeal();
        // At once: on the list, marked as saving, with its photo and the day's totals.
        expect(vm.today, hasLength(1));
        expect(vm.isSaving(vm.today.single), isTrue);
        expect(vm.photoOf(vm.today.single), isNotNull);
        expect(vm.dailyTotals.energyKcal, greaterThan(0));
        expect(await saving, isTrue);
        expect(vm.isSaving(vm.today.single), isFalse);
        expect(meals.images, hasLength(1));

        // Opened again later: the history downloads the stored photo (FR700_009, FR700_014).
        final later = build(MockClient((_) async => http.Response('{}', 500)));
        await later.load();
        final now = DateTime.now();
        expect(await later.loadHistory(now.subtract(const Duration(days: 1)), now), isTrue);
        final m = later.history.single;
        expect(later.hasPhoto(m), isTrue);
        expect(later.photoOf(m), isNull);
        await later.fetchPhoto(m);
        expect(later.photoOf(m), meals.images[m.imageUri]);
      },
    );

    test('a failed save takes the meal off the list again and keeps it for another try (E2, M8)', () async {
      final vm = build(MockClient((_) async => throw const SocketException('down')));
      await vm.load();
      camera.next = jpeg(640, 480);
      await vm.captureImage();
      vm.addFood(food('roti_canai'));
      meals.failNext = true;
      final saving = vm.confirmMeal();
      expect(vm.today, hasLength(1));
      expect(await saving, isFalse);
      expect(vm.today, isEmpty);
      expect(vm.step, MealStep.review);
      expect(vm.draft!.items, hasLength(1));
      expect(vm.takeMessage(), Messages.mealSaveFailed);
      expect(await vm.confirmMeal(), isTrue); // try again
      expect(meals.meals, hasLength(1));
    });

    test('UI first: a deleted meal leaves at once and comes back if the deletion fails', () async {
      final vm = build(MockClient((_) async => throw const SocketException('down')));
      await vm.load();
      vm.startManual();
      vm.addFood(food('roti_canai'));
      expect(await vm.confirmMeal(), isTrue);
      final m = vm.today.single;
      meals.failNext = true;
      final deleting = vm.deleteMeal(m);
      expect(vm.today, isEmpty);
      expect(vm.dailyTotals.energyKcal, 0);
      expect(await deleting, isFalse);
      expect(vm.today, hasLength(1));
      expect(meals.meals, hasLength(1));
      expect(await vm.deleteMeal(m), isTrue);
      expect(meals.meals, isEmpty);
    });

    test('while waiting, the patient can enter the food instead; a late answer is ignored (FR700_050)', () async {
      final slow = Completer<http.Response>();
      final vm = build(MockClient((_) => slow.future));
      await vm.load();
      final waiting = vm.recognise(jpeg(800, 600));
      expect(vm.step, MealStep.recognising);
      expect(vm.pendingPhoto, isNotNull); // shown on the waiting screen at once
      for (var i = 0; i < 500 && vm.draftImage == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(vm.draftImage, isNotNull);
      vm.enterManually();
      expect(vm.step, MealStep.review);
      expect(vm.draft!.entryMethod, EntryMethod.manual);
      slow.complete(http.Response(nasiLemak(), 200));
      await waiting;
      expect(vm.lastResult, isNull);
      expect(vm.step, MealStep.review);
      vm.addFood(food('roti_canai'));
      expect(await vm.confirmMeal(), isTrue);
      expect(meals.images, hasLength(1));
    });

    test('a cancelled camera keeps nothing and says nothing (A7)', () async {
      final vm = build(MockClient((_) async => http.Response(nasiLemak(), 200)));
      await vm.load();
      camera.next = null;
      expect(await vm.pickPhoto(camera: true), isNull);
      expect(vm.takeMessage(), isNull);
      expect(vm.step, MealStep.idle);
    });
  });
}
