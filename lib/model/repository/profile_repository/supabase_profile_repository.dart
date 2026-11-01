import 'package:supabase_flutter/supabase_flutter.dart'
    show PostgrestException, PostgrestTransformBuilder;

import 'package:physical_treatment_and_health_support_system/model/result.dart';
import 'package:physical_treatment_and_health_support_system/core/constants/app_constants.dart';
import 'package:physical_treatment_and_health_support_system/shared_client/supabase_provider/supabase_provider.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/health_profile.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/lookups.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/safety_limit.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/profile_repository/i_profile_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/supabase_guard.dart';

/// health_profile, its three declaration lists and safety_limit (Table 4.59).
/// RLS limits every row to the signed-in patient (owns_profile for the child tables).
class SupabaseProfileRepository implements IProfileRepository {
  final SupabaseProvider _sb;

  SupabaseProfileRepository(this._sb);

  /// The profile with its lists; [conditionColumns] adds the patient's answers
  /// per condition (migration 20261011130000).
  PostgrestTransformBuilder<Map<String, dynamic>?> _profileQuery(
    String accountId,
    String conditionColumns,
  ) => _sb
      .from('health_profile')
      .select(
        '*, profile_condition($conditionColumns health_condition(*)), '
        'profile_limitation(physical_limitation(*)), '
        'profile_restriction(dietary_restriction(*))',
      )
      .eq('account_id', accountId)
      .maybeSingle();

  static List<T> _nested<T>(
    Object? rows,
    String key,
    T Function(Map<String, dynamic>) parse,
  ) => [
    for (final r in (rows as List?) ?? const [])
      if ((r as Map<String, dynamic>)[key] != null)
        parse(r[key] as Map<String, dynamic>),
  ];

  @override
  Future<Result<HealthProfile?>> getProfile(
    String accountId,
  ) => supabaseGuard(() async {
    Map<String, dynamic>? row;
    try {
      row = await _profileQuery(accountId, 'is_controlled, note,');
    } on PostgrestException {
      // Before migration 20261011130000 there are no answers: all controlled.
      row = await _profileQuery(accountId, '');
    }
    if (row == null) return null;
    return HealthProfile.fromJson(
      row,
      conditions: [
        for (final pc in ((row['profile_condition'] as List?) ?? const [])
            .cast<Map<String, dynamic>>())
          if (pc['health_condition'] case final Map<String, dynamic> h)
            HealthCondition.fromJson(h).withStatus(
              controlled: pc['is_controlled'] as bool? ?? true,
              note: pc['note'] as String?,
            ),
      ],
      limitations: _nested(
        row['profile_limitation'],
        'physical_limitation',
        PhysicalLimitation.fromJson,
      ),
      restrictions: _nested(
        row['profile_restriction'],
        'dietary_restriction',
        DietaryRestriction.fromJson,
      ),
    );
  }, failMessage: Messages.healthInfoFailed);

  /// Writes in a fixed order: profile, then its lists, then the new safety limit
  /// (FR100_053, FR100_057). Supabase's REST API has no multi-statement
  /// transaction from the client, so a failure part-way reports
  /// [Messages.dbUnavailable]; saving again rewrites every step from scratch.
  @override
  Future<Result<void>> saveProfile(
    HealthProfile p,
    SafetyLimit limit,
  ) => supabaseGuard(() async {
    final saved = await _sb
        .from('health_profile')
        .upsert({
          ...p.toJson(),
          'version': p.version + 1,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }, onConflict: 'account_id')
        .select('profile_id')
        .single();
    final profileId = saved['profile_id'] as String;

    // Conditions with the patient's answers (11 Oct).
    await _sb.from('profile_condition').delete().eq('profile_id', profileId);
    final conditionRows = [
      for (final c in p.conditions)
        {
          'profile_id': profileId,
          'condition_id': c.conditionId,
          'is_controlled': c.controlled,
          'note': c.note,
        },
    ];
    if (conditionRows.isNotEmpty) {
      try {
        await _sb.from('profile_condition').insert(conditionRows);
      } on PostgrestException {
        // Before migration 20261011130000 the answers cannot be stored yet.
        await _sb.from('profile_condition').insert([
          for (final r in conditionRows)
            {'profile_id': r['profile_id'], 'condition_id': r['condition_id']},
        ]);
      }
    }
    for (final (table, column, ids) in [
      (
        'profile_limitation',
        'limitation_id',
        p.limitations.map((l) => l.limitationId),
      ),
      (
        'profile_restriction',
        'restriction_id',
        p.restrictions.map((r) => r.restrictionId),
      ),
    ]) {
      await _sb.from(table).delete().eq('profile_id', profileId);
      final rows = [
        for (final id in ids) {'profile_id': profileId, column: id},
      ];
      if (rows.isNotEmpty) await _sb.from(table).insert(rows);
    }

    // Only one current limit per profile (unique partial index): retire the old one first.
    await _sb
        .from('safety_limit')
        .update({'is_current': false})
        .eq('profile_id', profileId)
        .eq('is_current', true);
    await _sb.from('safety_limit').insert({
      ...limit.toJson(),
      'profile_id': profileId,
      'is_current': true,
    });
  }, failMessage: Messages.profileSaveFailed);

  @override
  Future<Result<SafetyLimit?>> getCurrentSafetyLimit(String profileId) =>
      supabaseGuard(() async {
        final row = await _sb
            .from('safety_limit')
            .select()
            .eq('profile_id', profileId)
            .eq('is_current', true)
            .maybeSingle();
        return row == null ? null : SafetyLimit.fromJson(row);
      });

  @override
  Future<Result<List<HealthCondition>>> getConditions() => supabaseGuard(
    () async =>
        (await _sb.from('health_condition').select().order('condition_id'))
            .map(HealthCondition.fromJson)
            .toList(),
  );

  @override
  Future<Result<List<PhysicalLimitation>>> getLimitations() => supabaseGuard(
    () async =>
        (await _sb.from('physical_limitation').select().order('limitation_id'))
            .map(PhysicalLimitation.fromJson)
            .toList(),
  );

  @override
  Future<Result<List<DietaryRestriction>>> getRestrictions() => supabaseGuard(
    () async =>
        (await _sb.from('dietary_restriction').select().eq('is_active', true).order('food_group').order('restriction_id'))
            .map(DietaryRestriction.fromJson)
            .toList(),
  );
}
