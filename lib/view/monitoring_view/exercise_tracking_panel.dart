import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:physical_treatment_and_health_support_system/core/themes/design_tokens.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/biometric_reading.dart';
import 'package:physical_treatment_and_health_support_system/view/common/trend_chart.dart';
import 'package:physical_treatment_and_health_support_system/view/common/tidy_text.dart';

/// Uses the same chart interaction as readings, with actual completed sessions as evidence.
class ExerciseTrackingPanel extends StatefulWidget {
  final List<ActivityRecord> sessions;
  final DateTime from, to;
  final bool available;
  final VoidCallback onRetry;
  const ExerciseTrackingPanel({
    super.key,
    required this.sessions,
    required this.from,
    required this.to,
    required this.onRetry,
    this.available = true,
  });
  @override
  State<ExerciseTrackingPanel> createState() => _ExerciseTrackingPanelState();
}

class _ExerciseTrackingPanelState extends State<ExerciseTrackingPanel> {
  bool daily = false;
  DateTime day(DateTime at) => DateTime(at.year, at.month, at.day);
  String duration(ActivityRecord s) => !s.durationRecorded
      ? 'Duration not recorded'
      : '${s.durationSec ~/ 60} min ${s.durationSec % 60} sec';
  Widget details(ActivityRecord s) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(s.exerciseName, style: const TextStyle(fontWeight: FontWeight.w700)),
      Text(
        'Completed: ${DateFormat('d MMM yyyy, HH:mm:ss').format(s.completedAt)}',
      ),
      Text(duration(s)),
      if (s.planName != null) Text('Plan: ${s.planName}'),
      if (s.repetitions != null) Text('Repetitions: ${s.repetitions}'),
      if (s.postureAccuracy != null)
        Text('Posture result: ${s.postureAccuracy!.toStringAsFixed(1)}%'),
      if (s.isDemo) const Text('Presentation demo (synthetic)'),
    ],
  );
  @override
  Widget build(BuildContext context) {
    if (!widget.available) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Exercise history could not be loaded. Your session totals are unavailable.',
          ),
          TextButton(
            onPressed: widget.onRetry,
            child: const Text('Retry exercise history'),
          ),
        ],
      );
    }
    final sessions = [...widget.sessions]
      ..sort((a, b) => a.completedAt.compareTo(b.completedAt));
    final known = sessions.where((s) => s.durationRecorded).toList();
    final groups = <DateTime, List<ActivityRecord>>{};
    for (final s in sessions) {
      (groups[day(s.completedAt)] ??= []).add(s);
    }
    final total = known.fold<int>(0, (a, s) => a + s.durationSec) / 60;
    final points = daily
        ? [
            for (final g in groups.entries)
              if (g.value.any((s) => s.durationRecorded))
                ChartPoint(
                  g.key,
                  g.value
                          .where((s) => s.durationRecorded)
                          .fold<int>(0, (a, s) => a + s.durationSec) /
                      60,
                ),
          ]
        : [
            for (final s in known)
              ChartPoint(s.completedAt, s.durationSec / 60),
          ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Exercise sessions',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          '${sessions.length} completed session${sessions.length == 1 ? '' : 's'} · ${groups.length} day${groups.length == 1 ? '' : 's'}',
          key: const ValueKey('tracking-exercise-count'),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        Text('Recorded exercise time: ${total.toStringAsFixed(1)} minutes'),
        if (known.length < sessions.length)
          Text(
            '${sessions.length - known.length} session duration${sessions.length - known.length == 1 ? ' is' : 's are'} not recorded; excluded from plotted totals.',
          ),
        const SizedBox(height: 12),
        SegmentedButton<bool>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: false, label: OneLineText('By session',alignment:Alignment.center)),
            ButtonSegment(value: true, label: OneLineText('Daily total',alignment:Alignment.center)),
          ],
          selected: {daily},
          onSelectionChanged: (v) => setState(() => daily = v.first),
        ),
        const SizedBox(height: 10),
        const Text(
          'Tap a point for details. Pinch to zoom; drag to move when zoomed.',
          style: TextStyle(fontSize: 13, color: AppTokens.inkMuted),
        ),
        if (points.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Text(
              sessions.isEmpty
                  ? 'No completed exercise sessions in this period. Finish an exercise in Treatment to see it here.'
                  : 'Session durations have not been recorded. Completion details are listed below.',
            ),
          )
        else
          TrendChart(
            key: ValueKey('exercise-${widget.from}-${widget.to}-$daily'),
            height: 260,
            unit: 'minutes',
            inspectable: true,
            zoomable: true,
            interactionId: 'tracking-exercise-chart',
            series: [
              ChartSeries(
                daily ? 'Recorded minutes per day' : 'Minutes per session',
                points,
                AppTokens.progress,
              ),
            ],
            inspectionBuilder: (at) {
              final selected = sessions
                  .where(
                    (s) =>
                        daily ? day(s.completedAt) == at : s.completedAt == at,
                  )
                  .toList();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (daily) ...[
                    Text(
                      DateFormat('d MMM yyyy').format(at),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      '${selected.length} completed sessions · ${(selected.where((s) => s.durationRecorded).fold<int>(0, (a, s) => a + s.durationSec) / 60).toStringAsFixed(1)} recorded minutes',
                    ),
                  ],
                  for (final s in selected)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: details(s),
                    ),
                ],
              );
            },
          ),
        const SizedBox(height: 16),
        const Text(
          'Recent exercise sessions',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const Text(
          'Completed treatment records. Days without a saved session remain unknown.',
          style: TextStyle(fontSize: 13, color: AppTokens.inkMuted),
        ),
        for (final s in sessions.reversed.take(30))
          Material(
            color: Colors.transparent,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(
                Icons.accessibility_new,
                color: AppTokens.brandDeep,
              ),
              title: Text(s.exerciseName),
              subtitle: Text(
                '${DateFormat('d MMM, HH:mm').format(s.completedAt)} · ${duration(s)}${s.isDemo ? ' · Demo' : ''}',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                builder: (_) => SafeArea(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: details(s),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
