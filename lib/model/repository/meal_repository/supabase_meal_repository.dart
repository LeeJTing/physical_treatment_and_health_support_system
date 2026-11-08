import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:physical_treatment_and_health_support_system/model/result.dart';
import 'package:physical_treatment_and_health_support_system/shared_client/supabase_provider/supabase_provider.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/diet_plan.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/food_item.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/meal_log.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/suitability_verdict.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/meal_repository/i_meal_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/supabase_guard.dart';

/// Supabase implementation of IMealRepository (Table 4.87). Confirmed meal photographs go to the
/// private storage bucket "meal-images", one folder per account (supabase/migrations
/// 20261026120000_diet_and_analysis.sql).
class SupabaseMealRepository implements IMealRepository {
  static const bucket = 'meal-images';
  static const _foodColumns =
      'food_item(*, food_restriction(dietary_restriction(restriction_code)))';
  final SupabaseProvider _sb;

  /// Photos already downloaded or uploaded in this session, by storage path, so the history does
  /// not download the same photo again.
  final Map<String, Uint8List> _photos = {};

  SupabaseMealRepository(this._sb);

  static FoodItem _food(Map row) {
    final r = Map<String, dynamic>.from(row);
    final tags = ((r['food_restriction'] as List?) ?? const [])
        .map((t) => (t as Map)['dietary_restriction']?['restriction_code'] as String?)
        .whereType<String>()
        .toList();
    return FoodItem.fromJson({...r, 'restrictions': tags});
  }

  /// Inserts the meal, then its items and verdicts; if a child insert fails the meal and the photo
  /// are removed again, so no half-saved meal is left (ASR_04).
  @override
  Future<Result<MealLog>> saveMeal(MealLog m, {Uint8List? image}) => supabaseGuard(() async {
    String? path;
    if (image != null) {
      path = '${m.accountId}/${m.mealId}.jpg';
      await _sb.client.storage
          .from(bucket)
          .uploadBinary(path, image, fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: true));
      _photos[path] = image;
    }
    final saved = m.copyWith(
      imageUri: path,
      items: [for (final i in m.items) i.withMeal(m.mealId)],
    );
    await _sb.from('meal_log').insert(saved.toJson());
    try {
      if (saved.items.isNotEmpty) {
        await _sb.from('meal_item').insert(saved.items.map((i) => i.toJson()).toList());
      }
      final verdicts = [
        for (final i in saved.items)
          for (final v in i.verdicts)
            if (v.isStorable) v.toJson(),
      ];
      if (verdicts.isNotEmpty) await _sb.from('suitability_verdict').insert(verdicts);
    } catch (_) {
      await _sb.from('meal_log').delete().eq('meal_id', m.mealId);
      if (path != null) {
        _photos.remove(path);
        await _sb.client.storage.from(bucket).remove([path]);
      }
      rethrow;
    }
    return saved;
  }, failMessage: 'Unable to save your meal. Please try again.');

  @override
  Future<Result<List<MealLog>>> findMeals(String accountId, DateTime from, DateTime to) =>
      supabaseGuard(() async {
        final rows = await _sb
            .from('meal_log')
            .select('*, meal_item(*, $_foodColumns, suitability_verdict(*))')
            .eq('account_id', accountId)
            .gte('consumed_at', from.toUtc().toIso8601String())
            .lte('consumed_at', to.toUtc().toIso8601String())
            .order('consumed_at', ascending: false);
        return rows.map((r) {
          final items = ((r['meal_item'] as List?) ?? const []).map((i) {
            final im = Map<String, dynamic>.from(i as Map);
            final vs = ((im['suitability_verdict'] as List?) ?? const [])
                .map((v) => SuitabilityVerdict.fromJson(Map<String, dynamic>.from(v as Map)))
                .toList();
            return MealItem.fromJson(im, _food(im['food_item'] as Map), verdicts: vs);
          }).toList();
          return MealLog.fromJson(r, items);
        }).toList();
      });

  /// Downloads a photo from the private bucket; the storage policy only lets the owner read it.
  @override
  Future<Result<Uint8List>> mealPhoto(String imageUri) => supabaseGuard(() async {
    final hit = _photos[imageUri];
    if (hit != null) return hit;
    final bytes = await _sb.client.storage.from(bucket).download(imageUri);
    _photos[imageUri] = bytes;
    return bytes;
  }, failMessage: 'Unable to load the photo of this meal.');

  @override
  Future<Result<void>> deleteMeal(MealLog m) => supabaseGuard(() async {
    await _sb.from('meal_log').delete().eq('meal_id', m.mealId);
    final uri = m.imageUri;
    if (uri != null && uri.isNotEmpty) {
      _photos.remove(uri);
      await _sb.client.storage.from(bucket).remove([uri]);
    }
  });

  @override
  Future<Result<void>> savePlan(DietPlan p) => supabaseGuard(() async {
    await _sb.from('diet_plan').insert(p.toJson());
    try {
      if (p.meals.isNotEmpty) {
        await _sb
            .from('planned_meal')
            .insert([for (final m in p.meals) m.copyWith(dietPlanId: p.dietPlanId).toJson()]);
      }
    } catch (_) {
      await _sb.from('diet_plan').delete().eq('diet_plan_id', p.dietPlanId);
      rethrow;
    }
  });

  @override
  Future<Result<DietPlan?>> planFor(String accountId, PlanType type, DateTime day) =>
      supabaseGuard(() async {
        final d = day.toIso8601String().substring(0, 10);
        final row = await _sb
            .from('diet_plan')
            .select('*, planned_meal(*, $_foodColumns)')
            .eq('account_id', accountId)
            .eq('plan_type', type.db)
            .lte('start_date', d)
            .gte('end_date', d)
            .order('generated_at', ascending: false)
            .limit(1)
            .maybeSingle();
        if (row == null) return null;
        final meals = ((row['planned_meal'] as List?) ?? const []).map((m) {
          final mm = Map<String, dynamic>.from(m as Map);
          return PlannedMeal.fromJson(mm, _food(mm['food_item'] as Map));
        }).toList();
        return DietPlan.fromJson(row, meals);
      });

  /// Replaces the plan's planned meals with the current list and updates the adherence rate.
  @override
  Future<Result<void>> updatePlan(DietPlan p) => supabaseGuard(() async {
    await _sb
        .from('diet_plan')
        .update({'adherence_rate': p.adherenceRate})
        .eq('diet_plan_id', p.dietPlanId);
    final keep = p.meals.map((m) => m.plannedMealId).toList();
    final stale = _sb.from('planned_meal').delete().eq('diet_plan_id', p.dietPlanId);
    await (keep.isEmpty ? stale : stale.not('planned_meal_id', 'in', '(${keep.join(',')})'));
    if (p.meals.isNotEmpty) {
      await _sb
          .from('planned_meal')
          .upsert([for (final m in p.meals) m.copyWith(dietPlanId: p.dietPlanId).toJson()]);
    }
  });
}
