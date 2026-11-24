import 'package:flutter/material.dart';
import 'package:physical_treatment_and_health_support_system/view/common/insights_surface.dart';
import 'package:provider/provider.dart';
import 'package:physical_treatment_and_health_support_system/core/themes/design_tokens.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/food_item.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/meal_log.dart';
import 'package:physical_treatment_and_health_support_system/view/diet_view/food_search_sheet.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/health_insights_view_model/meal_simulation_view_model.dart';

class MealSimulationView extends StatelessWidget {
  final Future<List<FoodItem>> Function(String) search;
  const MealSimulationView({super.key, required this.search});
  Future<FoodItem?> pick(BuildContext context, MealSimulationViewModel vm) =>
      FoodSearchSheet.show(
        context,
        title: 'Choose a suitable food',
        search: (s) async => (await search(s)).where(vm.suitable).toList(),
      );
  Future<void> grams(
    BuildContext context,
    MealSimulationViewModel vm,
    MealItem item,
  ) async {
    var gramsText = item.portionSizeG.toStringAsFixed(1);
    String? error;
    await showDialog<void>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          backgroundColor: AppTokens.surface,
          title: Text('${item.food.foodName} portion'),
          content: TextFormField(
            key: const ValueKey('simulation-grams'),
            initialValue: gramsText,
            onChanged: (value) => gramsText = value,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Total grams',
              errorText: error,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: InsightsSurface.primaryButtonStyle,
              onPressed: () {
                if (vm.resize(item, gramsText)) {
                  Navigator.pop(c);
                } else {
                  set(() => error = vm.errorMessage);
                }
              },
              child: const Text('Update'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<MealSimulationViewModel>(), r = vm.result;
    Widget box(Widget child) => Card(
      elevation: 0,
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: AppTokens.gap),
      child: Padding(padding: const EdgeInsets.all(16), child: child),
    );
    final rows = [
      ('Energy', 'kcal', r.original.energyKcal, r.proposed.energyKcal),
      ('Sodium', 'mg', r.original.sodiumMg, r.proposed.sodiumMg),
      ('Free sugars', 'g', r.original.sugarG, r.proposed.sugarG),
      ('Protein', 'g', r.original.proteinG, r.proposed.proteinG),
      ('Carbohydrate', 'g', r.original.carbG, r.proposed.carbG),
      ('Fat', 'g', r.original.fatG, r.proposed.fatG),
    ];
    return InsightsSurface(
      child: Scaffold(
        backgroundColor: AppTokens.screenBackground,
        appBar: AppBar(
          title: const Text('Meal change simulator'),
          backgroundColor: AppTokens.brandDeep,
          foregroundColor: Colors.white,
          actions: [
            IconButton(
              tooltip: 'Reset simulation',
              onPressed: vm.reset,
              icon: const Icon(Icons.restart_alt),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(AppTokens.gutter),
          children: [
            box(
              const Text(
                'Try food swaps and portion changes before saving. This preview calculates nutrition; it does not predict a glucose or blood pressure response. Your meal stays unchanged until you choose Use in meal draft.',
              ),
            ),
            if (vm.errorMessage != null)
              Text(
                vm.errorMessage!,
                style: const TextStyle(color: AppTokens.onDanger),
              ),
            for (final item in vm.proposed)
              box(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.food.foodName,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                    Text(
                      '${item.portionSizeG.toStringAsFixed(1)} g · ${item.energyKcal.round()} kcal',
                    ),
                    Wrap(
                      spacing: 8,
                      children: [
                        TextButton.icon(
                          onPressed: () => grams(context, vm, item),
                          icon: const Icon(Icons.scale),
                          label: const Text('Edit grams'),
                        ),
                        TextButton.icon(
                          onPressed: () async {
                            final food = await pick(context, vm);
                            if (food != null) vm.replace(item, food);
                          },
                          icon: const Icon(Icons.swap_horiz),
                          label: const Text('Try replacement'),
                        ),
                        IconButton(
                          tooltip:
                              'Remove ${item.food.foodName} from simulation',
                          onPressed: () => vm.remove(item),
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            OutlinedButton.icon(
              onPressed: () async {
                final food = await pick(context, vm);
                if (food != null) vm.add(food);
              },
              icon: const Icon(Icons.add),
              label: const Text('Try another food'),
            ),
            const SizedBox(height: 14),
            box(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Original vs proposed',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  for (final row in rows)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${row.$1}: ${row.$3.toStringAsFixed(1)} to ${row.$4.toStringAsFixed(1)} ${row.$2}',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          Text(
                            'Change: ${row.$4 - row.$3 >= 0 ? '+' : ''}${(row.$4 - row.$3).toStringAsFixed(1)} ${row.$2}',
                          ),
                          LinearProgressIndicator(
                            value:
                                (row.$4 /
                                        (row.$3 > row.$4 ? row.$3 : row.$4)
                                            .clamp(1, double.infinity))
                                    .clamp(0, 1),
                            backgroundColor: const Color(0xFFD6E4EE),
                            color: AppTokens.brandDeep,
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            box(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Today after this proposal',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const Text(
                    'Includes food already logged today plus the proposed meal, counted once.',
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${r.afterDay.energyKcal.round()} / ${vm.context.dailyEnergyKcal.round()} kcal',
                  ),
                  Text(
                    '${r.afterDay.sodiumMg.round()} / ${vm.context.dailySodiumMg.round()} mg sodium',
                  ),
                  Text(
                    '${r.afterDay.sugarG.toStringAsFixed(1)} / ${vm.context.dailySugarG.toStringAsFixed(1)} g free sugars',
                  ),
                  Text(
                    'Remaining: ${r.remaining.energyKcal.round()} kcal · ${r.remaining.sodiumMg.round()} mg sodium · ${r.remaining.sugarG.toStringAsFixed(1)} g free sugars',
                  ),
                ],
              ),
            ),
            if (r.warnings.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTokens.dangerContainer,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Review before using',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    for (final w in r.warnings)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(w),
                      ),
                  ],
                ),
              ),
          ],
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton(
              style: InsightsSurface.primaryButtonStyle,
              key: const ValueKey('apply-meal-simulation'),
              onPressed: r.items.isEmpty
                  ? null
                  : () async {
                      if (r.warnings.isNotEmpty) {
                        final yes = await showDialog<bool>(
                          context: context,
                          builder: (c) => AlertDialog(
                            backgroundColor: AppTokens.surface,
                            title: const Text(
                              'Use this proposal in your draft?',
                            ),
                            content: const Text(
                              'Some foods, portions or daily totals have warnings. They remain highlighted when you review and log what you actually eat.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(c, false),
                                child: const Text('Keep exploring'),
                              ),
                              FilledButton(
                                style: InsightsSurface.primaryButtonStyle,
                                onPressed: () => Navigator.pop(c, true),
                                child: const Text('Use proposal'),
                              ),
                            ],
                          ),
                        );
                        if (yes != true || !context.mounted) return;
                      }
                      Navigator.pop(context, r.items);
                    },
              child: const Text('Use in meal draft'),
            ),
          ),
        ),
      ),
    );
  }
}
