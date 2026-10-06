import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:physical_treatment_and_health_support_system/core/base/ui_state.dart';
import 'package:physical_treatment_and_health_support_system/core/themes/design_tokens.dart';
import 'package:physical_treatment_and_health_support_system/features/planning/widgets/planning_widgets.dart';
import 'package:physical_treatment_and_health_support_system/features/treatment/view/physical_treatment_view.dart';
import 'package:physical_treatment_and_health_support_system/features/treatment/view/recording_view.dart';
import 'package:physical_treatment_and_health_support_system/features/treatment/viewmodel/treatment_view_model.dart';
import 'package:physical_treatment_and_health_support_system/features/treatment/widgets/treatment_widgets.dart';

/// "Posture result" (UI Design, Posture Result Screen; FR300_09, FR300_10, FR300_19 to FR300_21):
/// accuracy ring, corrective guidance, Retry exercise or Continue. 80% or more updates the
/// pathway automatically.
class PostureResultView extends StatelessWidget {
  const PostureResultView({super.key});

  void _backTo(BuildContext context, String route) => Navigator.of(
    context,
  ).popUntil((r) => r.settings.name == route || r.isFirst);

  Future<void> _continue(BuildContext context) async {
    final vm = context.read<TreatmentViewModel>();
    final ok = await vm.acceptResult(); // FR300_21
    if (!context.mounted) return;
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Your progress has been updated.')),
      );
      _backTo(context, PhysicalTreatmentView.routeName);
    }
  }

  void _retry(BuildContext context) {
    context.read<TreatmentViewModel>().retry(); // FR300_20
    _backTo(context, RecordingView.routeName);
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<TreatmentViewModel>();
    final r = switch (vm.analysis) {
      UiSuccess(:final data) => data,
      _ => null,
    };
    if (r == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final passing = r.isPassing;
    final color = passing ? AppTokens.progress : const Color(0xFFC17A1A);
    final saving = vm.saving;
    return Scaffold(
      backgroundColor: AppTokens.background,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppTokens.gutter),
          children: [
            const Text(
              'Posture result',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w600,
                color: AppTokens.text,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              vm.current?.exerciseName ?? '',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppTokens.accent,
              ),
            ),
            const SizedBox(height: 16),
            TreatmentCard(
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
              child: Column(
                children: [
                  ScoreRing(
                    percent: r.accuracy,
                    color: color,
                    track: passing
                        ? AppTokens.goodContainer
                        : AppTokens.cautionContainer,
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: passing
                          ? AppTokens.goodContainer
                          : AppTokens.cautionContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          passing
                              ? Icons.check_circle_outline
                              : Icons.warning_amber_rounded,
                          size: 18,
                          color: passing ? AppTokens.good : AppTokens.caution,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          passing ? 'Great form' : 'Needs improvement',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: passing ? AppTokens.good : AppTokens.caution,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    r.holdSeconds != null
                        ? 'Held steady for ${r.holdSeconds!.toStringAsFixed(0)} seconds'
                        : '${r.repetitions} repetition${r.repetitions == 1 ? '' : 's'} counted',
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppTokens.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppTokens.gap),
            TreatmentCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    passing ? 'Feedback' : 'Corrective guidance', // FR300_19
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppTokens.accent,
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (final line in r.feedback)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            passing
                                ? Icons.thumb_up_alt_outlined
                                : Icons.tips_and_updates_outlined,
                            size: 20,
                            color: AppTokens.textBody,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              line,
                              style: const TextStyle(
                                fontSize: 16,
                                height: 1.4,
                                color: AppTokens.text,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            if (passing && vm.autoAdvanced) ...[
              const SizedBox(height: AppTokens.gap),
              const NoticeBanner(
                '80% or more: your progress was updated automatically.',
              ),
            ],
            if (saving case UiError(:final message)) ...[
              const SizedBox(height: AppTokens.gap),
              NoticeBanner(message, warning: true), // FR300_27
            ],
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: AppTokens.minTarget,
                    child: FilledButton(
                      onPressed: saving is Loading
                          ? null
                          : () => _retry(context),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTokens.action,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            AppTokens.radiusButton,
                          ),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      child: const Text('Retry exercise'),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SizedBox(
                    height: AppTokens.minTarget,
                    child: OutlinedButton(
                      onPressed: saving is Loading
                          ? null
                          : () => _continue(context),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTokens.primary,
                        side: const BorderSide(
                          color: AppTokens.primary,
                          width: 1.5,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            AppTokens.radiusButton,
                          ),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      child: saving is Loading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Continue'),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
