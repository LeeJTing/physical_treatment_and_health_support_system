import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/biometric_reading.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/biometric_repository/supabase_biometric_repository.dart';
import 'package:physical_treatment_and_health_support_system/shared_client/supabase_provider/supabase_provider.dart';
import 'package:physical_treatment_and_health_support_system/model/result.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final at = DateTime(2026, 11, 19, 12);
  BiometricReading reading() => BiometricReading(
    readingId: 'reading',
    accountId: 'account',
    metricType: MetricType.bodyWeight,
    primaryValue: 65,
    recordedAt: at.subtract(const Duration(days: 1)),
    source: ReadingSource.imported,
    importedAt: at,
  );

  test('import time survives storage without entering analysis inputs; legacy time remains unknown', () {
    final r = reading();
    expect(BiometricReading.fromJson(r.toJson()).importedAt, at);
    expect(r.toAnalysisJson().containsKey('imported_at'), isFalse);
    final legacy = r.toJson()..remove('imported_at');
    expect(BiometricReading.fromJson(legacy).importedAt, isNull);
  });

  for (final inserted in [0, 1]) {
    test('batch reports $inserted rows actually returned by the database', () async {
      final requests = <http.Request>[];
      final client = SupabaseClient(
        'https://isolated.supabase.co',
        'test-key',
        httpClient: MockClient((request) async {
          requests.add(request);
          if (request.method == 'GET') {
            return http.Response('[]', 200, request: request, headers: {'content-type': 'application/json'});
          }
          expect(request.url.queryParameters['select'], 'reading_id');
          expect(
            request.headers.entries.where((e) => e.key.toLowerCase() == 'prefer').single.value,
            contains('resolution=ignore-duplicates'),
          );
          final payload = (jsonDecode(request.body) as List).single as Map;
          expect(payload['imported_at'], at.toUtc().toIso8601String());
          return http.Response(
            inserted == 0 ? '[]' : '[{"reading_id":"reading"}]',
            201,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      addTearDown(client.dispose);
      final result = await SupabaseBiometricRepository(SupabaseProvider(client)).insertBatch([reading()]);
      expect(
        result.dataOrNull,
        inserted,
        reason: result is Failure<int> ? '${result.cause} (requests: ${requests.length})' : null,
      );
      expect(requests.map((r) => r.method), ['POST']);
    });
  }
}
