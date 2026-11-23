import 'dart:typed_data';
import 'package:physical_treatment_and_health_support_system/core/utils/id_utils.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/health_insights_service/health_insights_service.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/health_insights_service/weekly_report_service.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/biometric_reading.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/diet_plan.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/health_insights.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/meal_log.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/patient_treatment_plan.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/recovery_check_in.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/auth_repository/i_auth_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/biometric_repository/i_biometric_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/meal_repository/i_meal_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/recovery_repository/i_recovery_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/treatment_repository/i_treatment_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/result.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/base_view_model.dart';

class HealthInsightsViewModel extends BaseViewModel {
  final IAuthRepository _auth;
  final IBiometricRepository _readings;
  final IMealRepository _meals;
  final ITreatmentRepository _treatments;
  final IRecoveryRepository _recovery;
  final DateTime Function() _now;
  int _request = 0;
  bool includeDemo = true, saving = false, exporting = false;
  late DateTime selectedWeek;
  HealthInsights? data;
  List<PatientTreatmentPlan> plans = const [];
  HealthInsightsViewModel(
    this._auth,
    this._readings,
    this._meals,
    this._treatments,
    this._recovery, {
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now {
    selectedWeek = HealthInsightsService.monday(_now());
  }
  DateTime get today => HealthInsightsService.day(_now());
  Future<void> setIncludeDemo(bool value) async {
    includeDemo = value;
    await load();
  }

  Future<void> load({DateTime? week}) async {
    final generation = ++_request;
    selectedWeek = HealthInsightsService.monday(week ?? selectedWeek);
    if (selectedWeek.isAfter(today)) {
      selectedWeek = HealthInsightsService.monday(today);
    }
    final selected = selectedWeek, now = _now(), include = includeDemo;
    data = null;
    plans = const [];
    setError(null);
    setLoading(true);
    try {
      final account = (await _auth.currentAccount()).dataOrNull;
      if (account == null) {
        if (generation == _request) {
          setError('Sign in again to view your health insights.');
        }
        return;
      }
      final id = account.accountId;
      final end = selected
          .add(const Duration(days: 7))
          .subtract(const Duration(microseconds: 1));
      final until = now.isBefore(end) ? now : end;
      final from = selected.subtract(const Duration(days: 7));
      final results = await Future.wait<Object>([
        _meals.findMeals(id, from, until),
        _readings.findBetween(
          id,
          until.subtract(const Duration(days: 120)),
          until,
        ),
        _meals.plansForPeriod(id, from, end),
        _treatments.getPlanHistory(id),
        _recovery.findBetween(
          id,
          selected.subtract(const Duration(days: 27)),
          until,
        ),
        _readings.healthSourceState(id),
      ]);
      if (isDisposed || generation != _request) return;
      final mealResult = results[0] as Result<List<MealLog>>;
      final readingResult = results[1] as Result<List<BiometricReading>>;
      final planResult = results[2] as Result<List<DietPlan>>;
      final treatmentResult = results[3] as Result<List<PatientTreatmentPlan>>;
      final recoveryResult = results[4] as Result<List<RecoveryCheckIn>>;
      final sourceResult =
          results[5] as Result<({bool connected, DateTime? lastSync})>;
      final notices = <String>[
        if (mealResult is Failure)
          'Meal history is unavailable. Nutrition and meal comparisons are incomplete.',
        if (readingResult is Failure)
          'Health readings are unavailable. Reading counts are unknown.',
        if (planResult is Failure)
          'Saved diet plans are unavailable. Plan matching is unavailable.',
        if (treatmentResult is Failure)
          'Treatment history is unavailable. Exercise totals are incomplete.',
        if (recoveryResult is Failure)
          'Recovery check-ins are unavailable. Retry before editing a previous entry.',
        if (sourceResult is Failure) 'Last sync status is unavailable.',
      ];
      final ownedPlans = (treatmentResult.dataOrNull ?? [])
          .where((p) => p.accountId == id)
          .toList();
      final sessionResults = await Future.wait(
        ownedPlans.map((p) => _treatments.getSessions(p.patientPlanId)),
      );
      final sessions = <ExerciseEvidence>[];
      for (var i = 0; i < ownedPlans.length; i++) {
        final result = sessionResults[i];
        if (result is Failure) {
          notices.add(
            'Some exercise history is unavailable. Activity totals are incomplete.',
          );
          continue;
        }
        final p = ownedPlans[i];
        for (final s in result.dataOrNull ?? []) {
          sessions.add(
            ExerciseEvidence(
              s,
              p.plan.planName,
              p.plan.exercises
                      .where((e) => e.exercise.exerciseId == s.exerciseId)
                      .firstOrNull
                      ?.exercise
                      .exerciseName ??
                  'Exercise',
            ),
          );
        }
      }
      final current = (await _auth.currentAccount()).dataOrNull;
      if (isDisposed || generation != _request) return;
      if (current?.accountId != id) {
        setError('Your session changed. Open insights again.');
        return;
      }
      plans = ownedPlans;
      data = const HealthInsightsService().build(
        accountId: id,
        start: selected,
        now: now,
        meals: mealResult.dataOrNull ?? [],
        readings: readingResult.dataOrNull ?? [],
        plans: planResult.dataOrNull ?? [],
        treatments: ownedPlans,
        sessions: sessions,
        checkIns: recoveryResult.dataOrNull ?? [],
        includeDemo: include,
        plansAvailable: planResult is Success,
        notices: notices.toSet().toList(),
        lastSync: sourceResult.dataOrNull?.lastSync,
      );
    } catch (_) {
      if (generation == _request && !isDisposed) {
        setError('Unable to load health insights. Please retry.');
      }
    } finally {
      if (generation == _request && !isDisposed) setLoading(false);
    }
  }

  Future<bool> saveCheckIn({
    required String planId,
    required DateTime date,
    required int pain,
    required int stiffness,
    required int difficulty,
    String notes = '',
  }) async {
    if (saving) return false;
    final snapshot = data;
    final plan = plans.where((p) => p.patientPlanId == planId).firstOrNull;
    if (snapshot == null || plan == null) return false;
    saving = true;
    setError(null);
    notifyListeners();
    try {
      final user = (await _auth.currentAccount()).dataOrNull;
      if (user?.accountId != snapshot.accountId) {
        setError('Your session changed. Sign in again.');
        return false;
      }
      final chosen = HealthInsightsService.day(date);
      final existing = snapshot.recovery
          .expand((p) => p.checkIns)
          .where((r) => r.patientPlanId == planId && r.date == chosen)
          .firstOrNull;
      final value = RecoveryCheckIn(
        checkInId: existing?.checkInId ?? newId(),
        accountId: snapshot.accountId,
        patientPlanId: planId,
        date: chosen,
        updatedAt: _now(),
        pain: pain,
        stiffness: stiffness,
        difficulty: difficulty,
        notes: notes.trim(),
      );
      if (!value.valid(_now()) ||
          chosen.isBefore(HealthInsightsService.day(plan.selectedAt))) {
        setError(
          'Choose a date from the plan start through today and valid symptom scores.',
        );
        return false;
      }
      final saved = await _recovery.save(value);
      if (saved case Failure(:final message)) {
        setError(message);
        return false;
      }
      await load();
      return true;
    } finally {
      saving = false;
      notifyListeners();
    }
  }

  Future<bool> deleteCheckIn(RecoveryCheckIn value) async {
    if (saving || data?.accountId != value.accountId) return false;
    saving = true;
    notifyListeners();
    try {
      if ((await _auth.currentAccount()).dataOrNull?.accountId !=
          value.accountId) {
        setError('Your session changed.');
        return false;
      }
      final result = await _recovery.delete(value.accountId, value.checkInId);
      if (result case Failure(:final message)) {
        setError(message);
        return false;
      }
      await load();
      return true;
    } finally {
      saving = false;
      notifyListeners();
    }
  }

  Future<Uint8List?> exportReport() async {
    final snapshot = data;
    if (snapshot == null || exporting) return null;
    exporting = true;
    notifyListeners();
    try {
      if ((await _auth.currentAccount()).dataOrNull?.accountId !=
          snapshot.accountId) {
        setError('Your session changed.');
        return null;
      }
      final result = await const WeeklyReportService().create(snapshot);
      final stillSignedIn =
          (await _auth.currentAccount()).dataOrNull?.accountId ==
          snapshot.accountId;
      if (isDisposed || data != snapshot || !stillSignedIn) return null;
      if (result case Failure(:final message)) {
        setError(message);
        return null;
      }
      return result.dataOrNull;
    } finally {
      exporting = false;
      notifyListeners();
    }
  }
}
