import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:physical_treatment_and_health_support_system/core/constants/app_constants.dart';
import 'package:physical_treatment_and_health_support_system/core/routes/routes.dart';
import 'package:physical_treatment_and_health_support_system/core/themes/design_tokens.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/anomaly_event.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/health_analysis.dart';
import 'package:physical_treatment_and_health_support_system/view/common/trend_chart.dart';
import 'package:physical_treatment_and_health_support_system/view/common/user_guide.dart';
import 'package:physical_treatment_and_health_support_system/view/health_report_view/high_alert_view.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/analysis_view_model/analysis_view_model.dart';

/// Health Report (UC600; Table 4.58; Figma "Health Report"): the Health Score with its band, its
/// factors and the comparison with the previous period; the risk for each declared condition with
/// its three main factors; the forecast of each metric drawn with its history; the anomalies in
/// plain language with the size in the patient's own units; and the non-medical disclaimer with
/// the forecast and again with the score (M1).
class HealthReportView extends StatefulWidget {
  const HealthReportView({super.key});

  @override
  State<HealthReportView> createState() => _HealthReportViewState();
}

class _HealthReportViewState extends State<HealthReportView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    final vm = context.read<AnalysisViewModel>();
    await vm.loadAnalysis();
    if (!mounted) return;
    final high = vm.takeHighAlert();
    if (high != null) await HighAlertView.show(context, high); // A3
    if (mounted) await showGuideOnce(context, Guides.healthReport); // first visit only
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<AnalysisViewModel>();
    return Scaffold(
      backgroundColor: AppTokens.screenBackground,
      appBar: AppBar(
        title: const Text('Health Report'),
        backgroundColor: AppTokens.brandDeep,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Reminders and notification history',
            icon: const Icon(Icons.notifications_none),
            onPressed: () => Navigator.of(context).pushNamed(Routes.reminders), // A4, A5
          ),
          const HelpButton(guide: Guides.healthReport),
        ],
      ),
      body: !vm.loaded && vm.isLoading
          ? const _PreparingReport()
          : RefreshIndicator(
              onRefresh: _run,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(AppTokens.gutter, 16, AppTokens.gutter, 32),
                children: [
                  if (vm.running) const _Updating(),
                  if (vm.notice != null) _Notice(vm.notice!),
                  _ScoreCard(analysis: vm.analysis, comparison: vm.analysis?.periodComparison),
                  const SizedBox(height: 12),
                  if (vm.analysis?.summaryText case final s?) _card(
                    Text(s, style: const TextStyle(fontSize: 16, height: 1.4, color: AppTokens.ink)),
                  ),
                  const SizedBox(height: 12),
                  _scoreTrend(vm),
                  const SizedBox(height: 20),
                  _title('Readings that need attention'),
                  if (vm.anomalyHistory.isEmpty && vm.running)
                    _card(const Text('Checking your latest readings...', style: TextStyle(fontSize: 16, color: AppTokens.inkMuted)))
                  else if (vm.anomalyHistory.isEmpty)
                    _card(const Text(Messages.withinRange, style: TextStyle(fontSize: 16, color: AppTokens.ink))) // M6
                  else
                    for (final a in vm.anomalyHistory.take(10)) _AnomalyTile(a),
                  const SizedBox(height: 20),
                  _title('Risk for your conditions'),
                  ..._risks(vm.analysis),
                  const SizedBox(height: 20),
                  _title('Forecast for the next 7 days'),
                  for (final m in MetricType.values) _forecastCard(vm, m),
                  const SizedBox(height: 8),
                  const _Disclaimer(),
                ],
              ),
            ),
    );
  }

  Widget _title(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(t, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppTokens.ink)),
  );

  Widget _card(Widget child) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppTokens.surface,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: AppTokens.cardBorder),
    ),
    child: child,
  );

  /// Health Score trend over a selected range (FR400_025).
  Widget _scoreTrend(AnalysisViewModel vm) => _card(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text('Score trend', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppTokens.ink)),
            ),
            for (final d in const [7, 30, 90])
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: ChoiceChip(
                  label: Text('${d}d'),
                  selected: vm.trendDays == d,
                  onSelected: (_) => vm.scoreTrend(d),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        if (vm.trendLoading) ...[
          const LinearProgressIndicator(color: AppTokens.brandDeepAccent, backgroundColor: AppTokens.tint),
          const SizedBox(height: 8),
        ],
        if (vm.trend.where((a) => a.healthScore != null).length < 2)
          const Text('The trend appears after scores on two different days.',
              style: TextStyle(fontSize: 15, color: AppTokens.inkMuted))
        else
          TrendChart(
            height: 150,
            unit: 'points',
            series: [
              ChartSeries('Health Score', [
                for (final a in vm.trend)
                  if (a.healthScore != null) ChartPoint(a.analysisDate, a.healthScore!.toDouble()),
              ], AppTokens.brandDeepAccent),
            ],
          ),
      ],
    ),
  );

  List<Widget> _risks(HealthAnalysis? a) {
    final risks = a?.risks() ?? const <ConditionRisk>[];
    if (risks.isEmpty) {
      return [
        _card(const Text('No health condition is declared in your profile, so there is no condition risk to show.',
            style: TextStyle(fontSize: 16, color: AppTokens.inkMuted))),
      ];
    }
    return [
      for (final r in risks)
        _card(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(r.conditionName,
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppTokens.ink)),
                  ),
                  if (r.risk != null) _RiskPill(r.risk!),
                ],
              ),
              const SizedBox(height: 6),
              if (r.withheld)
                Text(r.message ?? 'Not available yet.', style: const TextStyle(fontSize: 15, color: AppTokens.inkMuted)) // M9
              else ...[
                const Text('What contributes most:', style: TextStyle(fontSize: 15, color: AppTokens.inkMuted)),
                for (final f in r.topFactors)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('• $f', style: const TextStyle(fontSize: 15, color: AppTokens.ink)),
                  ),
              ],
              const SizedBox(height: 8),
              const Text(Messages.analysisDisclaimer, style: TextStyle(fontSize: 12, color: AppTokens.inkMuted)),
            ],
          ),
        ),
    ];
  }

  /// The forecast drawn with the history on one chart (FR400_004), or why it is withheld (M2).
  Widget _forecastCard(AnalysisViewModel vm, MetricType m) {
    final f = vm.forecasts[m];
    final hist = f?.history ?? const [];
    final pts = f?.forecast?.points() ?? const [];
    final recent = hist.where((r) => r.recordedAt.isAfter(DateTime.now().subtract(const Duration(days: 30)))).toList();
    final usual = vm.usualRange(m);
    return _card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(m.label, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppTokens.ink)),
          if (usual != null)
            Text('Your usual range (30 days): $usual', style: const TextStyle(fontSize: 14, color: AppTokens.inkMuted)),
          const SizedBox(height: 10),
          if (f == null || (f.insufficient && hist.isEmpty))
            const Text(Messages.insufficientData, style: TextStyle(fontSize: 15, color: AppTokens.inkMuted))
          else ...[
            if (f.insufficient)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text(Messages.insufficientData, style: TextStyle(fontSize: 15, color: AppTokens.inkMuted)),
              ),
            if (f.stale)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text('Showing your last available forecast.', style: TextStyle(fontSize: 14, color: AppTokens.onWarn)),
              ),
            TrendChart(
              unit: m.unit,
              guide: m == MetricType.bloodPressure ? 140 : null,
              guideLabel: m == MetricType.bloodPressure ? '140 mmHg' : null,
              series: [
                ChartSeries(m == MetricType.bloodPressure ? 'Systolic' : m.label,
                    [for (final r in recent) ChartPoint(r.recordedAt, r.primaryValue)], AppTokens.cta),
                if (pts.isNotEmpty)
                  ChartSeries(
                    m == MetricType.bloodPressure ? 'Systolic' : m.label,
                    [for (final p in pts) ChartPoint(p.date, p.value, low: p.lower, high: p.upper)],
                    AppTokens.cta,
                    forecast: true,
                  ),
                if (m == MetricType.bloodPressure) ...[
                  ChartSeries('Diastolic', [
                    for (final r in recent)
                      if (r.secondaryValue != null) ChartPoint(r.recordedAt, r.secondaryValue!),
                  ], AppTokens.brandDeepAccent),
                  if (pts.any((p) => p.secondaryValue != null))
                    ChartSeries('Diastolic', [
                      for (final p in pts)
                        if (p.secondaryValue != null) ChartPoint(p.date, p.secondaryValue!),
                    ], AppTokens.brandDeepAccent, forecast: true),
                ],
              ],
            ),
            if (vm.forecastSummary(m) case final summary?)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(summary, style: const TextStyle(fontSize: 15, color: AppTokens.ink)),
              ),
            if (f.forecast != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Model ${f.forecast!.modelVersion} · ${f.forecast!.inputReadingCount} readings',
                  style: const TextStyle(fontSize: 12, color: AppTokens.inkMuted),
                ),
              ),
          ],
          const SizedBox(height: 6),
          const Text(Messages.analysisDisclaimer, style: TextStyle(fontSize: 12, color: AppTokens.inkMuted)), // FR400_006
        ],
      ),
    );
  }
}

/// The score, its band, its factors and the comparison (FR400_020 to FR400_023, FR400_032), with
/// the disclaimer inside the card (FR400_033).
class _ScoreCard extends StatelessWidget {
  final HealthAnalysis? analysis;
  final PeriodComparison? comparison;
  const _ScoreCard({required this.analysis, this.comparison});

  @override
  Widget build(BuildContext context) {
    final a = analysis;
    final score = a?.healthScore;
    final band = a?.scoreBand;
    final color = switch (band) {
      ScoreBand.good => AppTokens.good,
      ScoreBand.fair => AppTokens.brandDeepAccent,
      ScoreBand.needsAttention => AppTokens.caution,
      ScoreBand.atRisk => AppTokens.danger,
      null => AppTokens.inkMuted,
    };
    final (IconData icon, String cmp) = switch (comparison) {
      PeriodComparison.better => (Icons.trending_up, 'Better than the previous 7 days'),
      PeriodComparison.worse => (Icons.trending_down, 'Worse than the previous 7 days'),
      PeriodComparison.unchanged => (Icons.trending_flat, 'About the same as the previous 7 days'),
      null => (Icons.remove, ''),
    };
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTokens.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppTokens.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Health Score', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppTokens.ink)),
                    const SizedBox(height: 4),
                    Text(
                      score == null ? 'Not enough data yet' : band?.label ?? '',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: color),
                    ),
                    if (cmp.isNotEmpty)
                      Row(
                        children: [
                          Icon(icon, size: 20, color: AppTokens.inkMuted),
                          const SizedBox(width: 4),
                          Flexible(child: Text(cmp, style: const TextStyle(fontSize: 14, color: AppTokens.inkMuted))),
                        ],
                      ),
                  ],
                ),
              ),
              SizedBox(
                width: 92,
                height: 92,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox.expand(
                      child: CircularProgressIndicator(
                        value: (score ?? 0) / 100,
                        strokeWidth: 11,
                        color: color,
                        backgroundColor: AppTokens.tint,
                      ),
                    ),
                    Text(score?.toString() ?? '--',
                        style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: AppTokens.ink)),
                  ],
                ),
              ),
            ],
          ),
          if (score == null) ...[
            const SizedBox(height: 10),
            const Text(Messages.coverageBelowMinimum, style: TextStyle(fontSize: 15, color: AppTokens.inkMuted)), // M8
            if (a != null && a.missingData.isNotEmpty)
              Text('Still needed: ${a.missingData.join(', ')}.', style: const TextStyle(fontSize: 14, color: AppTokens.inkMuted)),
          ],
          if (a != null && a.factors().isNotEmpty) ...[
            const SizedBox(height: 14),
            for (final f in a.factors()) _FactorRow(f),
          ],
          const SizedBox(height: 12),
          const Text(Messages.analysisDisclaimer, style: TextStyle(fontSize: 12, color: AppTokens.inkMuted)),
        ],
      ),
    );
  }
}

/// One factor's contribution to the score (FR400_022), with its note in the patient's units.
class _FactorRow extends StatelessWidget {
  final ScoreFactor f;
  const _FactorRow(this.f);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(f.label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppTokens.ink))),
            Text('+${f.points.toStringAsFixed(0)} pts', style: const TextStyle(fontSize: 15, color: AppTokens.ink)),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: f.subScore / 100,
            minHeight: 8,
            backgroundColor: AppTokens.tint,
            color: f.subScore >= 80
                ? AppTokens.good
                : f.subScore >= 50
                ? AppTokens.caution
                : AppTokens.danger,
          ),
        ),
        Text('${f.note} · ${f.subScore}/100, weight ${(f.weight * 100).round()}%',
            style: const TextStyle(fontSize: 13, color: AppTokens.inkMuted)),
      ],
    ),
  );
}

class _RiskPill extends StatelessWidget {
  final String risk;
  const _RiskPill(this.risk);

  @override
  Widget build(BuildContext context) {
    final (Color bg, Color fg) = switch (risk) {
      'High' => (AppTokens.dangerContainer, AppTokens.onDanger),
      'Moderate' => (AppTokens.cautionContainer, AppTokens.caution),
      _ => (AppTokens.goodContainer, AppTokens.good),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text('$risk risk', style: TextStyle(color: fg, fontWeight: FontWeight.w600, fontSize: 14)),
    );
  }
}

/// One anomaly in plain language (FR400_015), with its severity indicator (C8): a yellow or orange
/// badge, red for High.
class _AnomalyTile extends StatelessWidget {
  final AnomalyEvent a;
  const _AnomalyTile(this.a);

  @override
  Widget build(BuildContext context) {
    final color = switch (a.severity) {
      Severity.low => const Color(0xFFF2C94C),
      Severity.medium => const Color(0xFFF2994A),
      Severity.high => AppTokens.danger,
    };
    final t = a.detectedAt;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTokens.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
                child: Text('${a.severity.db} severity',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
              ),
              const SizedBox(width: 8),
              Text('${a.metricType.label} · ${t.day}/${t.month}',
                  style: const TextStyle(fontSize: 14, color: AppTokens.inkMuted)),
            ],
          ),
          const SizedBox(height: 8),
          Text(a.explanationText, style: const TextStyle(fontSize: 15, height: 1.4, color: AppTokens.ink)),
          if (a.isHighSeverity())
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(Messages.consultProfessional,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppTokens.onDanger)),
            ),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  final String text;
  const _Notice(this.text);
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: AppTokens.warnContainer, borderRadius: BorderRadius.circular(16)),
    child: Text(text, style: const TextStyle(color: AppTokens.onWarn, fontSize: 15)),
  );
}

class _Disclaimer extends StatelessWidget {
  const _Disclaimer();
  @override
  Widget build(BuildContext context) => const Text(
    Messages.analysisDisclaimer,
    style: TextStyle(fontSize: 13, color: AppTokens.inkMuted, fontStyle: FontStyle.italic),
  );
}

/// The first time the report is worked out (up to 30 s): what is happening, instead of a bare
/// spinner.
class _PreparingReport extends StatelessWidget {
  const _PreparingReport();

  @override
  Widget build(BuildContext context) => const Center(
    child: Padding(
      padding: EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GuideIllustration(Icons.insights, badge: Icons.favorite, size: 120),
          SizedBox(height: 20),
          CircularProgressIndicator(color: AppTokens.brandDeepAccent),
          SizedBox(height: 14),
          Text(
            'Preparing your Health Report...',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppTokens.ink),
          ),
          SizedBox(height: 6),
          Text(
            'We look at your readings, exercise and meals. This can take up to 30 seconds.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, color: AppTokens.inkMuted),
          ),
        ],
      ),
    ),
  );
}

/// Shown above the last stored report while the new one is worked out.
class _Updating extends StatelessWidget {
  const _Updating();

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
    decoration: BoxDecoration(color: AppTokens.tint, borderRadius: BorderRadius.circular(16)),
    child: const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Updating your report with your latest readings...',
          style: TextStyle(fontSize: 15, color: AppTokens.ink),
        ),
        SizedBox(height: 8),
        LinearProgressIndicator(color: AppTokens.brandDeepAccent, backgroundColor: AppTokens.surface),
      ],
    ),
  );
}
