import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:physical_treatment_and_health_support_system/core/constants/app_constants.dart';
import 'package:physical_treatment_and_health_support_system/core/themes/design_tokens.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/meal_log.dart';
import 'package:physical_treatment_and_health_support_system/view/common/user_guide.dart';
import 'package:physical_treatment_and_health_support_system/view/diet_view/widgets/diet_widgets.dart';
import 'package:physical_treatment_and_health_support_system/view/diet_view/widgets/meal_photo.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/meal_log_view_model/meal_log_view_model.dart';
import 'package:physical_treatment_and_health_support_system/view/common/tidy_text.dart';

/// Dietary history filtered by a date range (UC800 A5, FR700_014), each meal with its photo; a tap
/// opens the meal's details. Delete (A5.1, FR700_015, FR700_016) after the confirmation (M6) takes
/// the meal off the list at once and puts it back if the deletion fails.
class MealHistoryView extends StatefulWidget {
  const MealHistoryView({super.key});

  @override
  State<MealHistoryView> createState() => _MealHistoryViewState();
}

class _MealHistoryViewState extends State<MealHistoryView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final vm = context.read<MealLogViewModel>();
      final now = DateTime.now();
      vm.loadHistory(now.subtract(const Duration(days: 6)), now);
    });
  }

  Future<void> _range(MealLogViewModel vm) async {
    final now = DateTime.now();
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: now,
      initialDateRange: DateTimeRange(start: vm.historyFrom, end: vm.historyTo.isAfter(now) ? now : vm.historyTo),
    );
    if (r != null) await vm.loadHistory(r.start, r.end);
  }

  Future<void> _delete(MealLogViewModel vm, MealLog m) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(tidy(Messages.confirmDeleteMeal), style: const TextStyle(fontSize: 17)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const OneLineText('Cancel', alignment: Alignment.center)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTokens.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const OneLineText('Confirm', alignment: Alignment.center),
          ),
        ],
      ),
    );
    if (yes != true) return;
    final ok = await vm.deleteMeal(m);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? 'Meal deleted.' : (vm.takeMessage() ?? Messages.deletionFailed))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<MealLogViewModel>();
    final byDay = <String, List<MealLog>>{};
    for (final m in vm.history) {
      final d = m.consumedAt;
      byDay.putIfAbsent('${d.day}/${d.month}/${d.year}', () => []).add(m);
    }
    final f = vm.historyFrom, t = vm.historyTo;
    return Scaffold(
      backgroundColor: AppTokens.screenBackground,
      appBar: AppBar(
        title: const OneLineText('Dietary history'),
        backgroundColor: AppTokens.brandDeep,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          OutlinedButton.icon(
            onPressed: () => _range(vm),
            icon: const Icon(Icons.date_range),
            label: OneLineText('${f.day}/${f.month}/${f.year} - ${t.day}/${t.month}/${t.year}'),
          ),
          const SizedBox(height: 12),
          if (vm.isLoading && vm.history.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (vm.isLoading)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: LinearProgressIndicator(color: AppTokens.brandDeepAccent),
            ),
          if (!vm.isLoading && vm.history.isEmpty)
            const EmptyState(
              icon: Icons.history,
              badge: Icons.restaurant,
              title: 'No meals in these dates',
              message: 'Meals you log, with their photos, appear here. Choose other dates above to look further back.',
            ),
          for (final e in byDay.entries) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: OneLineText(
                '${e.key} · ${fmtNum(e.value.fold<double>(0, (a, m) => a + m.totalEnergyKcal))} kcal',
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppTokens.ink),
              ),
            ),
            for (final m in e.value)
              MealCard(
                meal: m,
                photo: MealPhoto(vm: vm, meal: m),
                onTap: () => MealDetailsSheet.show(context, vm, m),
                onDelete: () => _delete(vm, m),
              ),
          ],
        ],
      ),
    );
  }
}
