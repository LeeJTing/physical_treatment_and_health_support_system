import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/meal_repository/supabase_meal_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/result.dart';
import 'package:physical_treatment_and_health_support_system/shared_client/supabase_provider/supabase_provider.dart';

void main() {
  test(
    'review loads every overlapping saved plan page with an account filter',
    () async {
      final requests = <http.Request>[];
      final client = SupabaseClient(
        'http://supabase.test',
        'test-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
          requests.add(request);
          final offset = int.parse(
            request.url.queryParameters['offset'] ?? '0',
          );
          final rows = [
            for (var i = 0; i < (offset == 0 ? 200 : 1); i++)
              {
                'diet_plan_id': 'p${offset + i}',
                'account_id': 'a',
                'safety_limit_id': 's',
                'plan_type': 'WEEKLY',
                'start_date': '2026-11-16',
                'end_date': '2026-11-22',
                'generated_at': '2026-11-15T08:00:00Z',
                'model_version': 'fixture',
                'planned_meal': i == 0 && offset == 0
                    ? [
                        {
                          'planned_meal_id': 'pm',
                          'plan_date': '2026-11-16',
                          'meal_slot': 'LUNCH',
                          'portion_size_g': 100,
                          'energy_kcal': 77,
                          'sodium_mg': 9,
                          'sugar_g': 8,
                          'food_item': {
                            'food_id': 'rice',
                            'food_key': 'rice',
                            'food_name': 'Rice',
                            'food_category': 'Rice',
                            'base_serving_g': 100,
                            'energy_kcal_per_100g': 130,
                            'food_restriction': [],
                          },
                        },
                      ]
                    : [],
              },
          ];
          return http.Response(
            jsonEncode(rows),
            200,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      addTearDown(client.dispose);
      final result = await SupabaseMealRepository(
        SupabaseProvider(client),
      ).plansForPeriod('a', DateTime(2026, 11, 9), DateTime(2026, 11, 22));
      expect(result.dataOrNull, hasLength(201));
      expect(result.dataOrNull!.first.meals.single.energyKcal, 77);
      expect(result.dataOrNull!.first.meals.single.food.foodName, 'Rice');
      expect(requests, hasLength(2));
      for (final r in requests) {
        expect(r.url.path, '/rest/v1/diet_plan');
        expect(r.url.queryParameters['account_id'], 'eq.a');
        expect(r.url.queryParameters['start_date'], 'lte.2026-11-22');
        expect(r.url.queryParameters['end_date'], 'gte.2026-11-09');
        expect(
          r.url.queryParameters['order'],
          'start_date.desc.nullslast,generated_at.desc.nullslast,diet_plan_id.asc.nullslast',
        );
        expect(r.url.queryParameters['limit'], '200');
      }
      expect(requests.last.url.queryParameters['offset'], '200');
    },
  );
  test('a failed query withholds comparison plans', () async {
    final client = SupabaseClient(
      'http://supabase.test',
      'test-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient(
        (r) async => http.Response(
          '{"message":"offline","code":"offline"}',
          503,
          request: r,
          headers: {'content-type': 'application/json'},
        ),
      ),
    );
    addTearDown(client.dispose);
    final result = await SupabaseMealRepository(
      SupabaseProvider(client),
    ).plansForPeriod('a', DateTime(2026, 11, 9), DateTime(2026, 11, 22));
    expect(result, isA<Failure>());
    expect(result.dataOrNull, isNull);
  });
}
