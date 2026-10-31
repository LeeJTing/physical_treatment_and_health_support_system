import 'package:physical_treatment_and_health_support_system/model/result.dart';
import 'package:physical_treatment_and_health_support_system/shared_client/supabase_provider/supabase_provider.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/food_item.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/food_repository/i_food_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/supabase_guard.dart';

/// Supabase implementation of IFoodRepository (Table 4.86). The catalogue (about 200 rows) is read
/// once with its restriction tags and kept in memory: it changes only with a new seed.
class SupabaseFoodRepository implements IFoodRepository {
  final SupabaseProvider _sb;
  List<FoodItem>? _cache;

  SupabaseFoodRepository(this._sb);

  Future<List<FoodItem>> _load() async {
    final c = _cache;
    if (c != null) return c;
    final rows = await _sb
        .from('food_item')
        .select('*, food_restriction(dietary_restriction(restriction_code))')
        .order('food_name');
    final foods = rows.map((r) {
      final tags = ((r['food_restriction'] as List?) ?? const [])
          .map((t) => (t as Map)['dietary_restriction']?['restriction_code'] as String?)
          .whereType<String>()
          .toList();
      return FoodItem.fromJson({...r, 'restrictions': tags});
    }).toList();
    return _cache = foods;
  }

  @override
  Future<Result<List<FoodItem>>> all() => supabaseGuard(_load);

  @override
  Future<Result<List<FoodItem>>> search(String term) =>
      supabaseGuard(() async => searchFoods(await _load(), term));

  @override
  Future<Result<FoodItem?>> byId(String foodId) => supabaseGuard(
    () async => (await _load()).where((f) => f.foodId == foodId).firstOrNull,
  );

  @override
  Future<Result<FoodItem?>> byKey(String foodKey) => supabaseGuard(
    () async => (await _load()).where((f) => f.foodKey == foodKey).firstOrNull,
  );

  @override
  Future<Result<List<String>>> restrictionsFor(String foodId) => supabaseGuard(
    () async =>
        (await _load()).where((f) => f.foodId == foodId).firstOrNull?.restrictionCodes ??
        const <String>[],
  );

  @override
  Future<Result<List<FoodItem>>> alternativesTo(FoodItem f, List<String> avoidCodes) =>
      supabaseGuard(
        () async => (await _load())
            .where(
              (g) =>
                  g.foodId != f.foodId &&
                  g.foodCategory == f.foodCategory &&
                  !g.restrictionCodes.any(avoidCodes.contains),
            )
            .toList(),
      );
}
