import 'package:physical_treatment_and_health_support_system/model/business_logic/diet_insights_service/diet_insights_service.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/risk_assessment_service/risk_assessment_service.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/suitability_service/suitability_service.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/biometric_reading.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/diet_insights.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/diet_plan.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/health_profile.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/meal_log.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/safety_limit.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/auth_repository/i_auth_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/biometric_repository/i_biometric_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/meal_repository/i_meal_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/result.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/base_view_model.dart';

class DietInsightsViewModel extends BaseViewModel {
  final IMealRepository _meals;
  final IBiometricRepository _readings;
  final IAuthRepository _auth;
  final RiskAssessmentService _risk;
  final DateTime Function() _now;
  final DietInsightsService _service;
  int _generation = 0;
  late DateTime selectedWeek;
  DietInsights? insights;
  List<String> notices = const [];
  DietInsightsViewModel(
    this._meals,
    this._readings,
    this._auth,
    this._risk, {
    DateTime Function()? now,
    this._service = const DietInsightsService(),
  }) : _now = now ?? DateTime.now {
    selectedWeek = DietInsightsService.monday(_now());
  }

  bool get canGoForward =>
      selectedWeek.isBefore(DietInsightsService.monday(_now()));
  Future<void> previousWeek() => load(
    week: DateTime(selectedWeek.year, selectedWeek.month, selectedWeek.day - 7),
  );
  Future<void> nextWeek() async {
    if (canGoForward) {
      await load(
        week: DateTime(
          selectedWeek.year,
          selectedWeek.month,
          selectedWeek.day + 7,
        ),
      );
    }
  }

  Future<void> load({DateTime? week}) async {
    final now = _now();
    final selected = DietInsightsService.monday(week ?? selectedWeek);
    if (selected.isAfter(DietInsightsService.monday(now))) return;
    final request = ++_generation;
    selectedWeek = selected;
    insights = null;
    notices = const [];
    setError(null);
    setLoading(true);
    try {
      final account = (await _auth.currentAccount()).dataOrNull;
      if (account == null) {
        if (request == _generation) {
          setError('Sign in again to view your diet review.');
        }
        return;
      }
      final weekEnd = DateTime(
        selected.year,
        selected.month,
        selected.day + 7,
      ).subtract(const Duration(microseconds: 1));
      final end = now.isBefore(weekEnd) ? now : weekEnd;
      final from = DateTime(end.year, end.month, end.day - 27);
      final jobs = [
        for (var i = 0; i < 7; i++)
          for (final type in [PlanType.daily, PlanType.weekly])
            (
              date: DateTime(selected.year, selected.month, selected.day + i),
              type: type,
            ),
      ];
      final results = await Future.wait<Object>([
        _meals.findMeals(account.accountId, from, end),
        _readings.findBetween(account.accountId, from, end),
        _risk.retrieve(),
        for (final job in jobs)
          _meals.planFor(account.accountId, job.type, job.date),
      ]);
      if (isDisposed || request != _generation) return;
      // A response started for a previous session must never be displayed after an account change.
      final current = (await _auth.currentAccount()).dataOrNull;
      if (isDisposed || request != _generation) return;
      if (current?.accountId != account.accountId) {
        setError('Your session changed. Open the review again.');
        return;
      }
      final meals = results[0] as Result<List<MealLog>>;
      if (meals case Failure(:final message)) {
        setError(message);
        return;
      }
      final readings = results[1] as Result<List<BiometricReading>>;
      final profile = results[2] as Result<ProfileSnapshot>;
      final context = profile.dataOrNull == null
          ? DietContext(limit: SafetyLimit.mostRestrictive(), failSafe: true)
          : DietContext.from(profile.dataOrNull!);
      final plans = <DateTime, DietPlan>{};
      var plansAvailable = true;
      for (var i = 0; i < jobs.length; i += 2) {
        final daily = results[i + 3] as Result<DietPlan?>,
            weekly = results[i + 4] as Result<DietPlan?>;
        if (daily is Failure || weekly is Failure) plansAvailable = false;
        final p = daily.dataOrNull ?? weekly.dataOrNull;
        if (p != null) plans[jobs[i].date] = p;
      }
      notices = [
        'Only recorded meals are included. No log does not mean no food was eaten; days with fewer than three main meals may be incomplete.',
        'Targets use your current profile and may differ from your targets when older meals were logged.',
        if (context.failSafe)
          'Your profile could not be fully loaded. Conservative default targets are shown.',
        if (!plansAvailable)
          'Some saved plans could not be loaded. Plan matching is unavailable; meal totals are still shown.',
        if (readings is Failure)
          'Health readings could not be loaded. The weekly nutrition review is still available.',
      ];
      insights = _service.build(
        accountId: account.accountId,
        weekStart: selected,
        now: now,
        meals: meals.dataOrNull!,
        readings: readings.dataOrNull ?? const [],
        context: context,
        plans: plans,
        plansAvailable: plansAvailable,
        readingError: readings is Failure
            ? 'Readings unavailable. Retry when your connection is restored.'
            : null,
      );
    } catch (_) {
      if (!isDisposed && request == _generation) {
        setError('Unable to load your diet review. Please try again.');
      }
    } finally {
      if (!isDisposed && request == _generation) setLoading(false);
    }
  }
}
