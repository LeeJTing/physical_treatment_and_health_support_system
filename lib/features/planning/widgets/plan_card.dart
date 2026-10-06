import 'package:flutter/material.dart';

import 'package:physical_treatment_and_health_support_system/core/themes/design_tokens.dart';
import 'package:physical_treatment_and_health_support_system/data/models/treatment_plan.dart';
import 'package:physical_treatment_and_health_support_system/features/planning/model/rehab_labels.dart';
import 'package:physical_treatment_and_health_support_system/features/planning/widgets/planning_widgets.dart';

/// One recommended plan: name, match score, aim, chips, and the two actions.
/// The best match gets the green outline.
class PlanCard extends StatelessWidget {
  final TreatmentPlan plan;
  final bool best;
  final bool busy;
  final VoidCallback onDetails;
  final VoidCallback onSelect;

  const PlanCard({
    super.key,
    required this.plan,
    required this.onDetails,
    required this.onSelect,
    this.best = false,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTokens.surface,
          borderRadius: BorderRadius.circular(AppTokens.radiusCard),
          border: Border.all(color: best ? AppTokens.highlight : AppTokens.border, width: best ? 2 : 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(plan.planName,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppTokens.text)),
                ),
                const SizedBox(width: 8),
                if (plan.suitabilityScore != null) MatchPill(plan.suitabilityScore!),
              ],
            ),
            const SizedBox(height: 8),
            Text(plan.aim, style: const TextStyle(fontSize: 15, height: 1.4, color: AppTokens.textBody)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                InfoChip(RehabLabels.area(plan.targetBodyArea)),
                InfoChip('${plan.exercises.length} exercises'),
                InfoChip('${plan.frequencyPerWeek}x a week'),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: AppTokens.minTarget,
                    child: OutlinedButton(
                      onPressed: onDetails,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTokens.primary,
                        side: const BorderSide(color: AppTokens.primary, width: 1.5),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTokens.radiusButton)),
                        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                      child: const Text('View details'),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SizedBox(
                    height: AppTokens.minTarget,
                    child: FilledButton(
                      onPressed: busy ? null : onSelect,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTokens.action,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: AppTokens.action.withValues(alpha: 0.5),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTokens.radiusButton)),
                        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                      child: const Text('Select'),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
}

/// Exercise details for one plan (FR500_08): name, instructions with safety
/// precautions, target body area, frequency, repetitions and duration.
Future<void> showPlanDetails(BuildContext context, TreatmentPlan plan) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTokens.background,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        builder: (context, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(AppTokens.gutter, 12, AppTokens.gutter, 24),
          children: [
            Center(
              child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(color: AppTokens.border, borderRadius: BorderRadius.circular(2))),
            ),
            const SizedBox(height: 16),
            Text(plan.planName,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: AppTokens.text)),
            const SizedBox(height: 6),
            Text(plan.aim, style: const TextStyle(fontSize: 15, height: 1.4, color: AppTokens.textBody)),
            const SizedBox(height: 12),
            Wrap(spacing: 6, runSpacing: 6, children: [
              InfoChip(RehabLabels.area(plan.targetBodyArea)),
              InfoChip('${plan.frequencyPerWeek}x a week'),
              InfoChip('About ${RehabLabels.duration(plan.totalDurationSec)} a session'),
            ]),
            const SizedBox(height: 20),
            for (final pe in plan.orderedExercises()) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTokens.surface,
                  borderRadius: BorderRadius.circular(AppTokens.radiusCard),
                  border: Border.all(color: AppTokens.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${pe.sequenceOrder}. ${pe.exercise.exerciseName}',
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: AppTokens.text)),
                    const SizedBox(height: 8),
                    Wrap(spacing: 6, runSpacing: 6, children: [
                      InfoChip('${pe.prescribedRepetitions} reps'),
                      InfoChip(RehabLabels.duration(pe.prescribedDurationSec)),
                      InfoChip(RehabLabels.area(pe.exercise.targetBodyArea)),
                    ]),
                    const SizedBox(height: 10),
                    Text(pe.exercise.instructionText,
                        style: const TextStyle(fontSize: 15, height: 1.45, color: AppTokens.textBody)),
                  ],
                ),
              ),
              const SizedBox(height: AppTokens.gap),
            ],
          ],
        ),
      ),
    );
