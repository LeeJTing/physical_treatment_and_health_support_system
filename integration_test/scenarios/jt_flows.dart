import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:physical_treatment_and_health_support_system/core/constants/app_constants.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/biometric_reading.dart';
import 'package:physical_treatment_and_health_support_system/device_platform/health_connect/health_data_source.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/lookups.dart';
import 'package:physical_treatment_and_health_support_system/view/diet_view/diet_plan_view.dart';
import 'package:physical_treatment_and_health_support_system/view/diet_view/widgets/plan_cards.dart';
import 'package:physical_treatment_and_health_support_system/view/diet_view/food_search_sheet.dart';
import 'package:physical_treatment_and_health_support_system/view/diet_view/widgets/diet_widgets.dart';
import 'package:physical_treatment_and_health_support_system/view/diet_view/meal_result_view.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/meal_log_view_model/meal_log_view_model.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/analysis_view_model/analysis_view_model.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/diet_plan_view_model/diet_plan_view_model.dart';
import '../support/demo_app.dart';
import '../support/demo_environment.dart';

void runJtFlows() {
  late DemoEnvironment env;

  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 4; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await t.pump(const Duration(milliseconds: 100));
    }
    await t.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 20),
    );
  }

  Future<void> boot(WidgetTester t, {bool signedIn = true}) async {
    await t.pumpWidget(const SizedBox.shrink());
    t.binding.testTextInput.register();
    env = (await t.runAsync(() => startDemo(signedIn: signedIn)))!;
    await settle(t);
  }

  Future<void> tap(WidgetTester t, String label) async {
    if (find.text(label).evaluate().isEmpty) {
      await t.scrollUntilVisible(find.text(label), 250, scrollable: find.byType(Scrollable).last);
      await settle(t);
    }
    final f = find.text(label).last;
    await t.ensureVisible(f);
    await settle(t);
    await t.tap(f);
    await settle(t);
  }

  Future<void> hideKeyboard(WidgetTester t) async {
    // Close the editing client before hiding the Android IME, so a delayed native edit cannot
    // restore the previous value after tester.enterText replaces an already-focused field.
    FocusManager.instance.primaryFocus?.unfocus();
    await t.pump();
    await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    await settle(t);
  }

  Future<void> searchFood(WidgetTester t, String term) async {
    await t.enterText(find.byType(TextField).last, term);
    await settle(t);
    await hideKeyboard(t);
    final tile = find.descendant(of: find.byType(FoodSearchSheet), matching: find.byType(FoodTile)).first;
    await t.ensureVisible(tile);
    await settle(t);
    await t.tap(tile);
    await settle(t);
  }

  testWidgets('JT-M100-01 login rejects a wrong password then opens the signed-in shell', (t) async {
    await boot(t, signedIn: false);
    await t.enterText(find.byType(TextFormField).at(0), 'demo@apths.test');
    await t.enterText(find.byType(TextFormField).at(1), 'wrong12345');
    await hideKeyboard(t);
    await tap(t, 'Log In');
    expect(find.text(Messages.incorrectCredentials), findsOneWidget);
    await t.enterText(find.byType(TextFormField).at(1), 'password123');
    await hideKeyboard(t);
    await tap(t, 'Log In');
    // Wait for the completed sign-in route, including any asynchronous startup work.
    for (var i = 0; i < 50 && find.byType(NavigationBar).evaluate().isEmpty; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(NavigationBar), findsOneWidget);
    expect((await env.auth.currentAccount()).dataOrNull?.email, 'demo@apths.test');
  });

  testWidgets('JT-M100-02 profile validates age and asks before updating diet plans', (t) async {
    await boot(t);
    await tap(t, 'Profile');
    await tap(t, 'Edit');
    expect(find.text('Other condition (not listed)'), findsNothing);
    await t.enterText(find.byType(TextFormField).first, '999');
    await hideKeyboard(t);
    expect(find.textContaining('range'), findsWidgets);
    await t.enterText(find.byType(TextFormField).first, '61');
    await hideKeyboard(t);
    await tap(t, 'Save');
    expect(find.text('Update your diet plan?'), findsOneWidget);
    await tap(t, 'Not now');
    expect((await env.profiles.getProfile(env.accountId)).dataOrNull!.age, 61);
    expect(env.ai.requests.where((p) => p == '/plan'), isEmpty);
  });

  testWidgets('JT-M200-01 invalid reading cannot save; valid weight is saved and deleted', (t) async {
    await boot(t);
    await tap(t, 'Tracking');
    await tap(t, 'Add Reading');
    await tap(t, 'Weight');
    final field = find.byType(TextField).last;
    await t.enterText(field, '900');
    await hideKeyboard(t);
    expect(t.widget<FilledButton>(find.widgetWithText(FilledButton, 'Save')).onPressed, isNull);
    await t.enterText(field, '66.7');
    await hideKeyboard(t);
    await tap(t, 'Save');
    expect(env.biometrics.readings.any((r) => r.primaryValue == 66.7), isTrue);
    await tap(t, 'Weight');
    await t.ensureVisible(find.byTooltip('Delete').first);
    await settle(t);
    await t.tap(find.byTooltip('Delete').first);
    await settle(t);
    await tap(t, 'Confirm');
    expect(env.biometrics.readings.any((r) => r.primaryValue == 66.7), isFalse);
  });

  testWidgets('JT-M400-01 report shows a score and seven-day forecasts; offline keeps stored results', (t) async {
    await boot(t);
    await tap(t, 'Tracking');
    await tap(t, 'Health Report');
    expect(find.text('Health Score'), findsWidgets);
    expect(env.ai.requests, contains('/analyse'));
    expect(env.ai.requests, contains('/forecast'));
    final context = t.element(find.text('Health Score').first);
    final vm = context.read<AnalysisViewModel>();
    expect(vm.analysis!.healthScore, 78);
    expect(vm.forecasts.values.every((f) => f.forecast?.points().length == 7), isTrue);
    env.ai.offline = true;
    await env.biometrics.insert(
      BiometricReading(
        readingId: 'offline-new-weight',
        accountId: env.accountId,
        metricType: MetricType.bodyWeight,
        primaryValue: 65.1,
        recordedAt: DateTime.now(),
      ),
    );
    await vm.loadAnalysis();
    await settle(t);
    expect(vm.analysis!.healthScore, 78);
    expect(vm.notice, isNotNull);
    expect(vm.forecasts[MetricType.bodyWeight]!.stale, isTrue);
  });

  testWidgets('JT-M600-01 health note opens and is marked read; health and meal reminders schedule', (t) async {
    await boot(t);
    await t.tap(find.byTooltip('Reminders, 1 unread'));
    await settle(t);
    await tap(t, 'Demo health note: review your blood pressure trend.');
    expect(find.text('Health note'), findsOneWidget);
    await tap(t, 'OK');
    expect((await env.notifications.unreadCount(env.accountId)).dataOrNull, 0);
    await tap(t, 'Remind me to log my health readings');
    await tap(t, 'Remind me at breakfast, lunch and dinner');
    expect(env.scheduler.scheduled.values.any((s) => s.contains('Log your health readings')), isTrue);
    expect(env.scheduler.scheduled.length, greaterThanOrEqualTo(4));
  });

  testWidgets('JT-M700-01 manual meal merges papaya, saves and reopens in history', (t) async {
    await boot(t);
    await tap(t, 'Diet');
    await tap(t, 'Log Meal');
    expect(find.text('Follow your diet plan'), findsOneWidget);
    await tap(t, 'Enter the food myself');
    await tap(t, 'Breakfast');
    await tap(t, 'Select or enter the food');
    await searchFood(t, 'papaya');
    final mealVm = t.element(find.byType(MealResultView)).read<MealLogViewModel>();
    expect(mealVm.draft!.items, hasLength(1), reason: 'The selected search food must reach the review draft.');
    await tap(t, 'Add another food');
    await searchFood(t, 'papaya');
    expect(find.text(env.foods.foods.firstWhere((f) => f.foodKey == 'betik').foodName), findsOneWidget);
    await tap(t, 'Save');
    final saved = env.meals.meals;
    expect(saved, hasLength(1));
    expect(saved.single.items, hasLength(1));
    expect(saved.single.items.single.portionSizeG, 300);
    await tap(t, 'History');
    expect(find.textContaining('Breakfast'), findsWidgets);
  });

  testWidgets('JT-M700-02 gallery fixture passes recognition into editable meal review', (t) async {
    await boot(t);
    await tap(t, 'Diet');
    await tap(t, 'Log Meal');
    await tap(t, 'Choose from gallery');
    expect(env.ai.requests, contains('/recognise'));
    expect(find.text('Your meal'), findsOneWidget);
    expect(find.text('Follow your diet plan'), findsOneWidget);
    expect(find.textContaining(RegExp(r'95%\s+confidence')), findsWidgets);
    await tap(t, 'Save');
    expect(env.meals.meals, hasLength(1));
  });

  testWidgets('JT-M700-03 adequate daily and weekly plans show food info without redirecting', (t) async {
    await boot(t);
    await tap(t, 'Diet');
    await tap(t, "Today's Plan");
    final dailyContext = t.element(find.byType(DietPlanView));
    final dailyVm = dailyContext.read<DietPlanViewModel>();
    expect(dailyVm.plan, isNotNull);
    final day = DateTime.now();
    expect(dailyVm.nutritionWarnings(day), isEmpty);
    await t.pageBack();
    await settle(t);
    await tap(t, 'Weekly Plan');
    final context = t.element(find.byType(DietPlanView));
    final vm = context.read<DietPlanViewModel>();
    expect(vm.plan!.days(), hasLength(7));
    final firstRow = find.byKey(ValueKey('saved-food-${vm.plan!.mealsFor(vm.plan!.days().first).first.plannedMealId}'));
    await t.scrollUntilVisible(
      firstRow,
      300,
      scrollable: find.descendant(of: find.byType(DietPlanView), matching: find.byType(Scrollable)).first,
    );
    await settle(t);
    await t.tap(firstRow);
    await settle(t);
    expect(find.text('Why this food'), findsOneWidget);
    expect(vm.type, PlanType.weekly);
    expect(find.byType(DietPlanView), findsOneWidget);
  });

  testWidgets('JT-M700-04 inadequate AI reply is retried and cannot overwrite the saved plan', (t) async {
    await boot(t);
    await tap(t, 'Diet');
    await tap(t, "Today's Plan");
    final vm = t.element(find.byType(DietPlanView)).read<DietPlanViewModel>();
    final before = vm.plan!.dietPlanId;
    final calls = env.ai.requests.where((p) => p == '/plan').length;
    env.ai.underfilled = true;
    await vm.regenerate();
    await settle(t);
    expect(env.ai.requests.where((p) => p == '/plan').length, calls + 3);
    expect((await env.meals.planFor(env.accountId, PlanType.daily, DateTime.now())).dataOrNull!.dietPlanId, before);
    expect(find.textContaining('No new plan was saved'), findsWidgets);
  });

  testWidgets('JT-M600-02 a high health alert requires acknowledgement and is stored once', (t) async {
    await boot(t);
    env.ai.highAlert = true;
    await tap(t, 'Tracking');
    await tap(t, 'Health Report');
    expect(find.textContaining(RegExp(r'High severity health\s+alert')), findsOneWidget);
    await tap(t, 'I understand');
    expect(
      (await env.notifications.getLog(
        env.accountId,
        DateTime.now().subtract(const Duration(days: 1)),
        DateTime.now(),
      )).dataOrNull!.where((n) => n.severity == Severity.high),
      hasLength(1),
    );
    final vm = t.element(find.text('Health Score').first).read<AnalysisViewModel>();
    await vm.loadAnalysis();
    await settle(t);
    expect(
      (await env.notifications.getLog(
        env.accountId,
        DateTime.now().subtract(const Duration(days: 1)),
        DateTime.now(),
      )).dataOrNull!.where((n) => n.severity == Severity.high),
      hasLength(1),
    );
  });

  testWidgets('JT-M700-05 manual builder merges repeats and permits saving warned choices', (t) async {
    await boot(t);
    await tap(t, 'Diet');
    await tap(t, "Today's Plan");
    await tap(t, 'Build my plan myself');
    for (var i = 0; i < 2; i++) {
      await tap(t, 'Add food to breakfast');
      await searchFood(t, 'papaya');
      await tap(t, 'Add to draft');
    }
    final papaya = find.byWidgetPredicate((w) => w is PlanFoodRow && w.meal.food.foodKey == 'betik');
    expect(papaya, findsOneWidget);
    expect(t.widget<PlanFoodRow>(papaya).meal.portionSizeG, 300);
    await tap(t, 'Add food to breakfast');
    await searchFood(t, 'nasi lemak');
    await tap(t, 'Add to draft');
    expect(find.text('Review this choice'), findsWidgets);
    await tap(t, 'Save plan');
    await tap(t, 'Save plan');
    final stored = (await env.meals.planFor(env.accountId, PlanType.daily, DateTime.now())).dataOrNull!;
    expect(stored.meals.where((m) => m.food.foodKey == 'betik' && m.mealSlot == MealSlot.breakfast), hasLength(1));
    expect(stored.meals.any((m) => m.food.foodKey == 'nasi_lemak'), isTrue);
  });

  testWidgets('JT-M200-02 Health Connect imports once and rejects duplicates', (t) async {
    await boot(t);
    final existing = env.biometrics.readings.first;
    env.health.records.addAll([
      HealthRecord('BLOOD_PRESSURE', existing.primaryValue, existing.recordedAt, secondary: existing.secondaryValue),
      HealthRecord('BODY_WEIGHT', 66.2, DateTime.now().subtract(const Duration(hours: 1))),
    ]);
    final before = env.biometrics.readings.length;
    await tap(t, 'Tracking');
    await tap(t, 'Connect');
    expect(env.health.granted, isTrue);
    expect(env.biometrics.readings.length, before + 1);
    await t.tap(find.byTooltip('Check Health Connect now'));
    await settle(t);
    expect(env.biometrics.readings.length, before + 1);
    expect(find.text('Health Connect: connected'), findsOneWidget);
  });

  testWidgets('JT-M100-03 server address validation and readiness stay local to the test transport', (t) async {
    await boot(t);
    await tap(t, 'Profile');
    await tap(t, 'AI server');
    expect(find.text('Connected'), findsOneWidget);
    await t.enterText(find.byType(TextField).last, 'not a server');
    await hideKeyboard(t);
    await tap(t, 'Test connection');
    expect(find.text('Connected'), findsNothing);
    await t.enterText(find.byType(TextField).last, 'http://isolated.test');
    await hideKeyboard(t);
    await tap(t, 'Test connection');
    expect(find.text('Connected'), findsOneWidget);
    expect(env.ai.requests, contains('/health'));
  });

  testWidgets('JT-M400-02 declared condition risk shows its three contributing factors', (t) async {
    await boot(t);
    final old = (await env.profiles.getProfile(env.accountId)).dataOrNull!;
    final profile = old.copyWith(
      conditions: [LookupSeed.conditions.firstWhere((c) => c.conditionCode == 'HYPERTENSION')],
    );
    await env.profiles.saveProfile(profile, profile.generateSafetyLimit());
    await tap(t, 'Tracking');
    await tap(t, 'Health Report');
    final vm = t.element(find.text('Health Score').first).read<AnalysisViewModel>();
    expect(vm.analysis!.riskFor('HYPERTENSION'), 'Moderate');
    await t.scrollUntilVisible(find.text('Hypertension'), 300, scrollable: find.byType(Scrollable).first);
    expect(find.text('Moderate risk'), findsOneWidget);
    expect(find.textContaining('Blood pressure history'), findsOneWidget);
  });

  testWidgets('JT-M100-04 accepting profile refresh saves a plan under the updated profile', (t) async {
    await boot(t);
    await tap(t, 'Profile');
    await tap(t, 'Edit');
    await t.enterText(find.byType(TextFormField).first, '61');
    await hideKeyboard(t);
    await tap(t, 'Save');
    await tap(t, 'Update plans');
    final profile = (await env.profiles.getProfile(env.accountId)).dataOrNull!;
    final plan = (await env.meals.planFor(env.accountId, PlanType.daily, DateTime.now())).dataOrNull;
    expect(profile.age, 61);
    expect(plan, isNotNull);
    expect(
      plan!.safetyLimitId,
      (await env.profiles.getCurrentSafetyLimit(profile.profileId)).dataOrNull!.safetyLimitId,
    );
  });
}
