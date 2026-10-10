import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:physical_treatment_and_health_support_system/viewmodel/ui_state.dart';
import 'package:physical_treatment_and_health_support_system/core/constants/app_constants.dart';
import 'package:physical_treatment_and_health_support_system/core/routes/routes.dart';
import 'package:physical_treatment_and_health_support_system/core/themes/design_tokens.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/treatment_plan.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/plan_rules/plan_rules.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/patient_treatment_plan.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/recommendation_service/recommendation.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/planning_view_model/planning_view_model.dart';
import 'package:physical_treatment_and_health_support_system/view/planning_view/widgets/plan_card.dart';
import 'package:physical_treatment_and_health_support_system/view/planning_view/widgets/planning_widgets.dart';

/// Recommended plans page (UI Design "Recommended Treatment Page"): the top
/// three plans with View details / Select, and Reject all plans (UC400).
class RecommendedPlansView extends StatelessWidget {
  const RecommendedPlansView({super.key});

  void _goHome(BuildContext context) => Navigator.of(
    context,
  ).popUntil((r) => r.settings.name == Routes.home || r.isFirst);

  /// Exit without choosing (FR500_16).
  void _exit(BuildContext context) {
    context.read<PlanningViewModel>().rejectAll();
    Navigator.of(context).pop();
  }

  Future<void> _select(BuildContext context, TreatmentPlan plan) async {
    final vm = context.read<PlanningViewModel>();
    final messenger = ScaffoldMessenger.of(context);
    final issues = vm.issuesFor(plan);
    // 1. Anything that blocks: explain and stop.
    final blocks = [
      for (final i in issues)
        if (i.level == PlanIssueLevel.block) i,
    ];
    if (blocks.isNotEmpty) {
      await _explain(context, 'You cannot add ${plan.planName}', blocks);
      return;
    }
    // 2. Plans to stop for it: the plan being eased, clashes (same area and
    // goal), then the risk cap.
    final replacing = [
      ?vm.easingFrom,
      for (final i in issues)
        if (i.code == 'clash' && i.patientPlanId != null) i.patientPlanId!,
    ];
    final capIssue = issues.where((i) => i.code == 'risk_cap').firstOrNull;
    if (capIssue != null) {
      final pick = await _pickPlanToStop(context, capIssue.message, [
        for (final a in vm.activePlans)
          if (!replacing.contains(a.patientPlanId)) a,
      ]);
      if (pick == null || !context.mounted) return;
      replacing.add(pick);
    }
    // 3. With other plans running, always confirm and show what to know.
    if (vm.activePlans.isNotEmpty) {
      final stopping = [
        for (final a in vm.activePlans)
          if (replacing.contains(a.patientPlanId)) a,
      ];
      final yes = await _confirm(context, plan, stopping, [
        for (final i in issues)
          if (i.level != PlanIssueLevel.block && i.code != 'risk_cap') i,
      ]);
      if (yes != true || !context.mounted) return;
    }
    if (await vm.select(plan, replacing: replacing)) {
      messenger.showSnackBar(
        const SnackBar(content: Text(Messages.planSaved)),
      ); // FR500_10
      if (context.mounted) _goHome(context);
    } else if (vm.saving case UiError(:final message)) {
      messenger.showSnackBar(SnackBar(content: Text(message)));
    }
  }

  /// Short line on a plan card about how it fits the plans already followed.
  String? _noteFor(PlanningViewModel vm, TreatmentPlan p) {
    if (vm.activePlans.isEmpty) return null;
    final issues = vm.issuesFor(p);
    final code = {for (final i in issues) i.code};
    final easing = vm.easingFrom;
    if (easing != null && code.isEmpty) {
      final name = vm.activePlans
          .firstWhere((a) => a.patientPlanId == easing)
          .plan
          .planName;
      return 'Replaces $name for now.';
    }
    if (code.contains('already_following')) {
      return 'You are already following this plan.';
    }
    if (code.contains('intensity') || code.contains('daily_time')) {
      return 'Not possible with your current plans and health profile.';
    }
    if (code.contains('clash')) {
      final names = [
        for (final i in issues)
          if (i.code == 'clash')
            vm.activePlans
                .firstWhere((a) => a.patientPlanId == i.patientPlanId)
                .plan
                .planName,
      ];
      return 'Clashes with ${names.join(' and ')} (same goal, same joints).';
    }
    if (code.contains('risk_cap')) {
      return 'You would need to replace one of your plans.';
    }
    return fitsTogether;
  }

  static const fitsTogether = 'Can be followed together with your current plans.';

  Future<void> _explain(
    BuildContext context,
    String title,
    List<PlanIssue> issues,
  ) => showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [for (final i in issues) _IssueLine(i)],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('OK'),
        ),
      ],
    ),
  );

  /// The risk-level cap is reached: the patient chooses which plan to stop.
  Future<String?> _pickPlanToStop(
    BuildContext context,
    String message,
    List<PatientTreatmentPlan> plans,
  ) => showDialog<String>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: const Text('Choose a plan to replace'),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
          child: Text(message),
        ),
        for (final a in plans)
          SimpleDialogOption(
            onPressed: () => Navigator.of(ctx).pop(a.patientPlanId),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                '${a.plan.planName} (${a.progressPercentage.round()}% done)',
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ),
        SimpleDialogOption(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Cancel'),
        ),
      ],
    ),
  );

  Future<bool?> _confirm(
    BuildContext context,
    TreatmentPlan plan,
    List<PatientTreatmentPlan> stopping,
    List<PlanIssue> notes,
  ) => showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(
        stopping.isEmpty ? 'Add ${plan.planName}?' : 'Replace your plan?',
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (stopping.isEmpty)
              const Text(
                'You will follow it together with your current plans: one '
                'exercise from each plan a day.',
              ),
            for (final a in stopping)
              Text(
                'This stops ${a.plan.planName} '
                '(${a.progressPercentage.round()}% done). Your past sessions '
                'stay in your history.',
              ),
            for (final i in notes)
              if (i.code != 'clash') _IssueLine(i),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(stopping.isEmpty ? 'Add plan' : 'Replace'),
        ),
      ],
    ),
  );

  Future<void> _rejectAll(BuildContext context) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: const Text(
          Messages.confirmReject,
          style: TextStyle(fontSize: 17, color: AppTokens.text),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('No'),
          ),
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
                  subtitle: vm.from == null
                      ? 'Based on your health profile'
                      : 'Your next step after ${vm.from!.plan.planName}',
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
                    noteFor: (p) =>
                        _noteFor(context.read<PlanningViewModel>(), p),
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
  final String? Function(TreatmentPlan) noteFor;

  const _PlanList({
    required this.recommendation,
    required this.notice,
    required this.busy,
    required this.onDetails,
    required this.onSelect,
    required this.onRejectAll,
    required this.noteFor,
  });

  @override
  Widget build(BuildContext context) {
    final plans = recommendation.plans;
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppTokens.gutter,
        AppTokens.gutter,
        AppTokens.gutter,
        24,
      ),
      children: [
        if (notice != null) ...[
          NoticeBanner(notice!, warning: true),
          const SizedBox(height: AppTokens.gap),
        ],
        // hybrid-3.0: why these plans, from the patient's own progress.
        if (recommendation.nextStepReason.isNotEmpty) ...[
          NoticeBanner(
            recommendation.nextStepReason,
            warning: recommendation.nextStep == NextStep.ease,
          ),
          const SizedBox(height: AppTokens.gap),
        ],
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
            note: noteFor(plans[i]),
            noteOk: noteFor(plans[i]) == RecommendedPlansView.fitsTogether,
          ),
          const SizedBox(height: AppTokens.gap),
        ],
        const SizedBox(height: 4),
        TokenButton(
          label: 'Reject all plans',
          color: AppTokens.danger,
          onPressed: busy ? null : onRejectAll,
        ),
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
        Text(
          'Finding the most suitable plans for you...',
          style: TextStyle(fontSize: 15, color: AppTokens.textMuted),
        ),
      ],
    ),
  );
}

class _Problem extends StatelessWidget {
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  const _Problem({
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(AppTokens.gutter),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        NoticeBanner(message, warning: true),
        const SizedBox(height: AppTokens.gutter),
        TokenButton(
          label: actionLabel,
          color: AppTokens.primary,
          onPressed: onAction,
        ),
      ],
    ),
  );
}

/// One check result in a dialog, with an icon by severity.
class _IssueLine extends StatelessWidget {
  final PlanIssue issue;
  const _IssueLine(this.issue);

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (issue.level) {
      PlanIssueLevel.block => (Icons.block, AppTokens.danger),
      PlanIssueLevel.replace => (Icons.swap_horiz, AppTokens.onWarn),
      PlanIssueLevel.warning => (Icons.warning_amber_rounded, AppTokens.onWarn),
      PlanIssueLevel.info => (Icons.info_outline, AppTokens.accent),
    };
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(issue.message)),
        ],
      ),
    );
  }
}
