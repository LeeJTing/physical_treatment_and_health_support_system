import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/meal_log.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/meal_repository/fake_meal_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/result.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/diet_insights_view_model/diet_insights_view_model.dart';
import '../integration_test/scenarios/diet_features.dart';

class _PausedMeals extends FakeMealRepository {
  final pending = Completer<Result<List<MealLog>>>();
  @override
  Future<Result<List<MealLog>>> findMeals(
    String accountId,
    DateTime from,
    DateTime to,
  ) => pending.future;
}

void main() {
  test(
    'a result arriving after sign out never displays the previous account records',
    () async {
      final f = DietFeatureFixture();
      await f.initialise(populated: false);
      final meals = _PausedMeals();
      final vm = DietInsightsViewModel(meals, f.readings, f.auth, f.risk);
      final work = vm.load();
      await Future<void>.delayed(Duration.zero);
      await f.auth.signOut();
      meals.pending.complete(const Success([]));
      await work;
      expect(vm.insights, isNull);
      expect(vm.errorMessage, contains('session changed'));
      expect(vm.isLoading, isFalse);
    },
  );
  test(
    'fundamental meal-data failure clears the old review and presents retry state',
    () async {
      final f = DietFeatureFixture();
      await f.initialise(populated: false);
      final meals = _PausedMeals();
      final vm = DietInsightsViewModel(meals, f.readings, f.auth, f.risk);
      final work = vm.load();
      meals.pending.complete(
        const Failure('Meal records unavailable', code: 'offline'),
      );
      await work;
      expect(vm.insights, isNull);
      expect(vm.errorMessage, 'Meal records unavailable');
      expect(vm.isLoading, isFalse);
    },
  );
  test(
    'future navigation cannot cancel the loading request for the selected week',
    () async {
      final f = DietFeatureFixture();
      await f.initialise(populated: false);
      final meals = _PausedMeals();
      final now = DateTime(2026, 11, 10);
      final vm = DietInsightsViewModel(
        meals,
        f.readings,
        f.auth,
        f.risk,
        now: () => now,
      );
      final work = vm.load();
      await vm.load(week: now.add(const Duration(days: 14)));
      meals.pending.complete(const Success([]));
      await work;
      expect(vm.isLoading, isFalse);
      expect(vm.insights, isNotNull);
      expect(vm.selectedWeek, DateTime(2026, 11, 9));
    },
  );
}
