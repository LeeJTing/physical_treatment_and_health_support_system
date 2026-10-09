import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:physical_treatment_and_health_support_system/viewmodel/ui_state.dart';
import 'package:physical_treatment_and_health_support_system/core/constants/app_constants.dart';
import 'package:physical_treatment_and_health_support_system/core/routes/routes.dart';
import 'package:physical_treatment_and_health_support_system/core/themes/design_tokens.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/reminder.dart';
import 'package:physical_treatment_and_health_support_system/view/planning_view/widgets/planning_widgets.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/notification_view_model/notification_view_model.dart';

/// Reminders (M600.1): the treatment plan's exercise reminders and an optional health-logging
/// reminder (FR600_001, FR600_002); time, days and on/off for each (FR600_003, FR600_004,
/// FR600_006); and the last two weeks of notifications (FR600_013, FR600_015, FR600_016). No Figma
/// frame exists for it, so it uses the planning screens' tokens.
class NotificationView extends StatefulWidget {
  const NotificationView({super.key});

  @override
  State<NotificationView> createState() => _NotificationViewState();
}

class _NotificationViewState extends State<NotificationView>
    with WidgetsBindingObserver {
  static const days = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
  static const dayNames = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => context.read<NotificationViewModel>().load(),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Back from the phone's Settings: the notice goes away once notifications are on.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      context.read<NotificationViewModel>().recheckPermission();
    }
  }

  String _time(int h, int m) {
    final hh = h % 12 == 0 ? 12 : h % 12;
    return '$hh:${m.toString().padLeft(2, '0')} ${h < 12 ? 'AM' : 'PM'}';
  }

  Future<void> _pickTime(Reminder r) async {
    final vm = context.read<NotificationViewModel>();
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: r.hour, minute: r.minute),
    );
    if (t != null) await vm.changeTime(r.reminderId, t.hour, t.minute);
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<NotificationViewModel>();
    return Scaffold(
      backgroundColor: AppTokens.background,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            8,
            8,
            AppTokens.gutter,
            AppTokens.gutter,
          ),
          children: [
            PlanningHeader(
              title: 'Reminders',
              subtitle: 'When we remind you to exercise and log your health',
              onBack: () => Navigator.of(context).maybePop(),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (vm.notificationsBlocked) ...[
                    const NoticeBanner(
                      Messages.notificationsOff,
                      warning: true,
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: vm.openNotificationSettings,
                        style: TextButton.styleFrom(
                          minimumSize: const Size(48, AppTokens.minTarget),
                        ),
                        icon: const Icon(Icons.notifications_active_outlined),
                        label: const Text(
                          'Turn on notifications',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                  ] else if (!vm.remindersOnTime &&
                      (vm.reminders is UiSuccess<List<Reminder>>) &&
                      (vm.reminders as UiSuccess<List<Reminder>>).data.any(
                        (r) => r.isEnabled,
                      )) ...[
                    const NoticeBanner(Messages.remindersMayBeLate),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: vm.openOnTimeSettings,
                        style: TextButton.styleFrom(
                          minimumSize: const Size(48, AppTokens.minTarget),
                        ),
                        icon: const Icon(Icons.alarm_on_outlined),
                        label: const Text(
                          'Turn on Alarms & reminders',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                  ],
                  switch (vm.reminders) {
                    Idle() || Loading() => const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(
                        child: CircularProgressIndicator(
                          color: AppTokens.primary,
                        ),
                      ),
                    ),
                    UiError(:final message) => NoticeBanner(
                      message,
                      warning: true,
                    ),
                    UiSuccess(:final data) when data.isEmpty =>
                      const NoticeBanner(
                        'No reminders yet. Exercise reminders are created when you select a treatment plan.',
                      ),
                    UiSuccess(:final data) => Column(
                      children: [
                        for (final r in data) ...[
                          _reminderCard(r),
                          const SizedBox(height: AppTokens.gap),
                        ],
                      ],
                    ),
                  },
                  if (vm.errorMessage case final e?) ...[
                    const SizedBox(height: 8),
                    NoticeBanner(e, warning: true),
                  ],
                  if (vm.reminders is UiSuccess && !vm.hasHealthLogReminder) ...[
                    const SizedBox(height: 4),
                    OutlinedButton.icon(
                      onPressed: vm.addHealthLogReminder,
                      icon: const Icon(Icons.monitor_heart_outlined),
                      label: const Text(
                        'Remind me to log my health readings',
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTokens.accent,
                        minimumSize: const Size.fromHeight(48),
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Recent notifications',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: AppTokens.text,
                          ),
                        ),
                      ),
                      if (vm.unreadCount > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: AppTokens.action,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${vm.unreadCount} unread',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (vm.log.isEmpty)
                    const Text(
                      'Nothing in the last two weeks.',
                      style: TextStyle(
                        fontSize: 15,
                        color: AppTokens.textMuted,
                      ),
                    )
                  else
                    for (final n in vm.log) _logTile(n, vm),
                ],
              ),
            ),
          ],
        ),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  r.title,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: AppTokens.text,
                  ),
                ),
              ),
              if (r.patientPlanId == null)
                IconButton(
                  tooltip: 'Delete this reminder',
                  icon: const Icon(
                    Icons.delete_outline,
                    color: AppTokens.textMuted,
                  ),
                  onPressed: () => _confirmDelete(r),
                ),
              Switch(
                value: r.isEnabled,
                activeTrackColor: AppTokens.progress,
                onChanged: (on) => vm.toggleReminder(r.reminderId, on),
              ),
            ],
          ),
          const SizedBox(height: 4),
          InkWell(
            onTap: () => _pickTime(r),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  const Icon(Icons.schedule, size: 20, color: AppTokens.accent),
                  const SizedBox(width: 6),
                  Text(
                    _time(r.hour, r.minute),
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      color: AppTokens.text,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Change',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppTokens.accent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          // On = filled, white letter; off = outline only, so the two differ by more than a tint.
          // Each day takes an equal share of the row and a 48 px tall tap area.
          Row(
            children: [
              for (var i = 0; i < 7; i++)
                Expanded(
                  child: Semantics(
                    button: true,
                    selected: r.repeatDays[i] == '1',
                    label: dayNames[i],
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => vm.toggleDay(r.reminderId, i + 1),
                      child: SizedBox(
                        height: AppTokens.minTarget,
                        child: Center(
                          child: Container(
                            width: 36,
                            height: 36,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: r.repeatDays[i] == '1'
                                  ? AppTokens.accent
                                  : AppTokens.surface,
                              border: Border.all(
                                color: r.repeatDays[i] == '1'
                                    ? AppTokens.accent
                                    : AppTokens.outline,
                                width: 1.5,
                              ),
                            ),
                            child: Text(
                              days[i],
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: r.repeatDays[i] == '1'
                                    ? Colors.white
                                    : AppTokens.textMuted,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Tap a day to turn it on or off.',
            style: TextStyle(fontSize: 13, color: AppTokens.textMuted),
          ),
          // The plan this reminder is for: the same place a tapped notification opens.
          if (r.patientPlanId != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => Navigator.of(context).pushNamed(
                  Routes.physicalTreatment,
                  arguments: r.patientPlanId,
                ),
                style: TextButton.styleFrom(
                  minimumSize: const Size(48, AppTokens.minTarget),
                  padding: EdgeInsets.zero,
                ),
                icon: const Icon(Icons.chevron_right),
                label: const Text(
                  'Open this plan',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(Reminder r) async {
    final vm = context.read<NotificationViewModel>();
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this reminder?'),
        content: Text('"${r.title}" will no longer remind you.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppTokens.danger),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (yes == true) await vm.deleteReminder(r.reminderId);
  }

  Widget _logTile(NotificationLog n, NotificationViewModel vm) {
    final when = n.issuedAt;
    final label = '${when.day}/${when.month} ${_time(when.hour, when.minute)}';
    final suppressed = n.deliveryStatus == DeliveryStatus.suppressed;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: n.isRead ? null : () => vm.markRead(n.notificationId),
      leading: Icon(
        suppressed
            ? Icons.notifications_off_outlined
            : Icons.notifications_outlined,
        color: n.isRead ? AppTokens.textMuted : AppTokens.action,
      ),
      title: Text(
        n.messageBody,
        style: TextStyle(
          fontSize: 15,
          color: AppTokens.text,
          fontWeight: n.isRead ? FontWeight.w400 : FontWeight.w600,
        ),
      ),
      subtitle: Text(
        label,
        style: const TextStyle(fontSize: 13, color: AppTokens.textMuted),
      ),
    );
  }
}
