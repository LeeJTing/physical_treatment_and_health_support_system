import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:physical_treatment_and_health_support_system/core/routes/routes.dart';
import 'package:physical_treatment_and_health_support_system/core/themes/design_tokens.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/exercise_session.dart';
import 'package:physical_treatment_and_health_support_system/view/common/rehab_labels.dart';
import 'package:physical_treatment_and_health_support_system/view/treatment_view/test_exercises_view.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/treatment_view_model/treatment_view_model.dart';

/// "Exit" on the recording, analysing and result screens (FR300_13): cancels the exercise in
/// progress and goes back to the home page, or in testing mode to the testing list. Asks first
/// when [confirm] is given (while recording or analysing, when something would be lost).
class ExitExerciseButton extends StatelessWidget {
  final String? confirm;
  const ExitExerciseButton({super.key, this.confirm});

  Future<void> _exit(BuildContext context) async {
    final question = confirm;
    if (question != null) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          content: Text(question, style: const TextStyle(fontSize: 17)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Keep going'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Exit', style: TextStyle(color: AppTokens.cta)),
            ),
          ],
        ),
      );
      if (ok != true || !context.mounted) return;
    }
    final vm = context.read<TreatmentViewModel>();
    final testing = vm.testing;
    vm.cancelExercise();
    if (testing) {
      // Testing mode: back to the exercise list, as Continue does (laptop emulator test, 22 Oct).
      Navigator.of(context).popUntil(
        (r) => r.settings.name == TestExercisesView.routeName || r.isFirst,
      );
      return;
    }
    Navigator.of(context).pushNamedAndRemoveUntil(Routes.home, (_) => false);
  }

  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: () => _exit(context),
    style: TextButton.styleFrom(
      minimumSize: const Size(AppTokens.minTarget, AppTokens.minTarget),
    ),
    child: const Text(
      'Exit',
      style: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: AppTokens.brandDeepAccent,
      ),
    ),
  );
}

/// White rounded card used across the treatment screens.
class TreatmentCard extends StatelessWidget {
  final Widget child;
  final Color border;
  final double borderWidth;
  final EdgeInsetsGeometry padding;

  const TreatmentCard({
    super.key,
    required this.child,
    this.border = AppTokens.border,
    this.borderWidth = 1,
    this.padding = const EdgeInsets.all(16),
  });

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: padding,
    decoration: BoxDecoration(
      color: AppTokens.surface,
      borderRadius: BorderRadius.circular(AppTokens.radiusCard),
      border: Border.all(color: border, width: borderWidth),
    ),
    child: child,
  );
}

/// "Overall progress  2 of 3 done" with the green bar (Physical Treatment Page, Treatment Screen).
class ProgressBlock extends StatelessWidget {
  final String label;
  final int done;
  final int total;
  final String? footerLeft;
  final String? footerRight;

  const ProgressBlock({
    super.key,
    required this.label,
    required this.done,
    required this.total,
    this.footerLeft,
    this.footerRight,
  });

  @override
  Widget build(BuildContext context) => TreatmentCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: AppTokens.text,
                ),
              ),
            ),
            Text(
              '$done of $total done',
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppTokens.text,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Semantics(
          label: '$done of $total exercises done',
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: total == 0 ? 0 : done / total,
              minHeight: 8,
              color: AppTokens.progress,
              backgroundColor: AppTokens.goodContainer,
            ),
          ),
        ),
        if (footerLeft != null || footerRight != null) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  footerLeft ?? '',
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppTokens.textMuted,
                  ),
                ),
              ),
              Text(
                footerRight ?? '',
                style: const TextStyle(
                  fontSize: 14,
                  color: AppTokens.textMuted,
                ),
              ),
            ],
          ),
        ],
      ],
    ),
  );
}

/// Status pill: "✓ 94% posture", "⚠ 61% posture", "Not started".
class StagePill extends StatelessWidget {
  final PathwayStage stage;
  const StagePill(this.stage, {super.key});

  @override
  Widget build(BuildContext context) {
    final best = stage.bestAccuracy;
    final (
      IconData? icon,
      String text,
      Color bg,
      Color fg,
    ) = switch (stage.status) {
      StageStatus.done => (
        Icons.check,
        best == null ? 'Done' : '${best.round()}% posture',
        AppTokens.goodContainer,
        AppTokens.good,
      ),
      StageStatus.attempted => (
        best != null && best >= ExerciseSession.passMark
            ? Icons.check
            : Icons.warning_amber_rounded,
        '${best?.round() ?? 0}% posture',
        best != null && best >= ExerciseSession.passMark
            ? AppTokens.goodContainer
            : AppTokens.cautionContainer,
        best != null && best >= ExerciseSession.passMark
            ? AppTokens.good
            : AppTokens.caution,
      ),
      StageStatus.current => (
        null,
        'Not started',
        AppTokens.accentContainer,
        AppTokens.accent,
      ),
      StageStatus.upcoming => (
        Icons.lock_outline,
        'Upcoming',
        AppTokens.background,
        AppTokens.textMuted,
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 15, color: fg),
            const SizedBox(width: 4),
          ],
          Text(
            text,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}

/// One exercise of the pathway; the current one gets the green outline and the button.
class StageCard extends StatelessWidget {
  final PathwayStage stage;
  final VoidCallback onOpen;
  final VoidCallback? onStart;

  const StageCard({
    super.key,
    required this.stage,
    required this.onOpen,
    this.onStart,
  });

  bool get _isNext =>
      stage.status == StageStatus.current ||
      stage.status == StageStatus.attempted;

  @override
  Widget build(BuildContext context) {
    final pe = stage.item;
    final subtitle =
        '${RehabLabels.area(pe.exercise.targetBodyArea)} · ${pe.prescribedRepetitions} reps · '
        '${RehabLabels.duration(pe.prescribedDurationSec)}';
    return Semantics(
      button: true,
      label: '${pe.exercise.exerciseName}, $subtitle',
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(AppTokens.radiusCard),
        child: TreatmentCard(
          border: _isNext ? AppTokens.highlight : AppTokens.border,
          borderWidth: _isNext ? 2 : 1,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          pe.exercise.exerciseName,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: AppTokens.text,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          style: const TextStyle(
                            fontSize: 14,
                            color: AppTokens.accent,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  StagePill(stage),
                ],
              ),
              if (_isNext && onStart != null) ...[
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  height: AppTokens.minTarget,
                  child: FilledButton(
                    onPressed: onStart,
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
                    child: Text(
                      stage.status == StageStatus.attempted
                          ? 'Try again'
                          : 'Start exercise',
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The accuracy ring on the Posture Result Screen.
class ScoreRing extends StatelessWidget {
  final double percent; // 0..100
  final Color color;
  final Color track;
  final double size;

  const ScoreRing({
    super.key,
    required this.percent,
    required this.color,
    required this.track,
    this.size = 150,
  });

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Posture accuracy ${percent.round()} percent',
    child: SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _RingPainter(percent / 100, color, track),
        child: Center(
          child: Text(
            '${percent.round()}%',
            style: const TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.w600,
              color: AppTokens.text,
            ),
          ),
        ),
      ),
    ),
  );
}

class _RingPainter extends CustomPainter {
  final double value;
  final Color color;
  final Color track;
  _RingPainter(this.value, this.color, this.track);

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 14.0;
    final rect = Offset.zero & size;
    final arc = rect.deflate(stroke / 2);
    final base = Paint()
      ..color = track
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    canvas.drawArc(arc, 0, 2 * math.pi, false, base);
    final fg = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.butt
      ..strokeWidth = stroke;
    canvas.drawArc(
      arc,
      -math.pi / 2,
      2 * math.pi * value.clamp(0.0, 1.0),
      false,
      fg,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.value != value || old.color != color;
}
