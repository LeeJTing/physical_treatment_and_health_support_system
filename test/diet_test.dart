import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;

import 'package:physical_treatment_and_health_support_system/core/utils/id_utils.dart';
import 'package:physical_treatment_and_health_support_system/device_platform/camera_gallery/meal_image_picker.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/diet_planner_service/diet_planner_service.dart';
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

Uint8List jpeg(int w, int h) => Uint8List.fromList(img.encodeJpg(img.Image(width: w, height: h)));

void main() {
  const s = SuitabilityService();

  group('food catalogue', () {
    test('holds the Malaysian and healthcare foods the server recognises', () {
      expect(foods.foods.length, greaterThanOrEqualTo(200));
      for (final k in ['nasi_lemak', 'roti_canai', 'char_kway_teow', 'asam_laksa', 'teh_tarik', 'oats', 'steamed_fish']) {
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
    test('hypertension: one item over 600 mg sodium is Not Suitable, with the excess', () {
      final vs = s.assess(MealItem.of(food('nasi_lemak'), grams: 250), ctx(conds: ['HYPERTENSION']));
      final v = vs.firstWhere((v) => v.nutrient == 'sodium_mg');
      expect(v.verdict, Verdict.notSuitable);
      expect(v.limit, 600);
      expect(v.excessAmount(), closeTo(150, 0.5));
      expect(v.reasonText, contains('exceeds your limit by 150 mg'));
      expect(v.conditionId, 1); // stored against the condition
    });

    test('80-100 % of the limit is Caution', () {
      final vs = s.assess(MealItem.of(food('nasi_lemak'), grams: 170), ctx(conds: ['HYPERTENSION']));
      expect(vs.firstWhere((v) => v.nutrient == 'sodium_mg').verdict, Verdict.caution);
    });

    test('diabetes: 7.5 g free sugars per item, most restrictive verdict shown (FR700_028)', () {
      final item = MealItem.of(food('teh_tarik')).withVerdicts(
        s.assess(MealItem.of(food('teh_tarik')), ctx(conds: ['DIABETES', 'HYPERTENSION'])),
      );
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
        PlannedMeal.of(food('steamed_fish'), day, MealSlot.dinner, 150),
      ]);
      expect(planner.validate(ok, ctx(conds: ['HYPERTENSION'])), isEmpty);
      final salty = plan([PlannedMeal.of(food('ikan_masin'), day, MealSlot.lunch, 40)]);
      expect(planner.validate(salty, ctx()), isNotEmpty);
      final peanut = plan([PlannedMeal.of(food('satay_ayam'), day, MealSlot.dinner, 100)]);
      expect(planner.validate(peanut, ctx(rs: ['PEANUT'])), isNotEmpty);
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
                    {'meal_slot': 'BREAKFAST', 'items': [{'food_key': 'oats', 'portion_g': 250}]},
                    {'meal_slot': 'LUNCH', 'items': [{'food_key': 'nasi_putih', 'portion_g': 160}, {'food_key': 'steamed_fish', 'portion_g': 150}]},
                    {'meal_slot': 'DINNER', 'items': [{'food_key': 'nasi_beras_perang', 'portion_g': 160}, {'food_key': 'grilled_chicken_breast', 'portion_g': 100}]},
                    {'meal_slot': 'SNACK', 'items': [{'food_key': 'epal', 'portion_g': 150}]},
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

    test('a photo is checked (C3) and reduced to 384 px JPEG before upload (C4)', () async {
      final svc = FoodRecognitionService(ApiClient(baseUrl: 'x', tokenProvider: () => null), foods);
      expect((await svc.prepare(jpeg(100, 100))).isSuccess, isFalse);
      expect((await svc.prepare(Uint8List.fromList([1, 2, 3]))).isSuccess, isFalse);
      final ok = (await svc.prepare(jpeg(1200, 900))).dataOrNull!;
      expect(ok.width, 384);
      expect(ok.height, 288);
    });

    test('recognised meal: items with verdicts; saved with its photo and model version', () async {
      final vm = build(MockClient((req) async {
        expect(req.headers['authorization'], 'Bearer t'); // FR700_047
        return http.Response(
          jsonEncode({
            'model_version': 'food-clip-vitb16-head-1',
            'is_food': true,
            'confidence': 0.86,
            'items': [
              {'food_key': 'nasi_lemak', 'confidence': 0.86, 'primary': true, 'candidates': [{'food_key': 'nasi_kerabu'}]},
              {'food_key': 'teh_tarik', 'confidence': 0.7, 'primary': false, 'candidates': []},
            ],
          }),
          200,
        );
      }));
      await vm.load();
      camera.next = jpeg(800, 600);
      await vm.captureImage();
      expect(vm.step, MealStep.review);
      expect(vm.manualEntryPrompt, isFalse);
      expect(vm.draft!.items.map((i) => i.food.foodKey), ['nasi_lemak', 'teh_tarik']);
      expect(meals.images, isEmpty); // not stored before confirmation (FR700_009)
      vm.adjustPortion(vm.draft!.items.first, 125); // FR700_007
      expect(vm.draft!.items.first.portionSizeG, 125);
      expect(await vm.confirmMeal(), isTrue);
      expect(meals.meals.single.modelVersion, 'food-clip-vitb16-head-1'); // FR700_008
      expect(meals.images, hasLength(1));
      expect(vm.dailyTotals.energyKcal, greaterThan(0)); // FR700_013
      await vm.deleteMeal(meals.meals.single); // FR700_015, FR700_016
      expect(meals.meals, isEmpty);
      expect(meals.images, isEmpty);
    });

    test('below 60 % confidence the patient enters the food (A2, FR700_005)', () async {
      final vm = build(MockClient((_) async => http.Response(
        jsonEncode({'model_version': 'v', 'is_food': true, 'confidence': 0.41, 'items': [{'food_key': 'mee_goreng', 'confidence': 0.41}]}),
        200,
      )));
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
      expect(meals.images, isEmpty);
    });
  });
}
