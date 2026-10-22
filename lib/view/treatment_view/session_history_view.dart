import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:physical_treatment_and_health_support_system/view/planning_view/widgets/planning_widgets.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/ui_state.dart';
import 'package:physical_treatment_and_health_support_system/core/themes/design_tokens.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/exercise_session.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/treatment_view_model/treatment_view_model.dart';
import 'package:physical_treatment_and_health_support_system/view/treatment_view/widgets/treatment_widgets.dart';

/// Past exercise sessions of the current plan with their posture accuracy, so the
/// patient can see whether their form is improving (FR300_10 results over time).
class SessionHistoryView extends StatefulWidget {
  const SessionHistoryView({super.key});

  @override
  State<SessionHistoryView> createState() => _SessionHistoryViewState();
}

class _SessionHistoryViewState extends State<SessionHistoryView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final vm = context.read<TreatmentViewModel>();
      if (vm.plan is! UiSuccess) vm.loadPlan();
    });
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<TreatmentViewModel>();
    return Scaffold(
      backgroundColor: AppTokens.background,
      body: Column(
        children: [
          const HeaderBar(
            title: 'Session history',
            subtitle: 'Your posture results over time',
          ),
          Expanded(
            child: switch (vm.plan) {
              Loading() ||
              Idle() => const Center(child: CircularProgressIndicator()),
              UiError(:final message) => _Message(
                message,
                onRetry: vm.loadPlan,
              ),
              UiSuccess() when vm.activePlan == null => const _Message(
                'You have no treatment plan yet. Choose one in AI-assisted treatment planning.',
              ),
              UiSuccess() when vm.history.isEmpty => const _Message(
                'No sessions recorded yet. Your results appear here after your first exercise.',
              ),
              UiSuccess() => RefreshIndicator(
                onRefresh: vm.loadPlan,
                child: _list(vm),
              ),
            },
          ),
        ],
      ),
    );
  }

  Widget _list(TreatmentViewModel vm) {
    final entries = vm.history;
    final scored = [
      for (final e in entries.reversed)
        if (e.session.postureAccuracy != null) e.session.postureAccuracy!,
    ];
    return ListView(
      padding: const EdgeInsets.all(AppTokens.gutter),
      children: [
        Text(
          vm.activePlan!.plan.planName,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppTokens.text,
          ),
        ),
        const SizedBox(height: AppTokens.gap),
        Row(
          children: [
            Expanded(child: _Stat('Sessions', '${vm.completedSessionCount}')),
            const SizedBox(width: AppTokens.gap),
            Expanded(child: _Stat('Average', _pct(vm.averageAccuracy))),
            const SizedBox(width: AppTokens.gap),
            Expanded(child: _Stat('Best', _pct(vm.bestAccuracy))),
          ],
        ),
        if (scored.length >= 2) ...[
          const SizedBox(height: AppTokens.gap),
          TreatmentCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Posture accuracy over time',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppTokens.text,
                  ),
                ),
                const SizedBox(height: 12),
                Semantics(
                  label:
                      'Accuracy of the last ${scored.length} attempts, from ${_pct(scored.first)} to ${_pct(scored.last)}',
                  child: SizedBox(
                    height: 120,
                    width: double.infinity,
                    child: CustomPaint(painter: _TrendPainter(scored)),
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Dashed line: 80% pass mark',
                  style: TextStyle(fontSize: 13, color: AppTokens.textMuted),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 20),
        const Text(
          'All attempts',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppTokens.text,
          ),
        ),
        const SizedBox(height: AppTokens.gap),
        for (final e in entries) ...[_EntryCard(e), const SizedBox(height: 10)],
      ],
    );
  }

  static String _pct(double? v) => v == null ? '-' : '${v.round()}%';
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  const _Stat(this.label, this.value);

  @override
  Widget build(BuildContext context) => TreatmentCard(
    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
    child: Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: AppTokens.primary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(fontSize: 14, color: AppTokens.textMuted),
        ),
      ],
    ),
  );
}

class _EntryCard extends StatelessWidget {
  final SessionHistoryEntry entry;
  const _EntryCard(this.entry);

  static String _date(DateTime? t) {
    if (t == null) return 'Not finished';
    final l = t.toLocal();
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final h = l.hour % 12 == 0 ? 12 : l.hour % 12;
    return '${l.day} ${months[l.month - 1]} ${l.year}, $h:${l.minute.toString().padLeft(2, '0')} ${l.hour < 12 ? 'AM' : 'PM'}';
  }

  @override
  Widget build(BuildContext context) {
    final s = entry.session;
    final acc = s.postureAccuracy;
    final pass = acc != null && acc >= ExerciseSession.passMark;
    final status = switch (s.completionStatus) {
      CompletionStatus.completed => 'Completed',
      CompletionStatus.retried => 'Tried again',
      CompletionStatus.abandoned => 'Stopped',
    };
    return TreatmentCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  entry.exerciseName,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: AppTokens.text,
                  ),
                ),
              ),
              if (acc != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: pass
                        ? AppTokens.goodContainer
                        : AppTokens.cautionContainer,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${acc.round()}%',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: pass ? AppTokens.good : AppTokens.caution,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            [
              _date(s.completedAt),
              status,
              if (s.repetitionsCompleted != null)
                '${s.repetitionsCompleted} reps',
            ].join(' · '),
            style: const TextStyle(fontSize: 14, color: AppTokens.textMuted),
          ),
          if ((s.postureFeedback ?? '').isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              s.postureFeedback!,
              style: const TextStyle(fontSize: 15, color: AppTokens.textBody),
            ),
          ],
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  final String text;
  final Future<void> Function()? onRetry;
  const _Message(this.text, {this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 17, color: AppTokens.text),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ],
      ),
    ),
  );
}

/// Accuracy line (0-100 %) oldest to newest, with a dashed line at the pass mark.
class _TrendPainter extends CustomPainter {
  final List<double> scores;
  _TrendPainter(this.scores);

  @override
  void paint(Canvas canvas, Size size) {
    double y(double v) => size.height - (v.clamp(0, 100) / 100) * size.height;
    final dx = scores.length > 1 ? size.width / (scores.length - 1) : 0.0;

    final dash = Paint()
      ..color = AppTokens.textMuted
      ..strokeWidth = 1;
    final passY = y(ExerciseSession.passMark);
    for (double x = 0; x < size.width; x += 10) {
      canvas.drawLine(
        Offset(x, passY),
        Offset(math.min(x + 5, size.width), passY),
        dash,
      );
    }

    final path = Path()..moveTo(0, y(scores.first));
    for (var i = 1; i < scores.length; i++) {
      path.lineTo(i * dx, y(scores[i]));
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = AppTokens.progress
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeJoin = StrokeJoin.round,
    );
    for (var i = 0; i < scores.length; i++) {
      canvas.drawCircle(
        Offset(i * dx, y(scores[i])),
        4.5,
        Paint()
          ..color = scores[i] >= ExerciseSession.passMark
              ? AppTokens.progress
              : AppTokens.caution,
      );
    }
  }

  @override
  bool shouldRepaint(_TrendPainter old) => old.scores != scores;
}
