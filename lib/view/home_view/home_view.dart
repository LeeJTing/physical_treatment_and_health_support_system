import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:physical_treatment_and_health_support_system/view/common/whole_words_text.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/ui_state.dart';
import 'package:physical_treatment_and_health_support_system/core/constants/app_constants.dart';
import 'package:physical_treatment_and_health_support_system/core/routes/routes.dart';
import 'package:physical_treatment_and_health_support_system/core/themes/design_tokens.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/patient_treatment_plan.dart';
import 'package:physical_treatment_and_health_support_system/view/planning_view/chat_view.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/chat_view_model/chat_view_model.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/home_view_model/home_view_model.dart';
import 'package:physical_treatment_and_health_support_system/view/common/rehab_labels.dart';

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
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => context.read<HomeViewModel>().load(),
    );
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

  void _notYet(String what) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        '$what is part of the Health Monitoring and Diet modules (coming soon).',
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
        // Header band with the greeting, the bell and the risk pill, as tall as their text needs
        // (audit, 24 Oct: fixed offsets put the pill under the Health Score card with large phone
        // text). At normal text size the card starts at top + 176 as in the Figma.
        ColoredBox(
          color: AppTokens.brandDeep,
          child: Padding(
            padding: EdgeInsets.fromLTRB(24, top + 24, 12, 16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 136),
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
          ),
        ),
        // The band's rounded last 54 px run behind the top of the card.
        Stack(
          children: [
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 54,
              child: Container(
                decoration: const BoxDecoration(
                  color: AppTokens.brandDeep,
                  borderRadius: BorderRadius.vertical(
                    bottom: Radius.circular(32),
                  ),
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: AppTokens.gutter),
              child: _HealthScoreCard(),
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
              const Row(
                children: [
                  Expanded(child: _VitalCard('Blood\npressure', 'mmHg')),
                  SizedBox(width: 10),
                  Expanded(child: _VitalCard('Blood\nglucose', 'mmol/L')),
                  SizedBox(width: 10),
                  Expanded(child: _VitalCard('Body\nweight', 'kg')),
                ],
              ),
              const SizedBox(height: AppTokens.gap),
              // Followed plans that no longer fit the profile (PlanRules.checkActive); a gap on
              // both sides (audit, 24 Oct: it touched the vitals row).
              if (d.planIssues.isNotEmpty) ...[
                _Notice(
                  d.planIssues.first.message,
                  onTap: () => _open(Routes.physicalTreatment),
                ),
                const SizedBox(height: AppTokens.gap),
              ],
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
                sodiumMg: limit.dailySodiumLimitMg,
                sugarG: limit.dailySugarLimitG,
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
                      () => _notYet('Logging a meal'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _QuickAction(
                      'Add Reading',
                      () => _notYet('Adding a reading'),
                    ),
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

/// M400 (Predictive Health Analysis) computes the score; until it does, the card says so.
class _HealthScoreCard extends StatelessWidget {
  const _HealthScoreCard();

  @override
  Widget build(BuildContext context) => _Card(
    child: Row(
      children: [
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Health Score',
                style: TextStyle(
                  color: AppTokens.ink,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(height: 6),
              Text(
                'Appears once your health readings are synced.',
                style: TextStyle(color: AppTokens.inkMuted, fontSize: 15),
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
              const SizedBox.expand(
                child: CircularProgressIndicator(
                  value: 0,
                  strokeWidth: 12,
                  backgroundColor: AppTokens.tint,
                ),
              ),
              Text(
                '--',
                style: TextStyle(
                  color: AppTokens.ink.withValues(alpha: 0.5),
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

/// Blood pressure, glucose and weight come from M200 (Health Monitoring); empty until then.
class _VitalCard extends StatelessWidget {
  final String label;
  final String unit;
  const _VitalCard(this.label, this.unit);

  @override
  Widget build(BuildContext context) => _Card(
    padding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        WholeWordsText(
          label,
          style: const TextStyle(color: AppTokens.inkMuted, fontSize: 15),
        ),
        const SizedBox(height: 10),
        const Text(
          '--',
          style: TextStyle(
            color: AppTokens.ink,
            fontSize: 26,
            fontWeight: FontWeight.w600,
          ),
        ),
        Text(
          unit,
          style: const TextStyle(color: AppTokens.inkMuted, fontSize: 14),
        ),
      ],
    ),
  );
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
        HomeViewModel.sessionSummary(p, next, RehabLabels.area),
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
  const _LimitsCard({
    required this.calories,
    required this.sodiumMg,
    required this.sugarG,
  });

  static String _n(num v) {
    final s = v.round().toString();
    return s.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
  }

  @override
  Widget build(BuildContext context) {
    Widget bar() => ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: const LinearProgressIndicator(
        value: 0,
        minHeight: 10,
        backgroundColor: AppTokens.tint,
      ),
    );
    Widget limit(String label, String value) => Column(
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
        bar(),
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
              const SizedBox(width: 8),
              // Wraps with large phone text instead of running off the card (audit, 24 Oct).
              Flexible(
                child: Text(
                  '0 / ${_n(calories)} kcal',
                  textAlign: TextAlign.end,
                  style: const TextStyle(
                    color: AppTokens.inkMuted,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          bar(),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: limit('Sodium', '0 / ${_n(sodiumMg)} mg')),
              const SizedBox(width: 24),
              Expanded(child: limit('Free sugars', '0 / ${_n(sugarG)} g')),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'Your daily limits. Logged meals will count towards them.',
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
