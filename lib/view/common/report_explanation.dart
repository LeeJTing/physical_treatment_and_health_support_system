import 'package:flutter/material.dart';
import 'package:physical_treatment_and_health_support_system/core/themes/design_tokens.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/report_explanation.dart';

class ReportExplanationBody extends StatelessWidget {
  final ReportExplanation explanation;
  const ReportExplanationBody(this.explanation, {super.key});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final entry in [
        ('Conclusion', explanation.conclusion),
        ('Analysis', explanation.analysis),
        ('Suggested next step', explanation.suggestion),
      ]) ...[
        Text(
          entry.$1,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            color: AppTokens.brandDeep,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          entry.$2,
          style: const TextStyle(height: 1.5, color: AppTokens.ink),
        ),
        const SizedBox(height: 12),
      ],
    ],
  );
}
