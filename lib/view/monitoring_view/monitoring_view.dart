import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import 'package:physical_treatment_and_health_support_system/core/constants/app_constants.dart';
import 'package:physical_treatment_and_health_support_system/core/routes/routes.dart';
import 'package:physical_treatment_and_health_support_system/core/themes/design_tokens.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/biometric_reading.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';
import 'package:physical_treatment_and_health_support_system/view/common/tidy_text.dart';
import 'package:physical_treatment_and_health_support_system/view/common/trend_chart.dart';
import 'package:physical_treatment_and_health_support_system/view/common/user_guide.dart';
import 'package:physical_treatment_and_health_support_system/view/health_report_view/health_report_view.dart';
import 'package:physical_treatment_and_health_support_system/view/monitoring_view/add_reading_sheet.dart';
import 'package:physical_treatment_and_health_support_system/view/monitoring_view/exercise_tracking_panel.dart';
import 'package:physical_treatment_and_health_support_system/view/monitoring_view/watch_import_view.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/analysis_view_model/analysis_view_model.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/monitoring_view_model/monitoring_view_model.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/ui_state.dart';

/// Health Tracking (UC700; Figma "Monitoring"): the Health Connect connection in words on a green
/// surface, the trend of each metric and of the exercise sessions over 7, 30, 90 days or a custom
/// range, the period summary, the recent readings newest first, and Add Reading at the bottom.
class MonitoringView extends StatefulWidget {
  /// True when opened as its own page (from a reminder), with a back button.
  final bool standalone;
  const MonitoringView({super.key, this.standalone = false});

  @override
  State<MonitoringView> createState() => _MonitoringViewState();
}

class _MonitoringViewState extends State<MonitoringView> {
  MetricType _metric = MetricType.bloodPressure;
  bool _exerciseSelected = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await context.read<MonitoringViewModel>().load();
      // As a tab, the app shell opens the first-visit guide when the tab is shown.
      if (mounted && widget.standalone) await showGuideOnce(context, Guides.tracking);
    });
  }

  void _showMessage(MonitoringViewModel vm) {
    final m = vm.takeMessage();
    if (m == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final fix = !vm.connected && vm.healthFix != null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(m),
          duration: Duration(seconds: fix ? 10 : 4),
          action: fix ? SnackBarAction(label: 'Fix', onPressed: vm.fixHealthSource) : null,
        ),
      );
    });
  }

  /// A new reading changes the forecast and the analysis (FR400_005, FR400_030).
  void _analyseAgain() {
    try {
      context.read<AnalysisViewModel>().loadAnalysis();
    } on ProviderNotFoundException {
      // Opened from a reminder outside the app shell: the report runs when it is opened.
    }
  }

  Future<void> _add(MonitoringViewModel vm) async {
    final saved = await AddReadingSheet.show(context, vm, _metric);
    if (saved == true && mounted) _analyseAgain();
  }

  Future<void> _customRange(MonitoringViewModel vm) async {
    final now = DateTime.now();
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 3),
      lastDate: now,
      initialDateRange: DateTimeRange(start: vm.rangeStart, end: vm.rangeEnd.isAfter(now) ? now : vm.rangeEnd),
    );
    if (r != null) await vm.loadRange(r.start, r.end);
  }

  Future<void> _delete(MonitoringViewModel vm, BiometricReading r) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: const Text(Messages.confirmDeleteEntry, style: TextStyle(fontSize: 17)), // M10
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTokens.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (yes != true) return;
    final ok = await vm.deleteReading(r.readingId);
    if (ok && mounted) _analyseAgain();
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<MonitoringViewModel>();
    _showMessage(vm);
    final body = ColoredBox(
      color: AppTokens.screenBackground,
      child: Column(
        children: [
          Expanded(
            child: RefreshIndicator(onRefresh: vm.load, child: _content(vm)),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(AppTokens.gutter, 8, AppTokens.gutter, 12),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTokens.cta,
                    shape: const StadiumBorder(),
                    textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  onPressed: _exerciseSelected ? () async {
                    await Navigator.of(context).pushNamed(Routes.physicalTreatment);
                    if(mounted)await vm.load();
                  } : () => _add(vm),
                  icon: Icon(_exerciseSelected ? Icons.accessibility_new : Icons.add),
                  label: Text(_exerciseSelected ? 'Open treatment' : 'Add Reading',style:const TextStyle(fontFamily:'Roboto')),
                ),
              ),
            ),
          ),
        ],
      ),
    );
    if (!widget.standalone) return body;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Health Tracking'),
        backgroundColor: AppTokens.brandDeep,
        foregroundColor: Colors.white,
        actions: const [HelpButton(guide: Guides.tracking)],
      ),
      body: body,
    );
  }

  Widget _content(MonitoringViewModel vm) {
    final d = vm.data;
    final top = widget.standalone ? 0.0 : MediaQuery.paddingOf(context).top;
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        if (!widget.standalone)
          Container(
            color: AppTokens.brandDeep,
            padding: EdgeInsets.fromLTRB(24, top + 20, 12, 12),
            // The title keeps the whole width of its line, with "How to use this screen" beside
            // it and the Health Report button below that (phone test, 9 Nov: squeezed between the
            // two buttons, the "g" of "Tracking" broke onto a second line).
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Row(
                  children: [
                    Expanded(
                      child: OneLineText(
                        'Health Tracking',
                        style: TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w700),
                      ),
                    ),
                    HelpButton(guide: Guides.tracking),
                  ],
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    style: TextButton.styleFrom(foregroundColor: Colors.white),
                    onPressed: () => _openReport(),
                    icon: const Icon(Icons.insights),
                    label: const OneLineText('Health Report', style: TextStyle(fontSize: 16)),
                  ),
                ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(AppTokens.gutter, 16, AppTokens.gutter, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ConnectionCard(vm: vm),
              if (vm.watchConnection case final connection?) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTokens.successContainer,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppTokens.cardBorder),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${connection.device.name} · Automatic sync',
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        vm.watchSyncing
                            ? 'Syncing watch readings...'
                            : vm.watchSyncMessage ?? 'Checks automatically while HealthGuide is open.',
                      ),
                      if (connection.lastSync case final at?)
                        Text(
                          'Last checked ${_importDate(at)}',
                        ),
                      Wrap(
                        children: [
                          TextButton.icon(
                            onPressed: vm.watchSyncing || vm.importing ? null : () => vm.syncWatch(quiet: false),
                            icon: const Icon(Icons.sync),
                            label: const Text('Sync watch now'),
                          ),
                          TextButton(
                            onPressed: () async {
                              try {
                                await vm.disconnectWatch();
                              } catch (_) {
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Could not disconnect the watch. Try again.')),
                                );
                              }
                            },
                            child: const Text('Disconnect watch'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: vm.importing || vm.watchSyncing
                    ? null
                    : () async {
                        await Navigator.of(
                          context,
                        ).push<bool>(MaterialPageRoute(builder: (_) => WatchImportView(viewModel: vm)));
                        if (mounted) _showMessage(vm);
                      },
                icon: const Icon(Icons.watch),
                label: const Text('Import from watch'),
              ),
              const SizedBox(height: 16),
              _RangeChips(vm: vm, onCustom: () => _customRange(vm)),
              const SizedBox(height: 8),
              // Another period is loading: the old one stays on screen under a thin bar.
              SizedBox(
                height: 4,
                child: vm.reloading
                    ? const LinearProgressIndicator(color: AppTokens.brandDeepAccent, backgroundColor: AppTokens.tint)
                    : null,
              ),
              const SizedBox(height: 8),
              if (vm.state case UiError(:final message)) _Banner(message, onRetry: vm.load),
              if (d == null && vm.state is Loading)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (d != null) ...[
                _card(
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // No tick on the chosen one, and each name on one line: with the tick, the last
                      // letter of "Pressure" or "Glucose" dropped onto a second line (phone, 9 Nov).
                      Wrap(spacing:8,runSpacing:8,children:[
                        for(final (metric,label) in [(MetricType.bloodPressure,'Pressure'),(MetricType.bloodGlucose,'Glucose'),(MetricType.bodyWeight,'Weight')])
                          ChoiceChip(showCheckmark:false,label:OneLineText(label,alignment:Alignment.center),
                            selected:!_exerciseSelected && _metric==metric,
                            onSelected:(_)=>setState((){_exerciseSelected=false;_metric=metric;})),
                        ChoiceChip(showCheckmark:false,label:const OneLineText('Exercise',alignment:Alignment.center),
                          selected:_exerciseSelected,onSelected:(_)=>setState(()=>_exerciseSelected=true)),
                      ]),
                      const SizedBox(height: 14),
                      if(_exerciseSelected)ExerciseTrackingPanel(sessions:d.sessions,from:vm.rangeStart,to:vm.rangeEnd,
                        available:d.sessionsAvailable,onRetry:vm.load)
                      else _metricChart(d, vm),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _card(_summary(d.summary,sessionsAvailable:d.sessionsAvailable)),
                const SizedBox(height: 20),
                if(!_exerciseSelected)...[
                const Text(
                  'Recent readings',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppTokens.ink),
                ),
                const SizedBox(height: 8),
                if (d.readings.isEmpty)
                  EmptyState(
                    icon: Icons.monitor_heart,
                    badge: Icons.add,
                    title: 'No readings in this period',
                    message:
                        'Add your blood pressure, blood glucose or weight, or connect Health Connect '
                        'to bring them in from your watch.',
                    actionLabel: 'Add a reading',
                    onAction: () => _add(vm),
                  )
                else
                  for (final r in d.recentFirst.take(30)) _readingTile(vm, r),
                ],
              ],
            ],
          ),
        ),
      ],
    );
  }

  void _openReport() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) =>
          ChangeNotifierProvider.value(value: context.read<AnalysisViewModel>(), child: const HealthReportView()),
    ),
  );

  Widget _card(Widget child) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppTokens.surface,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: AppTokens.cardBorder),
    ),
    child: child,
  );

  Widget _metricChart(MonitoringData d, MonitoringViewModel vm) {
    final rs = d.of(_metric);
    if (rs.isEmpty) {
      return const SizedBox(
        height: 120,
        child: Center(
          child: Text(
            Messages.noData,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, color: AppTokens.inkMuted),
          ),
        ), // A4 M8
      );
    }
    final series = _metric == MetricType.bloodPressure
        ? [
            ChartSeries('Systolic', [for (final r in rs) ChartPoint(r.recordedAt, r.primaryValue)], AppTokens.cta),
            ChartSeries('Diastolic', [
              for (final r in rs)
                if (r.secondaryValue != null) ChartPoint(r.recordedAt, r.secondaryValue!),
            ], AppTokens.brandDeepAccent),
          ]
        : [
            ChartSeries(_metric.label, [
              for (final r in rs) ChartPoint(r.recordedAt, r.primaryValue),
            ], AppTokens.brandDeepAccent),
          ];
    final imported = rs.where((r) => r.source == ReadingSource.imported).toList();
    final importTimes = imported.map((r) => r.importedAt).whereType<DateTime>().toList()..sort();
    final latestImport = importTimes.isEmpty ? null : importTimes.last;
    final latestCount = latestImport == null ? 0 : imported.where((r) => r.importedAt == latestImport).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          container: true,
          identifier: 'tracking-reading-count',
          child: Text(
            '${rs.length} reading${rs.length == 1 ? '' : 's'} · ${imported.length} imported',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
        ),
        if (latestImport != null)
          Text(
            'Latest import shown: ${_importDate(latestImport)} · $latestCount reading${latestCount == 1 ? '' : 's'}',
            style: const TextStyle(fontSize: 13, color: AppTokens.inkMuted),
          )
        else if (imported.isNotEmpty)
          const Text(
            'Import time not recorded for these older readings.',
            style: TextStyle(fontSize: 13, color: AppTokens.inkMuted),
          ),
        const SizedBox(height: 8),
        const Text(
          'Tap a reading for details. Pinch to zoom; drag to move when zoomed.',
          style: TextStyle(fontSize: 13, color: AppTokens.inkMuted),
        ),
        const SizedBox(height: 8),
        TrendChart(
          key: ValueKey('tracking-${_metric.db}-${vm.rangeStart}-${DateFormat('yyyy-MM-dd').format(vm.rangeEnd)}'),
          series: series,
          unit: _metric.unit,
          height: 260,
          inspectable: true,
          zoomable: true,
          interactionId: 'tracking-metric-chart',
          inspectionBuilder: (at) => _graphReading(rs.firstWhere((r) => r.recordedAt == at)),
        ),
      ],
    );
  }

  String _importDate(DateTime at) => DateFormat('d MMM yyyy, HH:mm:ss').format(at.toLocal());

  Widget _graphReading(BiometricReading r) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('${r.metricType.label}: ${r.display()}', style: const TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 4),
      Text('Recorded: ${DateFormat('d MMM yyyy, HH:mm').format(r.recordedAt)}'),
      if (r.measurementContext case final context?) Text(context.label),
      Text(r.sourceDevice == null ? r.source.label : '${r.sourceDevice} · Watch estimate'),
      if (r.source == ReadingSource.imported)
        Text(r.importedAt == null ? 'Import time not recorded' : 'Imported: ${_importDate(r.importedAt!)}'),
    ],
  );

  /// Period summary (UC700 C2, FR200_019).
  Widget _summary(PeriodSummary s,{bool sessionsAvailable=true}) {
    Widget row(String l, String v) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(l, style: const TextStyle(fontSize: 16, color: AppTokens.inkMuted)),
          ),
          Text(
            v,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppTokens.ink),
          ),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Summary of this period',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppTokens.ink),
        ),
        const SizedBox(height: 6),
        row('Exercise sessions completed', sessionsAvailable?'${s.sessions}':'Unavailable'),
        row('Total exercise time', sessionsAvailable?'${s.exerciseMinutes} min':'Unavailable'),
        row('Readings recorded', '${s.readings}'),
        for (final m in MetricType.values) row('Average ${m.label.toLowerCase()}', s.means[m] ?? '--'),
      ],
    );
  }

  Widget _readingTile(MonitoringViewModel vm, BiometricReading r) {
    final t = r.recordedAt;
    final when =
        '${t.day}/${t.month}/${t.year} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    final ctx = r.measurementContext?.label;
    return Card(
      elevation: 0,
      color: AppTokens.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppTokens.cardBorder),
      ),
      child: ListTile(
        minVerticalPadding: 12,
        title: Text(
          '${r.metricType.label}: ${r.display()}',
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: AppTokens.ink),
        ),
        subtitle: Text(
          [
                'Recorded $when',
                ?ctx,
                r.sourceDevice == null ? r.source.label : '${r.sourceDevice} · Watch estimate',
              ].join(' · ') +
              (r.source == ReadingSource.imported
                  ? '\n${r.importedAt == null ? 'Import time not recorded' : 'Imported: ${_importDate(r.importedAt!)}'}'
                  : ''),
          style: const TextStyle(fontSize: 14, color: AppTokens.inkMuted),
        ),
        trailing: IconButton(
          tooltip: 'Delete',
          icon: const Icon(Icons.delete_outline),
          onPressed: () => _delete(vm, r),
        ),
      ),
    );
  }
}

/// Connection state in words on a green surface, not by colour only (UI Design), with the time of
/// the last import (FR100_064) and the import action (UC700 A1).
class _ConnectionCard extends StatelessWidget {
  final MonitoringViewModel vm;
  const _ConnectionCard({required this.vm});

  @override
  Widget build(BuildContext context) {
    final last = vm.lastSync;
    final when = last == null
        ? 'Syncing automatically'
        : 'Syncing automatically · last checked ${last.day}/${last.month} '
              '${last.hour.toString().padLeft(2, '0')}:${last.minute.toString().padLeft(2, '0')}';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: vm.connected ? AppTokens.successContainer : AppTokens.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTokens.cardBorder),
      ),
      child: Row(
        children: [
          Icon(vm.connected ? Icons.link : Icons.link_off, color: AppTokens.brandDeep, size: 30),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  vm.connected ? 'Health Connect: connected' : 'Health Connect: not connected',
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: AppTokens.ink),
                ),
                Text(
                  vm.connected ? when : 'Connect to import your readings automatically.',
                  style: const TextStyle(fontSize: 14, color: AppTokens.inkMuted),
                ),
              ],
            ),
          ),
          // Connected: new readings come in by themselves (every minute and when the app returns
          // to the front); the icon only checks at once.
          if (vm.connected)
            vm.importing
                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5))
                : IconButton(
                    tooltip: 'Check Health Connect now',
                    onPressed: vm.importFromHealthSource,
                    icon: const Icon(Icons.sync, color: AppTokens.brandDeep),
                  )
          else
            TextButton(
              onPressed: vm.importing ? null : vm.connect,
              child: const Text('Connect', style: TextStyle(fontSize: 15)),
            ),
        ],
      ),
    );
  }
}

/// 7 days, 30 days, 90 days or a custom range (UC700 C13).
class _RangeChips extends StatelessWidget {
  final MonitoringViewModel vm;
  final VoidCallback onCustom;
  const _RangeChips({required this.vm, required this.onCustom});

  @override
  Widget build(BuildContext context) {
    final s = vm.rangeStart, e = vm.rangeEnd;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          children: [
            for (final d in AppConstants.rangeChoices)
              ChoiceChip(
                label: OneLineText('$d days', style: const TextStyle(fontSize: 15)),
                selected: vm.rangeDays == d,
                onSelected: (_) => vm.selectDays(d),
              ),
            ChoiceChip(
              label: const OneLineText('Custom', style: TextStyle(fontSize: 15)),
              selected: vm.rangeDays == null,
              onSelected: (_) => onCustom(),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '${s.day}/${s.month}/${s.year} - ${e.day}/${e.month}/${e.year}',
          style: const TextStyle(fontSize: 14, color: AppTokens.inkMuted),
        ),
      ],
    );
  }
}

class _Banner extends StatelessWidget {
  final String text;
  final Future<void> Function() onRetry;
  const _Banner(this.text, {required this.onRetry});

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: AppTokens.warnContainer, borderRadius: BorderRadius.circular(16)),
    child: Row(
      children: [
        Expanded(
          child: Text(text, style: const TextStyle(color: AppTokens.onWarn, fontSize: 15)),
        ),
        TextButton(onPressed: onRetry, child: const Text('Try again')),
      ],
    ),
  );
}
