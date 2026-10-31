// Checks the connection between the app and the AI server on the laptop, through the app's own
// services (the same code the phone runs), endpoint by endpoint.
//
//   dart run tool/check_ai_server.dart http://192.168.1.20:8000
//   dart run tool/check_ai_server.dart https://xxxx.trycloudflare.com --photo C:\path\nasi_lemak.jpg
//   dart run tool/check_ai_server.dart <address> --token <Supabase access token>
//
// Without --token it sends "dev-token", which the server accepts only with DEV_AUTH_BYPASS=true.
// Without --photo it sends a plain test image (the pipeline is checked; no food is expected).
// Exit code 0 when every check passed.
import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'package:physical_treatment_and_health_support_system/core/utils/id_utils.dart';
import 'package:physical_treatment_and_health_support_system/device_platform/local_settings/local_settings.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/anomaly_detection_service/anomaly_detection_service.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/diet_planner_service/diet_planner_service.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/food_recognition_service/food_recognition_service.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/forecast_service/forecast_service.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/server_connection_service/server_connection_service.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/suitability_service/suitability_service.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/biometric_reading.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/health_profile.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/lookups.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/analysis_repository/fake_analysis_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/food_repository/fake_food_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/result.dart';
import 'package:physical_treatment_and_health_support_system/shared_client/api_client/api_client.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty || args.first.startsWith('-')) {
    stderr.writeln('Usage: dart run tool/check_ai_server.dart <server address> [--token T] [--photo file.jpg]');
    exit(64);
  }
  String? opt(String name) {
    final i = args.indexOf(name);
    return i >= 0 && i + 1 < args.length ? args[i + 1] : null;
  }

  final address = ServerConnectionService.normalise(args.first);
  if (address == null) {
    stderr.writeln('Not a server address: ${args.first}');
    exit(64);
  }
  final token = opt('--token') ?? 'dev-token';
  final api = ApiClient(baseUrl: address, tokenProvider: () => token);
  var failed = 0;
  void report(String what, Result r, String Function(dynamic) ok) {
    switch (r) {
      case Success(:final data):
        stdout.writeln('  PASS  $what: ${ok(data)}');
      case Failure(:final message, :final code):
        failed++;
        stdout.writeln('  FAIL  $what: $message (code $code)');
    }
  }

  stdout.writeln('AI server: $address');

  // 1. Reachable at all (no token needed), and which models are loaded.
  final conn = ServerConnectionService(api, MemoryLocalSettings(), defaultAddress: address);
  final health = await conn.test();
  report('GET /health', health, (s) => 'version ${s.version}, ${s.latencyMs} ms, modules ${s.modules}');
  if (health is Failure) {
    stdout.writeln('\nThe server cannot be reached, so the other checks were skipped.');
    exit(1);
  }

  // 2. The login token is accepted (401 means DEV_AUTH_BYPASS=false without --token, or a stale token).
  final foodsRes = await api.get('/foods');
  report('GET /foods (login token)', foodsRes, (d) => '${(d['foods'] as List).length} foods');

  // 3. Health analysis (M400): 20 days of blood pressure for a 61-year-old with hypertension.
  final now = DateTime.now();
  final history = [
    for (var i = 0; i < 20; i++)
      BiometricReading(
        readingId: newId(),
        accountId: 'check',
        metricType: MetricType.bloodPressure,
        primaryValue: 128 + (i % 5) * 2,
        secondaryValue: 82 + (i % 3),
        source: ReadingSource.manual,
        recordedAt: now.subtract(Duration(days: 20 - i)),
      ),
  ];
  final hypertension = LookupSeed.conditions.firstWhere((c) => c.conditionCode == 'HYPERTENSION');
  final profile = HealthProfile(
    profileId: newId(),
    accountId: 'check',
    age: 61,
    gender: Gender.male,
    weightKg: 78,
    heightCm: 170,
    conditions: [hypertension],
    updatedAt: now,
  );
  final limit = profile.generateSafetyLimit();
  final fc = await ForecastService(api).forecast('check', MetricType.bloodPressure, history);
  report('POST /forecast', fc, (f) => '${f.points().length} days, model ${f.modelVersion}');
  final an = await AnomalyDetectionService(api, FakeAnalysisRepository()).analyse(
    accountId: 'check',
    profile: profile,
    limit: limit,
    history: history,
  );
  report('POST /analyse', an, (o) => o.analysis.healthScore == null
      ? 'answered; Health Score withheld as designed for this sample (needs ${o.analysis.missingData.join(', ')})'
      : 'Health Score ${o.analysis.healthScore} (${o.analysis.scoreBand?.name}), ${o.anomalies.length} anomalies');

  // 4. Diet plan (M700) with the catalogue the app ships.
  final foods = FakeFoodRepository.fromJson(File('assets/seed/food_catalogue.json').readAsStringSync());
  final ctx = DietContext(conditions: [hypertension], restrictions: const [], limit: limit);
  final plan = await DietPlannerService(api, foods).generate(
    accountId: 'check',
    ctx: ctx,
    type: PlanType.daily,
    start: now,
  );
  report('POST /plan', plan, (p) => '${p.meals.length} meals, ${p.totalsFor(p.meals.first.planDate).energyKcal.round()} kcal on day 1');

  // 5. Meal photo (M700): prepared on the "phone" exactly as the app does, then recognised.
  final photoPath = opt('--photo');
  final Uint8List original = photoPath != null
      ? File(photoPath).readAsBytesSync()
      : Uint8List.fromList(img.encodeJpg(img.Image(width: 640, height: 480)..clear(img.ColorRgb8(200, 160, 90))));
  final recog = FoodRecognitionService(api, foods);
  final prepared = await recog.prepare(original);
  report('photo check and resize', prepared, (p) => '${p.width} x ${p.height}, ${p.upload.length ~/ 1024} KB');
  if (prepared case Success(:final data)) {
    final sw = Stopwatch()..start();
    final r = await recog.recognise(data, ['HYPERTENSION']);
    sw.stop();
    report('POST /recognise', r, (x) {
      final items = x.items
          .map((i) => '${i.food.foodName} ${(i.confidence * 100).round()}%'
              '${i.confidence < recog.confidenceFloor ? ' (below the 60% floor: the app asks the patient to search)' : ''}')
          .join(', ');
      return '${sw.elapsedMilliseconds} ms, ${items.isEmpty ? 'no food found' : items}, model ${recog.modelVersion}';
    });
  }

  stdout.writeln(failed == 0 ? '\nAll checks passed: the app can use this server.' : '\n$failed check(s) failed.');
  exit(failed == 0 ? 0 : 1);
}
