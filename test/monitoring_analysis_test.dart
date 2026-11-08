import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:physical_treatment_and_health_support_system/core/constants/app_constants.dart';
import 'package:physical_treatment_and_health_support_system/core/utils/id_utils.dart';
import 'package:physical_treatment_and_health_support_system/device_platform/health_connect/health_data_source.dart';
import 'package:physical_treatment_and_health_support_system/device_platform/notification_scheduler/notification_scheduler.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/anomaly_detection_service/anomaly_detection_service.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/forecast_service/forecast_service.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/health_connect_service/health_connect_service.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/local_notification_service/local_notification_service.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/risk_assessment_service/risk_assessment_service.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/biometric_reading.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/health_analysis.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/health_profile.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/lookups.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/analysis_repository/fake_analysis_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/auth_repository/fake_auth_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/biometric_repository/fake_biometric_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/meal_repository/fake_meal_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/notification_repository/fake_notification_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/profile_repository/fake_profile_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/treatment_repository/fake_treatment_repository.dart';
import 'package:physical_treatment_and_health_support_system/shared_client/api_client/api_client.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/analysis_view_model/analysis_view_model.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/monitoring_view_model/monitoring_view_model.dart';

final String catalogueJson = File('assets/seed/catalogue.json').readAsStringSync();

/// Records what would be shown on the phone.
class _Scheduler implements NotificationScheduler {
  bool permitted = true;
  final shown = <String>[];
  @override
  Future<void> init() async {}
  @override
  Future<bool> requestPermission() async => permitted;
  @override
  Future<bool> isPermitted() async => permitted;
  @override
  Future<bool> openSettings() async => true;
  @override
  Future<void> scheduleOnce(int id, String title, String body, DateTime at, {String? payload}) async =>
      shown.add('$title|$payload');
  @override
  Future<void> cancel(int id) async {}
  @override
  Stream<String> get taps => const Stream.empty();
  @override
  Future<String?> launchPayload() async => null;
  @override
  Future<bool> canRingOnTime() async => true;
  @override
  Future<void> openExactAlarmSettings() async {}
}

void main() {
  final now = DateTime(2026, 10, 26, 9);
  late FakeAuthRepository auth;
  late FakeBiometricRepository readings;
  late FakeTreatmentRepository treatments;
  late String accountId;

  setUp(() async {
    auth = FakeAuthRepository();
    accountId = (await auth.login('demo@apths.test', 'password123')).dataOrNull!.accountId;
    readings = FakeBiometricRepository();
    treatments = FakeTreatmentRepository.fromJson(catalogueJson);
  });

  BiometricReading bp(DateTime at, double s, double d, {ReadingSource src = ReadingSource.manual}) => BiometricReading(
    readingId: newId(),
    accountId: accountId,
    metricType: MetricType.bloodPressure,
    primaryValue: s,
    secondaryValue: d,
    source: src,
    recordedAt: at,
  );

  group('BiometricReading (Table 4.35)', () {
    test('plausible ranges, systolic over diastolic, no future time (FR200_004 to FR200_006)', () {
      expect(bp(now, 128, 82).isPlausible(), isTrue);
      expect(bp(now, 260, 82).isPlausible(), isFalse);
      expect(bp(now, 120, 30).isPlausible(), isFalse);
      expect(bp(now, 80, 90).isValidBloodPressure(), isFalse);
      expect(bp(now.add(const Duration(hours: 1)), 120, 80).isFutureDated(now), isTrue);
      expect(bp(now, 128, 82).display(), '128/82 mmHg');
    });

    test('an import within 5 minutes of a stored reading is a duplicate (C11)', () {
      expect(bp(now, 120, 80).duplicates(bp(now.add(const Duration(minutes: 4)), 121, 80)), isTrue);
      expect(bp(now, 120, 80).duplicates(bp(now.add(const Duration(minutes: 6)), 121, 80)), isFalse);
    });

    test('period summary (C2)', () {
      final s = PeriodSummary.of([bp(now, 120, 80), bp(now, 130, 90)], [
        ActivityRecord(sessionId: 's', exerciseName: 'Sit to Stand', durationSec: 600, completedAt: now),
      ]);
      expect(s.readings, 2);
      expect(s.sessions, 1);
      expect(s.exerciseMinutes, 10);
      expect(s.means[MetricType.bloodPressure], '125/85 mmHg');
    });
  });

  group('MonitoringViewModel (UC700)', () {
    late FakeHealthDataSource source;
    late MonitoringViewModel vm;

    setUp(() async {
      source = FakeHealthDataSource();
      vm = MonitoringViewModel(readings, HealthConnectService(source), auth, treatments, null, () => now);
      await vm.load();
    });

    test('validation messages of the entry form (M4, M6)', () {
      expect(vm.validate(metric: MetricType.bloodPressure, primary: 120, recordedAt: now), Messages.emptyField);
      expect(vm.validate(metric: MetricType.bloodGlucose, primary: 5.5, recordedAt: now), Messages.emptyField);
      expect(vm.validate(metric: MetricType.bodyWeight, primary: 400, recordedAt: now), Messages.implausibleValue);
      expect(vm.validate(metric: MetricType.bloodPressure, primary: 120, secondary: 80, recordedAt: now), isNull);
    });

    test('a saved reading is tagged Manual and shown in the period (FR200_010, FR200_017)', () async {
      final msg = await vm.addReading(metric: MetricType.bodyWeight, primary: 70.5, recordedAt: now.subtract(const Duration(hours: 1)));
      expect(msg, isNull);
      expect(vm.takeMessage(), Messages.readingSaved);
      expect(readings.readings.single.source, ReadingSource.manual);
      expect(vm.data!.readings, hasLength(1));
      expect(vm.summary().means[MetricType.bodyWeight], '70.5 kg');
    });

    test('a failed save keeps the form and says so (E2)', () async {
      readings.failNext = true;
      final msg = await vm.addReading(metric: MetricType.bodyWeight, primary: 70, recordedAt: now.subtract(const Duration(hours: 1)));
      expect(msg, Messages.readingSaveFailed);
    });

    test('start after end is rejected (FR200_020)', () async {
      expect(await vm.loadRange(now, now.subtract(const Duration(days: 3))), isFalse);
      expect(vm.takeMessage(), Messages.invalidDateRange);
    });

    test('Health Connect import: permission, duplicates discarded, sync time recorded (FR200_009 to FR200_012)', () async {
      await readings.insert(bp(now.subtract(const Duration(hours: 2)), 130, 85));
      source.records.addAll([
        HealthRecord('BLOOD_PRESSURE', 131, now.subtract(const Duration(hours: 2, minutes: 3)), secondary: 86), // duplicate
        HealthRecord('BLOOD_PRESSURE', 125, now.subtract(const Duration(hours: 30)), secondary: 80),
        HealthRecord('BODY_WEIGHT', 71.2, now.subtract(const Duration(hours: 5))),
        HealthRecord('BODY_WEIGHT', 900, now.subtract(const Duration(hours: 6))), // implausible
      ]);
      expect(await vm.connect(), isTrue);
      expect(readings.readings.where((r) => r.source == ReadingSource.imported), hasLength(2));
      expect(vm.connected, isTrue);
      expect(vm.lastSync, now);
    });

    test('keeps Health Connect in step without pressing Import readings', () async {
      expect(await vm.connect(), isTrue);
      final before = readings.readings.length;
      // A reading added later in another health app arrives by itself on the next sync.
      source.records.add(HealthRecord('BODY_WEIGHT', 70.4, now.subtract(const Duration(minutes: 1))));
      await vm.syncNow();
      expect(readings.readings.length, before + 1);
      expect(vm.takeMessage(), contains('Imported 1 reading'));
      // Nothing new: quiet, no message.
      await vm.syncNow();
      expect(vm.takeMessage(), isNull);
      vm.startAutoSync(every: const Duration(hours: 1));
      vm.stopAutoSync();
    });

    test('refused permission imports nothing (A1.1)', () async {
      source.available = false;
      expect(await vm.connect(), isFalse);
      expect(readings.readings, isEmpty);
    });

    test('delete one entry (FR200_022)', () async {
      await vm.addReading(metric: MetricType.bodyWeight, primary: 70, recordedAt: now.subtract(const Duration(hours: 1)));
      expect(await vm.deleteReading(readings.readings.single.readingId), isTrue);
      expect(readings.readings, isEmpty);
    });

    test('UI first: a deleted reading leaves at once and comes back if the deletion fails (E4)', () async {
      await vm.addReading(metric: MetricType.bodyWeight, primary: 70, recordedAt: now.subtract(const Duration(hours: 1)));
      await vm.loadRange(vm.rangeStart, now, days: vm.rangeDays);
      final id = readings.readings.single.readingId;
      readings.failNext = true;
      final deleting = vm.deleteReading(id);
      expect(vm.data!.readings, isEmpty); // at once
      expect(await deleting, isFalse);
      expect(vm.data!.readings, hasLength(1)); // put back
      expect(vm.takeMessage(), Messages.deletionFailed);
    });
  });

  group('AnalysisViewModel (UC600)', () {
    test('forecast, score, risks and a High alert passed to M600 (FR400_017, FR600_009 to FR600_014)', () async {
      final profiles = FakeProfileRepository();
      final p = HealthProfile(
        profileId: newId(),
        accountId: accountId,
        age: 61,
        gender: Gender.male,
        weightKg: 78,
        heightCm: 170,
        conditions: [LookupSeed.conditions.first],
        updatedAt: DateTime.now(),
      );
      await profiles.saveProfile(p, p.generateSafetyLimit());
      for (var i = 0; i < 20; i++) {
        await readings.insert(bp(now.subtract(Duration(days: 20 - i)), 128, 82));
      }
      final paths = <String>[];
      Map<String, dynamic>? analyseBody;
      final api = ApiClient(
        baseUrl: 'http://ai',
        tokenProvider: () => 't',
        httpClient: MockClient((req) async {
          paths.add(req.url.path);
          if (req.url.path == '/forecast') {
            return http.Response(jsonEncode({
              'model_version': 'forecast-gbdt-1.0',
              'input_reading_count': 20,
              'withheld': false,
              'points': [for (var d = 1; d <= 7; d++) {'date': '2026-10-${26 + d > 31 ? 31 : 26 + d}', 'value': 129, 'lower': 124, 'upper': 134}],
            }), 200);
          }
          analyseBody = jsonDecode(req.body) as Map<String, dynamic>;
          return http.Response(jsonEncode({
            'model_version': 'analysis-1.0',
            'anomalies': [
              {'metric_type': 'BLOOD_PRESSURE', 'anomaly_type': 'DEVIATION', 'severity': 'High', 'reading_id': 'x',
               'explanation_text': 'Your blood pressure reading of 185/112 mmHg is beyond the safe limit.'},
            ],
            'baselines': {'BLOOD_PRESSURE': {'mean': 128.0, 'sd': 3.0, 'n': 20}},
            'health_score': 72,
            'score_band': 'FAIR',
            'factor_contributions': {
              'blood_pressure': {'label': 'Blood pressure control', 'sub_score': 80, 'weight': 0.4, 'points': 32, 'note': ''},
              'bmi': {'label': 'Body mass index', 'sub_score': 67, 'weight': 0.6, 'points': 40, 'note': ''},
            },
            'period_comparison': 'BETTER',
            'condition_risks': {
              'HYPERTENSION': {'condition_name': 'High blood pressure', 'risk': 'Moderate', 'withheld': false,
                               'top_factors': ['Age 61', 'BMI 27.0']},
            },
            'input_window': {'from': '2026-09-26', 'to': '2026-10-26'},
            'summary_text': 'Your Health Score is 72 (Fair).',
            'missing': [],
          }), 200);
        }),
      );
      final analysisRepo = FakeAnalysisRepository();
      final log = FakeNotificationRepository();
      final scheduler = _Scheduler();
      final alerts = LocalNotificationService(log, treatments, scheduler: scheduler);
      final vm = AnalysisViewModel(
        analysisRepo,
        ForecastService(api),
        AnomalyDetectionService(api, analysisRepo),
        RiskAssessmentService(auth, profiles),
        readings,
        FakeMealRepository(),
        treatments,
        auth,
        alerts,
        () => now,
      );
      await vm.loadAnalysis();

      expect(vm.forecasts[MetricType.bloodPressure]!.forecast!.points(), hasLength(7)); // FR400_004
      // The prediction in words: the expected level, its likely range and the direction.
      final summary = vm.forecastSummary(MetricType.bloodPressure)!;
      expect(summary, contains('Next 7 days'));
      expect(summary, contains('between 124 and 134'));
      expect(summary, contains('stay about where it is'));
      expect(vm.forecastSummary(MetricType.bloodGlucose), isNull);
      expect(vm.forecasts[MetricType.bloodGlucose]!.insufficient, isTrue); // A1
      expect(analysisRepo.forecasts.single.modelVersion, 'forecast-gbdt-1.0'); // FR400_007
      final HealthAnalysis a = vm.analysis!;
      expect(a.healthScore, 72);
      expect(a.scoreBand, ScoreBand.fair);
      expect(a.factors().first.label, 'Body mass index'); // largest contribution first
      expect(a.riskFor('HYPERTENSION'), 'Moderate');
      expect(a.conditionRisks!['HYPERTENSION']['model_version'], 'analysis-1.0'); // FR400_029
      expect(analysisRepo.analyses, hasLength(1)); // FR400_024
      expect(analysisRepo.anomalyLog, hasLength(1)); // FR400_016
      final entry = log.log.single; // FR600_013
      expect(entry.severity, Severity.high);
      expect(entry.messageBody, contains(Messages.consultProfessional)); // FR600_012
      expect(scheduler.shown.single, startsWith('Health alert'));
      expect(vm.takeHighAlert(), isNotNull); // full-screen warning (FR600_010)
      // Only pseudonymous data leaves the phone (FR400_036).
      expect(jsonEncode(analyseBody), isNot(contains(accountId)));
      expect(jsonEncode(analyseBody), isNot(contains('demo@apths.test')));

      // The same anomaly is not alerted twice.
      await vm.loadAnalysis();
      expect(log.log, hasLength(1));
    });

    test('service down: the last stored score stays and the notice says so (E2, FR400_039)', () async {
      final analysisRepo = FakeAnalysisRepository();
      await analysisRepo.saveAnalysis(HealthAnalysis(
        analysisId: 'a',
        accountId: accountId,
        analysisDate: DateTime(2026, 10, 25),
        healthScore: 66,
        scoreBand: ScoreBand.fair,
        modelVersion: 'analysis-1.0',
      ));
      final api = ApiClient(
        baseUrl: 'http://ai',
        tokenProvider: () => 't',
        httpClient: MockClient((_) async => throw const SocketException('down')),
      );
      final vm = AnalysisViewModel(
        analysisRepo,
        ForecastService(api),
        AnomalyDetectionService(api, analysisRepo),
        RiskAssessmentService(auth, FakeProfileRepository()),
        readings,
        FakeMealRepository(),
        treatments,
        auth,
        null,
        () => now,
      );
      await vm.loadAnalysis();
      expect(vm.analysis!.healthScore, 66);
      expect(vm.notice, Messages.analysisUnavailable);
    });
  });
}
