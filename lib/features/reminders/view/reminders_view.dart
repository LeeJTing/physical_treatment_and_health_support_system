import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:physical_treatment_and_health_support_system/core/base/ui_state.dart';
import 'package:physical_treatment_and_health_support_system/core/themes/design_tokens.dart';
import 'package:physical_treatment_and_health_support_system/data/models/enums.dart';
import 'package:physical_treatment_and_health_support_system/data/models/reminder.dart';
import 'package:physical_treatment_and_health_support_system/features/planning/widgets/planning_widgets.dart';
import 'package:physical_treatment_and_health_support_system/features/reminders/viewmodel/notification_view_model.dart';

/// Exercise reminders (M600.1): time, days, on/off (FR600_003, FR600_004, FR600_006), and the
/// last two weeks of notifications (FR600_013, FR600_015, FR600_016). No Figma frame exists for
/// it, so it uses the planning screens' tokens.
class RemindersView extends StatefulWidget {
  const RemindersView({super.key});

  @override
  State<RemindersView> createState() => _RemindersViewState();
}

class _RemindersViewState extends State<RemindersView> {
  static const days = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => context.read<NotificationViewModel>().load());
  }

  String _time(int h, int m) {
    final hh = h % 12 == 0 ? 12 : h % 12;
    return '$hh:${m.toString().padLeft(2, '0')} ${h < 12 ? 'AM' : 'PM'}';
  }

  Future<void> _pickTime(Reminder r) async {
    final vm = context.read<NotificationViewModel>();
    final t = await showTimePicker(context: context, initialTime: TimeOfDay(hour: r.hour, minute: r.minute));
    if (t != null) await vm.changeTime(r.reminderId, t.hour, t.minute);
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<NotificationViewModel>();
    return Scaffold(
      backgroundColor: AppTokens.background,
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(8, 8, AppTokens.gutter, AppTokens.gutter), children: [
          PlanningHeader(
              title: 'Reminders', subtitle: 'When we remind you to exercise', onBack: () => Navigator.of(context).maybePop()),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              switch (vm.reminders) {
                Idle() || Loading() => const Padding(
                    padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator(color: AppTokens.primary))),
                UiError(:final message) => NoticeBanner(message, warning: true),
                UiSuccess(:final data) when data.isEmpty =>
                  const NoticeBanner('No reminders yet. They are created when you select a treatment plan.'),
                UiSuccess(:final data) => Column(children: [
                    for (final r in data) ...[_reminderCard(r), const SizedBox(height: AppTokens.gap)],
                  ]),
              },
              if (vm.errorMessage case final e?) ...[const SizedBox(height: 8), NoticeBanner(e, warning: true)],
              const SizedBox(height: 20),
              Row(children: [
                const Expanded(
                  child: Text('Recent notifications',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppTokens.text)),
                ),
                if (vm.unreadCount > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(color: AppTokens.action, borderRadius: BorderRadius.circular(12)),
                    child: Text('${vm.unreadCount} unread',
                        style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                  ),
              ]),
              const SizedBox(height: 8),
              if (vm.log.isEmpty)
                const Text('Nothing in the last two weeks.', style: TextStyle(fontSize: 15, color: AppTokens.textMuted))
              else
                for (final n in vm.log) _logTile(n, vm),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _reminderCard(Reminder r) {
    final vm = context.read<NotificationViewModel>();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTokens.surface,
        borderRadius: BorderRadius.circular(AppTokens.radiusCard),
        border: Border.all(color: AppTokens.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(r.title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: AppTokens.text)),
          ),
          Switch(
            value: r.isEnabled,
            activeTrackColor: AppTokens.progress,
            onChanged: (on) => vm.toggleReminder(r.reminderId, on),
          ),
        ]),
        const SizedBox(height: 4),
        InkWell(
          onTap: () => _pickTime(r),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(children: [
              const Icon(Icons.schedule, size: 20, color: AppTokens.accent),
              const SizedBox(width: 6),
              Text(_time(r.hour, r.minute),
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: AppTokens.text)),
              const SizedBox(width: 8),
              const Text('Change', style: TextStyle(fontSize: 14, color: AppTokens.accent, fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
        const SizedBox(height: 8),
        Row(children: [
          for (var i = 0; i < 7; i++)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: r.repeatDays[i] == '1' ? AppTokens.accentContainer : AppTokens.background,
                ),
                child: Text(days[i],
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: r.repeatDays[i] == '1' ? AppTokens.accent : AppTokens.textMuted)),
              ),
            ),
        ]),
      ]),
    );
  }

  Widget _logTile(NotificationLog n, NotificationViewModel vm) {
    final when = n.issuedAt;
    final label = '${when.day}/${when.month} ${_time(when.hour, when.minute)}';
    final suppressed = n.deliveryStatus == DeliveryStatus.suppressed;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: n.isRead ? null : () => vm.markRead(n.notificationId),
      leading: Icon(suppressed ? Icons.notifications_off_outlined : Icons.notifications_outlined,
          color: n.isRead ? AppTokens.textMuted : AppTokens.action),
      title: Text(n.messageBody, style: TextStyle(fontSize: 15, color: AppTokens.text,
          fontWeight: n.isRead ? FontWeight.w400 : FontWeight.w600)),
      subtitle: Text(label, style: const TextStyle(fontSize: 13, color: AppTokens.textMuted)),
    );
  }
}
