import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:physical_treatment_and_health_support_system/core/themes/design_tokens.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/exercise.dart';
import 'package:physical_treatment_and_health_support_system/view/common/rehab_labels.dart';
import 'package:physical_treatment_and_health_support_system/view/common/state_builder.dart';
import 'package:physical_treatment_and_health_support_system/view/treatment_view/guide/guide_view.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/treatment_view_model/treatment_view_model.dart';

/// Testing mode (20 Oct): every exercise of the catalogue, each straight to the
/// recorder and the posture check. No plan, no one-exercise-per-day rule, full
/// movement targets, and nothing is saved.
class TestExercisesView extends StatefulWidget {
  const TestExercisesView({super.key});
  static const routeName = '/treatment/test';

  @override
  State<TestExercisesView> createState() => _TestExercisesViewState();
}

class _TestExercisesViewState extends State<TestExercisesView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => context.read<TreatmentViewModel>().loadTestExercises(),
    );
  }

  Future<void> _start(Exercise e) async {
    context.read<TreatmentViewModel>().startTest(e);
    // The same guide as a real exercise (23 Oct), so testing mode shows it too.
    await openExerciseGuide(context, reps: e.defaultRepetitions);
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<TreatmentViewModel>();
    return Scaffold(
      backgroundColor: AppTokens.background,
      appBar: AppBar(title: const Text('Testing mode')),
      body: StateBuilder<List<Exercise>>(
        state: vm.testExercises,
        idle: const Center(child: CircularProgressIndicator()),
        onSuccess: (exercises) => ListView(
          padding: const EdgeInsets.all(AppTokens.gutter),
          children: [
            Container(
              key: const Key('test_mode_notice'),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTokens.accentContainer,
                borderRadius: BorderRadius.circular(AppTokens.radiusCard),
              ),
              child: const Text(
                'Choose any exercise to record it and check your posture now. '
                'Results are not saved and no plan changes. The movement '
                'targets are the full ones, not lowered for age or risk.',
                style: TextStyle(
                  fontSize: 15,
                  height: 1.4,
                  color: AppTokens.textBody,
                ),
              ),
            ),
            const SizedBox(height: AppTokens.gap),
            for (final e in exercises)
              Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  key: Key('test_exercise_${e.poseKey}'),
                  title: Text(
                    e.exerciseName,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    [
                      RehabLabels.area(e.targetBodyArea),
                      if (e.cameraTip != null) 'Camera: ${e.cameraTip}',
                    ].join('\n'),
                  ),
                  isThreeLine: e.cameraTip != null,
                  trailing: const Icon(Icons.videocam_outlined),
                  onTap: () => _start(e),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
