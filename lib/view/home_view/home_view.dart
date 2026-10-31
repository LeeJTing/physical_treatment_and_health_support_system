import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:physical_treatment_and_health_support_system/viewmodel/ui_state.dart';
import 'package:physical_treatment_and_health_support_system/core/constants/app_constants.dart';
import 'package:physical_treatment_and_health_support_system/core/routes/routes.dart';
import 'package:physical_treatment_and_health_support_system/core/themes/design_tokens.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/patient_treatment_plan.dart';
import 'package:physical_treatment_and_health_support_system/view/planning_view/chat_view.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/chat_view_model/chat_view_model.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/home_view_model/home_view_model.dart';
import 'package:physical_treatment_and_health_support_system/view/common/rehab_labels.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/food_item.dart';
import 'package:physical_treatment_and_health_support_system/view/health_report_view/health_report_view.dart';
import 'package:physical_treatment_and_health_support_system/view/home_view/main_shell.dart';
import 'package:physical_treatment_and_health_support_system/view/monitoring_view/add_reading_sheet.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/analysis_view_model/analysis_view_model.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/meal_log_view_model/meal_log_view_model.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/monitoring_view_model/monitoring_view_model.dart';

/// Home dashboard (Figma "Home"). The Home tab of the app shell.
class HomeView extends StatefulWidget {
  const HomeView({super.key});

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<HomeViewModel>().load();
      // Score, vitals and today's intake (M400, M200, M700).
      context.read<MealLogViewModel>().load();
      context.read<AnalysisViewModel>().loadAnalysis();
    });
  }

  /// Opens a screen and refreshes the dashboard when the patient comes back.
  Future<void> _open(String route) async {
    await Navigator.of(context).pushNamed(route);
    if (mounted) await context.read<HomeViewModel>().load();
  }

  void _openChat() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => ChangeNotifierProvider(
        create: (c) => ChatViewModel(c.read(), c.read(), c.read()),
        child: const ChatView(openedFrom: Routes.home),
      ),
    ),
  );

  /// Quick action "Add Reading" (UC700 BF-6), straight from Home.
  Future<void> _addReading() async {
    final mvm = context.read<MonitoringViewModel>();
    final analysis = context.read<AnalysisViewModel>();
    if (mvm.accountId == null) await mvm.load();
    if (!mounted) return;
    final saved = await AddReadingSheet.show(context, mvm);
    if (saved == true) await analysis.loadAnalysis(); // FR400_030
  }

  void _openReport() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => ChangeNotifierProvider.value(
        value: context.read<AnalysisViewModel>(),
        child: const HealthReportView(),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<HomeViewModel>();
    return ColoredBox(
      color: AppTokens.screenBackground,
      child: switch (vm.state) {
        UiError(:final message) => _Retry(message, vm.load),
        UiSuccess(:final data) => RefreshIndicator(
          onRefresh: vm.load,
          child: _content(vm, data),
        ),
        _ => const Center(
          child: CircularProgressIndicator(color: AppTokens.brandDeep),
        ),
      },
    );
  }

  Widget _content(HomeViewModel vm, HomeData d) {
    final top = MediaQuery.paddingOf(context).top;
    final limit = d.profile.safetyLimit;
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        // Header band with the greeting, the bell and the risk pill.
        Stack(
          children: [
            Container(
              height: top + 230,
              decoration: const BoxDecoration(
                color: AppTokens.brandDeep,
                borderRadius: BorderRadius.vertical(
                  bottom: Radius.circular(32),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(24, top + 24, 12, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          vm.greeting(),
                          style: const TextStyle(
                            color: AppTokens.onBrandMuted,
                            fontSize: 17,
                          ),
                        ),
                        Text(
                          HomeViewModel.displayName(d.username),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 32,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Material(
                          color: AppTokens.tint,
                          shape: const StadiumBorder(),
                          child: InkWell(
                            customBorder: const StadiumBorder(),
                            onTap: () => _open(Routes.healthProfile),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 8,
                              ),
                              child: Text(
                                HomeViewModel.riskPill(d),
                                style: const TextStyle(
                                  color: AppTokens.brandDeep,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  _Bell(unread: d.unread, onTap: () => _open(Routes.reminders)),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                AppTokens.gutter,
                top + 176,
                AppTokens.gutter,
                0,
              ),
              child: _HealthScoreCard(onTap: _openReport),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppTokens.gutter,
            AppTokens.gap,
            AppTokens.gutter,
            28,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (d.profileNeedsAttention || d.profileStale) ...[
                _Notice(
                  d.profileStale
                      ? Messages.profileStale
                      : Messages.profileNotConfigured,
                  onTap: () => _open(Routes.healthProfile),
                ),
                const SizedBox(height: AppTokens.gap),
              ],
              Row(
                children: [
                  Expanded(
                    child: _VitalCard('Blood\npressure', 'mmHg', MetricType.bloodPressure, _openReport),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _VitalCard('Blood\nglucose', 'mmol/L', MetricType.bloodGlucose, _openReport),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _VitalCard('Body\nweight', 'kg', MetricType.bodyWeight, _openReport),
                  ),
                ],
              ),
              const SizedBox(height: AppTokens.gap),
              // Followed plans that no longer fit the profile (PlanRules.checkActive).
              if (d.planIssues.isNotEmpty) ...[
                _Notice(
                  d.planIssues.first.message,
                  onTap: () => _open(Routes.physicalTreatment),
                ),
                const SizedBox(height: AppTokens.gap),
              ],
              const SizedBox(height: AppTokens.gap),
              _SessionCard(
                data: d,
                onStart: () => _open(Routes.physicalTreatment),
                onGetPlan: () => _open(Routes.treatmentPlanning),
                onWhyPaused: () => Navigator.of(context).pushNamed(
                  Routes.ageLimit,
                  arguments: d.profile.profile?.age,
                ),
              ),
              const SizedBox(height: AppTokens.gap),
              _LimitsCard(
                calories: limit.dailyCalorieTarget,
                sodiumMg: limit.dailySodiumLimitMg.clamp(0, AppConstants.whoSodiumMg).toInt(),
                sugarG: limit.dailySugarLimitG.clamp(0, AppConstants.whoSugarG).toDouble(),
                consumed: context.watch<MealLogViewModel>().dailyTotals,
              ),
              const SizedBox(height: 24),
              const Text(
                'Quick actions',
                style: TextStyle(
                  color: AppTokens.ink,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppTokens.gap),
              Row(
                children: [
                  Expanded(
                    child: _QuickAction(
                      'Log Meal',
                      () => MainShell.of(context)?.selectTab(MainShell.dietTab),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _QuickAction('Add Reading', _addReading),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: _QuickAction('Ask AI', _openChat)),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Bell extends StatelessWidget {
  final int unread;
  final VoidCallback onTap;
  const _Bell({required this.unread, required this.onTap});

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: unread == 0 ? 'Reminders' : 'Reminders, $unread unread',
    iconSize: 30,
    onPressed: onTap,
    icon: Badge(
      isLabelVisible: unread > 0,
      backgroundColor: AppTokens.cta,
      label: Text('$unread'),
      child: const Icon(Icons.notifications_none, color: Colors.white),
    ),
  );
}

/// White card used by the dashboard.
class _Card extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  const _Card({required this.child, this.padding = const EdgeInsets.all(20)});

  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: AppTokens.surface,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: AppTokens.cardBorder),
    ),
    child: child,
  );
}

/// The Health Score from M400 (FR400_020, FR400_023): the most important number on the screen,
/// with the non-medical disclaimer inside the card (UI Design, Home Screen).
class _HealthScoreCard extends StatelessWidget {
  final VoidCallback onTap;
  const _HealthScoreCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final a = context.watch<AnalysisViewModel>().analysis;
    final score = a?.healthScore;
    final band = a?.scoreBand;
    final color = switch (band) {
      ScoreBand.good => AppTokens.good,
      ScoreBand.fair => AppTokens.brandDeepAccent,
      ScoreBand.needsAttention => AppTokens.caution,
      ScoreBand.atRisk => AppTokens.danger,
      null => AppTokens.inkMuted,
    };
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onTap,
      child: _Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Health Score',
                        style: TextStyle(color: AppTokens.ink, fontSize: 22, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        score == null
                            ? 'Needs 7 readings and 3 days of activity or meals.'
                            : '${band?.label ?? ''} · tap for your Health Report',
                        style: TextStyle(color: score == null ? AppTokens.inkMuted : color, fontSize: 15),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 84,
                  height: 84,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox.expand(
                        child: CircularProgressIndicator(
                          value: (score ?? 0) / 100,
                          strokeWidth: 12,
                          color: color,
                          backgroundColor: AppTokens.tint,
                        ),
                      ),
                      Text(
                        score?.toString() ?? '--',
                        style: TextStyle(
                          color: AppTokens.ink.withValues(alpha: score == null ? 0.5 : 1),
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              Messages.analysisDisclaimer,
              style: TextStyle(color: AppTokens.inkMuted, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

/// The newest blood pressure, glucose and weight reading (M200).
class _VitalCard extends StatelessWidget {
  final String label;
  final String unit;
  final MetricType metric;
  final VoidCallback onTap;
  const _VitalCard(this.label, this.unit, this.metric, this.onTap);

  @override
  Widget build(BuildContext context) {
    final r = context.watch<AnalysisViewModel>().latest(metric);
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onTap,
      child: _Card(
        padding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: AppTokens.inkMuted, fontSize: 15)),
            const SizedBox(height: 10),
            FittedBox(
              child: Text(
                r?.valueText() ?? '--',
                style: const TextStyle(color: AppTokens.ink, fontSize: 26, fontWeight: FontWeight.w600),
              ),
            ),
            Text(unit, style: const TextStyle(color: AppTokens.inkMuted, fontSize: 14)),
          ],
        ),
      ),
    );
  }
}

/// "TODAY'S SESSION": the next exercise of the active plan, or a way to get a plan.
class _SessionCard extends StatelessWidget {
  final HomeData data;
  final VoidCallback onStart;
  final VoidCallback onGetPlan;

  /// The age-limit page (plans paused from 65).
  final VoidCallback onWhyPaused;
  const _SessionCard({
    required this.data,
    required this.onStart,
    required this.onGetPlan,
    required this.onWhyPaused,
  });

  @override
  Widget build(BuildContext context) {
    final plan = data.plan;
    final next = data.nextStage;
    final (
      String title,
      String subtitle,
      String button,
      VoidCallback action,
    ) = switch (plan) {
      // 65 and over (Terms of Use, section 2).
      null when data.plansPaused => (
        'No exercise plan',
        'Exercise plans are for users under ${AppConstants.planAgeLimit} '
            '(Terms of Use, section 2).',
        'Why',
        onWhyPaused,
      ),
      final PatientTreatmentPlan p when data.plansPaused => (
        p.plan.planName,
        'Paused: exercise plans are for users under '
            '${AppConstants.planAgeLimit} (Terms of Use, section 2). Your '
            'progress is kept.',
        'Why',
        onWhyPaused,
      ),
      null => (
        'No treatment plan yet',
        'Get a plan matched to your health profile.',
        'Get a plan',
        onGetPlan,
      ),
      final PatientTreatmentPlan p when next == null => (
        p.plan.planName,
        'Plan completed. Well done!',
        'View plan',
        onStart,
      ),
      final PatientTreatmentPlan p when data.restDay => (
        p.plan.planName,
        'Rest today: a possible fall was seen. Try your exercises another day.',
        'View plan',
        onStart,
      ),
      final PatientTreatmentPlan p when data.doneToday => (
        p.plan.planName,
        data.planCount > 1
            ? "Today's exercises are done for all your plans. Come back tomorrow."
            : "Today's exercise is done. Come back for the next one.",
        'View plan',
        onStart,
      ),
      final PatientTreatmentPlan p => (
        p.plan.planName,
        HomeViewModel.sessionSummary(p.plan, RehabLabels.area),
        'Start',
        onStart,
      ),
    };
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 22, 20, 22),
      decoration: BoxDecoration(
        color: AppTokens.primary,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  "TODAY'S SESSION",
                  style: TextStyle(
                    color: AppTokens.onPrimaryMuted,
                    fontSize: 14,
                    letterSpacing: 3,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Icon(
                data.doneToday ? Icons.check_circle : Icons.fitness_center,
                color: AppTokens.highlight,
                size: 30,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(
              color: AppTokens.onPrimaryMuted,
              fontSize: 16,
            ),
          ),
          if (data.planCount > 1) ...[
            const SizedBox(height: 4),
            Text(
              '${data.plansDoneToday} of ${data.planCount} plans done today',
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
          ],
          if (plan != null &&
              next != null &&
              !data.doneToday &&
              !data.plansPaused) ...[
            const SizedBox(height: 4),
            Text(
              'Next: ${next.exercise.exerciseName}',
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
          ],
          ...[
            const SizedBox(height: 16),
            SizedBox(
              height: 52,
              child: FilledButton(
                onPressed: action,
                style: FilledButton.styleFrom(
                  backgroundColor: AppTokens.cta,
                  foregroundColor: Colors.white,
                  shape: const StadiumBorder(),
                  padding: const EdgeInsets.symmetric(horizontal: 44),
                  textStyle: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                child: Text(button),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The daily limits from the safety limit (FR100_055). Meal totals come with M700 (Diet).
class _LimitsCard extends StatelessWidget {
  final int calories;
  final int sodiumMg;
  final double sugarG;

  /// Logged today (M700, FR700_013).
  final Nutrients consumed;
  const _LimitsCard({
    required this.calories,
    required this.sodiumMg,
    required this.sugarG,
    this.consumed = Nutrients.zero,
  });

  static String _n(num v) {
    final s = v.round().toString();
    return s.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
  }

  @override
  Widget build(BuildContext context) {
    Widget bar(double used, num limit) => ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: LinearProgressIndicator(
        value: limit <= 0 ? 1 : (used / limit).clamp(0.0, 1.0),
        minHeight: 10,
        color: used > limit ? AppTokens.danger : AppTokens.brandDeepAccent,
        backgroundColor: AppTokens.tint,
      ),
    );
    Widget limit(String label, String value, double used, num max) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: AppTokens.inkMuted, fontSize: 15),
        ),
        Text(
          value,
          style: const TextStyle(
            color: AppTokens.ink,
            fontSize: 17,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 6),
        bar(used, max),
      ],
    );
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Energy today',
                  style: TextStyle(
                    color: AppTokens.ink,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                '${_n(consumed.energyKcal)} / ${_n(calories)} kcal',
                style: const TextStyle(color: AppTokens.inkMuted, fontSize: 16),
              ),
            ],
          ),
          const SizedBox(height: 12),
          bar(consumed.energyKcal, calories),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: limit('Sodium', '${_n(consumed.sodiumMg)} / ${_n(sodiumMg)} mg', consumed.sodiumMg, sodiumMg),
              ),
              const SizedBox(width: 24),
              Expanded(
                child: limit('Free sugars', '${_n(consumed.sugarG)} / ${_n(sugarG)} g', consumed.sugarG, sugarG),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'Your daily limits and what your logged meals used today.',
            style: TextStyle(color: AppTokens.inkMuted, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _QuickAction(this.label, this.onTap);

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 56,
    child: FilledButton(
      onPressed: onTap,
      style: FilledButton.styleFrom(
        backgroundColor: AppTokens.tint,
        foregroundColor: AppTokens.brandDeep,
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
      ),
      child: FittedBox(child: Text(label)),
    ),
  );
}

class _Notice extends StatelessWidget {
  final String text;
  final VoidCallback onTap;
  const _Notice(this.text, {required this.onTap});

  @override
  Widget build(BuildContext context) => Material(
    color: AppTokens.warnContainer,
    borderRadius: BorderRadius.circular(18),
    child: InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.info_outline, color: AppTokens.onWarn),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(color: AppTokens.onWarn, fontSize: 16),
              ),
            ),
            const Icon(Icons.chevron_right, color: AppTokens.onWarn),
          ],
        ),
      ),
    ),
  );
}

class _Retry extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;
  const _Retry(this.message, this.onRetry);

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 17, color: AppTokens.ink),
          ),
          const SizedBox(height: 16),
          OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
        ],
      ),
    ),
  );
}

/// Placeholder for a tab or route whose module is not built yet.
class ComingSoonView extends StatelessWidget {
  final String title;
  const ComingSoonView(this.title, {super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: const Center(child: Text('Coming soon')),
  );
}
