import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:physical_treatment_and_health_support_system/model/business_logic/health_insights_service/report_explanation_service.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/health_insights.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/report_explanation.dart';
import 'package:physical_treatment_and_health_support_system/model/result.dart';

class WeeklyReportService {
  const WeeklyReportService();
  Future<Result<Uint8List>> create(HealthInsights data) => guard(() async {
    final doc = pw.Document(
      title: 'HealthGuide weekly progress report',
      author: 'HealthGuide',
    );
    final teal = PdfColor.fromHex('#116C63'),
        blue = PdfColor.fromHex('#4775B0');
    String safe(String s) => s
        .replaceAll('’', "'")
        .replaceAll('–', '-')
        .replaceAll('—', '-')
        .replaceAll('·', ' / ')
        .replaceAll('→', 'to');
    pw.Widget heading(String s) => pw.Padding(
      padding: const pw.EdgeInsets.only(top: 14, bottom: 7),
      child: pw.Text(
        s,
        style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14),
      ),
    );
    pw.Widget text(String s) => pw.Paragraph(
      text: safe(s),
      style: const pw.TextStyle(fontSize: 10, lineSpacing: 3),
    );
    const explanations = ReportExplanationService();
    List<pw.Widget> explain(
      String title,
      ReportExplanation e, {
      List<DateTime> evidenceDays = const [],
    }) => [
      pw.Inseparable(
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            heading(title),
            text('Conclusion: ${e.conclusion}'),
            text('Analysis: ${e.analysis}'),
            text('Suggested next step: ${e.suggestion}'),
            if (evidenceDays.isNotEmpty)
              text(
                'Evidence dates: ${evidenceDays.map((d) => DateFormat('d MMM').format(d)).join(', ')}',
              ),
          ],
        ),
      ),
    ];
    pw.Widget footer(pw.Context c) => pw.Padding(
      padding: const pw.EdgeInsets.only(top: 12),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'HealthGuide / Personal progress summary',
            style: const pw.TextStyle(fontSize: 8),
          ),
          pw.Text(
            '${c.pageNumber} / ${c.pagesCount}',
            style: const pw.TextStyle(fontSize: 8),
          ),
        ],
      ),
    );
    final max = data.comparison.days.fold<double>(1, (v, d) {
      final high = d.planned.energyKcal > d.logged.energyKcal
          ? d.planned.energyKcal
          : d.logged.energyKcal;
      return high > v ? high : v;
    });
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        footer: footer,
        build: (c) => [
          pw.Text(
            'Weekly progress report',
            style: pw.TextStyle(
              fontSize: 24,
              fontWeight: pw.FontWeight.bold,
              color: teal,
            ),
          ),
          pw.SizedBox(height: 8),
          text(
            '${DateFormat('d MMM yyyy').format(data.start)} - ${DateFormat('d MMM yyyy').format(data.end)} / Evidence through ${DateFormat('d MMM HH:mm').format(data.asOf)}',
          ),
          text(
            data.includesDemo && data.demoCount > 0
                ? 'PRESENTATION DATA INCLUDED: synthetic and real records may be mixed. This report is for demonstrating the system.'
                : 'Presentation data excluded or none found in the loaded history.',
          ),
          ...data.notices.map((n) => text('Data notice: $n')),
          ...explain(
            'Weekly conclusion and next steps',
            explanations.weekly(data),
          ),
          if (data.foodGuidance case final guidance?) ...[
            heading('Weekly food priorities'),
            text(guidance.basis),
            if (guidance.priorities.isEmpty)
              text(
                'No supported food change identified. Review daily coverage before changing portions.',
              ),
            for (final p in guidance.priorities)
              pw.Inseparable(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    heading(p.title),
                    text(p.detail),
                    text(
                      'Evidence: ${p.dates.map((d) => DateFormat('d MMM').format(d)).join(', ')}',
                    ),
                  ],
                ),
              ),
            for (final d in guidance.days)
              pw.Inseparable(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    if (d == guidance.days.first) heading('Daily food review'),
                    heading(DateFormat('EEE, d MMM').format(d.date)),
                    text(d.conclusion),
                    for (final a in d.actions)
                      text('${a.label}: ${a.portion}. ${a.reason}'),
                  ],
                ),
              ),
          ],
          ...data.facts
              .take(3)
              .expand(
                (f) => [
                  ...explain(
                    f.title,
                    explanations.fact(data, f),
                    evidenceDays: f.evidenceDays,
                  ),
                ],
              ),
          pw.Inseparable(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                heading('Daily recorded energy against the saved plan'),
                text(
                  'Blue: saved plan. Green: recorded food. A missing log remains unknown. Planned amounts are reference values; later-created plans cannot establish adherence.',
                ),
                for (final d in data.comparison.days)
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(bottom: 8),
                    child: pw.Row(
                      children: [
                        pw.SizedBox(
                          width: 58,
                          child: pw.Text(
                            DateFormat('EEE d').format(d.date),
                            style: const pw.TextStyle(fontSize: 10),
                          ),
                        ),
                        pw.Expanded(
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              if (d.hasPlan)
                                pw.Container(
                                  height: 7,
                                  width: 340 * d.planned.energyKcal / max,
                                  color: blue,
                                ),
                              pw.SizedBox(height: 3),
                              if (d.hasLogs)
                                pw.Container(
                                  height: 7,
                                  width: 340 * d.logged.energyKcal / max,
                                  color: teal,
                                ),
                            ],
                          ),
                        ),
                        pw.SizedBox(
                          width: 110,
                          child: pw.Text(
                            '${d.hasPlan ? d.planned.energyKcal.round() : 'No plan'} / ${d.hasLogs ? d.logged.energyKcal.round() : 'No log'}',
                            style: const pw.TextStyle(fontSize: 9),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          heading('Observations and next steps'),
          ...data.facts
              .skip(3)
              .expand(
                (f) => [
                  ...explain(
                    f.title,
                    explanations.fact(data, f),
                    evidenceDays: f.evidenceDays,
                  ),
                ],
              ),
          heading('Recovery diary'),
          text(
            'Symptoms are self-reported. Posture scores assess recorded movements. Neither proves recovery or changes prescribed treatment.',
          ),
          for (final r in data.recovery.where(
            (r) => r.checkIns.isNotEmpty || r.sessions.isNotEmpty,
          ))
            ...explain(r.planName, explanations.recovery(r)),
          if (data.recovery.every((r) => r.checkIns.isEmpty))
            text(
              'No recovery check-ins in the loaded 28-day period. Missing entries are unknown.',
            ),
          ...explain(
            'Data coverage and interpretation',
            explanations.quality(data),
          ),
          text(
            'Reading sources in the 120-day history ending at the selected period:',
          ),
          for (final entry in data.sourceCounts.entries)
            text('${safe(entry.key)}: ${entry.value} records'),
          text(
            'Coverage measures completeness, not medical accuracy. Wearable readings remain device estimates. Temporal patterns do not establish cause and effect. Current profile guidance may differ from historical targets. This report supports a conversation with your care team and does not diagnose conditions or recommend treatment changes.',
          ),
        ],
      ),
    );
    return doc.save();
  }, message: 'The PDF could not be prepared. Please try again.');
}
