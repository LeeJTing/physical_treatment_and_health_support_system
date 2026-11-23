import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/recovery_check_in.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/recovery_repository/supabase_recovery_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/result.dart';
import 'package:physical_treatment_and_health_support_system/shared_client/supabase_provider/supabase_provider.dart';

void main() {
  RecoveryCheckIn value({int pain = 3}) => RecoveryCheckIn(
    checkInId: 'entry',
    accountId: 'owner',
    patientPlanId: 'plan',
    date: DateTime(2026, 11, 19),
    updatedAt: DateTime(2026, 11, 20),
    pain: pain,
    stiffness: 2,
    difficulty: 2,
  );
  test(
    'recovery queries are account scoped and edits upsert one plan/date',
    () async {
      final requests = <http.Request>[];
      final client = SupabaseClient(
        'http://supabase.test',
        'test-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((r) async {
          requests.add(r);
          return http.Response(
            r.method == 'GET' ? '[]' : '',
            r.method == 'GET' ? 200 : 204,
            request: r,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      addTearDown(client.dispose);
      final repo = SupabaseRecoveryRepository(SupabaseProvider(client));
      expect(
        (await repo.findBetween(
          'owner',
          DateTime(2026, 11, 1),
          DateTime(2026, 11, 20),
        )).isSuccess,
        isTrue,
      );
      expect((await repo.save(value())).isSuccess, isTrue);
      expect((await repo.delete('owner', 'entry')).isSuccess, isTrue);
      expect(requests.first.url.queryParameters['account_id'], 'eq.owner');
      expect(
        requests.first.url.queryParameters['check_in_date'],
        anyOf('gte.2026-11-01', 'lte.2026-11-20'),
      );
      expect(
        requests[1].url.queryParameters['on_conflict'],
        'account_id,patient_plan_id,check_in_date',
      );
      expect(jsonDecode(requests[1].body)['account_id'], 'owner');
      expect(jsonDecode(requests[1].body).containsKey('updated_at'), isFalse);
      expect(requests.last.url.queryParameters['account_id'], 'eq.owner');
      expect(requests.last.url.queryParameters['check_in_id'], 'eq.entry');
    },
  );
  test(
    'access failures and invalid scores return failure without throwing',
    () async {
      var requests = 0;
      final client = SupabaseClient(
        'http://supabase.test',
        'test-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((r) async {
          requests++;
          return http.Response(
            jsonEncode({'code': '42501', 'message': 'raw private denial'}),
            403,
            request: r,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      addTearDown(client.dispose);
      final repo = SupabaseRecoveryRepository(SupabaseProvider(client));
      expect(await repo.save(value(pain: 11)), isA<Failure>());
      expect(requests, 0);
      final result = await repo.save(value());
      expect(result, isA<Failure>());
      expect((result as Failure).message, contains('not saved'));
      expect(result.message, isNot(contains('raw private')));
    },
  );
}
