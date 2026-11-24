import 'package:flutter_test/flutter_test.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/health_insights_service/health_insights_service.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/health_insights_service/report_explanation_service.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/anomaly_event.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/biometric_reading.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/forecast.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/health_analysis.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/health_insights.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/recovery_check_in.dart';
import '../integration_test/support/health_insights_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const service = ReportExplanationService();
  HealthInsights build({List<BiometricReading> readings = const []}) =>
      const HealthInsightsService().build(
        accountId: 'a',
        start: DateTime(2026, 11, 16),
        now: DateTime(2026, 11, 20),
        meals: [],
        readings: readings,
        plans: [],
        treatments: [],
        sessions: [],
        checkIns: [],
      );

  test('empty history never becomes adherence or normal-health evidence', () {
    final d = build();
    expect(service.weekly(d).conclusion, contains('not enough'));
    expect(service.quality(d).conclusion, contains('No valid readings'));
    expect(service.health(null, []).conclusion, contains('not available'));
    expect(
      service.fact(d, d.facts.first).conclusion,
      contains('cannot be assessed'),
    );
    expect(
      service.forecast(MetricType.bodyWeight, null).conclusion,
      contains('no usable forecast'),
    );
  });

  test('metric conclusion uses daily means and handles equal values', () {
    for (final value in [60.0, 65.0, 55.0]) {
      final d = build(
        readings: [
          for (final day in [9, 10, 16, 17])
            BiometricReading(
              readingId: '$day',
              accountId: 'a',
              metricType: MetricType.bodyWeight,
              primaryValue: day < 16 ? 60 : value,
              recordedAt: DateTime(2026, 11, day),
            ),
        ],
      );
      final e = service.fact(d, d.facts.last);
      expect(
        e.conclusion,
        contains(
          value == 60
              ? 'unchanged'
              : value > 60
              ? 'higher'
              : 'lower',
        ),
      );
      expect(e.conclusion, contains('does not establish'));
    }
  });

  RecoveryCheckIn check(
    int day, {
    int pain = 3,
    int stiffness = 3,
    int difficulty = 2,
  }) => RecoveryCheckIn(
    checkInId: '$day',
    accountId: 'a',
    patientPlanId: 'p',
    date: DateTime(2026, 11, day),
    updatedAt: DateTime(2026, 11, day),
    pain: pain,
    stiffness: stiffness,
    difficulty: difficulty,
  );

  test('recovery notices difficulty-only worsening and sorts check-ins', () {
    final checks = [check(19, difficulty: 4), check(16)];
    final e = service.recovery(RecoveryProgress('p', 'Plan', checks, []));
    expect(e.conclusion, contains('increased'));
    expect(e.analysis, contains('difficulty 2/5 to 4/5 (+2)'));
    expect(e.suggestion, contains('before increasing exercise'));
    expect(checks.first.date.day, 19);
    final sparse = service.recovery(
      RecoveryProgress('p', 'Plan', [check(16)], []),
    );
    expect(sparse.conclusion, contains('too few'));
  });

  test(
    'recent symptom reversal takes precedence over first-to-last decline',
    () {
      final e = service.recovery(
        RecoveryProgress('p', 'Plan', [
          check(16, pain: 7),
          check(17, pain: 2),
          check(19, pain: 4),
        ], []),
      );
      expect(e.conclusion, contains('increased since the preceding'));
      expect(e.analysis, contains('7/10 to 4/10 (-3 points)'));
    },
  );

  test('high-severity advice remains visible without a calculated score', () {
    final e = service.health(null, [
      AnomalyEvent(
        anomalyId: 'alert',
        accountId: 'a',
        metricType: MetricType.bodyWeight,
        anomalyType: AnomalyType.values.first,
        severity: Severity.high,
        explanationText: 'Saved alert',
        detectedAt: DateTime(2026, 11, 20),
      ),
    ]);
    expect(e.suggestion, contains('high-severity'));
    final withheld = service.risk(
      const ConditionRisk(
        conditionCode: 'c',
        conditionName: 'Condition',
        withheld: true,
        message: 'More readings needed.',
      ),
    );
    expect(withheld.conclusion, contains('not available'));
    expect(withheld.analysis, 'More readings needed.');
  });

  test(
    'stale forecast describes predicted dates and uncertainty without promising improvement',
    () {
      final f = Forecast(
        forecastId: 'f',
        accountId: 'a',
        metricType: MetricType.bodyWeight,
        inputReadingCount: 20,
        modelVersion: 'fixture',
        generatedAt: DateTime(2026, 11, 20),
        predictedValues: {
          'points': [
            {'date': '2026-11-22', 'value': 64, 'lower': 60, 'upper': 68},
            {'date': '2026-11-21', 'value': 65, 'lower': 61, 'upper': 69},
          ],
        },
      );
      final e = service.forecast(MetricType.bodyWeight, f, stale: true);
      expect(e.conclusion, contains('last saved forecast'));
      expect(e.conclusion, contains('decrease'));
      expect(e.analysis, contains('65.0 to 64.0 kg'));
      expect(e.analysis, contains('60.0-68.0 kg'));
      expect(e.analysis, contains('does not establish improvement'));
      expect(
        service
            .forecast(MetricType.bodyWeight, f, insufficient: true)
            .conclusion,
        contains('no usable forecast'),
      );
    },
  );

  test(
    'weekly explanations retain evidence and identify synthetic presentation data',
    () async {
      final fixture = await HealthInsightsFixture.create();
      addTearDown(fixture.dispose);
      final d = fixture.vm.data!;
      expect(service.weekly(d).analysis, contains('Synthetic presentation'));
      for (final fact in d.facts) {
        final e = service.fact(d, fact);
        expect(e.analysis, fact.text);
        expect(e.conclusion, isNotEmpty);
        expect(e.suggestion, isNotEmpty);
      }
      await fixture.vm.setIncludeDemo(false);
      expect(
        service.weekly(fixture.vm.data!).analysis,
        isNot(contains('Synthetic presentation')),
      );
    },
  );
}
