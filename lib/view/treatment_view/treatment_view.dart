import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:physical_treatment_and_health_support_system/viewmodel/ui_state.dart';
import 'package:physical_treatment_and_health_support_system/core/routes/routes.dart';
import 'package:physical_treatment_and_health_support_system/core/themes/design_tokens.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/treatment_plan.dart';
import 'package:physical_treatment_and_health_support_system/view/common/rehab_labels.dart';
import 'package:physical_treatment_and_health_support_system/view/planning_view/widgets/planning_widgets.dart';
import 'package:physical_treatment_and_health_support_system/view/treatment_view/recording_view.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/treatment_view_model/treatment_view_model.dart';
import 'package:physical_treatment_and_health_support_system/view/treatment_view/widgets/treatment_widgets.dart';

/// "My treatment plan" (UI Design, Physical Treatment Page; TreatmentView in Table 4.42):
/// the rehabilitation pathway with completed, current and upcoming exercises (FR300_01, FR300_02).
class TreatmentView extends StatefulWidget {
  const TreatmentView({super.key});
  static const routeName = Routes.physicalTreatment;

  @override
  State<TreatmentView> createState() => _TreatmentViewState();
}

class _TreatmentViewState extends State<TreatmentView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => context.read<TreatmentViewModel>().loadPlan(),
    );
  }

  Future<void> _start(PlanExercise pe) async {
    final vm = context.read<TreatmentViewModel>();
    await vm.startExercise(pe.exercise); // FR300_05
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: RecordingView.routeName),
        builder: (_) => ChangeNotifierProvider.value(
          value: vm,
          child: const RecordingView(),
        ),
      ),
    );
  }

  Future<void> _confirmEnd() async {
    final vm = context.read<TreatmentViewModel>();
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Stop this plan?'),
        content: const Text(
          'Your progress so far is kept. You can get a new plan from AI-assisted planning.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep plan'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppTokens.danger),
            child: const Text('Stop plan'),
          ),
        ],
      ),
    );
    if (yes == true && mounted) {
      final ok = await vm.endPlan();
      if (mounted && !ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'The service is temporarily unavailable. Please try again later.',
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<TreatmentViewModel>();
    final plan = vm.activePlan;
    return Scaffold(
      backgroundColor: AppTokens.background,
      body: SafeArea(
        child: switch (vm.plan) {
          Idle() || Loading() => const Center(
            child: CircularProgressIndicator(color: AppTokens.primary),
          ),
          UiError(:final message) => Padding(
            padding: const EdgeInsets.all(AppTokens.gutter),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                NoticeBanner(message, warning: true), // FR300_22
                const SizedBox(height: AppTokens.gutter),
                TokenButton(
                  label: 'Try again',
                  color: AppTokens.primary,
                  onPressed: vm.loadPlan,
                ),
              ],
            ),
          ),
          UiSuccess() when plan == null => _NoPlan(
            onBack: () => Navigator.of(context).maybePop(),
          ),
          UiSuccess() => ListView(
            padding: const EdgeInsets.fromLTRB(
              8,
              8,
              AppTokens.gutter,
              AppTokens.gutter,
            ),
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: PlanningHeader(
                      title: 'My treatment plan',
                      subtitle: plan!.plan.planName,
                      onBack: () => Navigator.of(context).maybePop(),
                    ),
                  ),
                  IconButton(
                    onPressed: _confirmEnd,
                    tooltip: 'Stop this plan',
                    icon: const Icon(
                      Icons.delete_outline,
                      color: AppTokens.accent,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Column(
                  children: [
                    ProgressBlock(
                      label: 'Overall progress',
                      done: plan.completedStages,
                      total: plan.plan.exercises.length,
                    ),
                    if (plan.completedStages >= plan.plan.exercises.length &&
                        plan.plan.exercises.isNotEmpty) ...[
                      const SizedBox(height: AppTokens.gap),
                      const NoticeBanner(
                        'Plan complete. Well done! Get your next plan from AI-assisted planning.',
                      ),
                    ],
                    for (final stage in vm.pathway) ...[
                      const SizedBox(height: AppTokens.gap),
                      StageCard(
                        stage: stage,
                        onOpen: () => showExerciseDetails(
                          context,
                          stage.item,
                          onStart: stage.status == StageStatus.upcoming
                              ? null
                              : () => _start(stage.item),
                        ),
                        onStart: () => _start(stage.item),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        },
      ),
    );
  }
}

class _NoPlan extends StatelessWidget {
  final VoidCallback onBack;
  const _NoPlan({required this.onBack});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      8,
      8,
      AppTokens.gutter,
      AppTokens.gutter,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PlanningHeader(
          title: 'My treatment plan',
          subtitle: 'No plan selected yet',
          onBack: onBack,
        ),
        const Spacer(),
        const NoticeBanner(
          'You do not have a treatment plan yet. Get one from AI-assisted planning.',
        ),
        const SizedBox(height: AppTokens.gutter),
        TokenButton(
          label: 'Get a treatment plan',
          color: AppTokens.action,
          onPressed: () => Navigator.of(
            context,
          ).pushReplacementNamed(Routes.treatmentPlanning),
        ),
        const Spacer(),
      ],
    ),
  );
}

/// Exercise detail (FR300_03, FR300_04): instructions, repetitions, duration, safety points and the
/// recording tip, with "Start exercise" (FR300_05).
Future<void> showExerciseDetails(
  BuildContext context,
  PlanExercise pe, {
  VoidCallback? onStart,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  backgroundColor: AppTokens.background,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
  ),
  builder: (ctx) => DraggableScrollableSheet(
    expand: false,
    initialChildSize: 0.7,
    maxChildSize: 0.95,
    builder: (ctx, controller) => ListView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(
        AppTokens.gutter,
        12,
        AppTokens.gutter,
        24,
      ),
      children: [
        Center(
          child: Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppTokens.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          pe.exercise.exerciseName,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w600,
            color: AppTokens.text,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            InfoChip('${pe.prescribedRepetitions} reps'),
            InfoChip(RehabLabels.duration(pe.prescribedDurationSec)),
            InfoChip(RehabLabels.area(pe.exercise.targetBodyArea)),
          ],
        ),
        const SizedBox(height: 16),
        const Text(
          'How to do it',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: AppTokens.text,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          pe.exercise.steps,
          style: const TextStyle(
            fontSize: 16,
            height: 1.5,
            color: AppTokens.textBody,
          ),
        ),
        if (pe.exercise.cameraTip case final tip?) ...[
          const SizedBox(height: 16),
          NoticeBanner('Recording: $tip'),
        ],
        if (onStart != null) ...[
          const SizedBox(height: 24),
          TokenButton(
            label: 'Start exercise',
            color: AppTokens.action,
            onPressed: () {
              Navigator.of(ctx).pop();
              onStart();
            },
          ),
        ],
      ],
    ),
  ),
);
