import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:physical_treatment_and_health_support_system/core/base/ui_state.dart';
import 'package:physical_treatment_and_health_support_system/core/constants/app_constants.dart';
import 'package:physical_treatment_and_health_support_system/core/routes/routes.dart';
import 'package:physical_treatment_and_health_support_system/core/themes/design_tokens.dart';
import 'package:physical_treatment_and_health_support_system/data/models/treatment_plan.dart';
import 'package:physical_treatment_and_health_support_system/features/planning/model/recommendation.dart';
import 'package:physical_treatment_and_health_support_system/features/planning/viewmodel/planning_view_model.dart';
import 'package:physical_treatment_and_health_support_system/features/planning/widgets/plan_card.dart';
import 'package:physical_treatment_and_health_support_system/features/planning/widgets/planning_widgets.dart';

/// Recommended plans page (UI Design "Recommended Treatment Page"): the top
/// three plans with View details / Select, and Reject all plans (UC400).
class RecommendedPlansView extends StatelessWidget {
  const RecommendedPlansView({super.key});

  void _goHome(BuildContext context) =>
      Navigator.of(context).popUntil((r) => r.settings.name == Routes.home || r.isFirst);

  /// Exit without choosing (FR500_16).
  void _exit(BuildContext context) {
    context.read<PlanningViewModel>().rejectAll();
    Navigator.of(context).pop();
  }

  Future<void> _select(BuildContext context, TreatmentPlan plan) async {
    final vm = context.read<PlanningViewModel>();
    final messenger = ScaffoldMessenger.of(context);
    if (await vm.select(plan)) {
      messenger.showSnackBar(const SnackBar(content: Text(Messages.planSaved))); // FR500_10
      if (context.mounted) _goHome(context);
    } else if (vm.saving case UiError(:final message)) {
      messenger.showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _rejectAll(BuildContext context) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: const Text(Messages.confirmReject, style: TextStyle(fontSize: 17, color: AppTokens.text)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppTokens.danger),
            child: const Text('Yes, reject all'),
          ),
        ],
      ),
    );
    if (yes == true && context.mounted) {
      context.read<PlanningViewModel>().rejectAll(); // FR500_12
      _goHome(context); // FR500_13
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<PlanningViewModel>();
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _exit(context);
      },
      child: Scaffold(
        backgroundColor: AppTokens.background,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, AppTokens.gutter, 0),
                child: PlanningHeader(
                  title: 'Recommended plans',
                  subtitle: 'Based on your health profile',
                  onBack: () => _exit(context),
                ),
              ),
              Expanded(
                child: switch (vm.recommendation) {
                  Idle() || Loading() => const _Loading(),
                  UiError(:final message) => _Problem(
                      message: message,
                      actionLabel: 'Try again',
                      onAction: vm.retry,
                    ),
                  UiSuccess(:final data) when data.plans.isEmpty => _Problem(
                      message: Messages.conditionNotMet, // FR500_14
                      actionLabel: 'Back to planning',
                      onAction: () => _exit(context),
                    ),
                  UiSuccess(:final data) => _PlanList(
                      recommendation: data,
                      notice: vm.notice,
                      busy: vm.saving is Loading,
                      onDetails: (p) => showPlanDetails(context, p),
                      onSelect: (p) => _select(context, p),
                      onRejectAll: () => _rejectAll(context),
                    ),
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlanList extends StatelessWidget {
  final Recommendation recommendation;
  final String? notice;
  final bool busy;
  final void Function(TreatmentPlan) onDetails;
  final void Function(TreatmentPlan) onSelect;
  final VoidCallback onRejectAll;

  const _PlanList({
    required this.recommendation,
    required this.notice,
    required this.busy,
    required this.onDetails,
    required this.onSelect,
    required this.onRejectAll,
  });

  @override
  Widget build(BuildContext context) {
    final plans = recommendation.plans;
    return ListView(
      padding: const EdgeInsets.fromLTRB(AppTokens.gutter, AppTokens.gutter, AppTokens.gutter, 24),
      children: [
        if (notice != null) ...[NoticeBanner(notice!, warning: true), const SizedBox(height: AppTokens.gap)],
        if (recommendation.status == RecommendationStatus.onlyOne) ...[
          const NoticeBanner(Messages.onlyOnePlan), // FR500_15
          const SizedBox(height: AppTokens.gap),
        ],
        for (var i = 0; i < plans.length; i++) ...[
          PlanCard(
            plan: plans[i],
            best: i == 0,
            busy: busy,
            onDetails: () => onDetails(plans[i]),
            onSelect: () => onSelect(plans[i]),
          ),
          const SizedBox(height: AppTokens.gap),
        ],
        const SizedBox(height: 4),
        TokenButton(label: 'Reject all plans', color: AppTokens.danger, onPressed: busy ? null : onRejectAll),
      ],
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) => const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: AppTokens.primary),
            SizedBox(height: 16),
            Text('Finding the most suitable plans for you...',
                style: TextStyle(fontSize: 15, color: AppTokens.textMuted)),
          ],
        ),
      );
}

class _Problem extends StatelessWidget {
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  const _Problem({required this.message, required this.actionLabel, required this.onAction});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(AppTokens.gutter),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            NoticeBanner(message, warning: true),
            const SizedBox(height: AppTokens.gutter),
            TokenButton(label: actionLabel, color: AppTokens.primary, onPressed: onAction),
          ],
        ),
      );
}
