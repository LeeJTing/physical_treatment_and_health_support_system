import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:physical_treatment_and_health_support_system/core/routes/routes.dart';
import 'package:physical_treatment_and_health_support_system/core/themes/design_tokens.dart';
import 'package:physical_treatment_and_health_support_system/features/treatment/view/physical_treatment_view.dart';
import 'package:physical_treatment_and_health_support_system/features/treatment/view/session_history_view.dart';
import 'package:physical_treatment_and_health_support_system/features/treatment/viewmodel/treatment_view_model.dart';
import 'package:physical_treatment_and_health_support_system/features/treatment/widgets/treatment_widgets.dart';

/// The Treatment tab (UI Design, Treatment Screen): open my plan, get a new plan, progress
/// overview and the next reminder. The bottom navigation bar belongs to the app shell.
class TreatmentTabView extends StatefulWidget {
  const TreatmentTabView({super.key});

  @override
  State<TreatmentTabView> createState() => _TreatmentTabViewState();
}

class _TreatmentTabViewState extends State<TreatmentTabView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => context.read<TreatmentViewModel>().loadPlan());
  }

  Future<void> _openPlan() async {
    final vm = context.read<TreatmentViewModel>();
    await Navigator.of(context).push(MaterialPageRoute<void>(
      settings: const RouteSettings(name: PhysicalTreatmentView.routeName),
      builder: (_) => ChangeNotifierProvider.value(value: vm, child: const PhysicalTreatmentView()),
    ));
    if (mounted) await vm.loadPlan();
  }

  Future<void> _openHistory() async {
    final vm = context.read<TreatmentViewModel>();
    await Navigator.of(context).push(MaterialPageRoute<void>(
      settings: const RouteSettings(name: Routes.sessionHistory),
      builder: (_) => ChangeNotifierProvider.value(value: vm, child: const SessionHistoryView()),
    ));
  }

  Future<void> _openPlanning() async {
    await Navigator.of(context).pushNamed(Routes.treatmentPlanning);
    if (mounted) await context.read<TreatmentViewModel>().loadPlan();
  }

  static String _when(DateTime t) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(t.year, t.month, t.day);
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final time = '$h:${t.minute.toString().padLeft(2, '0')} ${t.hour < 12 ? 'AM' : 'PM'}';
    const names = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    final label = day == today
        ? 'Today'
        : day == today.add(const Duration(days: 1))
            ? 'Tomorrow'
            : names[t.weekday - 1];
    return '$label, $time';
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<TreatmentViewModel>();
    final plan = vm.activePlan;
    final next = plan?.currentExercise();
    final days = plan == null ? 0 : DateTime.now().difference(plan.selectedAt).inDays;
    return ColoredBox(
      color: AppTokens.background,
      child: ListView(padding: EdgeInsets.zero, children: [
        Container(
          color: AppTokens.primary,
          padding: EdgeInsets.fromLTRB(AppTokens.gutter, MediaQuery.paddingOf(context).top + 20, AppTokens.gutter, 28),
          child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Treatment', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: Colors.white)),
            SizedBox(height: 4),
            Text('Manage your plan or get a new one',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: AppTokens.onPrimaryMuted)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.all(AppTokens.gutter),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _NavCard(
              dark: true,
              icon: Icons.monitor_heart_outlined,
              title: 'My treatment plan',
              subtitle: plan == null ? 'No plan yet: get one below' : 'View pathway, do exercises, check posture',
              onTap: _openPlan,
            ),
            const SizedBox(height: AppTokens.gap),
            _NavCard(
              icon: Icons.auto_awesome_outlined,
              title: 'AI-assisted treatment planning',
              subtitle: 'Get a new plan, ask the chat bot',
              onTap: _openPlanning,
            ),
            if (plan != null) ...[
              const SizedBox(height: AppTokens.gap),
              _NavCard(
                icon: Icons.insights_outlined,
                title: 'Session history',
                subtitle: vm.sessions.isEmpty ? 'Your posture results will appear here' : 'Your posture accuracy over time',
                onTap: _openHistory,
              ),
            ],
            if (plan != null) ...[
              const SizedBox(height: 28),
              const Text('Progress overview',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppTokens.text)),
              const SizedBox(height: AppTokens.gap),
              ProgressBlock(
                label: plan.plan.planName,
                done: plan.completedStages,
                total: plan.plan.exercises.length,
                footerLeft: days == 0 ? 'Started today' : 'Started $days day${days == 1 ? '' : 's'} ago',
                footerRight: '${plan.plan.frequencyPerWeek}x a week',
              ),
              const SizedBox(height: AppTokens.gap),
              TreatmentCard(
                child: Row(children: [
                  const Icon(Icons.notifications_active_outlined, color: AppTokens.text),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Next reminder',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppTokens.text)),
                      const SizedBox(height: 2),
                      Text(
                        vm.nextReminderAt == null
                            ? 'No reminder scheduled'
                            : '${_when(vm.nextReminderAt!)}${next == null ? '' : ' · ${next.exerciseName}'}',
                        style: const TextStyle(fontSize: 14, color: AppTokens.textMuted),
                      ),
                    ]),
                  ),
                ]),
              ),
            ],
          ]),
        ),
      ]),
    );
  }
}

class _NavCard extends StatelessWidget {
  final bool dark;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _NavCard({required this.icon, required this.title, required this.subtitle, required this.onTap, this.dark = false});

  @override
  Widget build(BuildContext context) {
    final fg = dark ? Colors.white : AppTokens.text;
    return Semantics(
      button: true,
      child: Material(
        color: dark ? AppTokens.primary : AppTokens.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusCard + 4),
          side: dark ? BorderSide.none : const BorderSide(color: AppTokens.border),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppTokens.radiusCard + 4),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                    color: dark ? Colors.white.withValues(alpha: 0.12) : AppTokens.goodContainer, shape: BoxShape.circle),
                child: Icon(icon, color: dark ? Colors.white : AppTokens.good),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: fg)),
                  const SizedBox(height: 4),
                  Text(subtitle,
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w500, color: dark ? AppTokens.onPrimaryMuted : AppTokens.textMuted)),
                ]),
              ),
              Icon(Icons.chevron_right, color: dark ? AppTokens.onPrimaryMuted : AppTokens.textMuted),
            ]),
          ),
        ),
      ),
    );
  }
}
