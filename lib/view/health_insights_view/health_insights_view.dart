import 'package:flutter/material.dart';
import 'package:physical_treatment_and_health_support_system/view/common/insights_surface.dart';
import 'package:physical_treatment_and_health_support_system/view/common/diet_food_guidance.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import 'package:physical_treatment_and_health_support_system/core/themes/design_tokens.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/health_insights.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/recovery_check_in.dart';
import 'package:physical_treatment_and_health_support_system/view/common/trend_chart.dart';
import 'package:physical_treatment_and_health_support_system/view/common/report_explanation.dart';
import 'package:physical_treatment_and_health_support_system/view/health_insights_view/health_timeline.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/health_insights_view_model/health_insights_view_model.dart';

class HealthInsightsView extends StatefulWidget {
  final int initialTab;
  const HealthInsightsView({super.key, this.initialTab = 0});
  @override
  State<HealthInsightsView> createState() => _HealthInsightsViewState();
}

class _HealthInsightsViewState extends State<HealthInsightsView>
    with SingleTickerProviderStateMixin {
  late final TabController tabs = TabController(
    length: 4,
    vsync: this,
    initialIndex: widget.initialTab.clamp(0, 3),
  );
  DateTime? selectedDay;
  HealthTimelineEvent? selectedEvent;
  final kinds = TimelineKind.values.toSet();
  String date(DateTime d) => DateFormat('d MMM yyyy').format(d);
  @override
  void dispose() {
    tabs.dispose();
    super.dispose();
  }

  void evidence(DateTime d) {
    setState(() {
      selectedDay = DateUtils.dateOnly(d);
      selectedEvent = null;
    });
    tabs.animateTo(0);
  }

  Widget card(Widget child) => Card(
    margin: const EdgeInsets.only(bottom: AppTokens.gap),
    elevation: 0,
    color: Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
      side: const BorderSide(color: AppTokens.cardBorder),
    ),
    child: Padding(
      padding: const EdgeInsets.all(AppTokens.gutter),
      child: child,
    ),
  );
  Widget title(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: AppTokens.ink,
      ),
    ),
  );
  Widget note(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: const TextStyle(height: 1.45, color: AppTokens.inkMuted),
    ),
  );
  Widget list(List<Widget> children) => ListView(
    padding: const EdgeInsets.all(AppTokens.gutter),
    children: children,
  );
  Future<void> chooseWeek(HealthInsightsViewModel vm) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: vm.selectedWeek,
      firstDate: DateTime(2020),
      lastDate: vm.today,
      helpText: 'Choose a day in the week to review',
    );
    if (picked != null) await vm.load(week: picked);
  }

  Future<void> export(HealthInsightsViewModel vm) async {
    final start = vm.data?.start;
    final bytes = await vm.exportReport();
    if (bytes == null || !mounted) return;
    try {
      await Printing.layoutPdf(
        name: 'HealthGuide-${DateFormat('yyyy-MM-dd').format(start!)}.pdf',
        onLayout: (_) async => bytes,
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'The print dialog could not open. Please try again on a supported device.',
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<HealthInsightsViewModel>(), data = vm.data;
    if (data != null &&
        (selectedDay == null ||
            selectedDay!.isBefore(data.start) ||
            selectedDay!.isAfter(data.end))) {
      selectedDay = vm.today.isBefore(data.start) || vm.today.isAfter(data.end)
          ? data.start
          : vm.today;
      selectedEvent = null;
    }
    return InsightsSurface(
      child: Scaffold(
        backgroundColor: AppTokens.screenBackground,
        appBar: AppBar(
          title: const Text('Health insights'),
          backgroundColor: AppTokens.brandDeep,
          foregroundColor: Colors.white,
          actions: [
            IconButton(
              tooltip: 'Refresh insights',
              onPressed: vm.isLoading ? null : () => vm.load(),
              icon: const Icon(Icons.refresh),
            ),
            IconButton(
              tooltip: 'Export weekly PDF',
              onPressed: data == null || vm.exporting ? null : () => export(vm),
              icon: vm.exporting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.picture_as_pdf),
            ),
          ],
          bottom: TabBar(
            controller: tabs,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.white,
            dividerColor: Colors.transparent,
            labelStyle: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
            unselectedLabelStyle: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
            tabs: const [
              Tab(text: 'Timeline'),
              Tab(text: 'Weekly report'),
              Tab(text: 'Data quality'),
              Tab(text: 'Recovery'),
            ],
          ),
        ),
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Previous insights week',
                      onPressed: vm.isLoading
                          ? null
                          : () => vm.load(
                              week: vm.selectedWeek.subtract(
                                const Duration(days: 7),
                              ),
                            ),
                      icon: const Icon(Icons.chevron_left),
                    ),
                    Expanded(
                      child: TextButton(
                        onPressed: vm.isLoading ? null : () => chooseWeek(vm),
                        child: Text(
                          '${DateFormat('d MMM').format(vm.selectedWeek)} – ${DateFormat('d MMM yyyy').format(vm.selectedWeek.add(const Duration(days: 6)))}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: AppTokens.ink,
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Next insights week',
                      onPressed:
                          vm.isLoading ||
                              !vm.selectedWeek
                                  .add(const Duration(days: 7))
                                  .isBefore(
                                    vm.today.add(const Duration(days: 1)),
                                  )
                          ? null
                          : () => vm.load(
                              week: vm.selectedWeek.add(
                                const Duration(days: 7),
                              ),
                            ),
                      icon: const Icon(Icons.chevron_right),
                    ),
                  ],
                ),
              ),
              SwitchListTile(
                dense: true,
                key: const ValueKey('include-presentation-data'),
                title: const Text('Include presentation data'),
                subtitle: Text(
                  data == null
                      ? 'Applies to these insights and the exported PDF.'
                      : '${data.demoCount} synthetic records in loaded history. Filter applies here and in this PDF.',
                ),
                value: vm.includeDemo,
                onChanged: vm.isLoading ? null : vm.setIncludeDemo,
              ),
              if (vm.isLoading) const LinearProgressIndicator(),
              if (vm.errorMessage != null)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    vm.errorMessage!,
                    style: const TextStyle(color: AppTokens.onDanger),
                  ),
                ),
              Expanded(
                child: data == null
                    ? Center(
                        child: vm.isLoading
                            ? const Text('Bringing your records together…')
                            : FilledButton(
                                style: InsightsSurface.primaryButtonStyle,
                                onPressed: () => vm.load(),
                                child: const Text('Try again'),
                              ),
                      )
                    : TabBarView(
                        controller: tabs,
                        children: [
                          timeline(data),
                          KeyedSubtree(
                            key: const ValueKey('weekly-insights-list'),
                            child: weekly(data, vm),
                          ),
                          quality(data, vm),
                          recovery(data, vm),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget timeline(HealthInsights d) {
    final events = d.timeline
        .where((e) => DateUtils.isSameDay(e.at, selectedDay))
        .toList();
    final chosen = selectedEvent == null
        ? null
        : events.where((e) => e.id == selectedEvent!.id).firstOrNull;
    final nearby = chosen == null
        ? const <HealthTimelineEvent>[]
        : events
              .where(
                (e) =>
                    e.kind == TimelineKind.reading &&
                    e.id != chosen.id &&
                    e.at.difference(chosen.at).inMinutes.abs() <= 180,
              )
              .toList();
    return list([
      if (d.includesDemo && d.demoCount > 0)
        card(
          note(
            'Presentation data is included. Synthetic records are labelled Demo.',
          ),
        ),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (var i = 0; i < 7; i++)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text(
                    DateFormat('EEE d').format(d.start.add(Duration(days: i))),
                  ),
                  selected: DateUtils.isSameDay(
                    selectedDay,
                    d.start.add(Duration(days: i)),
                  ),
                  onSelected: (_) => setState(() {
                    selectedDay = d.start.add(Duration(days: i));
                    selectedEvent = null;
                  }),
                ),
              ),
          ],
        ),
      ),
      Wrap(
        spacing: 6,
        children: [
          for (final kind in TimelineKind.values)
            FilterChip(
              label: Text(switch (kind) {
                TimelineKind.planned => 'Planned',
                TimelineKind.meal => 'Meals',
                TimelineKind.reading => 'Readings',
                TimelineKind.exercise => 'Exercise',
                TimelineKind.recovery => 'Recovery',
              }),
              selected: kinds.contains(kind),
              onSelected: (v) => setState(() {
                v ? kinds.add(kind) : kinds.remove(kind);
              }),
            ),
        ],
      ),
      card(
        HealthTimeline(
          events: events.where((e) => kinds.contains(e.kind)).toList(),
          selectedId: chosen?.id,
          onSelected: (e) => setState(() => selectedEvent = e),
        ),
      ),
      if (chosen != null)
        card(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              title('${DateFormat.Hm().format(chosen.at)} · ${chosen.title}'),
              if (chosen.isDemo) const Chip(label: Text('Demo')),
              Text(chosen.detail),
              if (nearby.isNotEmpty) ...[
                const SizedBox(height: 14),
                title('Nearby readings within 3 hours'),
                note(
                  'These events occurred near each other. Timing alone does not show that one caused another.',
                ),
                for (final r in nearby)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('${DateFormat.Hm().format(r.at)} · ${r.title}'),
                    subtitle: Text(r.detail),
                    onTap: () => setState(() => selectedEvent = r),
                  ),
              ],
            ],
          ),
        ),
      title('Records for ${date(selectedDay!)}'),
      if (events.where((e) => kinds.contains(e.kind)).isEmpty)
        card(
          note(
            'No records of the selected types for this day. Missing data remains unknown.',
          ),
        ),
      for (final e in events.where((e) => kinds.contains(e.kind)))
        card(
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Text(DateFormat.Hm().format(e.at)),
            title: Text('${e.title}${e.isDemo ? ' · Demo' : ''}'),
            subtitle: Text(
              e.detail,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => setState(() => selectedEvent = e),
          ),
        ),
    ]);
  }

  Widget weekly(HealthInsights d, HealthInsightsViewModel vm) => list([
    card(
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            title('Your week, explained'),
            Text(
              '${d.comparison.compared.length} meals compared',
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: AppTokens.brandDeep,
              ),
            ),
            note(
              '${d.loggedDays}/${d.elapsedDays} elapsed days logged · ${d.sessions.length} completed exercise sessions',
            ),
            if (d.includesDemo && d.demoCount > 0)
              note(
                'Includes synthetic presentation data. This is a demonstration report.',
              ),
            FilledButton.icon(
              onPressed: vm.exporting ? null : () => export(vm),
              icon: const Icon(Icons.picture_as_pdf),
              label: const Text('Export / print PDF'),
            ),
          ],
        ),
      ),
    ),
    for (final notice in d.notices) card(note(notice)),
    card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          title('Weekly conclusion and next steps'),
          ReportExplanationBody(vm.explainWeek(d)),
        ],
      ),
    ),
    if (d.foodGuidance case final guidance?)
      card(DietFoodGuidanceBody(guidance)),
    card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          title('Plan and recorded energy'),
          TrendChart(
            unit: 'kcal',
            inspectable: true,
            zoomable: true,
            interactionId: 'weekly-insights-energy',
            series: [
              ChartSeries('Saved plan', [
                for (final day in d.comparison.days)
                  if (day.hasPlan) ChartPoint(day.date, day.planned.energyKcal),
              ], const Color(0xFF4775B0)),
              ChartSeries('Recorded food', [
                for (final day in d.comparison.days)
                  if (day.hasLogs) ChartPoint(day.date, day.logged.energyKcal),
              ], AppTokens.brandDeep),
            ],
          ),
          note(
            'No log remains unknown. Partial days can understate intake. Saved plans created later are reference only.',
          ),
        ],
      ),
    ),
    for (final fact in d.facts)
      card(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            title(fact.title),
            ReportExplanationBody(vm.explainFact(d, fact)),
            if (fact.evidenceDays.isNotEmpty) ...[
              const SizedBox(height: 10),
              const Text('View supporting records'),
              Wrap(
                spacing: 7,
                children: [
                  for (final day in fact.evidenceDays.take(7))
                    ActionChip(
                      label: Text(DateFormat('d MMM').format(day)),
                      onPressed: () => evidence(day),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    card(
      note(
        'These summaries are calculated from your saved records on the device. Associations do not establish cause and effect, and the report does not diagnose conditions or change treatment.',
      ),
    ),
  ]);
  Widget quality(HealthInsights d, HealthInsightsViewModel vm) {
    final weekReadings = d.readings
        .where((r) => !r.recordedAt.isBefore(d.start))
        .toList();
    final imported = weekReadings
        .where((r) => r.source == ReadingSource.imported)
        .toList();
    final batches = <String, int>{};
    for (final r in imported) {
      if (r.importedAt != null) {
        final k = DateFormat('yyyy-MM-dd HH:mm:ss').format(r.importedAt!);
        batches[k] = (batches[k] ?? 0) + 1;
      }
    }
    final dates = batches.keys.toList()..sort((a, b) => b.compareTo(a));
    return list([
      title('Understand your data'),
      card(ReportExplanationBody(vm.explainQuality(d))),
      card(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            title('Saved history and sync'),
            Text(
              'Last successful source sync: ${d.lastSync == null ? 'Not recorded' : DateFormat('d MMM yyyy HH:mm:ss').format(d.lastSync!)}',
            ),
            const SizedBox(height: 8),
            Text(
              '${weekReadings.length} valid readings in this week · ${imported.length} imported',
            ),
            note(
              'This reads saved records. To reconnect or check for new watch records, use Import from watch in Tracking. A source sync time is not proof that every watch-screen measurement was saved.',
            ),
            for (final key in dates.take(5))
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.download_done),
                title: Text('$key · ${batches[key]} records'),
                subtitle: const Text(
                  'Grouped by first import time to the nearest second',
                ),
              ),
            if (imported.any((r) => r.importedAt == null))
              note('Some older imports do not have a saved import time.'),
          ],
        ),
      ),
      for (final notice in d.notices) card(note(notice)),
      card(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            title('Coverage by metric'),
            note(
              'History is the 120 days ending at the selected period. The 14-reading minimum is an input check; it does not guarantee reliable forecasting.',
            ),
            for (final metric in MetricType.values)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Builder(
                  builder: (context) {
                    final history = d.readings
                        .where((r) => r.metricType == metric)
                        .toList();
                    final records = weekReadings
                        .where((r) => r.metricType == metric)
                        .toList();
                    final days = records
                        .map((r) => DateUtils.dateOnly(r.recordedAt))
                        .toSet();
                    final missing = [
                      for (var i = 0; i < d.elapsedDays; i++)
                        if (!days.contains(d.start.add(Duration(days: i))))
                          DateFormat(
                            'EEE d',
                          ).format(d.start.add(Duration(days: i))),
                    ];
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          metric.label,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          '${records.length} readings on ${days.length}/${d.elapsedDays} elapsed days · ${history.length} history readings',
                        ),
                        LinearProgressIndicator(
                          value: d.elapsedDays == 0
                              ? 0
                              : days.length / d.elapsedDays,
                        ),
                        Text(
                          history.length < 14
                              ? '${14 - history.length} more readings needed for the forecast minimum.'
                              : 'Forecast minimum met; consistency, recency and source still matter.',
                        ),
                        if (missing.isNotEmpty)
                          Text('No reading recorded: ${missing.join(', ')}'),
                        if (history.isNotEmpty)
                          Text(
                            'Latest in this period: ${DateFormat('d MMM HH:mm').format(history.last.recordedAt)}',
                          ),
                      ],
                    );
                  },
                ),
              ),
          ],
        ),
      ),
      card(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            title('Sources in the loaded history'),
            for (final e in d.sourceCounts.entries)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(e.key),
                trailing: Text('${e.value}'),
              ),
            note(
              '${d.invalidReadings} invalid readings excluded. Coverage describes completeness, not clinical accuracy. Wearable records retain their source and remain device estimates.',
            ),
            note(
              'The presentation-data switch applies to this insights screen and PDF. Existing Health Report forecasts have their own input history.',
            ),
          ],
        ),
      ),
    ]);
  }

  Widget recovery(HealthInsights d, HealthInsightsViewModel vm) => list([
    title('How recovery feels'),
    note(
      'Daily pain, stiffness and exercise difficulty alongside recorded treatment. The diary covers 28 days ending at the selected week. Missing check-ins are unknown.',
    ),
    FilledButton.icon(
      key: const ValueKey('new-recovery-check-in'),
      onPressed: vm.saving || vm.plans.isEmpty ? null : () => checkIn(vm),
      icon: const Icon(Icons.add),
      label: const Text('Add recovery check-in'),
    ),
    if (vm.plans.isEmpty)
      note('Choose a treatment plan before recording a recovery check-in.'),
    for (final notice in d.notices.where(
      (n) =>
          n.contains('Recovery') ||
          n.contains('exercise') ||
          n.contains('Treatment'),
    ))
      card(note(notice)),
    for (final p in d.recovery.where(
      (p) => p.checkIns.isNotEmpty || p.sessions.isNotEmpty,
    ))
      recoveryCard(p, vm),
    if (d.recovery.every((r) => r.checkIns.isEmpty))
      card(
        note(
          'No symptom check-ins yet. Add at least two for the same treatment plan to see a change over time.',
        ),
      ),
    card(
      note(
        'Scores are your own reports, not a medical assessment. If exercise makes symptoms worse, pause that exercise and discuss it with your care team. Check-ins never advance the treatment plan automatically.',
      ),
    ),
  ]);
  Widget recoveryCard(RecoveryProgress p, HealthInsightsViewModel vm) {
    final groups = <String, List<ExerciseEvidence>>{};
    for (final s in p.sessions) {
      (groups[s.session.exerciseId] ??= []).add(s);
    }
    return card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          title(p.planName),
          ReportExplanationBody(vm.explainRecovery(p)),
          Text(
            '${p.checkIns.length} symptom check-ins · ${p.sessions.length} completed sessions',
          ),
          if (p.worsening)
            Container(
              margin: const EdgeInsets.symmetric(vertical: 10),
              padding: const EdgeInsets.all(12),
              color: AppTokens.dangerContainer,
              child: const Text(
                'Your latest check-in reports more pain or stiffness than the preceding check-in. Review this with your care team before increasing exercise.',
              ),
            ),
          if (p.painChange != null)
            Text(
              'Pain change: ${p.painChange! >= 0 ? '+' : ''}${p.painChange!.round()} points · Stiffness change: ${p.stiffnessChange! >= 0 ? '+' : ''}${p.stiffnessChange!.round()} points (first to latest check-in)',
            ),
          if (p.checkIns.isNotEmpty)
            TrendChart(
              unit: '/10',
              inspectable: true,
              series: [
                ChartSeries('Pain', [
                  for (final c in p.checkIns)
                    ChartPoint(c.date, c.pain.toDouble()),
                ], const Color(0xFFC44E52)),
                ChartSeries('Stiffness', [
                  for (final c in p.checkIns)
                    ChartPoint(c.date, c.stiffness.toDouble()),
                ], const Color(0xFF8064A2)),
              ],
            ),
          for (final g in groups.values) ...[
            const SizedBox(height: 8),
            Text(
              g.first.exerciseName,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(
              '${g.length} completed sessions · ${g.fold<double>(0, (a, s) => a + s.session.durationMinutes()).toStringAsFixed(1)} minutes',
            ),
            if (g.where((s) => s.session.postureAccuracy != null).length >= 2)
              TrendChart(
                unit: '%',
                height: 140,
                inspectable: true,
                series: [
                  ChartSeries('Posture result', [
                    for (final s in g)
                      if (s.session.postureAccuracy != null)
                        ChartPoint(
                          s.session.completedAt!,
                          s.session.postureAccuracy!,
                        ),
                  ], AppTokens.brandDeep),
                ],
              ),
          ],
          for (final c in p.checkIns.reversed)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('${date(c.date)}${c.isDemo ? ' · Demo' : ''}'),
              subtitle: Text(
                'Pain ${c.pain}/10 · Stiffness ${c.stiffness}/10 · Difficulty ${c.difficulty}/5${c.notes.isEmpty ? '' : '\n${c.notes}'}',
              ),
              trailing: Wrap(
                children: [
                  IconButton(
                    tooltip: 'Edit recovery check-in',
                    onPressed: vm.saving
                        ? null
                        : () => checkIn(vm, existing: c),
                    icon: const Icon(Icons.edit_outlined),
                  ),
                  IconButton(
                    tooltip: 'Delete recovery check-in',
                    onPressed: vm.saving
                        ? null
                        : () async {
                            final ok = await showDialog<bool>(
                              context: context,
                              builder: (c) => AlertDialog(
                                backgroundColor: AppTokens.surface,
                                title: const Text('Delete this check-in?'),
                                content: const Text(
                                  'The diary entry will be removed. Your exercise sessions and treatment progress remain.',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(c, false),
                                    child: const Text('Cancel'),
                                  ),
                                  FilledButton(
                                    style: InsightsSurface.primaryButtonStyle,
                                    onPressed: () => Navigator.pop(c, true),
                                    child: const Text('Delete'),
                                  ),
                                ],
                              ),
                            );
                            if (ok == true) await vm.deleteCheckIn(c);
                          },
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ),
            ),
          note(
            'Symptoms and posture are shown separately. Different exercises are not combined into a recovery score.',
          ),
        ],
      ),
    );
  }

  Future<void> checkIn(
    HealthInsightsViewModel vm, {
    RecoveryCheckIn? existing,
  }) async {
    var planId = existing?.patientPlanId ?? vm.plans.last.patientPlanId;
    var chosenDate = existing?.date ?? vm.today;
    var pain = existing?.pain ?? 0,
        stiffness = existing?.stiffness ?? 0,
        difficulty = existing?.difficulty ?? 1;
    var busy = false;
    String? error;
    var notes = existing?.notes ?? '';
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (outer) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
          backgroundColor: AppTokens.surface,
          title: Text(
            existing == null ? 'Recovery check-in' : 'Edit recovery check-in',
          ),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: planId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Treatment plan',
                    ),
                    items: [
                      for (final p in vm.plans)
                        DropdownMenuItem(
                          value: p.patientPlanId,
                          child: Text(
                            '${p.plan.planName} · ${DateFormat('d MMM').format(p.selectedAt)}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: busy || existing != null
                        ? null
                        : (v) => update(() => planId = v!),
                  ),
                  TextButton(
                    onPressed: busy || existing != null
                        ? null
                        : () async {
                            final p = vm.plans.firstWhere(
                              (p) => p.patientPlanId == planId,
                            );
                            final first = DateUtils.dateOnly(p.selectedAt);
                            final initial = chosenDate.isBefore(first)
                                ? first
                                : chosenDate;
                            final picked = await showDatePicker(
                              context: ctx,
                              initialDate: initial,
                              firstDate: first,
                              lastDate: vm.today,
                            );
                            if (picked != null) {
                              update(() => chosenDate = picked);
                            }
                          },
                    child: Text('Date: ${date(chosenDate)}'),
                  ),
                  Text('Pain: $pain / 10 (0 = none, 10 = worst)'),
                  Slider(
                    key: const ValueKey('recovery-pain'),
                    value: pain.toDouble(),
                    min: 0,
                    max: 10,
                    divisions: 10,
                    label: '$pain',
                    onChanged: busy
                        ? null
                        : (v) => update(() => pain = v.round()),
                  ),
                  Text('Stiffness: $stiffness / 10 (0 = none)'),
                  Slider(
                    key: const ValueKey('recovery-stiffness'),
                    value: stiffness.toDouble(),
                    min: 0,
                    max: 10,
                    divisions: 10,
                    label: '$stiffness',
                    onChanged: busy
                        ? null
                        : (v) => update(() => stiffness = v.round()),
                  ),
                  Text(
                    'Exercise difficulty: $difficulty / 5 (1 = easy, 5 = very hard)',
                  ),
                  Slider(
                    value: difficulty.toDouble(),
                    min: 1,
                    max: 5,
                    divisions: 4,
                    label: '$difficulty',
                    onChanged: busy
                        ? null
                        : (v) => update(() => difficulty = v.round()),
                  ),
                  TextFormField(
                    initialValue: notes,
                    onChanged: (value) => notes = value,
                    maxLength: 500,
                    maxLines: 3,
                    enabled: !busy,
                    decoration: const InputDecoration(
                      labelText: 'Notes (optional)',
                    ),
                  ),
                  if (error != null)
                    Text(
                      error!,
                      style: const TextStyle(color: AppTokens.onDanger),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: InsightsSurface.primaryButtonStyle,
              onPressed: busy
                  ? null
                  : () async {
                      update(() => busy = true);
                      final saved = await vm.saveCheckIn(
                        planId: planId,
                        date: chosenDate,
                        pain: pain,
                        stiffness: stiffness,
                        difficulty: difficulty,
                        notes: notes,
                      );
                      if (!ctx.mounted) return;
                      if (saved) {
                        Navigator.pop(ctx);
                      } else {
                        update(() {
                          busy = false;
                          error = vm.errorMessage ?? 'Please retry.';
                        });
                      }
                    },
              child: busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save check-in'),
            ),
          ],
        ),
      ),
    );
  }
}
