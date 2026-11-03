import 'package:flutter/foundation.dart';
import 'package:physical_treatment_and_health_support_system/model/result.dart';
import 'package:physical_treatment_and_health_support_system/core/constants/app_constants.dart';
import 'package:physical_treatment_and_health_support_system/shared_client/api_client/api_client.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/exercise_session.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/health_profile.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/patient_treatment_plan.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/rehab_info.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/treatment_plan.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/recommendation_service/recommendation.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/treatment_repository/i_treatment_repository.dart';

/// The patient's own plans and their attempts, by patientPlanId (hybrid-3.0).
/// A record, not a class, because the Chapter 4 diagram has no such class.
typedef PatientProgress = ({
  List<PatientTreatmentPlan> plans,
  Map<String, List<ExerciseSession>> sessions,
});

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
  /// empty means cold start (content + rules only). [progress] is the
  /// patient's own history: the server decides the next step from it and
  /// learns which plans suit from the results on similar exercises.
  Future<Result<Recommendation>> topThree(
    ProfileSnapshot snapshot,
    RehabInfo rehab,
    List<TreatmentPlan> catalogue, {
    List<PlanOutcome> outcomes = const [],
    PatientProgress? progress,
    String? nextFromPlanId,
  }) async {
    final age = snapshot.profile?.age;
    final res = await _api.post(AppConstants.recommendPath, {
      'rehab': rehab.toJson(),
      // No plan from 65 (Terms of Use, section 2); the conditions choose the
      // sources shown with the safety reasons.
      'age': ?age,
      'conditions': [
        for (final c in snapshot.profile?.conditions ?? const [])
          c.conditionCode,
      ],
      // Body-map parts (hybrid-2.1 focus block); left out for a list choice.
      if (rehab.focusParts.isNotEmpty) 'focus_parts': rehab.focusParts,
      // Optional pace (hybrid-2.2): prefers plans with about that many days a week.
      if (rehab.pace != null) 'pace': rehab.pace,
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
      if (progress != null)
        'progress': progressJson(progress, fromPlanId: nextFromPlanId),
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
      // Debug builds only: the server's reason (e.g. a 422 field error) is
      // replaced by the UC400 M4 message for the patient, so log it here.
      if (kDebugMode) {
        debugPrint('recommend failed: ${res.code} ${res.message}');
      }
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
        final ranked = (body['ranked'] as List).cast<Map<String, dynamic>>();
        return Recommendation(
          status: RecommendationStatus.fromWire(body['status'] as String?),
          plans: plans,
          modelVersion: modelVersion,
          nextStep: NextStep.fromWire(body['next_step'] as String?),
          nextStepReason: body['next_step_reason'] as String? ?? '',
          why: {
            for (final r in ranked)
              r['plan_id'] as String: PlanReason.listFrom(r['why']),
          },
          excluded: [
            for (final e
                in ((body['excluded'] as List?) ?? const [])
                    .cast<Map<String, dynamic>>())
              if (byId[e['plan_id']] case final p?)
                ExcludedPlan(p, PlanReason.listFrom(e['why'])),
          ],
          restriction: PlanRestriction.fromWire(body['restriction'] as String?),
        );
      },
      message: Messages.recommendFailed,
      code: 'bad_response',
    );
  }

  /// Attempts at a plan's current exercise that did not pass before easier
  /// plans are offered (EASE_FAILS on the server).
  static const easeAfterFails = 3;

  /// The exercise the plan moved on from without it ever passing, and its scored tries (bug list #9,
  /// 1 Nov). Below 80% the plan moves on at the third saved try (Elwin, 23 Oct), so [failsAtCurrent]
  /// never reached 3 on that path and gentler plans were never offered. Only the stage just left
  /// counts: once the next one is passed, the offer goes.
  static (String exerciseId, int fails)? movedOnWithoutPass(
    PatientTreatmentPlan p,
    List<ExerciseSession> sessions,
  ) {
    final ordered = p.plan.orderedExercises();
    final i = p.completedStages - 1;
    if (i < 0 || i >= ordered.length) return null;
    final id = ordered[i].exerciseId;
    final scored = [
      for (final s in sessions)
        if (s.exerciseId == id && s.postureAccuracy != null) s,
    ];
    if (scored.length < easeAfterFails ||
        scored.any((s) => s.postureIsPassing())) {
      return null;
    }
    return (id, scored.length);
  }

  /// How long a possible fall keeps suggesting gentler plans.
  static const fallWindow = Duration(days: 7);

  /// Scored attempts at the plan's current exercise that did not pass. A pass
  /// at the current exercise moves the pathway on, so every scored attempt at
  /// it so far is one that did not pass.
  static int failsAtCurrent(
    PatientTreatmentPlan p,
    List<ExerciseSession> sessions,
  ) {
    final current = p.currentExercise()?.exerciseId;
    if (current == null) return 0;
    return sessions
        .where(
          (s) =>
              s.exerciseId == current &&
              s.postureAccuracy != null &&
              !s.postureIsPassing(),
        )
        .length;
  }

  /// The `progress` body of /recommend: each plan's status and difficulty,
  /// and the patient's results per exercise over all plans. An exercise shared
  /// by two plans is saved once per plan; such copies count once. [fromPlanId]
  /// (the catalogue plan the patient moves on from) is sent only for "Find my
  /// next plan" / "See gentler plans": only then does the server step up or
  /// ease; for the questionnaire the history only ranks the plans.
  static Map<String, dynamic> progressJson(
    PatientProgress progress, {
    DateTime? now,
    String? fromPlanId,
  }) {
    final today = now ?? DateTime.now();
    final seen = <String>{};
    final byExercise = <String, List<ExerciseSession>>{};
    for (final list in progress.sessions.values) {
      for (final s in list) {
        if (s.postureAccuracy == null) continue;
        final key =
            '${s.exerciseId}|${s.completedAt?.toIso8601String()}|'
            '${s.postureAccuracy}|${s.repetitionsCompleted}|'
            '${s.completedAt == null ? s.sessionId : ''}';
        if (seen.add(key)) (byExercise[s.exerciseId] ??= []).add(s);
      }
    }
    return {
      'from_plan_id': ?fromPlanId,
      'plans': [
        for (final p in progress.plans)
          {
            'plan_id': p.plan.planId,
            'status': p.status.db,
            'progress_percentage': p.progressPercentage,
            ..._struggle(p, progress.sessions[p.patientPlanId] ?? const []),
            'fall_alerts': [
              for (final s
                  in progress.sessions[p.patientPlanId] ??
                      const <ExerciseSession>[])
                if (s.hadFallAlert() &&
                    s.completedAt != null &&
                    today.difference(s.completedAt!) <= fallWindow)
                  s,
            ].length,
          },
      ],
      'exercises': [
        for (final MapEntry(key: id, value: list) in byExercise.entries)
          {
            'exercise_id': id,
            'attempts': list.length,
            'passes': list.where((s) => s.postureIsPassing()).length,
            'mean_accuracy': double.parse(
              (list.map((s) => s.postureAccuracy!).reduce((a, b) => a + b) /
                      list.length)
                  .toStringAsFixed(1),
            ),
          },
      ],
    };
  }

  /// The failed tries the server eases on, and the exercise it then leaves out of the gentler plans
  /// (hybrid-3.1): the current exercise, or the one the plan just moved on from without a pass (#9).
  static Map<String, dynamic> _struggle(
    PatientTreatmentPlan p,
    List<ExerciseSession> sessions,
  ) {
    final atCurrent = failsAtCurrent(p, sessions);
    final left = movedOnWithoutPass(p, sessions);
    if (left != null && atCurrent < easeAfterFails) {
      return {'consecutive_fails': left.$2, 'current_exercise_id': left.$1};
    }
    return {
      'consecutive_fails': atCurrent,
      'current_exercise_id': p.currentExercise()?.exerciseId,
    };
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
