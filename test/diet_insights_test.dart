import 'package:flutter_test/flutter_test.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/diet_insights_service/diet_insights_service.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/suitability_service/suitability_service.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/biometric_reading.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/food_item.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/food_recognition_details.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/meal_log.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/safety_limit.dart';

final _food = FoodItem.fromJson({
  'food_id': 'f',
  'food_key': 'rice',
  'food_name': 'Rice',
  'food_category': 'Rice',
  'base_serving_g': 100,
  'energy_kcal_per_100g': 100,
  'carb_g_per_100g': 20,
  'protein_g_per_100g': 4,
  'sodium_mg_per_100g': 200,
});
MealLog _meal(
  String id,
  DateTime at, {
  double grams = 100,
  String account = 'a',
  MealSlot slot = MealSlot.lunch,
}) => MealLog(
  mealId: id,
  accountId: account,
  mealType: slot,
  entryMethod: EntryMethod.manual,
  consumedAt: at,
  items: [MealItem.of(_food, grams: grams)],
);
BiometricReading _reading(
  String id,
  DateTime at,
  double value, {
  MeasurementContext context = MeasurementContext.postMeal,
  String account = 'a',
}) => BiometricReading(
  readingId: id,
  accountId: account,
  metricType: MetricType.bloodGlucose,
  primaryValue: value,
  recordedAt: at,
  measurementContext: context,
);
void main() {
  const service = DietInsightsService();
  final now = DateTime(2026, 11, 10, 22);
  final ctx = DietContext(limit: SafetyLimit.mostRestrictive());
  test(
    'missing days are not zero intake; future, duplicate and other-account meals excluded',
    () {
      final m = _meal('m', DateTime(2026, 11, 9, 12));
      final result = service.build(
        accountId: 'a',
        weekStart: now,
        now: now,
        context: ctx,
        readings: [],
        meals: [
          m,
          m,
          _meal('other', DateTime(2026, 11, 9, 12), account: 'b'),
          _meal('future', DateTime(2026, 11, 11, 12)),
        ],
      );
      expect(result.week.loggedDays, 1);
      expect(result.week.elapsedDays, 2);
      expect(result.week.nutrients.first.average, 100);
      expect(result.week.days.last.future, true);
      expect(result.week.days.first.mainMeals, 1);
      expect(result.week.contributors['sodium_mg']!.single.amount, 200);
    },
  );
  test('empty week has no log denominator and withholds both associations', () {
    final r = service.build(
      accountId: 'a',
      weekStart: now,
      now: now,
      context: ctx,
      readings: [],
      meals: [],
    );
    expect(r.week.loggedDays, 0);
    expect(r.week.nutrients.every((n) => n.average == 0), true);
    expect(r.patterns.every((p) => !p.available), true);
    expect(r.week.dueSlots, 0);
  });
  test('Spearman uses average tie ranks and withholds constant input', () {
    expect(
      DietInsightsService.spearman([1, 2, 3, 4], [4, 3, 2, 1]),
      closeTo(-1, 1e-9),
    );
    expect(
      DietInsightsService.spearman([1, 1, 3, 4], [1, 2, 3, 4]),
      closeTo(.948683298, 1e-8),
    );
    expect(DietInsightsService.spearman([1, 1, 1], [1, 2, 3]), isNull);
    expect(DietInsightsService.spearman([1, double.nan], [2, 3]), isNull);
  });
  test(
    'timed after-meal readings produce an exploratory association after minimum coverage',
    () {
      final meals = <MealLog>[], rs = <BiometricReading>[];
      for (var i = 0; i < 14; i++) {
        final at = DateTime(2026, 10, 22 + i, 12);
        meals.add(_meal('m$i', at, grams: 100 + i * 20));
        rs.add(_reading('r$i', at.add(const Duration(hours: 2)), 5 + i * .2));
      }
      final p = service
          .build(
            accountId: 'a',
            weekStart: now,
            now: now,
            context: ctx,
            readings: rs,
            meals: meals,
          )
          .patterns
          .first;
      expect(p.points.length, 14);
      expect(p.distinctDays, 14);
      expect(p.correlation, closeTo(1, 1e-9));
    },
  );
  test(
    'fasting, late and intervening-food pairs are refused; duplicate reading is counted once',
    () {
      final at = DateTime(2026, 11, 9, 12);
      final r = _reading('r', at.add(const Duration(hours: 2)), 6);
      final meals = [
        _meal('m', at),
        _meal(
          'snack',
          at.add(const Duration(minutes: 70)),
          slot: MealSlot.snack,
        ),
      ];
      final p = service
          .build(
            accountId: 'a',
            weekStart: now,
            now: now,
            context: ctx,
            readings: [
              r,
              r,
              _reading(
                'fast',
                at.add(const Duration(minutes: 100)),
                6,
                context: MeasurementContext.fasting,
              ),
              _reading('late', at.add(const Duration(minutes: 151)), 7),
            ],
            meals: meals,
          )
          .patterns
          .first;
      expect(p.points, isEmpty);
      final p2 = service
          .build(
            accountId: 'a',
            weekStart: now,
            now: now,
            context: ctx,
            readings: [r, r],
            meals: [_meal('m', at)],
          )
          .patterns
          .first;
      expect(p2.points.length, 1);
      expect(p2.available, false);
    },
  );
  test(
    'pressure pairs require all three main meal slots and a next-morning reading',
    () {
      final meals = <MealLog>[], rs = <BiometricReading>[];
      for (var i = 0; i < 14; i++) {
        for (final slot in [
          MealSlot.breakfast,
          MealSlot.lunch,
          MealSlot.dinner,
        ]) {
          meals.add(
            _meal(
              '$i-${slot.name}',
              DateTime(
                2026,
                10,
                22 + i,
                slot == MealSlot.breakfast
                    ? 8
                    : slot == MealSlot.lunch
                    ? 12
                    : 19,
              ),
              slot: slot,
              grams: 100 + i * 10,
            ),
          );
        }
        rs.add(
          BiometricReading(
            readingId: 'bp$i',
            accountId: 'a',
            metricType: MetricType.bloodPressure,
            primaryValue: 110 + i.toDouble(),
            secondaryValue: 75,
            recordedAt: DateTime(2026, 10, 23 + i, 7),
          ),
        );
      }
      final result = service.build(
        accountId: 'a',
        weekStart: now,
        now: now,
        context: ctx,
        readings: rs,
        meals: meals,
      );
      expect(result.patterns.last.correlation, closeTo(1, 1e-9));
      final incomplete = service.build(
        accountId: 'a',
        weekStart: now,
        now: now,
        context: ctx,
        readings: rs,
        meals: meals.where((m) => m.mealType != MealSlot.dinner).toList(),
      );
      expect(incomplete.patterns.last.points, isEmpty);
    },
  );
  test(
    'readings failure is explicit even when sufficient pairs were previously available',
    () {
      final r = service.build(
        accountId: 'a',
        weekStart: now,
        now: now,
        context: ctx,
        readings: [],
        meals: [],
        readingError: 'Readings unavailable',
      );
      expect(r.patterns.first.withheldReason, 'Readings unavailable');
    },
  );
  test(
    'recognition metadata survives storage and scaling; manual duplicate merge clears an obsolete count',
    () {
      final item = MealItem.of(
        _food,
        recognitionDetails: const FoodRecognitionDetails(
          count: 2,
          unit: 'piece',
          modelEstimate: true,
        ),
      );
      final stored = MealItem.fromJson(item.toJson(), _food);
      expect(stored.recognitionDetails!.count, 2);
      expect(stored.scaleTo(150).recognitionDetails!.unitWeightG, 75);
      final combined = MealItem.mergeDuplicates([
        item,
        MealItem.of(_food),
      ]).single;
      expect(combined.portionSizeG, 200);
      expect(combined.recognitionDetails, isNull);
    },
  );
  test(
    'invalid photo regions and non-integer counts cannot become display metadata',
    () {
      final details = FoodRecognitionDetails.fromJson({
        'count': 2.5,
        'boxes': [
          [0, 0, 2, 1],
          [.5, .5, .1, .1],
          [0, 0, 1, 1],
        ],
      });
      expect(details.count, isNull);
      expect(details.boxes.length, 1);
    },
  );
}
