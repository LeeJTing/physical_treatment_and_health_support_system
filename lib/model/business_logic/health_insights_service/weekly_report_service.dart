import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:physical_treatment_and_health_support_system/model/entity/health_insights.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/plan_comparison.dart';
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
    pw.Widget footer(pw.Context c) => pw.Row(
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
          ...data.facts
              .take(3)
              .expand(
                (f) => [
                  heading(f.title),
                  text(f.text),
                  text(
                    'Evidence dates: ${f.evidenceDays.map((d) => DateFormat('d MMM').format(d)).join(', ')}',
                  ),
                ],
              ),
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
    );
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        footer: footer,
        build: (c) => [
          heading('Observations and next steps'),
          ...data.facts
              .skip(3)
              .expand(
                (f) => [
                  heading(f.title),
                  text(f.text),
                  text(
                    'Evidence dates: ${f.evidenceDays.map((d) => DateFormat('d MMM').format(d)).join(', ')}',
                  ),
                ],
              ),
          heading('Recovery diary'),
          text(
            'Symptoms are self-reported. Posture scores assess recorded movements. Neither proves recovery or changes prescribed treatment.',
          ),
          for (final r in data.recovery.where((r) => r.checkIns.isNotEmpty))
            text(
              '${r.planName}: ${r.checkIns.length} check-ins. Latest pain ${r.checkIns.last.pain}/10; stiffness ${r.checkIns.last.stiffness}/10; difficulty ${r.checkIns.last.difficulty}/5. ${r.painChange == null ? 'More than one check-in is needed for change.' : 'Pain change from first to last: ${r.painChange! >= 0 ? '+' : ''}${r.painChange!.round()} points.'}',
            ),
          if (data.recovery.every((r) => r.checkIns.isEmpty))
            text(
              'No recovery check-ins in the loaded 28-day period. Missing entries are unknown.',
            ),
          heading('Data coverage and interpretation'),
          text(
            '${data.loggedDays}/${data.elapsedDays} elapsed days have meal logs; ${data.completeMealDays} days have all three main meals recorded. ${data.invalidReadings} invalid readings excluded. ${data.comparison.count(MealComparisonStatus.close)} meals close to plan out of ${data.comparison.compared.length} comparable meals.',
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
