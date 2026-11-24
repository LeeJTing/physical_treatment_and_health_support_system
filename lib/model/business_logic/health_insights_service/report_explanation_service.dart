import 'package:physical_treatment_and_health_support_system/model/entity/anomaly_event.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/forecast.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/health_analysis.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/health_insights.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/plan_comparison.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/report_explanation.dart';

/// Descriptive interpretations of existing calculations. No new clinical
/// thresholds, inferred diagnoses, external uploads or network dependency.
class ReportExplanationService {
  const ReportExplanationService();

  ReportExplanation weekly(HealthInsights d) {
    final compared = d.comparison.compared;
    final changed = compared.where((m) => m.changed).length;
    final partial = d.completeMealDays < d.elapsedDays;
    return ReportExplanation(
      compared.isEmpty
          ? 'There is not enough comparable meal evidence to assess plan follow-through this week.'
          : changed == 0
          ? 'All ${compared.length} comparable meals were close to the saved plan.'
          : '$changed of ${compared.length} comparable meals differed from the saved plan.',
      '${d.loggedDays}/${d.elapsedDays} elapsed days have meal logs and ${d.completeMealDays} have all three main meals. '
      '${d.sessions.length} completed exercise sessions were recorded. '
      '${partial ? 'Incomplete days limit conclusions about total intake.' : 'Main-meal coverage is complete for elapsed days; snacks and portions may still be missing.'} '
      '${d.notices.isEmpty ? '' : 'Some records could not be loaded; read the data notices before interpreting this report. '}'
      '${d.includesDemo && d.demoCount > 0 ? 'Synthetic presentation records are included, so this is a demonstration rather than a personal health conclusion.' : ''}',
      changed > 0
          ? 'Review the changed meals below and compare food choices and portions with the meal simulator. ${partial ? 'Complete missing meal logs before judging daily intake.' : 'Keep recording actual portions.'}'
          : 'Keep recording actual meals and prescribed exercise. ${partial ? 'Complete missing meal logs before comparing daily totals.' : 'Review the next week using the same recording routine.'}',
    );
  }

  ReportExplanation fact(HealthInsights d, InsightFact f) {
    switch (f.title) {
      case 'Diet plan follow-through':
        final meals = d.comparison.compared;
        final changed = meals.where((m) => m.changed).length;
        return ReportExplanation(
          meals.isEmpty
              ? 'Plan follow-through cannot be assessed from the available records.'
              : changed == 0
              ? 'The comparable meals matched the saved plan closely.'
              : 'Some recorded food choices or portions differed from the saved plan.',
          f.text,
          meals.isEmpty
              ? 'Save a plan before the meal and log what you eat to enable a fair comparison.'
              : changed > 0
              ? 'Open the supporting meal records and use the meal simulator to review the differences.'
              : 'Continue checking portions and recording what you actually eat.',
        );
      case 'Previous period comparison':
        final prior = d.comparison.previousMeals
            .where(
              (m) =>
                  m.comparable &&
                  m.date.isBefore(
                    d.start
                        .subtract(const Duration(days: 7))
                        .add(Duration(days: d.elapsedDays)),
                  ),
            )
            .toList();
        final current = d.comparison.compared;
        final delta = current.isEmpty || prior.isEmpty
            ? null
            : d.comparison.count(MealComparisonStatus.close) / current.length -
                  prior
                          .where((m) => m.status == MealComparisonStatus.close)
                          .length /
                      prior.length;
        return ReportExplanation(
          delta == null
              ? 'A comparison with the previous period is unavailable.'
              : delta.abs() < .000001
              ? 'The close-to-plan share was unchanged.'
              : delta > 0
              ? 'A larger share of comparable meals was close to plan.'
              : 'A smaller share of comparable meals was close to plan.',
          f.text,
          'Compare the supporting meals in both periods and check recording completeness before attributing the change to your habits.',
        );
      case 'Recorded nutrition':
        return ReportExplanation(
          d.completeMealDays < d.loggedDays
              ? 'The recorded averages may understate your actual daily intake.'
              : 'These averages describe logged days, rather than the whole week.',
          f.text,
          'Record all meals, snacks and actual portions. Compare complete days with your saved plan before changing food amounts.',
        );
      case 'Treatment activity':
        return ReportExplanation(
          d.sessions.isEmpty
              ? 'No completed exercise sessions were recorded this week.'
              : 'Exercise activity was recorded, but session counts alone cannot establish recovery.',
          f.text,
          'Follow your assigned exercise schedule and record completed sessions and symptoms. Review difficulties with your care team before increasing exercise.',
        );
      case 'A useful next step':
      case 'Keep the useful habit':
        return ReportExplanation(
          f.title == 'A useful next step'
              ? 'Meal differences give you a specific habit to review.'
              : 'Keep the recording habit that supports useful comparisons.',
          f.text,
          'Use the supporting dates to review individual meals and choose one practical logging or portion-checking habit for next week.',
        );
      default:
        return ReportExplanation(
          f.conclusion ??
              'This comparison describes recorded ${f.title.toLowerCase()} in the two periods; measurement conditions and coverage affect its interpretation.',
          f.text,
          'Keep recording under comparable conditions and check the supporting dates and reading sources. Discuss a persistent change with your care team.',
        );
    }
  }

  ReportExplanation quality(HealthInsights d) {
    final readings = d.readings
        .where(
          (r) =>
              !r.recordedAt.isBefore(d.start) && !r.recordedAt.isAfter(d.asOf),
        )
        .toList();
    final missing = MetricType.values
        .where((m) => !readings.any((r) => r.metricType == m))
        .map((m) => m.label)
        .toList();
    return ReportExplanation(
      readings.isEmpty
          ? 'No valid readings are available for the selected week.'
          : missing.isNotEmpty
          ? 'Some tracked metrics have no readings in the selected week.'
          : 'Each tracked metric has readings; consistency and source still affect interpretation.',
      '${readings.length} valid readings are available in this week. '
          '${missing.isEmpty ? '' : 'No weekly readings for ${missing.join(', ')}. '}'
          '${d.invalidReadings} invalid readings were excluded from the loaded history. '
          '${d.lastSync == null ? 'No successful source sync time is saved.' : 'A saved sync time confirms a source check, not that every watch measurement was imported.'} '
          '${d.notices.isEmpty ? '' : 'Retrieval notices mean the loaded history may be incomplete.'}',
      'Review missing dates in Data quality and use Import from watch in Tracking to check for new saved readings. Keep reading conditions and sources consistent; additional readings do not guarantee forecast accuracy.',
    );
  }

  ReportExplanation recovery(RecoveryProgress p) {
    final checks = [...p.checkIns]..sort((a, b) => a.date.compareTo(b.date));
    if (checks.length < 2) {
      return ReportExplanation(
        'There are too few symptom check-ins to describe a change.',
        '${checks.length} symptom check-ins and ${p.sessions.length} completed sessions are available for this plan. Exercise completion and posture results do not establish symptom recovery.',
        'Add check-ins on different days for this same plan, recording pain, stiffness and difficulty. Continue following your assigned plan.',
      );
    }
    final first = checks.first,
        last = checks.last,
        previous = checks[checks.length - 2];
    final pain = last.pain - first.pain,
        stiffness = last.stiffness - first.stiffness;
    final difficulty = last.difficulty - first.difficulty;
    final worse =
        last.pain > previous.pain ||
        last.stiffness > previous.stiffness ||
        last.difficulty > previous.difficulty;
    String change(int v) => '${v >= 0 ? '+' : ''}$v';
    return ReportExplanation(
      worse
          ? 'At least one symptom score increased since the preceding check-in.'
          : pain <= 0 &&
                stiffness <= 0 &&
                difficulty <= 0 &&
                (pain < 0 || stiffness < 0 || difficulty < 0)
          ? 'Your latest symptom scores are lower or unchanged compared with the first check-in.'
          : pain == 0 && stiffness == 0 && difficulty == 0
          ? 'Your latest symptom scores match the first check-in.'
          : 'Symptom scores show mixed changes compared with the first check-in.',
      '${checks.length} check-ins: pain ${first.pain}/10 to ${last.pain}/10 (${change(pain)} points), stiffness ${first.stiffness}/10 to ${last.stiffness}/10 (${change(stiffness)}), and difficulty ${first.difficulty}/5 to ${last.difficulty}/5 (${change(difficulty)}). Missing days remain unknown; these self-reports do not prove treatment effectiveness.',
      worse
          ? 'Review the increase with your care team before increasing exercise. Note which activities felt difficult in your next check-in.'
          : 'Continue symptom check-ins and follow your assigned exercise plan. Share persistent difficulties with your care team; lower scores alone are not a reason to advance treatment.',
    );
  }

  ReportExplanation health(HealthAnalysis? a, List<AnomalyEvent> anomalies) {
    final high = anomalies.any((e) => e.isHighSeverity());
    if (a == null) {
      return ReportExplanation(
        'A health conclusion is not available yet.',
        'No saved health analysis is available to interpret.',
        high
            ? 'Review the high-severity reading alerts and follow their advice to consult a health professional.'
            : 'Record your readings, meals and exercise, then refresh the report.',
      );
    }
    final factors = a.factors()
      ..sort((x, y) => x.subScore.compareTo(y.subScore));
    final focus = factors.firstOrNull;
    return ReportExplanation(
      a.healthScore == null
          ? 'There is not enough evidence to calculate the Health Score.'
          : 'Your calculated Health Score is ${a.healthScore}/100 (${(a.scoreBand ?? HealthAnalysis.bandFor(a.healthScore!)).label.toLowerCase()}).',
      '${a.summaryText ?? 'The score summarises available readings, meals and recorded exercise.'} '
      '${focus == null ? '' : '${focus.label} has the lowest available factor score (${focus.subScore}/100). ${focus.note} '}'
      '${anomalies.isEmpty ? 'An empty alert list does not establish that all readings are healthy.' : '${anomalies.length} saved alerts appear in the recent history; inspect their dates and explanations.'}',
      high
          ? 'Review the high-severity reading alerts and follow their advice to consult a health professional.'
          : a.healthScore == null
          ? 'Complete the missing records${a.missingData.isEmpty ? '' : ': ${a.missingData.join(', ')}'} and refresh the report.'
          : 'Review ${focus?.label.toLowerCase() ?? 'the contributing factors'} and its supporting records first. Keep logging consistently and follow your existing care plan.',
    );
  }

  ReportExplanation risk(ConditionRisk r) => ReportExplanation(
    r.withheld || r.risk == null
        ? 'A risk indication for ${r.conditionName} is not available.'
        : 'The model indicates ${r.risk!.toLowerCase()} risk for ${r.conditionName}.',
    r.withheld || r.risk == null
        ? r.message ?? 'Required readings are missing.'
        : '${r.topFactors.isEmpty ? 'No contributing factors were supplied.' : 'Main contributing factors: ${r.topFactors.join('; ')}.'} This is a model indication, not a diagnosis.',
    r.withheld || r.risk == null
        ? 'Record the required measurements and refresh this report.'
        : r.risk == 'High'
        ? 'Discuss this indication and its supporting readings with your care team.'
        : 'Continue monitoring as advised and review changes with your care team.',
  );

  ReportExplanation forecast(
    MetricType metric,
    Forecast? f, {
    bool stale = false,
    bool insufficient = false,
  }) {
    final points =
        f
            ?.points()
            .where(
              (p) => p.value.isFinite && p.lower.isFinite && p.upper.isFinite,
            )
            .toList() ??
        <ForecastPoint>[];
    points.sort((a, b) => a.date.compareTo(b.date));
    if (f == null || f.isWithheld() || insufficient || points.isEmpty) {
      return const ReportExplanation(
        'There is no usable forecast to interpret.',
        'Insufficient or unavailable forecast data prevents a supported prediction. Missing values are unknown.',
        'Keep recording measurements consistently and refresh when more history is available.',
      );
    }
    final first = points.first, last = points.last;
    final delta = last.value - first.value;
    final direction =
        delta.toStringAsFixed(1) == '0.0' || delta.toStringAsFixed(1) == '-0.0'
        ? 'little change'
        : delta > 0
        ? 'an increase'
        : 'a decrease';
    final name = metric == MetricType.bloodPressure
        ? 'Systolic blood pressure'
        : metric.label;
    return ReportExplanation(
      '${stale ? 'The last saved forecast' : 'The forecast'} projects $direction in ${name.toLowerCase()} across its predicted dates.',
      'Predicted values run from ${first.value.toStringAsFixed(1)} to ${last.value.toStringAsFixed(1)} ${metric.unit}; the final prediction band is ${last.lower.toStringAsFixed(1)}-${last.upper.toStringAsFixed(1)} ${metric.unit}. The band reflects uncertainty. ${stale ? 'This forecast could not be refreshed. ' : ''}A projected direction alone does not establish improvement or worsening.',
      'Compare future measured readings with the projection. ${stale ? 'Refresh to request an updated forecast. ' : ''}Use measured readings and care-team advice when making health decisions.',
    );
  }
}
