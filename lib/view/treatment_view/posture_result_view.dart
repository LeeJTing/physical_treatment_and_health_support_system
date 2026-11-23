import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:physical_treatment_and_health_support_system/core/constants/app_constants.dart';
import 'package:physical_treatment_and_health_support_system/view/treatment_view/widgets/result_outlook.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/ui_state.dart';
import 'package:physical_treatment_and_health_support_system/core/themes/design_tokens.dart';
import 'package:physical_treatment_and_health_support_system/view/common/status_bar_strip.dart';
import 'package:physical_treatment_and_health_support_system/view/planning_view/widgets/planning_widgets.dart';
import 'package:physical_treatment_and_health_support_system/view/treatment_view/treatment_view.dart';
import 'package:physical_treatment_and_health_support_system/view/treatment_view/recording_view.dart';
import 'package:physical_treatment_and_health_support_system/view/treatment_view/test_exercises_view.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/treatment_view_model/treatment_view_model.dart';
import 'package:physical_treatment_and_health_support_system/view/treatment_view/widgets/treatment_widgets.dart';

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
    if (vm.testing) {
      _backTo(
        context,
        TestExercisesView.routeName,
      ); // testing mode: nothing to save
      return;
    }
    final ok = await vm.acceptResult(); // FR300_21
    if (!context.mounted) return;
    if (ok) {
      final tries = vm.lastTriesBelowPass;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            vm.lastMovedOn
                ? 'Your progress has been updated.'
                : 'Saved. You will do this exercise again next time '
                      '(try $tries of ${AppConstants.triesBeforeMovingOn} below 80%).',
          ),
        ),
      );
      _backTo(context, TreatmentView.routeName);
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
    // Posture text review (8 Oct): the fall message is shown once, in the banner, and a possible
    // fall offers no retry today.
    final fell = r.safetyAlert != null;
    final lines = [
      for (final l in r.feedback)
        if (l != r.safetyAlert) l,
    ];
    final String? restHint = fell
        ? 'Rest now and try this exercise another day.'
        : passing
        ? null
        : vm.retriesInARow >= 2
        ? 'You have tried this a few times. Rest now and try again tomorrow.'
        : 'Rest for a minute before you try again.';
    // Research and outlook (Elwin, 10 Nov): worked out by the ViewModel; null after a possible
    // fall, and the outlook also in testing mode.
    final evidence = vm.resultEvidence;
    final outlook = vm.resultOutlook;
    final plan = vm.activePlan;
    final showProgress = !fell && !vm.testing && plan != null;
    final page = Scaffold(
      backgroundColor: AppTokens.background,
      // The header band runs under the status bar, as on the Treatment tab (16 Nov).
      appBar: const StatusBarStrip(color: AppTokens.primary),
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          // Header band. The back arrow goes to the previous screen, the same as the phone's
          // Back (PopScope below); it replaced the Exit button (Elwin, 9 Nov).
          Container(
            color: AppTokens.primary,
            padding: const EdgeInsets.fromLTRB(8, 8, AppTokens.gutter, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      tooltip: 'Back',
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Posture result',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              vm.current?.exerciseName ?? '',
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                                color: AppTokens.onPrimaryMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                // Testing mode: said at the top, before the score (laptop emulator test, 20 Oct).
                if (vm.testing)
                  const Padding(
                    padding: EdgeInsets.only(left: 8, top: 12),
                    child: NoticeBanner(
                      'Testing mode: this result is not saved and no plan changes.',
                      key: Key('test_mode_result'),
                    ),
                  ),
                if (r.safetyAlert != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 8, top: 12),
                    child: _SafetyBanner(message: r.safetyAlert!),
                  ),
              ],
            ),
          ),
          // The band's rounded end runs behind the top of the score card, as on Home.
          Stack(
            children: [
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: 64,
                child: Container(
                  decoration: const BoxDecoration(
                    color: AppTokens.primary,
                    borderRadius: BorderRadius.vertical(
                      bottom: Radius.circular(32),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppTokens.gutter,
                  4,
                  AppTokens.gutter,
                  0,
                ),
                child: _ScoreCard(
                  accuracy: r.accuracy,
                  passing: passing,
                  color: color,
                  amount: r.holdSeconds != null
                      ? r.holdSeconds!.toStringAsFixed(0)
                      : '${r.repetitions}',
                  amountLabel: r.holdSeconds != null
                      ? 'seconds held steady'
                      : 'repetition${r.repetitions == 1 ? '' : 's'} counted',
                  done: showProgress ? plan.completedStages : null,
                  total: showProgress ? plan.plan.exercises.length : null,
                  gentler: r.romScale != null,
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.all(AppTokens.gutter),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (lines.isNotEmpty) ...[
                  TreatmentCard(
                    radius: _cardRadius,
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          passing
                              ? 'Feedback'
                              : 'Corrective guidance', // FR300_19
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: AppTokens.accent,
                          ),
                        ),
                        const SizedBox(height: 10),
                        for (final (i, line) in lines.indexed)
                          _TipRow(
                            line,
                            number: passing ? null : i + 1,
                            last: i == lines.length - 1,
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: _gap),
                ],
                if (passing && vm.autoAdvanced) ...[
                  const NoticeBanner(
                    'Score 80% or more: your progress has been saved.',
                  ),
                  const SizedBox(height: _gap),
                ],
                if (saving case UiError(:final message)) ...[
                  NoticeBanner(message, warning: true), // FR300_27
                  const SizedBox(height: _gap),
                ],
                // Below 80% (Elwin, 23 Oct): what Continue does is said before it is tapped; with
                // the rest advice in one quiet box instead of loose paragraphs (16 Nov).
                if ((!passing && !vm.testing) || restHint != null) ...[
                  _InfoBox(
                    children: [
                      if (!passing && !vm.testing)
                        Text(
                          'Continue saves this try. Your plan moves on when you score 80% or '
                          'more, or after ${AppConstants.triesBeforeMovingOn} tries below 80%.',
                          key: const Key('below_pass_rule'),
                          style: _infoStyle,
                        ),
                      if (restHint != null) Text(restHint, style: _infoStyle),
                    ],
                  ),
                  const SizedBox(height: _gap),
                ],
                if (outlook != null) ...[
                  OutlookCard(
                    projection: outlook,
                    sessionsPerWeek: plan!.plan.frequencyPerWeek,
                    planStart: plan.selectedAt,
                    totalExercises: plan.plan.exercises.length,
                    group: evidence,
                  ),
                  const SizedBox(height: _gap),
                ],
                if (evidence != null)
                  EvidenceCard(
                    group: evidence,
                    passing: passing,
                    onOpenStudy: vm.openStudy,
                  ),
              ],
            ),
          ),
        ],
      ),
      // Retry and Continue stay at the bottom of the screen (10 Nov): the research and outlook
      // cards made the page longer, and saving must never need a scroll.
      bottomNavigationBar: SafeArea(
        child: Container(
          decoration: const BoxDecoration(
            color: AppTokens.background,
            border: Border(top: BorderSide(color: AppTokens.border)),
          ),
          padding: const EdgeInsets.fromLTRB(
            AppTokens.gutter,
            12,
            AppTokens.gutter,
            12,
          ),
          child: Row(
            children: [
              if (!fell) ...[
                Expanded(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      minHeight: AppTokens.minTarget,
                    ),
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
              ],
              Expanded(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minHeight: AppTokens.minTarget,
                  ),
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
        ),
      ),
    );
    // The phone's Back (23 Oct) went to the recorder without recording the try. Now it is
    // Retry exercise, or Continue after a possible fall (no retry today).
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || saving is Loading) return;
        fell ? _continue(context) : _retry(context);
      },
      child: page,
    );
  }
}

const _cardRadius = 22.0; // as the cards on Home
const _gap = 14.0;
const _infoStyle = TextStyle(fontSize: 15, height: 1.4, color: AppTokens.text);

/// The score: ring, verdict, then the amount done and the place in the plan side by side.
class _ScoreCard extends StatelessWidget {
  final double accuracy;
  final bool passing;
  final Color color;

  /// Repetitions counted, or seconds held, and its label.
  final String amount;
  final String amountLabel;

  /// Exercises of the plan passed and in total; null in testing mode and after a possible fall.
  final int? done;
  final int? total;

  /// The targets were lowered for this patient's health.
  final bool gentler;

  const _ScoreCard({
    required this.accuracy,
    required this.passing,
    required this.color,
    required this.amount,
    required this.amountLabel,
    required this.done,
    required this.total,
    required this.gentler,
  });

  @override
  Widget build(BuildContext context) {
    final amountCell = Column(
      children: [
        Text(
          amount,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: AppTokens.text,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          amountLabel,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13, color: AppTokens.textMuted),
        ),
      ],
    );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 24, 18, 18),
      decoration: BoxDecoration(
        color: AppTokens.surface,
        borderRadius: BorderRadius.circular(_cardRadius),
        border: Border.all(color: AppTokens.cardBorder),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 18,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          ScoreRing(
            percent: accuracy,
            color: color,
            track: passing
                ? AppTokens.goodContainer
                : AppTokens.cautionContainer,
            animate: true,
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: passing
                  ? AppTokens.goodContainer
                  : AppTokens.cautionContainer,
              borderRadius: BorderRadius.circular(20),
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
                // Flexible: wraps instead of overflowing with large phone text.
                Flexible(
                  child: Text(
                    passing ? 'Great form' : 'Needs improvement',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: passing ? AppTokens.good : AppTokens.caution,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // The reward, right under the verdict (15 Nov).
          if (passing && done != null) ...[
            const SizedBox(height: 10),
            const Text(
              'Well done!',
              key: Key('result_well_done'),
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppTokens.good,
              ),
            ),
          ],
          const SizedBox(height: 16),
          const Divider(height: 1, color: AppTokens.border),
          const SizedBox(height: 14),
          if (done == null)
            amountCell
          else
            IntrinsicHeight(
              child: Row(
                children: [
                  Expanded(child: amountCell),
                  const VerticalDivider(width: 24, color: AppTokens.border),
                  Expanded(
                    child: PlanProgressDots(done: done!, total: total!),
                  ),
                ],
              ),
            ),
          if (gentler) ...[
            const SizedBox(height: 14),
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.tune, size: 16, color: AppTokens.textMuted),
                SizedBox(width: 6),
                Flexible(
                  child: Text(
                    'We made the targets gentler to suit your health.',
                    style: TextStyle(fontSize: 13, color: AppTokens.textMuted),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// One line of feedback in its own soft row: numbered when it is something to correct, a tick
/// when it is praise.
class _TipRow extends StatelessWidget {
  final String text;
  final int? number;
  final bool last;
  const _TipRow(this.text, {required this.number, required this.last});

  @override
  Widget build(BuildContext context) {
    final good = number == null;
    return Container(
      margin: EdgeInsets.only(bottom: last ? 0 : 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: good ? AppTokens.goodContainer : AppTokens.cautionContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: good ? AppTokens.good : AppTokens.caution,
              shape: BoxShape.circle,
            ),
            child: good
                ? const Icon(Icons.check, size: 16, color: Colors.white)
                : ExcludeSemantics(
                    child: Text(
                      '$number',
                      textScaler: TextScaler.noScaling,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                text,
                style: const TextStyle(
                  fontSize: 16,
                  height: 1.35,
                  color: AppTokens.text,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A quiet box for what happens next (what Continue does, when to rest).
class _InfoBox extends StatelessWidget {
  final List<Widget> children;
  const _InfoBox({required this.children});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppTokens.tint,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 1),
          child: Icon(Icons.info_outline, size: 20, color: AppTokens.accent),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final (i, c) in children.indexed) ...[
                if (i > 0) const SizedBox(height: 8),
                c,
              ],
            ],
          ),
        ),
      ],
    ),
  );
}

/// Shown first when the video looks like the patient lost their balance or fell.
class _SafetyBanner extends StatelessWidget {
  final String message;
  const _SafetyBanner({required this.message});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppTokens.dangerContainer,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppTokens.danger),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.health_and_safety_outlined, color: AppTokens.onDanger),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            message,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppTokens.onDanger,
            ),
          ),
        ),
      ],
    ),
  );
}
