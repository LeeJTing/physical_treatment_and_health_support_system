import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:physical_treatment_and_health_support_system/core/constants/app_constants.dart';
import 'package:physical_treatment_and_health_support_system/core/themes/design_tokens.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/food_item.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/meal_log.dart';
import 'package:physical_treatment_and_health_support_system/view/diet_view/diet_plan_view.dart';
import 'package:physical_treatment_and_health_support_system/view/diet_view/meal_history_view.dart';
import 'package:physical_treatment_and_health_support_system/view/diet_view/meal_result_view.dart';
import 'package:physical_treatment_and_health_support_system/view/diet_view/widgets/diet_widgets.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/analysis_view_model/analysis_view_model.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/diet_plan_view_model/diet_plan_view_model.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/meal_log_view_model/meal_log_view_model.dart';

/// Diet (Table 4.57; Figma "Diet"): the camera action is the most prominent control (UC800 BF-1),
/// the remaining allowance is on the same screen (FR700_039), today's meals carry their verdicts
/// with reasons and safer choices (UC900 BF-4 to BF-7), then the recommendations for the next meal
/// and the daily and weekly plans.
class DietView extends StatefulWidget {
  const DietView({super.key});

  @override
  State<DietView> createState() => _DietViewState();
}

class _DietViewState extends State<DietView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  Future<void> _reload() async {
    await context.read<MealLogViewModel>().load();
    if (!mounted) return;
    await context.read<DietPlanViewModel>().loadRecommendations();
  }

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  /// UC800 BF-4: the image sources (camera, gallery), and manual entry.
  Future<void> _logMeal() async {
    final vm = context.read<MealLogViewModel>();
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera, size: 30),
              title: const Text('Take a photo', style: TextStyle(fontSize: 18)),
              onTap: () => Navigator.pop(ctx, 'camera'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, size: 30),
              title: const Text('Choose from gallery', style: TextStyle(fontSize: 18)),
              onTap: () => Navigator.pop(ctx, 'gallery'),
            ),
            ListTile(
              leading: const Icon(Icons.edit_note, size: 30),
              title: const Text('Enter the food myself', style: TextStyle(fontSize: 18)),
              onTap: () => Navigator.pop(ctx, 'manual'),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    final nav = Navigator.of(context);
    switch (choice) {
      case 'camera':
        final f = vm.captureImage();
        await _openResult(nav, vm, f);
      case 'gallery':
        final f = vm.pickFromGallery();
        await _openResult(nav, vm, f);
      default:
        vm.startManual();
        await _openResult(nav, vm, Future.value());
    }
  }

  Future<void> _openResult(NavigatorState nav, MealLogViewModel vm, Future<void> work) async {
    // The photo is picked first; the result screen opens when there is something to review.
    await work;
    if (!mounted) return;
    final msg = vm.messagePeek;
    if (vm.step == MealStep.idle) {
      if (msg != null) _snack(vm.takeMessage()!);
      return;
    }
    final saved = await nav.push<bool>(
      MaterialPageRoute(
        builder: (_) => ChangeNotifierProvider.value(value: vm, child: const MealResultView()),
      ),
    );
    if (saved == true && mounted) await _afterChange();
  }

  /// A logged meal changes the plan's adherence, the recommendations and the analysis (FR400_030).
  Future<void> _afterChange() async {
    final plan = context.read<DietPlanViewModel>();
    try {
      context.read<AnalysisViewModel>().loadAnalysis();
    } on ProviderNotFoundException {
      // Outside the app shell.
    }
    await plan.loadRecommendations();
  }

  Future<void> _alternatives(MealLogViewModel vm, MealItem i) async {
    final alts = await vm.alternativesFor(i);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Instead of ${i.food.foodName}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              if (alts.isEmpty) const Text('No alternative in the same food group fits your limits.'),
              for (final a in alts) FoodTile(food: a),
              const DietDisclaimer(),
            ],
          ),
        ),
      ),
    );
  }

  void _openPlan(PlanType t) {
    final plan = context.read<DietPlanViewModel>();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChangeNotifierProvider.value(value: plan, child: DietPlanView(type: t)),
      ),
    );
  }

  void _openHistory() {
    final vm = context.read<MealLogViewModel>();
    Navigator.of(context)
        .push(
          MaterialPageRoute<void>(
            builder: (_) => ChangeNotifierProvider.value(value: vm, child: const MealHistoryView()),
          ),
        )
        .then((_) {
          if (mounted) _afterChange();
        });
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<MealLogViewModel>();
    final plan = context.watch<DietPlanViewModel>();
    final top = MediaQuery.paddingOf(context).top;
    final ctx = vm.ctx;
    return ColoredBox(
      color: AppTokens.screenBackground,
      child: RefreshIndicator(
        onRefresh: _reload,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            Container(
              color: AppTokens.brandDeep,
              padding: EdgeInsets.fromLTRB(24, top + 20, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Diet', style: TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  const Text(
                    'Photograph your meal to see its nutrients and whether it suits you.',
                    style: TextStyle(color: AppTokens.onBrandMuted, fontSize: 16),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    height: 64,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTokens.cta,
                        shape: const StadiumBorder(),
                        textStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                      ),
                      onPressed: vm.step == MealStep.recognising ? null : _logMeal,
                      icon: const Icon(Icons.photo_camera, size: 28),
                      label: Text(vm.step == MealStep.recognising ? 'Identifying...' : 'Log Meal'),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(AppTokens.gutter, 16, AppTokens.gutter, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AllowanceCard(
                    consumed: vm.dailyTotals,
                    energyTarget: ctx.dailyEnergyKcal,
                    sodiumLimit: ctx.dailySodiumMg,
                    sugarLimit: ctx.dailySugarG,
                    note: ctx.failSafe ? Messages.dietProfileUnavailable : null,
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      const Expanded(
                        child: Text("Today's meals",
                            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppTokens.ink)),
                      ),
                      TextButton(onPressed: _openHistory, child: const Text('History', style: TextStyle(fontSize: 16))),
                    ],
                  ),
                  if (vm.today.isEmpty)
                    const Text('No meal logged today.', style: TextStyle(fontSize: 16, color: AppTokens.inkMuted))
                  else ...[
                    if (vm.allTodaySuitable)
                      Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: AppTokens.goodContainer, borderRadius: BorderRadius.circular(14)),
                        child: const Text(Messages.allItemsSuitable, style: TextStyle(color: AppTokens.good, fontSize: 15)), // M3
                      ),
                    for (final m in vm.today) MealCard(meal: m, onAlternatives: (i) => _alternatives(vm, i)),
                  ],
                  const SizedBox(height: 16),
                  _recommendations(plan),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _PlanButton(
                          icon: Icons.today,
                          label: "Today's Plan",
                          onTap: () => _openPlan(PlanType.daily),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _PlanButton(
                          icon: Icons.date_range,
                          label: 'Weekly Plan',
                          onTap: () => _openPlan(PlanType.weekly),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const DietDisclaimer(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Meal recommendations for the next meal (UC900 BF-8 to BF-13, A2).
  Widget _recommendations(DietPlanViewModel plan) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppTokens.surface,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: AppTokens.cardBorder),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Suggested for ${plan.nextSlot.label.toLowerCase()}',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppTokens.ink)),
            ),
            IconButton(tooltip: 'Refresh', onPressed: plan.refreshRecommendations, icon: const Icon(Icons.refresh)),
          ],
        ),
        if (plan.recommendations.isEmpty)
          const Text('Nothing fits what is left of today\'s allowance.',
              style: TextStyle(fontSize: 15, color: AppTokens.inkMuted))
        else
          for (final f in plan.recommendations)
            FoodTile(
              food: f,
              onTap: () => _details(f),
              trailing: const Icon(Icons.chevron_right),
            ),
      ],
    ),
  );

  /// The full nutrient breakdown of the selected item (UC900 BF-13).
  void _details(FoodItem f) => showModalBottomSheet<void>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(f.foodName, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
            Text('One serving, ${f.baseServingG.round()} g', style: const TextStyle(color: AppTokens.inkMuted)),
            const SizedBox(height: 14),
            NutrientTable(f.nutrientsFor(f.baseServingG)),
            const DietDisclaimer(),
          ],
        ),
      ),
    ),
  );
}

class _PlanButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _PlanButton({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 60,
    child: FilledButton.icon(
      style: FilledButton.styleFrom(
        backgroundColor: AppTokens.tint,
        foregroundColor: AppTokens.brandDeep,
        shape: const StadiumBorder(),
        textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
      ),
      onPressed: onTap,
      icon: Icon(icon),
      label: Text(label),
    ),
  );
}
