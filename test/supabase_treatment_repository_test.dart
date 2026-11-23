import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:physical_treatment_and_health_support_system/model/result.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/patient_treatment_plan.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/treatment_plan.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/treatment_repository/supabase_treatment_repository.dart';
import 'package:physical_treatment_and_health_support_system/shared_client/supabase_provider/supabase_provider.dart';

/// The Supabase repository against a stand-in for the REST API: what it sends to patient_plan.
void main() {
  // Elwin's phone, 16 Nov: "value too long for type character varying(20)" on every try at an
  // exercise judged by a trained model, so Continue could not save it.
  test(
    'the model version sent to the database fits its 20-character column',
    () {
      String? fit(String? v) => SupabaseTreatmentRepository.dbModelVersion(v);
      expect(fit(null), isNull);
      expect(fit('rules-1.0'), 'rules-1.0'); // rules only: unchanged
      expect(fit('rules-1.0+shoulder_flexion_v6'), 'rules-1.0+gru-v6');
      expect(fit('rules-1.0+sit_to_stand_v4'), 'rules-1.0+gru-v4');
      expect(fit('rules-1.0+shoulder_abduction_v12'), 'rules-1.0+gru-v12');
      for (final v in [
        'rules-1.0+shoulder_flexion_v6',
        'rules-1.0+hip_abduction_v6',
        'rules-1.0+knee_extension_v4',
        'an-unexpected-and-very-long-version-name',
      ]) {
        expect(fit(v)!.length, lessThanOrEqualTo(20), reason: v);
      }
    },
  );

  final plan = TreatmentPlan.fromJson(
    ((jsonDecode(File('assets/seed/catalogue.json').readAsStringSync())
                    as Map<String, dynamic>)['plans']
                as List)
            .first
        as Map<String, dynamic>,
  );
  final next = PatientTreatmentPlan(
    patientPlanId: 'pp-new',
    accountId: 'acc-1',
    plan: plan,
    selectedAt: DateTime.utc(2026, 10, 24),
  );

  /// Records each request; the insert answers [insertStatus].
  (SupabaseTreatmentRepository, List<http.Request>) repo({
    required int insertStatus,
  }) {
    final sent = <http.Request>[];
    final client = MockClient((req) async {
      sent.add(req);
      if (req.method == 'POST') {
        return insertStatus < 300
            ? http.Response('', insertStatus, request: req)
            : http.Response(
                jsonEncode({
                  'code': '23505',
                  'message': 'duplicate key value',
                  'details': null,
                  'hint': null,
                }),
                insertStatus,
                request: req,
              );
      }
      return http.Response('', 204, request: req);
    });
    final sb = SupabaseClient(
      'http://supabase.test',
      'test-key',
      httpClient: client,
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    return (SupabaseTreatmentRepository(SupabaseProvider(sb)), sent);
  }

  String? statusSent(http.Request r) =>
      (jsonDecode(r.body) as Map<String, dynamic>)['status'] as String?;

  test(
    'a replacement abandons the old plan, then inserts the new one',
    () async {
      final (r, sent) = repo(insertStatus: 201);
      final res = await r.assignPlan(next, replacing: ['pp-old']);
      expect(res.isSuccess, isTrue);
      expect([for (final s in sent) s.method], ['PATCH', 'POST']);
      expect(statusSent(sent.first), 'ABANDONED');
      expect(sent.first.url.query, contains('pp-old'));
    },
  );

  test(
    'a failed insert makes the replaced plan ACTIVE again, so the patient keeps a plan',
    () async {
      final (r, sent) = repo(insertStatus: 409);
      final res = await r.assignPlan(next, replacing: ['pp-old']);
      expect((res as Failure<void>).code, '23505'); // still the insert's error
      expect([for (final s in sent) s.method], ['PATCH', 'POST', 'PATCH']);
      expect(statusSent(sent.last), 'ACTIVE');
      expect(sent.last.url.query, contains('pp-old'));
    },
  );

  test('a failed insert with nothing replaced changes nothing else', () async {
    final (r, sent) = repo(insertStatus: 409);
    final res = await r.assignPlan(next);
    expect(res.isSuccess, isFalse);
    expect([for (final s in sent) s.method], ['POST']);
  });
}
