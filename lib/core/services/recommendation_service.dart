import 'package:physical_treatment_and_health_support_system/core/base/result.dart';
import 'package:physical_treatment_and_health_support_system/core/constants/app_constants.dart';
import 'package:physical_treatment_and_health_support_system/core/services/api_client.dart';
import 'package:physical_treatment_and_health_support_system/data/models/health_profile.dart';
import 'package:physical_treatment_and_health_support_system/data/models/rehab_info.dart';
import 'package:physical_treatment_and_health_support_system/data/models/treatment_plan.dart';
import 'package:physical_treatment_and_health_support_system/features/planning/model/recommendation.dart';

/// Hybrid recommendation (Table 4.77). The scoring runs on the AI server's
/// /recommend; this class builds the request from the profile, the
/// questionnaire and the catalogue, and maps the ranked ids back to plans.
class RecommendationService {
  final ApiClient _api;

  /// Version of the server algorithm that produced the last result.
  String modelVersion = 'unknown';

  RecommendationService(this._api);

  /// Ranks [catalogue] for the patient and returns the best three (FR500_05-07).
  Future<Result<Recommendation>> topThree(
    ProfileSnapshot snapshot,
    RehabInfo rehab,
    List<TreatmentPlan> catalogue,
  ) async {
    final res = await _api.post(
      AppConstants.recommendPath,
      {
        'rehab': rehab.toJson(),
        'safety_limit': snapshot.safetyLimit.toJson(),
        'limitations': [for (final l in snapshot.profile?.limitations ?? const []) l.limitationCode],
        'plans': [for (final p in catalogue) p.toJson()],
      },
      timeout: AppConstants.recommendTimeout,
    );
    if (res is Failure<Map<String, dynamic>>) {
      return Failure(Messages.recommendFailed, code: res.code, cause: res.cause);
    }
    return guard(() async {
      final body = res.dataOrNull!;
      final byId = {for (final p in catalogue) p.planId: p};
      final plans = <TreatmentPlan>[
        for (final r in (body['ranked'] as List).cast<Map<String, dynamic>>())
          if (byId[r['plan_id']] case final p?) p.withScore((r['suitability_score'] as num).toDouble()),
      ];
      modelVersion = body['model_version'] as String? ?? modelVersion;
      return Recommendation(
        status: RecommendationStatus.fromWire(body['status'] as String?),
        plans: plans,
        modelVersion: modelVersion,
      );
    }, message: Messages.recommendFailed, code: 'bad_response');
  }

  /// False when nothing suits the condition (FR500_14).
  bool hasCandidate(Recommendation r) => r.plans.isNotEmpty;
}
