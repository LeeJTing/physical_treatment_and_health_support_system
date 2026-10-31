import 'package:physical_treatment_and_health_support_system/core/constants/app_constants.dart';
import 'package:physical_treatment_and_health_support_system/core/utils/id_utils.dart';
import 'package:physical_treatment_and_health_support_system/model/result.dart';
import 'package:physical_treatment_and_health_support_system/shared_client/api_client/api_client.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/anomaly_event.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/biometric_reading.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/health_analysis.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/health_profile.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/meal_log.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/safety_limit.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/analysis_repository/i_analysis_repository.dart';

/// Result of one /analyse call: the anomalies and the day's Health Score with the risks.
class AnalysisOutcome {
  final List<AnomalyEvent> anomalies;
  final HealthAnalysis analysis;

  /// 30-day baselines per metric, for the report ("usual range 128-140 mmHg").
  final Map<String, dynamic> baselines;

  const AnalysisOutcome({
    required this.anomalies,
    required this.analysis,
    this.baselines = const {},
  });
}

/// Sends the reading history, the declared conditions and the analysis feature set to /analyse,
/// which computes the rolling baseline, detects deviations and sustained trends, classifies
/// severity, scores health and predicts the per-condition risk (Table 4.91). Only the pseudonymous
/// feature set leaves the phone: no account id, name or email (FR400_036, NFR_15).
class AnomalyDetectionService {
  final ApiClient _api;
  final IAnalysisRepository _repo;

  /// 30-day window the baseline is computed over (FR400_009).
  final int windowDays = 30;

  /// Returned by the server and stored with each analysis.
  String modelVersion = '';

  AnomalyDetectionService(this._api, this._repo);

  /// Baseline, deviation and trend detection plus the Health Score and risks in one call
  /// (FR400_009 to FR400_033).
  Future<Result<AnalysisOutcome>> analyse({
    required String accountId,
    required HealthProfile? profile,
    required SafetyLimit limit,
    required List<BiometricReading> history,
    List<ActivityRecord> sessions = const [],
    List<MealLog> meals = const [],
    DateTime? asOf,
  }) async {
    final now = asOf ?? DateTime.now();
    final res = await _api.post(
      AppConstants.analysePath,
      {
        'profile': {
          'age': profile?.age,
          'gender': profile?.gender?.db,
          'weight_kg': profile?.weightKg,
          'height_cm': profile?.heightCm,
          'bmi': profile?.calculateBmi(),
          'conditions': profile?.conditions.map((c) => c.conditionCode).toList() ?? const [],
        },
        'readings': history.map((r) => r.toAnalysisJson()).toList(),
        'sessions': sessions.map((s) => s.toAnalysisJson()).toList(),
        'meals': [
          for (final m in meals)
            {
              'consumed_at': m.consumedAt.toLocal().toIso8601String(),
              'energy_kcal': m.totalEnergyKcal,
              'sodium_mg': m.totalSodiumMg,
              'sugar_g': m.totalSugarG,
            },
        ],
        'limits': {
          'daily_calorie_target': limit.dailyCalorieTarget,
          'daily_sodium_limit_mg': limit.dailySodiumLimitMg,
          'daily_sugar_limit_g': limit.dailySugarLimitG,
        },
        'as_of': now.toIso8601String(),
        'period_days': AppConstants.analysisPeriodDays,
      },
      timeout: AppConstants.analysisTimeout,
    );
    if (res case Failure(:final code, :final cause)) {
      return Failure(Messages.analysisUnavailable, code: code, cause: cause);
    }
    final b = res.dataOrNull!;
    modelVersion = (b['model_version'] ?? '') as String;
    final anomalies = [
      for (final a in (b['anomalies'] as List? ?? const []))
        AnomalyEvent.fromServer(Map<String, dynamic>.from(a as Map), accountId, now),
    ];
    // FR400_029: the model version and the input window go with every risk prediction.
    final risks = <String, dynamic>{
      for (final e in Map<String, dynamic>.from((b['condition_risks'] ?? const {}) as Map).entries)
        e.key: {
          ...Map<String, dynamic>.from(e.value as Map),
          'model_version': modelVersion,
          'input_window': b['input_window'],
        },
    };
    final score = (b['health_score'] as num?)?.toInt();
    final analysis = HealthAnalysis(
      analysisId: newId(),
      accountId: accountId,
      analysisDate: DateTime(now.year, now.month, now.day),
      healthScore: score,
      scoreBand: ScoreBand.fromDb(b['score_band'] as String?) ??
          (score == null ? null : ScoreBand.forScore(score)),
      factorContributions: b['factor_contributions'] == null
          ? null
          : Map<String, dynamic>.from(b['factor_contributions'] as Map),
      conditionRisks: risks,
      periodComparison: PeriodComparison.fromDb(b['period_comparison'] as String?),
      summaryText: b['summary_text'] as String?,
      modelVersion: modelVersion,
      missingData: ((b['missing'] as List?) ?? const []).cast<String>(),
    );
    return Success(
      AnalysisOutcome(
        anomalies: anomalies,
        analysis: analysis,
        baselines: Map<String, dynamic>.from((b['baselines'] ?? const {}) as Map),
      ),
    );
  }

  /// The Health Score part of [analyse] (FR400_020, FR400_026).
  Future<Result<HealthAnalysis>> score({
    required String accountId,
    required HealthProfile? profile,
    required SafetyLimit limit,
    required List<BiometricReading> history,
    List<ActivityRecord> sessions = const [],
    List<MealLog> meals = const [],
  }) async {
    final r = await analyse(
      accountId: accountId,
      profile: profile,
      limit: limit,
      history: history,
      sessions: sessions,
      meals: meals,
    );
    return switch (r) {
      Success(:final data) => Success(data.analysis),
      Failure(:final message, :final code, :final cause) =>
        Failure(message, code: code, cause: cause),
    };
  }

  /// The last stored analysis, so the screen still renders while the server is unreachable
  /// (FR400_039).
  Future<HealthAnalysis?> lastStored(String accountId) async =>
      (await _repo.latestAnalysis(accountId)).dataOrNull;
}
