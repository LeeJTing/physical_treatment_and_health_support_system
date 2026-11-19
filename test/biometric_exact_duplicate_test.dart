import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/biometric_reading.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/biometric_repository/fake_biometric_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/biometric_repository/supabase_biometric_repository.dart';
import 'package:physical_treatment_and_health_support_system/shared_client/supabase_provider/supabase_provider.dart';

void main() {
  final at = DateTime.utc(2026, 11, 19, 17, 40);
  BiometricReading reading(
    MetricType metric,
    DateTime time, {
    double? value,
    String account = 'a',
  }) => BiometricReading(
    readingId: '$account-${metric.db}-${time.microsecondsSinceEpoch}',
    accountId: account,
    metricType: metric,
    primaryValue:
        value ??
        switch (metric) {
          MetricType.bloodPressure => 116,
          MetricType.bloodGlucose => 5.5,
          MetricType.bodyWeight => 65,
        },
    secondaryValue: metric == MetricType.bloodPressure ? 84 : null,
    source: ReadingSource.imported,
    sourceDevice: 'Test watch',
    importedAt: at.add(const Duration(hours: 1)),
    recordedAt: time,
  );

  test(
    'identity scopes account, metric and exact UTC instant, including sub-millisecond times',
    () {
      final first = reading(MetricType.bloodPressure, at);
      expect(
        first.duplicates(reading(MetricType.bloodPressure, at.toLocal())),
        isTrue,
      );
      expect(
        first.duplicates(reading(MetricType.bloodPressure, at, account: 'b')),
        isFalse,
      );
      expect(first.duplicates(reading(MetricType.bloodGlucose, at)), isFalse);
      expect(
        first.duplicates(
          reading(
            MetricType.bloodPressure,
            at.add(const Duration(microseconds: 1)),
          ),
        ),
        isFalse,
      );
      expect(
        first.duplicates(
          reading(MetricType.bloodPressure, at.add(const Duration(seconds: 1))),
        ),
        isFalse,
      );
      expect(
        first.duplicates(
          reading(MetricType.bloodPressure, at.add(const Duration(minutes: 5))),
        ),
        isFalse,
      );
    },
  );

  test(
    'fake imports retain consecutive records for all metrics and retry without changing original import time',
    () async {
      final repo = FakeBiometricRepository();
      final rows = [
        for (final m in MetricType.values) ...[
          reading(m, at),
          reading(m, at.add(const Duration(minutes: 1))),
        ],
      ];
      expect((await repo.insertBatch([...rows, rows.first])).dataOrNull, 6);
      final importTimes = repo.readings.map((r) => r.importedAt).toList();
      expect((await repo.insertBatch(rows)).dataOrNull, 0);
      expect(repo.readings.map((r) => r.importedAt), importTimes);
      expect(
        (await repo.insertBatch([
          reading(MetricType.bloodPressure, at, account: 'b'),
        ])).dataOrNull,
        1,
      );
    },
  );

  test(
    'REST import retains new timestamps without a broad pre-read and preserves stored snapshots on retries',
    () async {
      final persisted = <String, Map<String, dynamic>>{};
      var requests = 0;
      final client = SupabaseClient(
        'http://supabase.test',
        'test-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((r) async {
          requests++;
          expect(r.method, 'POST');
          expect(
            r.url.queryParameters['on_conflict'],
            'account_id,metric_type,recorded_at',
          );
          expect(r.headers['prefer'], contains('resolution=ignore-duplicates'));
          final inserted = <Map<String, dynamic>>[];
          for (final row
              in (jsonDecode(r.body) as List).cast<Map<String, dynamic>>()) {
            final key =
                '${row['account_id']}|${row['metric_type']}|${row['recorded_at']}';
            if (persisted.containsKey(key)) continue;
            persisted[key] = row;
            inserted.add({'reading_id': row['reading_id']});
          }
          return http.Response(
            jsonEncode(inserted),
            201,
            request: r,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      addTearDown(client.dispose);
      final repo = SupabaseBiometricRepository(SupabaseProvider(client));
      final rows = [
        reading(MetricType.bloodPressure, at, value: 115),
        reading(
          MetricType.bloodPressure,
          at.add(const Duration(minutes: 1)),
          value: 116,
        ),
        reading(MetricType.bloodGlucose, at),
        reading(MetricType.bloodGlucose, at.add(const Duration(minutes: 1))),
      ];
      expect((await repo.insertBatch([...rows, rows.first])).dataOrNull, 4);
      final first = Map<String, dynamic>.from(persisted.values.first);
      final retry = BiometricReading.fromJson(
        rows.first.toJson()
          ..['imported_at'] = at.add(const Duration(days: 1)).toIso8601String(),
      );
      expect((await repo.insertBatch([retry, ...rows])).dataOrNull, 0);
      expect(persisted.values.first, first);
      expect(requests, 2);
    },
  );
}
