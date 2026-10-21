import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:physical_treatment_and_health_support_system/viewmodel/ui_state.dart';
import 'package:physical_treatment_and_health_support_system/core/themes/design_tokens.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/exercise_session.dart';
import 'package:physical_treatment_and_health_support_system/view/planning_view/widgets/planning_widgets.dart';
import 'package:physical_treatment_and_health_support_system/view/treatment_view/posture_result_view.dart';
import 'package:physical_treatment_and_health_support_system/view/treatment_view/widgets/treatment_widgets.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/treatment_view_model/treatment_view_model.dart';

/// "Analysing your posture" (UI Design, Posture Analyse Loading Page). The server does all the
/// work in one request, so the middle steps advance on a timer and every step completes when
/// the result arrives; a step is never shown as done before the upload has started.
class AnalysingView extends StatefulWidget {
  final File file;
  final int? clipSeconds;
  const AnalysingView({super.key, required this.file, this.clipSeconds});

  @override
  State<AnalysingView> createState() => _AnalysingViewState();
}

class _AnalysingViewState extends State<AnalysingView> {
  static const steps = [
    'Video received',
    'Body landmarks extracted',
    'Analysing posture',
    'Calculating accuracy score',
  ];
  int _step = 0; // index of the step in progress
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _run() async {
    final vm = context.read<TreatmentViewModel>();
    setState(() => _step = 1);
    _timer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (_step < steps.length - 1) setState(() => _step++);
    });
    await vm.submitVideo(widget.file, clipSeconds: widget.clipSeconds);
    _timer?.cancel();
    if (!mounted) return;
    if (vm.analysis is UiSuccess<PostureResult>) {
      setState(() => _step = steps.length);
      await Future<void>.delayed(const Duration(milliseconds: 400));
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => ChangeNotifierProvider.value(
            value: vm,
            child: const PostureResultView(),
          ),
        ),
      );
    } else {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<TreatmentViewModel>();
    final error = switch (vm.analysis) {
      UiError(:final message) => message,
      _ => null,
    };
    return Scaffold(
      backgroundColor: AppTokens.background,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppTokens.gutter),
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Analysing your posture',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w600,
                      color: AppTokens.text,
                    ),
                  ),
                ),
                ExitExerciseButton(
                  confirm: error == null
                      ? 'Leave this exercise? The video is still being checked and '
                            'this attempt will not be saved.'
                      : null,
                ),
              ],
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
            const SizedBox(height: 20),
            AspectRatio(
              aspectRatio: 1.05,
              child: Container(
                decoration: BoxDecoration(
                  color: AppTokens.primary,
                  borderRadius: BorderRadius.circular(AppTokens.radiusCard),
                ),
                child: Center(
                  child: error == null
                      ? const SizedBox(
                          width: 64,
                          height: 64,
                          child: CircularProgressIndicator(
                            strokeWidth: 5,
                            color: AppTokens.progress,
                            backgroundColor: Colors.white24,
                          ),
                        )
                      : const Icon(
                          Icons.error_outline,
                          color: AppTokens.onPrimaryMuted,
                          size: 64,
                        ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (error == null)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: AppTokens.surface,
                  borderRadius: BorderRadius.circular(AppTokens.radiusCard),
                  border: Border.all(color: AppTokens.border),
                ),
                child: Column(
                  children: [
                    for (var i = 0; i < steps.length; i++)
                      _StepRow(
                        label: steps[i],
                        state: i < _step
                            ? 2
                            : i == _step
                            ? 1
                            : 0,
                      ),
                  ],
                ),
              )
            else ...[
              NoticeBanner(error, warning: true), // FR300_16 / 17 / 25 / 26
              const SizedBox(height: AppTokens.gutter),
              TokenButton(
                label:
                    'Record again', // FR300_18: show the instructions and capture again
                color: AppTokens.action,
                onPressed: () {
                  vm.retry();
                  Navigator.of(context).pop();
                },
              ),
            ],
            const SizedBox(height: 16),
            if (error == null)
              const Text(
                'This usually takes a few seconds',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: AppTokens.accent),
              ),
          ],
        ),
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  final String label;
  final int state; // 0 pending, 1 in progress, 2 done
  const _StepRow({required this.label, required this.state});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      children: [
        Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: state == 2 ? AppTokens.goodContainer : Colors.transparent,
            border: Border.all(
              color: state == 1
                  ? AppTokens.primary
                  : state == 2
                  ? AppTokens.goodContainer
                  : AppTokens.border,
              width: 2,
            ),
          ),
          child: state == 2
              ? const Icon(Icons.check, size: 16, color: AppTokens.good)
              : state == 1
              ? Center(
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: const BoxDecoration(
                      color: AppTokens.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                )
              : null,
        ),
        const SizedBox(width: 14),
        // Expanded: wraps with large phone text instead of overflowing (22 Oct).
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 16,
              fontWeight: state == 1 ? FontWeight.w600 : FontWeight.w500,
              color: state == 0 ? AppTokens.textMuted : AppTokens.text,
            ),
          ),
        ),
      ],
    ),
  );
}
