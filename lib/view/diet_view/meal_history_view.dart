import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:physical_treatment_and_health_support_system/core/constants/app_constants.dart';
import 'package:physical_treatment_and_health_support_system/core/themes/design_tokens.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/meal_log.dart';
import 'package:physical_treatment_and_health_support_system/view/diet_view/widgets/diet_widgets.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/meal_log_view_model/meal_log_view_model.dart';

/// Dietary history filtered by a date range (UC800 A5, FR700_014), with Delete (A5.1, FR700_015,
/// FR700_016) after the confirmation (M6).
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
        content: const Text(Messages.confirmDeleteMeal, style: TextStyle(fontSize: 17)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTokens.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (yes == true) await vm.deleteMeal(m);
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
        title: const Text('Dietary history'),
        backgroundColor: AppTokens.brandDeep,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          OutlinedButton.icon(
            onPressed: () => _range(vm),
            icon: const Icon(Icons.date_range),
            label: Text('${f.day}/${f.month}/${f.year} - ${t.day}/${t.month}/${t.year}'),
          ),
          const SizedBox(height: 12),
          if (vm.isLoading) const Center(child: CircularProgressIndicator()),
          if (!vm.isLoading && vm.history.isEmpty)
            const Text(Messages.noData, style: TextStyle(fontSize: 16, color: AppTokens.inkMuted)),
          for (final e in byDay.entries) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                '${e.key} · ${fmtNum(e.value.fold<double>(0, (a, m) => a + m.totalEnergyKcal))} kcal',
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppTokens.ink),
              ),
            ),
            for (final m in e.value) MealCard(meal: m, onDelete: () => _delete(vm, m)),
          ],
        ],
      ),
    );
  }
}
