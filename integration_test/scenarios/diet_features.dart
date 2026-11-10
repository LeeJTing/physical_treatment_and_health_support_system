// Shared by host widget tests and the isolated Android integration target.
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:physical_treatment_and_health_support_system/device_platform/camera_gallery/meal_image_picker.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/food_recognition_service/food_recognition_service.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/risk_assessment_service/risk_assessment_service.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/biometric_reading.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/food_item.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/food_recognition_details.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/meal_log.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/auth_repository/fake_auth_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/biometric_repository/fake_biometric_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/food_repository/fake_food_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/meal_repository/fake_meal_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/profile_repository/fake_profile_repository.dart';
import 'package:physical_treatment_and_health_support_system/shared_client/api_client/api_client.dart';
import 'package:physical_treatment_and_health_support_system/view/diet_view/diet_insights_view.dart';
import 'package:physical_treatment_and_health_support_system/view/diet_view/meal_quantity_dialog.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/diet_insights_view_model/diet_insights_view_model.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/meal_log_view_model/meal_log_view_model.dart';

class _NoPhoto implements MealImageSource {
  @override
  Future<Uint8List?> capture() async => null;
  @override
  Future<Uint8List?> pickFromGallery() async => null;
}

final fixtureFood = FoodItem.fromJson({
  'food_id': 'fixture-rice',
  'food_key': 'rice',
  'food_name': 'Rice (test fixture)',
  'food_category': 'Rice',
  'base_serving_g': 100,
  'energy_kcal_per_100g': 130,
  'carb_g_per_100g': 28,
  'sodium_mg_per_100g': 150,
  'protein_g_per_100g': 3,
});
final _now = DateTime(2026, 11, 10, 22);

class DietFeatureFixture {
  final auth = FakeAuthRepository();
  final meals = FakeMealRepository();
  final readings = FakeBiometricRepository();
  final profiles = FakeProfileRepository();
  late final RiskAssessmentService risk = RiskAssessmentService(auth, profiles);
  late final DietInsightsViewModel vm = DietInsightsViewModel(
    meals,
    readings,
    auth,
    risk,
    now: () => _now,
  );
  late String account;
  Future<void> initialise({bool populated = true}) async {
    account = (await auth.login(
      'demo@apths.test',
      'password123',
    )).dataOrNull!.accountId;
    if (!populated) return;
    for (var d = 0; d < 14; d++) {
      final date = DateTime(2026, 10, 27 + d);
      for (final (slot, hour) in [
        (MealSlot.breakfast, 8),
        (MealSlot.lunch, 12),
        (MealSlot.dinner, 19),
      ]) {
        meals.meals.add(
          MealLog(
            mealId: '$d-${slot.name}',
            accountId: account,
            mealType: slot,
            entryMethod: EntryMethod.manual,
            consumedAt: DateTime(date.year, date.month, date.day, hour),
            items: [MealItem.of(fixtureFood, grams: 100 + d * 10)],
          ),
        );
      }
      readings.readings.add(
        BiometricReading(
          readingId: 'g$d',
          accountId: account,
          metricType: MetricType.bloodGlucose,
          primaryValue: 5 + d * .1,
          measurementContext: MeasurementContext.postMeal,
          recordedAt: DateTime(date.year, date.month, date.day, 14),
        ),
      );
      readings.readings.add(
        BiometricReading(
          readingId: 'p$d',
          accountId: account,
          metricType: MetricType.bloodPressure,
          primaryValue: 115 + d.toDouble(),
          secondaryValue: 75,
          recordedAt: DateTime(date.year, date.month, date.day + 1, 7),
        ),
      );
    }
    await vm.load();
  }
}

void runDietFeatureTests({
  Future<void> Function(WidgetTester, String)? capture,
}) {
  void hostSize(WidgetTester t) {
    if (t.binding is AutomatedTestWidgetsFlutterBinding) {
      t.view.physicalSize = const Size(430, 932);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
    }
  }

  Future<void> showReview(
    WidgetTester t,
    DietFeatureFixture f, {
    double scale = 1,
  }) async {
    await t.pumpWidget(
      ChangeNotifierProvider.value(
        value: f.vm,
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: RepaintBoundary(
              key: const ValueKey('diet-evidence'),
              child: child!,
            ),
          ),
          home: const DietInsightsView(),
        ),
      ),
    );
    await t.pumpAndSettle();
  }

  testWidgets(
    'ACD-C01 recorded week and nutrient contributors render with missing-day guidance',
    (t) async {
      hostSize(t);
      final f = DietFeatureFixture();
      await f.initialise();
      await showReview(t, f);
      expect(find.text('Your recorded week'), findsOneWidget);
      expect(find.textContaining('1 of 2 elapsed days'), findsOneWidget);
      expect(f.vm.insights!.week.loggedDays, 1);
      expect(t.takeException(), isNull);
      await capture?.call(t, 'C01-weekly-review');
      await t.scrollUntilVisible(
        find.text('Foods contributing most'),
        450,
        scrollable: find.byType(Scrollable).last,
      );
      await t.pumpAndSettle();
      expect(find.textContaining('Rice (test fixture)'), findsWidgets);
      await capture?.call(t, 'C02-food-contributors');
    },
  );

  testWidgets(
    'ACD-D01 timed pairs render scatter plots and methods at larger text size',
    (t) async {
      hostSize(t);
      final f = DietFeatureFixture();
      await f.initialise();
      await showReview(t, f, scale: 1.3);
      await t.tap(find.text('Meal & readings'));
      await t.pumpAndSettle();
      expect(find.text('Patterns in your records'), findsOneWidget);
      expect(find.textContaining('not proof'), findsOneWidget);
      expect(f.vm.insights!.patterns.every((p) => p.available), isTrue);
      expect(find.textContaining('(Spearman)'), findsWidgets);
      expect(t.takeException(), isNull);
      await capture?.call(t, 'D01-meal-reading-pattern');
    },
  );

  testWidgets(
    'ACD-D02 empty and failed readings withhold associations without inventing intake',
    (t) async {
      hostSize(t);
      final f = DietFeatureFixture();
      await f.initialise(populated: false);
      await f.vm.load();
      await showReview(t, f);
      expect(f.vm.insights!.week.loggedDays, 0);
      await t.tap(find.text('Meal & readings'));
      await t.pumpAndSettle();
      expect(find.textContaining('0 paired records'), findsWidgets);
      expect(f.vm.insights!.patterns.every((p) => !p.available), isTrue);
      await capture?.call(t, 'D02-insufficient-records');
      f.readings.failNext = true;
      await f.vm.load();
      await t.pumpAndSettle();
      expect(find.textContaining('Readings unavailable'), findsWidgets);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'ACD-A01 quantity review validates, recalculates and persists confirmed counts',
    (t) async {
      hostSize(t);
      final f = DietFeatureFixture();
      await f.initialise(populated: false);
      final egg = FoodItem.fromJson({
        'food_id': 'egg',
        'food_key': 'telur_rebus',
        'food_name': 'Boiled egg',
        'food_category': 'Protein',
        'base_serving_g': 50,
        'energy_kcal_per_100g': 143,
      });
      final foods = FakeFoodRepository([egg]);
      final vm = MealLogViewModel(
        f.meals,
        FoodRecognitionService(
          ApiClient(
            baseUrl: 'http://isolated.test',
            tokenProvider: () => null,
            httpClient: MockClient((_) async => http.Response('{}', 503)),
          ),
          foods,
        ),
        foods,
        f.risk,
        f.auth,
        _NoPhoto(),
      );
      await vm.load();
      vm.startManual();
      vm.addFood(egg, grams: 100);
      final item = vm.draft!.items.single.withRecognitionDetails(
        const FoodRecognitionDetails(
          count: 2,
          unit: 'whole',
          modelEstimate: true,
        ),
      );
      vm.draft = vm.draft!.copyWith(items: [item]);
      expect(vm.confirmQuantity(item, 0, 150), isNotNull);
      expect(vm.confirmQuantity(item, 3, double.nan), isNotNull);
      await t.pumpWidget(
        MaterialApp(
          builder: (_, child) => RepaintBoundary(
            key: const ValueKey('diet-evidence'),
            child: child!,
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => MealQuantityDialog.show(context, vm, item),
                  child: const Text('Review quantity'),
                ),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('Review quantity'));
      await t.pumpAndSettle();
      await capture?.call(t, 'A01-quantity-review');
      await t.enterText(find.byType(TextFormField).first, '3');
      await t.pump();
      expect(
        (t.widget<TextFormField>(
          find.byType(TextFormField).last,
        )).controller!.text,
        '150',
      );
      await t.tap(find.text('Confirm quantity'));
      await t.pumpAndSettle();
      final reviewed = vm.draft!.items.single;
      expect(reviewed.portionSizeG, 150);
      expect(reviewed.recognitionDetails!.count, 3);
      expect(reviewed.recognitionDetails!.confirmed, isTrue);
      expect(reviewed.energyKcal, closeTo(214.5, 0.01));
      expect(await vm.confirmMeal(), isTrue);
      expect(f.meals.meals.single.items.single.recognitionDetails!.count, 3);
      expect(t.takeException(), isNull);
    },
  );
}
