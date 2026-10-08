import 'package:physical_treatment_and_health_support_system/model/result.dart';
import 'package:physical_treatment_and_health_support_system/core/constants/app_constants.dart';
import 'package:physical_treatment_and_health_support_system/shared_client/api_client/api_client.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/health_profile.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/rehab_info.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/treatment_plan.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/recommendation_service/recommendation.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/treatment_repository/i_treatment_repository.dart';

/// Hybrid recommendation (Table 4.77). The scoring runs on the AI server's
/// /recommend; this class builds the request from the profile, the
/// questionnaire and the catalogue, and maps the ranked ids back to plans.
class RecommendationService {
  final ApiClient _api;

  /// Version of the server algorithm that produced the last result.
  String modelVersion = 'unknown';

  RecommendationService(this._api);

  /// Ranks [catalogue] for the patient and returns the best three (FR500_05-07).
  /// [outcomes] is the anonymised cohort evidence for the collaborative score;
  /// empty means cold start (content + rules only).
  Future<Result<Recommendation>> topThree(
    ProfileSnapshot snapshot,
    RehabInfo rehab,
    List<TreatmentPlan> catalogue, {
    List<PlanOutcome> outcomes = const [],
  }) async {
    final age = snapshot.profile?.age;
    final res = await _api.post(AppConstants.recommendPath, {
      'rehab': rehab.toJson(),
      'safety_limit': snapshot.safetyLimit.toJson(),
      'limitations': [
        for (final l in snapshot.profile?.limitations ?? const [])
          l.limitationCode,
      ],
      'plans': [for (final p in catalogue) p.toJson()],
      // The patient's own cohort, compared with the outcome cells. Without a
      // profile age there is no cohort, so the server runs a cold start.
      if (age != null)
        'cohort': {
          'risk_level': snapshot.riskLevel.db,
          'age_band': ageBand(age),
        },
      'plan_outcomes': [
        for (final o in outcomes)
          {
            'plan_id': o.planId,
            'risk_level': o.riskLevel,
            'age_band': o.ageBand,
            'patients': o.patients,
            'completion_rate': o.completionRate,
            'mean_accuracy': o.meanAccuracy,
            'mean_progress': o.meanProgress,
          },
      ],
    }, timeout: AppConstants.recommendTimeout);
    if (res is Failure<Map<String, dynamic>>) {
      return Failure(
        Messages.recommendFailed,
        code: res.code,
        cause: res.cause,
      );
    }
    return guard(
      () async {
        final body = res.dataOrNull!;
        final byId = {for (final p in catalogue) p.planId: p};
        final plans = <TreatmentPlan>[
          for (final r in (body['ranked'] as List).cast<Map<String, dynamic>>())
            if (byId[r['plan_id']] case final p?)
              p.withScore((r['suitability_score'] as num).toDouble()),
        ];
        modelVersion = body['model_version'] as String? ?? modelVersion;
        return Recommendation(
          status: RecommendationStatus.fromWire(body['status'] as String?),
          plans: plans,
          modelVersion: modelVersion,
        );
      },
      message: Messages.recommendFailed,
      code: 'bad_response',
    );
  }

  /// Age bands of the plan_outcome_stats() RPC.
  static String ageBand(int age) => age < 60
      ? '<60'
      : age < 75
      ? '60-74'
      : '75+';

  /// False when nothing suits the condition (FR500_14).
  bool hasCandidate(Recommendation r) => r.plans.isNotEmpty;
}
