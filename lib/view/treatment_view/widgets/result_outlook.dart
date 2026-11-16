import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:physical_treatment_and_health_support_system/core/constants/exercise_evidence.dart';
import 'package:physical_treatment_and_health_support_system/core/themes/design_tokens.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/progress_projection/progress_projection.dart';
import 'package:physical_treatment_and_health_support_system/view/treatment_view/widgets/treatment_widgets.dart';

/// The icon of each kind of benefit (the text comes from ExerciseEvidence).
IconData _benefitIcon(BenefitKind kind) => switch (kind) {
  BenefitKind.pain => Icons.healing_outlined,
  BenefitKind.walking => Icons.directions_walk,
  BenefitKind.strength => Icons.fitness_center,
  BenefitKind.standing => Icons.chair_outlined,
  BenefitKind.falls => Icons.shield_outlined,
  BenefitKind.movement => Icons.open_with,
  BenefitKind.hand => Icons.back_hand_outlined,
  BenefitKind.practice => Icons.repeat,
  BenefitKind.daily => Icons.accessibility_new,
};

String _day(DateTime t) {
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
  return '${t.day} ${months[t.month - 1]}';
}

const _heading = TextStyle(
  fontSize: 16,
  fontWeight: FontWeight.w600,
  color: AppTokens.accent,
);
const _body = TextStyle(fontSize: 15, height: 1.4, color: AppTokens.text);
const _lead = TextStyle(
  fontSize: 17,
  height: 1.3,
  fontWeight: FontWeight.w600,
  color: AppTokens.text,
);
const _small = TextStyle(
  fontSize: 13,
  height: 1.35,
  color: AppTokens.textMuted,
);

/// Under the score (15 Nov): where the patient is in the plan, as dots, with "Well done!" when
/// the exercise was passed. The reward and the progress come before anything else.
class PlanProgressDots extends StatelessWidget {
  final int done;
  final int total;
  final bool celebrate;
  const PlanProgressDots({
    super.key,
    required this.done,
    required this.total,
    this.celebrate = false,
  });

  @override
  Widget build(BuildContext context) => Semantics(
    label: celebrate
        ? 'Well done! $done of $total exercises done'
        : '$done of $total exercises done',
    child: ExcludeSemantics(
      child: Column(
        children: [
          if (celebrate) ...[
            const Text(
              'Well done!',
              key: Key('result_well_done'),
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppTokens.good,
              ),
            ),
            const SizedBox(height: 8),
          ],
          // Dots for a plan of up to eight exercises (every plan in the catalogue); a bar beyond.
          if (total <= 8)
            Wrap(
              spacing: 8,
              children: [
                for (var i = 0; i < total; i++)
                  Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i < done ? AppTokens.progress : AppTokens.surface,
                      border: Border.all(
                        color: i < done ? AppTokens.progress : AppTokens.border,
                        width: 2,
                      ),
                    ),
                  ),
              ],
            )
          else
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: total == 0 ? 0 : done / total,
                minHeight: 8,
                color: AppTokens.progress,
                backgroundColor: AppTokens.border,
              ),
            ),
          const SizedBox(height: 6),
          Text(
            '$done of $total exercises done',
            key: const Key('result_plan_progress'),
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppTokens.text,
            ),
          ),
        ],
      ),
    ),
  );
}

/// "Why it helps": the benefits in the patient's words, each with an icon; the research is one
/// line (the source, which opens the study, and "More"). "More" opens the review's numbers, its
/// finding and the full citation (Elwin, 10, 11 and 15 Nov).
class EvidenceCard extends StatefulWidget {
  final EvidenceGroup group;
  final bool passing;

  /// Opens the study (TreatmentViewModel.openStudy): the message to show when it could not be
  /// opened, else null.
  final Future<String?> Function() onOpenStudy;
  const EvidenceCard({
    super.key,
    required this.group,
    required this.passing,
    required this.onOpenStudy,
  });

  @override
  State<EvidenceCard> createState() => _EvidenceCardState();
}

class _EvidenceCardState extends State<EvidenceCard> {
  bool _open = false;

  Future<void> _openLink() async {
    final problem = await widget.onOpenStudy();
    if (problem != null && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(problem)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final group = widget.group;
    final passing = widget.passing;
    return TreatmentCard(
      key: const Key('evidence_card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Wrap: with large phone text the group chip moves under the title.
          Wrap(
            spacing: 10,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.favorite_outline,
                    size: 20,
                    color: AppTokens.accent,
                  ),
                  SizedBox(width: 8),
                  Flexible(child: Text('Why it helps', style: _heading)),
                ],
              ),
              _Chip(group.title),
            ],
          ),
          const SizedBox(height: 12),
          for (final b in group.benefits)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: const BoxDecoration(
                      color: AppTokens.accentContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _benefitIcon(b.kind),
                      size: 22,
                      color: AppTokens.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text(b.text, style: _lead)),
                ],
              ),
            ),
          Row(
            children: [
              Icon(
                passing
                    ? Icons.check_circle_outline
                    : Icons.tips_and_updates_outlined,
                size: 18,
                color: passing ? AppTokens.good : AppTokens.caution,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  passing
                      ? ExerciseEvidence.whenPassing
                      : ExerciseEvidence.whenBelow,
                  style: const TextStyle(fontSize: 14, color: AppTokens.text),
                ),
              ),
            ],
          ),
          const Divider(height: 20, color: AppTokens.border),
          // The research in one line: the source opens the study, More opens the details.
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              TextButton.icon(
                key: const Key('evidence_link'),
                onPressed: _openLink,
                icon: const Icon(Icons.open_in_new, size: 16),
                label: Text(group.source.citation),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  minimumSize: const Size(0, AppTokens.minTarget),
                ),
              ),
              TextButton.icon(
                key: const Key('evidence_more'),
                onPressed: () => setState(() => _open = !_open),
                icon: Icon(
                  _open ? Icons.expand_less : Icons.expand_more,
                  size: 20,
                ),
                label: Text(_open ? 'Less' : 'More'),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  minimumSize: const Size(0, AppTokens.minTarget),
                ),
              ),
            ],
          ),
          const Text(ExerciseEvidence.caveat, style: _small),
          if (_open) ...[
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final (i, f) in group.facts.indexed) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(child: _Tile(f.value, f.label)),
                ],
              ],
            ),
            const SizedBox(height: 10),
            Text(group.finding, style: _body),
            const SizedBox(height: 8),
            Text(
              '${group.source.citation}. ${group.source.title}. ${group.source.journal}.',
              style: _small,
            ),
            const SizedBox(height: 6),
            const Text(ExerciseEvidence.caveatMore, style: _small),
          ],
        ],
      ),
    );
  }
}

/// "Your outlook": the plan's finish date as the key number, the projected score (once there is
/// a trend) and the exercises left; the graph of the patient's scores with the projection; the
/// study result in one line (Elwin, 10, 11 and 15 Nov).
class OutlookCard extends StatelessWidget {
  final ProgressProjection projection;
  final int sessionsPerWeek;
  final DateTime planStart;
  final EvidenceGroup? group;
  const OutlookCard({
    super.key,
    required this.projection,
    required this.sessionsPerWeek,
    required this.planStart,
    this.group,
  });

  @override
  Widget build(BuildContext context) {
    final p = projection;
    final done = p.remainingExercises == 0;
    final trend = p.past.length >= 2;
    final g = group;
    final studyWeek = g?.weeks == null
        ? null
        : planStart.add(Duration(days: g!.weeks! * 7));
    final tries = p.triesPerExercise <= 1.05
        ? '1 try'
        : '${p.triesPerExercise.toStringAsFixed(1)} tries';
    return TreatmentCard(
      key: const Key('outlook_card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.insights_outlined, size: 20, color: AppTokens.accent),
              SizedBox(width: 8),
              Expanded(child: Text('Your outlook', style: _heading)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // The one number in the accent colour: when the plan should be finished.
              Expanded(
                child: _Tile(
                  done ? 'Done' : _day(p.finishDate),
                  'plan\nfinish',
                  key: const Key('outlook_finish'),
                  emphasis: true,
                ),
              ),
              // No empty tile: the projected score appears once there is a trend.
              if (trend) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: _Tile(
                    '${p.projectedAtFinish.round()}%',
                    'score\nby then',
                    key: const Key('outlook_score'),
                  ),
                ),
              ],
              const SizedBox(width: 8),
              Expanded(
                child: _Tile('${p.remainingExercises}', 'exercises\nleft'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (trend) ...[
            Semantics(
              label:
                  'Posture scores in this plan: ${p.past.length} so far, the latest '
                  '${p.past.last.accuracy.round()}%, projected '
                  '${p.projectedAtFinish.round()}% by ${_day(p.finishDate)}',
              child: SizedBox(
                height: 150,
                width: double.infinity,
                child: CustomPaint(
                  painter: _OutlookPainter(p, studyWeek: studyWeek),
                ),
              ),
            ),
            const SizedBox(height: 6),
            const Wrap(
              spacing: 14,
              runSpacing: 4,
              children: [
                _Legend(color: AppTokens.progress, label: 'Your scores'),
                _Legend(
                  color: AppTokens.progress,
                  label: 'Projected',
                  dashed: true,
                ),
                _Legend(
                  color: AppTokens.textMuted,
                  label: '80% pass',
                  dashed: true,
                ),
              ],
            ),
          ] else
            const _Line(
              Icons.timeline,
              'One more try shows your trend.',
              key: Key('outlook_need_more'),
            ),
          if (p.reachesPassMark != null)
            _Line(
              Icons.flag_outlined,
              '80% by about ${_day(p.reachesPassMark!)}',
            ),
          if (g != null)
            _Line(
              Icons.menu_book_outlined,
              g.weeks != null
                  ? 'Studies: ${g.outcome} by week ${g.weeks}'
                  : 'Studies: ${g.outcome}',
              key: const Key('outlook_study'),
            ),
          _Line(
            Icons.speed_outlined,
            'Pace: $tries per exercise · $sessionsPerWeek× a week',
          ),
          const SizedBox(height: 4),
          const Text(
            'Estimate from your scores, not a medical prediction.',
            style: _small,
          ),
        ],
      ),
    );
  }
}

/// A key number: the value large, its label small underneath. Neutral by default; [emphasis]
/// gives the one number that matters most the accent colour.
class _Tile extends StatelessWidget {
  final String value;
  final String label;
  final bool emphasis;
  const _Tile(this.value, this.label, {super.key, this.emphasis = false});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
    decoration: BoxDecoration(
      color: emphasis ? AppTokens.primary : AppTokens.background,
      borderRadius: BorderRadius.circular(12),
      border: emphasis ? null : Border.all(color: AppTokens.border),
    ),
    child: Column(
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            maxLines: 1,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: emphasis ? Colors.white : AppTokens.text,
            ),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            height: 1.25,
            color: emphasis ? AppTokens.onPrimaryMuted : AppTokens.textBody,
          ),
        ),
      ],
    ),
  );
}

class _Chip extends StatelessWidget {
  final String text;
  const _Chip(this.text);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: AppTokens.accentContainer,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: AppTokens.primary,
      ),
    ),
  );
}

/// One short fact with an icon.
class _Line extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Line(this.icon, this.text, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: AppTokens.textBody),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 14, color: AppTokens.text),
          ),
        ),
      ],
    ),
  );
}

class _Legend extends StatelessWidget {
  final Color color;
  final String label;
  final bool dashed;
  const _Legend({
    required this.color,
    required this.label,
    this.dashed = false,
  });

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      SizedBox(
        width: 22,
        height: 10,
        child: CustomPaint(painter: _LegendLine(color, dashed)),
      ),
      const SizedBox(width: 6),
      Text(label, style: _small),
    ],
  );
}

class _LegendLine extends CustomPainter {
  final Color color;
  final bool dashed;
  _LegendLine(this.color, this.dashed);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.5;
    final y = size.height / 2;
    if (!dashed) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
      return;
    }
    for (double x = 0; x < size.width; x += 8) {
      canvas.drawLine(
        Offset(x, y),
        Offset(math.min(x + 4, size.width), y),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_LegendLine old) => false;
}

/// Scores so far (solid), the projection to the finish date (dashed), the 80% line, and the week
/// the study measured, when it falls inside the chart.
class _OutlookPainter extends CustomPainter {
  final ProgressProjection p;
  final DateTime? studyWeek;
  _OutlookPainter(this.p, {this.studyWeek});

  @override
  void paint(Canvas canvas, Size size) {
    final start = p.past.isEmpty ? DateTime.now() : p.past.first.at;
    var end = p.finishDate;
    final sw = studyWeek;
    if (sw != null && sw.isAfter(end)) end = sw;
    final spanH = math.max(1, end.difference(start).inHours);
    // Room for the percentage labels on the left and the dates underneath.
    const left = 40.0, right = 8.0, top = 6.0, bottom = 18.0;
    double x(DateTime t) =>
        left +
        (t.difference(start).inHours / spanH) * (size.width - left - right);
    double y(double v) =>
        top + (1 - v.clamp(0, 100) / 100) * (size.height - top - bottom);

    void label(String text, Offset at, {bool alignRight = false}) {
      final tp = TextPainter(
        text: TextSpan(
          text: text,
          style: const TextStyle(fontSize: 11, color: AppTokens.textMuted),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(alignRight ? at.dx - tp.width : at.dx, at.dy));
    }

    for (final v in const [100.0, 80.0, 0.0]) {
      label('${v.round()}%', Offset(left - 6, y(v) - 7), alignRight: true);
    }
    final bottomY = size.height - bottom + 4;
    label(_day(start), Offset(left, bottomY));
    label(_day(end), Offset(size.width - right, bottomY), alignRight: true);
    canvas.drawLine(
      Offset(left, y(0)),
      Offset(size.width - right, y(0)),
      Paint()
        ..color = AppTokens.border
        ..strokeWidth = 1,
    );

    void dashedLine(Offset a, Offset b, Paint paint) {
      final d = (b - a).distance;
      if (d == 0) return;
      final dir = (b - a) / d;
      for (double s = 0; s < d; s += 9) {
        canvas.drawLine(a + dir * s, a + dir * math.min(s + 5, d), paint);
      }
    }

    final muted = Paint()
      ..color = AppTokens.textMuted
      ..strokeWidth = 1;
    dashedLine(Offset(left, y(80)), Offset(size.width - right, y(80)), muted);

    if (sw != null) {
      final sx = x(sw);
      dashedLine(Offset(sx, y(100)), Offset(sx, y(0)), muted);
      final tp = TextPainter(
        text: const TextSpan(
          text: 'Study result',
          style: TextStyle(fontSize: 11, color: AppTokens.textMuted),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(math.max(left, sx - tp.width - 4), y(100)));
    }

    final line = Paint()
      ..color = AppTokens.progress
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;
    if (p.past.isNotEmpty) {
      final path = Path()..moveTo(x(p.past.first.at), y(p.past.first.accuracy));
      for (final pt in p.past.skip(1)) {
        path.lineTo(x(pt.at), y(pt.accuracy));
      }
      canvas.drawPath(path, line);
      final lastPt = p.past.last;
      dashedLine(
        Offset(x(lastPt.at), y(lastPt.accuracy)),
        Offset(x(p.finishDate), y(p.projectedAtFinish)),
        Paint()
          ..color = AppTokens.progress
          ..strokeWidth = 2.5,
      );
      for (final pt in p.past) {
        canvas.drawCircle(
          Offset(x(pt.at), y(pt.accuracy)),
          4.5,
          Paint()
            ..color = pt.accuracy >= 80
                ? AppTokens.progress
                : AppTokens.caution,
        );
      }
    }
    // The finish date at the end of the projection.
    canvas.drawCircle(
      Offset(x(p.finishDate), y(p.projectedAtFinish)),
      4,
      Paint()
        ..color = AppTokens.surface
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      Offset(x(p.finishDate), y(p.projectedAtFinish)),
      4,
      Paint()
        ..color = AppTokens.progress
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_OutlookPainter old) =>
      old.p != p || old.studyWeek != studyWeek;
}
