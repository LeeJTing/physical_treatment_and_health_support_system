import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:physical_treatment_and_health_support_system/model/business_logic/diet_planner_service/diet_planner_service.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/risk_assessment_service/risk_assessment_service.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/diet_plan.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/food_item.dart';
import 'package:physical_treatment_and_health_support_system/core/themes/design_tokens.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/auth_repository/fake_auth_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/food_repository/fake_food_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/meal_repository/fake_meal_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/profile_repository/fake_profile_repository.dart';
import 'package:physical_treatment_and_health_support_system/shared_client/api_client/api_client.dart';
import 'package:physical_treatment_and_health_support_system/view/diet_view/manual_diet_plan_view.dart';
import 'package:physical_treatment_and_health_support_system/view/diet_view/diet_plan_view.dart';
import 'package:physical_treatment_and_health_support_system/view/diet_view/food_search_sheet.dart';
import 'package:physical_treatment_and_health_support_system/view/diet_view/widgets/plan_cards.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/diet_plan_view_model/diet_plan_view_model.dart';

void main() {
  final foods = FakeFoodRepository.fromJson(File('assets/seed/food_catalogue.json').readAsStringSync());
  late FakeMealRepository repo;
  late DietPlanViewModel vm;
  final snapshots = Platform.environment['PLAN_UI_SNAPSHOTS'] != null;
  setUpAll(() async {
    if (!snapshots) return;
    TestWidgetsFlutterBinding.ensureInitialized();
    for (final font in [
      ('QaFont', r'C:\Windows\Fonts\segoeui.ttf'),
      ('MaterialIcons', r'C:\flutter\bin\cache\artifacts\material_fonts\MaterialIcons-Regular.otf'),
    ]) {
      final loader = FontLoader(font.$1)..addFont(File(font.$2).readAsBytes().then(ByteData.sublistView));
      await loader.load();
    }
  });
  const captureKey = ValueKey('plan-ui-capture');
  Future<void> capture(WidgetTester tester, String name) async {
    final folder = Platform.environment['PLAN_UI_SNAPSHOTS'];
    if (folder == null) return;
    final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(captureKey));
    await tester.runAsync(() async {
      final picture = await boundary.toImage(pixelRatio: 2);
      final data = await picture.toByteData(format: ui.ImageByteFormat.png);
      await File('$folder/$name.png').writeAsBytes(data!.buffer.asUint8List());
      picture.dispose();
    });
  }

  setUp(() async {
    final auth = FakeAuthRepository();
    await auth.login('demo@apths.test', 'password123');
    repo = FakeMealRepository();
    vm = DietPlanViewModel(
      DietPlannerService(
        ApiClient(
          baseUrl: 'http://ai',
          tokenProvider: () => 't',
          httpClient: MockClient((_) async => http.Response('{"error":{"code":"offline","message":"down"}}', 503)),
        ),
        foods,
      ),
      repo,
      foods,
      RiskAssessmentService(auth, FakeProfileRepository()),
      auth,
    );
    await vm.load(PlanType.daily);
    await vm.saveManualPlan({
      MealSlot.breakfast: [foods.foods.firstWhere((f) => f.foodKey == 'oats')],
    });
  });

  Future<void> open(WidgetTester tester, {double scale = 1}) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: snapshots ? ThemeData(fontFamily: 'QaFont') : null,
        builder: (c, child) => RepaintBoundary(
          key: captureKey,
          child: MediaQuery(
            data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              child: const Text('Open builder'),
              onPressed: () =>
                  Navigator.push<void>(context, MaterialPageRoute(builder: (_) => ManualDietPlanView(viewModel: vm))),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open builder'));
    await tester.pumpAndSettle();
  }

  Future<void> resizeBreakfast(WidgetTester tester) async {
    await tester.scrollUntilVisible(find.text('Portion'), 200, scrollable: find.byType(Scrollable).first);
    await Scrollable.ensureVisible(tester.element(find.text('Portion').first), alignment: 0.5);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Portion').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('125 g'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Update draft'));
    await tester.pumpAndSettle();
  }

  testWidgets('a changed draft is visible at large phone text and Close can discard without changing the saved plan', (
    tester,
  ) async {
    await open(tester, scale: 1.3);
    await capture(tester, 'manual-overview-130');
    await resizeBreakfast(tester);
    expect(find.textContaining('125 g ·'), findsOneWidget);
    expect(repo.plans.single.meals.single.portionSizeG, 250);
    await tester.tap(find.byTooltip('Close plan builder'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Leave'), findsOneWidget);
    await tester.tap(find.text('Discard changes'));
    await tester.pumpAndSettle();
    expect(find.text('Open builder'), findsOneWidget);
    expect(repo.plans.single.meals.single.portionSizeG, 250);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the whole day is confirmed before a revised portion is saved', (tester) async {
    await open(tester);
    await resizeBreakfast(tester);
    await tester.tap(find.text('Save plan'));
    await tester.pumpAndSettle();
    expect(
      find.byWidgetPredicate((w) => w is Text && w.data?.replaceAll('\u00a0', ' ') == "Save today's plan?"),
      findsOneWidget,
    );
    expect(repo.plans, hasLength(1));
    await tester.tap(find.widgetWithText(FilledButton, 'Save plan').last);
    await tester.pumpAndSettle();
    expect(find.text('Open builder'), findsOneWidget);
    expect(repo.plans.last.meals.single.portionSizeG, 125);
    expect(tester.takeException(), isNull);
  });

  testWidgets('picking papaya twice displays one combined row in the draft', (tester) async {
    await open(tester);
    final papaya = foods.foods.firstWhere((f) => f.foodKey == 'betik');
    for (var pick = 0; pick < 2; pick++) {
      final add = find.text('Add food to snack');
      await tester.scrollUntilVisible(add, 200, scrollable: find.byType(Scrollable).first);
      await Scrollable.ensureVisible(tester.element(add), alignment: 0.5);
      await tester.pumpAndSettle();
      await tester.tap(add);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'papaya');
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: find.byType(FoodSearchSheet), matching: find.text(papaya.foodName)).first);
      await tester.pumpAndSettle();
      if (pick == 1) expect(find.textContaining('combined into one'), findsOneWidget);
      await tester.tap(find.text('Add to draft'));
      await tester.pumpAndSettle();
    }
    expect(find.text(papaya.foodName), findsOneWidget);
    expect(find.textContaining('${(papaya.baseServingG * 2).round()} g ·'), findsOneWidget);
    expect(repo.plans.single.meals.single.food.foodKey, 'oats'); // still a local draft
    expect(tester.takeException(), isNull);
  });

  testWidgets('food search and delayed suggestions show progress until their results arrive', (tester) async {
    final search = Completer<List<FoodItem>>();
    final suggestions = Completer<List<FoodItem>>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FoodSearchSheet(search: (_) => search.future, suggestedLater: suggestions.future),
        ),
      ),
    );
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    search.complete([]);
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.textContaining('No food found'), findsNothing);
    suggestions.complete([foods.foods.firstWhere((f) => f.foodKey == 'betik')]);
    await tester.pumpAndSettle();
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.text('Did you mean'), findsOneWidget);
    expect(find.textContaining('No food found'), findsNothing);
  });

  testWidgets('a conflicting draft food is red while Save stays enabled; correction clears the warning', (
    tester,
  ) async {
    final bad = foods.foods.firstWhere((f) => f.foodKey == 'nasi_lemak');
    await repo.updatePlan(vm.plan!.copyWith(meals: [PlannedMeal.of(bad, vm.plan!.startDate, MealSlot.breakfast, 250)]));
    await vm.load(PlanType.daily);
    await open(tester, scale: 1.3);
    await tester.scrollUntilVisible(find.text('Review this choice'), 200, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    final row = tester.widget<Container>(
      find.descendant(of: find.byType(PlanFoodRow), matching: find.byType(Container)).first,
    );
    expect((row.decoration! as BoxDecoration).color, AppTokens.dangerContainer);
    await capture(tester, 'manual-warning-130');
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Save plan')).onPressed, isNotNull);
    await resizeBreakfast(tester);
    expect(find.text('Review this choice'), findsNothing);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Save plan')).onPressed, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a warned manual draft can be confirmed and saved without correcting its food', (tester) async {
    final bad = foods.foods.firstWhere((f) => f.foodKey == 'nasi_lemak');
    await repo.updatePlan(vm.plan!.copyWith(meals: [PlannedMeal.of(bad, vm.plan!.startDate, MealSlot.breakfast, 250)]));
    await vm.load(PlanType.daily);
    await open(tester);
    await tester.tap(find.text('Save plan'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save plan').last);
    await tester.pumpAndSettle();
    expect(find.text('Open builder'), findsOneWidget);
    expect(repo.plans.last.meals.single.food.foodKey, 'nasi_lemak');
    expect(vm.savedFoodWarnings(vm.plan!.meals.single), isNotEmpty);
    expect(tester.takeException(), isNull);
  });

  for (final type in PlanType.values) {
    testWidgets('${type.name} saved plan uses the shared cards and red food warnings', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final original = vm.plan!;
      final bad = foods.foods.firstWhere((f) => f.foodKey == 'nasi_lemak');
      final rows = [PlannedMeal.of(bad, original.startDate, MealSlot.breakfast, 250)];
      if (type == PlanType.daily) {
        await repo.updatePlan(original.copyWith(meals: rows));
      } else {
        await repo.updatePlan(original.copyWith(meals: rows));
        await repo.savePlan(
          DietPlan(
            dietPlanId: 'week-ui',
            accountId: original.accountId,
            safetyLimitId: original.safetyLimitId,
            planType: type,
            startDate: original.startDate,
            endDate: original.startDate.add(const Duration(days: 6)),
            modelVersion: 'manual',
            generatedAt: DateTime.now(),
            meals: rows.map((m) => m.carriedOver()).toList(),
          ),
        );
      }
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: vm,
          child: MaterialApp(
            theme: snapshots ? ThemeData(fontFamily: 'QaFont') : null,
            builder: (c, child) => RepaintBoundary(key: captureKey, child: child!),
            home: DietPlanView(type: type),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.byType(PlanTotalsCard), 200, scrollable: find.byType(Scrollable).first);
      expect(find.byType(PlanTotalsCard), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Review this choice'), 200, scrollable: find.byType(Scrollable).first);
      await Scrollable.ensureVisible(tester.element(find.text('Review this choice')), alignment: 0.3);
      await tester.pumpAndSettle();
      expect(find.byType(PlanMealCard), findsWidgets);
      final row = tester.widget<Container>(
        find.descendant(of: find.byType(PlanFoodRow), matching: find.byType(Container)).first,
      );
      expect((row.decoration! as BoxDecoration).color, AppTokens.dangerContainer);
      await capture(tester, '${type.name}-warning');
      expect(tester.takeException(), isNull);
    });
  }
}
