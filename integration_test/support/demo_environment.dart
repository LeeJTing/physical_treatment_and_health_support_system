import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:physical_treatment_and_health_support_system/core/constants/app_constants.dart';
import 'package:physical_treatment_and_health_support_system/device_platform/camera_gallery/meal_image_picker.dart';
import 'package:physical_treatment_and_health_support_system/device_platform/health_connect/health_data_source.dart';
import 'package:physical_treatment_and_health_support_system/device_platform/local_settings/local_settings.dart';
import 'package:physical_treatment_and_health_support_system/device_platform/notification_scheduler/notification_scheduler.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/biometric_reading.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/health_profile.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/reminder.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/terms_acceptance.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/analysis_repository/fake_analysis_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/auth_repository/fake_auth_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/biometric_repository/fake_biometric_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/food_repository/fake_food_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/meal_repository/fake_meal_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/notification_repository/fake_notification_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/profile_repository/fake_profile_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/terms_repository/fake_terms_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/treatment_repository/fake_treatment_repository.dart';

/// Per-launch disposable state. No Supabase, real health records or external AI requests.
class DemoEnvironment {
  final auth = FakeAuthRepository();
  final profiles = FakeProfileRepository();
  final notifications = FakeNotificationRepository();
  final terms = FakeTermsRepository();
  final biometrics = FakeBiometricRepository();
  final analysis = FakeAnalysisRepository();
  final meals = FakeMealRepository();
  final settings = MemoryLocalSettings({
    for (final key in ['diet', 'diet_plan', 'tracking', 'health_report', 'reminders']) 'guide_seen_$key': '1',
  });
  final health = FakeHealthDataSource();
  final scheduler = DemoScheduler();
  final photos = DemoPhotos();
  late FakeFoodRepository foods;
  late FakeTreatmentRepository treatments;
  late DemoAiClient ai;
  late String accountId;

  static Future<DemoEnvironment> create({bool signedIn = true}) async {
    final e = DemoEnvironment();
    e.foods = FakeFoodRepository.fromJson(await rootBundle.loadString('assets/seed/food_catalogue.json'));
    e.treatments = FakeTreatmentRepository.fromJson(await rootBundle.loadString('assets/seed/catalogue.json'));
    e.ai = DemoAiClient(e.foods);
    e.accountId = (await e.auth.login('demo@apths.test', 'password123')).dataOrNull!.accountId;
    final now = DateTime.now();
    final profile = HealthProfile(
      profileId: 'e2e-profile',
      accountId: e.accountId,
      age: 60,
      gender: Gender.female,
      weightKg: 65,
      heightCm: 158,
      updatedAt: now,
    );
    await e.profiles.saveProfile(profile, profile.generateSafetyLimit());
    await e.terms.saveAcceptance(
      TermsAcceptance(
        acceptanceId: 'e2e-terms',
        accountId: e.accountId,
        termsVersion: AppConstants.termsVersion,
        acceptedAt: now,
        language: 'en',
        healthDataConsent: true,
        ageGroup: TermsAgeGroup.adult,
      ),
    );
    for (var d = 1; d <= 20; d++) {
      for (final metric in MetricType.values) {
        await e.biometrics.insert(
          BiometricReading(
            readingId: 'seed-${metric.db}-$d',
            accountId: e.accountId,
            metricType: metric,
            primaryValue: switch (metric) {
              MetricType.bloodPressure => 125 + (d % 3).toDouble(),
              MetricType.bloodGlucose => 5.5,
              MetricType.bodyWeight => 65,
            },
            secondaryValue: metric == MetricType.bloodPressure ? 80 : null,
            source: ReadingSource.manual,
            recordedAt: now.subtract(Duration(days: d)),
          ),
        );
      }
    }
    await e.notifications.logNotification(
      NotificationLog(
        notificationId: 'e2e-health-alert',
        accountId: e.accountId,
        notificationType: NotificationType.alert,
        severity: Severity.medium,
        messageBody: 'Demo health note: review your blood pressure trend.',
        deliveryStatus: DeliveryStatus.delivered,
        issuedAt: now.subtract(const Duration(minutes: 10)),
      ),
    );
    if (!signedIn) {
      await e.auth.signOut();
    }
    return e;
  }
}

/// Scripted transport responses exercise production ApiClient/decoders, not model accuracy.
class DemoAiClient extends http.BaseClient {
  final FakeFoodRepository foods;
  final List<String> requests = [];
  bool offline = false;
  bool underfilled = false;
  bool highAlert = false;
  DemoAiClient(this.foods);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final bytes = await request.finalize().toBytes();
    final path = request.url.path;
    requests.add(path);
    if (offline) {
      return _reply({
        'error': {'code': 'offline', 'message': 'Demo server unavailable'},
      }, 503);
    }
    final body = request.headers['content-type']?.contains('application/json') == true && bytes.isNotEmpty
        ? jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>
        : <String, dynamic>{};
    if (path == '/health') {
      return _reply({
        'ok': true,
        'status': 'ok',
        'version': 'e2e-api-fixture',
        'modules': {'food_recognition': 'ready', 'diet_planner': 'ready', 'analysis': 'ready'},
        'recogniser_ready': true,
        'planner_ready': true,
        'analysis_ready': true,
        'catalogue_version': 'food-catalogue-2.0',
        'recogniser_version': 'e2e-fixture',
        'planner_version': 'e2e-fixture',
        'analysis_version': 'e2e-fixture',
      });
    }
    if (path == '/plan/alternatives') return _reply([]);
    if (path == '/recognise') {
      return _reply({
        'confidence': 0.95,
        'is_food': true,
        'model_version': 'e2e-recogniser-fixture',
        'items': [
          {'food_key': 'betik', 'portion_g': 150, 'confidence': 0.95, 'candidates': []},
        ],
      });
    }
    if (path == '/plan') {
      final start = DateTime.parse(body['start_date'] as String);
      final target = ((body['limits'] as Map)['daily_calorie_target'] as num).toDouble();
      return _reply({
        'model_version': 'e2e-planner-fixture',
        'days': [
          for (var i = 0; i < (body['plan_type'] == 'WEEKLY' ? 7 : 1); i++) _day(start.add(Duration(days: i)), target),
        ],
      });
    }
    if (path == '/forecast') {
      final weight = body['metric_type'] == 'BODY_WEIGHT';
      final glucose = body['metric_type'] == 'BLOOD_GLUCOSE';
      final value = weight
          ? 65.0
          : glucose
          ? 5.5
          : 126.0;
      return _reply({
        'model_version': 'e2e-forecast-fixture',
        'input_reading_count': (body['readings'] as List).length,
        'horizon_days': 7,
        'points': [
          for (var i = 1; i <= 7; i++)
            {
              'date': DateTime.now().add(Duration(days: i)).toIso8601String().substring(0, 10),
              'value': value,
              'lower': value - 1,
              'upper': value + 1,
              if (!weight && !glucose) 'secondary_value': 80,
            },
        ],
      });
    }
    if (path == '/analyse') {
      return _reply({
        'model_version': 'e2e-analysis-fixture',
        'health_score': 78,
        'score_band': 'FAIR',
        'period_comparison': 'STABLE',
        'summary_text': 'Demo report based on isolated test readings.',
        'condition_risks': {
          if (((body['profile'] as Map?)?['conditions'] as List? ?? []).contains('HYPERTENSION'))
            'HYPERTENSION': {
              'condition_name': 'Hypertension',
              'risk': 'Moderate',
              'withheld': false,
              'top_factors': ['Blood pressure history', 'Age', 'Body mass index'],
            },
        },
        'factor_contributions': {},
        'missing': [],
        'baselines': {},
        'anomalies': highAlert
            ? [
                {
                  'reading_id': 'e2e-high',
                  'metric_type': 'BLOOD_PRESSURE',
                  'anomaly_type': 'DEVIATION',
                  'severity': 'High',
                  'explanation_text': 'Demo high blood pressure alert. Consult a healthcare professional.',
                },
              ]
            : [],
      });
    }
    // Unscripted endpoints cannot accidentally reach the real server.
    return _reply({
      'error': {'code': 'not_scripted', 'message': 'Endpoint not part of the isolated test contract'},
    }, 501);
  }

  Map<String, dynamic> _day(DateTime day, double target) {
    final choices = <String, List<(String, double)>>{
      'BREAKFAST': [('oats', 125)],
      'LUNCH': [('nasi_putih', 250), ('steamed_fish', 100), ('boiled_vegetables', 100)],
      'DINNER': [('nasi_beras_perang', 250), ('silken_tofu', 100), ('boiled_vegetables', 100)],
      'SNACK': [('betik', 150)],
    };
    // Unknown keys are deliberately checked here instead of silently omitting a fixture food.
    final all = {for (final food in foods.foods) food.foodKey: food};
    final fixed = choices.values
        .expand((x) => x)
        .where((x) => !x.$1.startsWith('nasi_'))
        .fold(0.0, (sum, x) => sum + all[x.$1]!.nutrientsFor(x.$2).energyKcal);
    final riceEnergy = (target * 0.85 - fixed).clamp(100.0, target) / 2;
    return {
      'plan_date': day.toIso8601String().substring(0, 10),
      'meals': [
        for (final entry in choices.entries)
          {
            'meal_slot': entry.key,
            'items': [
              for (final food in entry.value)
                if (!underfilled || entry.key == 'SNACK')
                  {
                    'food_key': food.$1,
                    'portion_g': food.$1.startsWith('nasi_')
                        ? (riceEnergy / all[food.$1]!.energyKcalPer100g * 100).round()
                        : food.$2,
                  },
            ],
          },
      ],
    };
  }

  http.StreamedResponse _reply(Object value, [int status = 200]) => http.StreamedResponse(
    Stream.value(utf8.encode(jsonEncode(value))),
    status,
    headers: {'content-type': 'application/json'},
  );
}

class DemoPhotos implements MealImageSource {
  final Uint8List bytes = Uint8List.fromList(img.encodeJpg(img.Image(width: 400, height: 400)));
  bool cancel = false;
  @override
  Future<Uint8List?> capture() async => cancel ? null : bytes;
  @override
  Future<Uint8List?> pickFromGallery() async => cancel ? null : bytes;
}

class DemoScheduler implements NotificationScheduler {
  final scheduled = <int, String>{};
  @override
  Future<void> init() async {}
  @override
  Future<bool> requestPermission() async => true;
  @override
  Future<bool> isPermitted() async => true;
  @override
  Future<bool> openSettings() async => true;
  @override
  Future<void> scheduleOnce(int id, String title, String body, DateTime at, {String? payload}) async {
    scheduled[id] = '$title|$body|$payload';
  }

  @override
  Future<void> cancel(int id) async => scheduled.remove(id);
  @override
  Future<void> cancelAll() async => scheduled.clear();
  @override
  Stream<String> get taps => const Stream.empty();
  @override
  Future<String?> launchPayload() async => null;
  @override
  Future<bool> canRingOnTime() async => true;
  @override
  Future<void> openExactAlarmSettings() async {}
}
