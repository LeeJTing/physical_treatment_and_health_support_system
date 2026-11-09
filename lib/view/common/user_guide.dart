import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:physical_treatment_and_health_support_system/core/themes/design_tokens.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/user_guide_view_model/user_guide_view_model.dart';
import 'package:physical_treatment_and_health_support_system/view/common/tidy_text.dart';

/// One page of a picture guide: a drawn picture, a short title and one or two plain sentences.
class GuideStep {
  final IconData icon;
  final IconData? badge;
  final String title;
  final String text;
  const GuideStep(this.icon, this.title, this.text, {this.badge});
}

/// A picture guide for one screen. [key] names it on the phone (seen or not).
class UserGuide {
  final String key;
  final String title;
  final List<GuideStep> steps;
  const UserGuide(this.key, this.title, this.steps);
}

/// The picture guides of the author's screens, in plain British English for older patients.
abstract final class Guides {
  static const diet = UserGuide('diet', 'Logging a meal', [
    GuideStep(
      Icons.photo_camera,
      'Take the photo from above',
      'Tap Log Meal and hold the phone over the plate so the whole meal fits in the picture. '
          'Daylight or a bright room works best.',
      badge: Icons.wb_sunny,
    ),
    GuideStep(
      Icons.fact_check,
      'Check what was found',
      'The foods we recognise are listed with a portion. Tap "Not this food?" to correct one, '
          'or + and - to change the portion.',
      badge: Icons.edit,
    ),
    GuideStep(
      Icons.verified_user,
      'See if it suits you',
      'Green means Suitable, orange Caution and red Not Suitable for your conditions. '
          'Tap "See a safer choice" for a better option.',
      badge: Icons.check_circle,
    ),
    GuideStep(
      Icons.photo_library,
      'Save, and look back later',
      'Your meal, its photo and today\'s totals are saved. Open History to see past meals and '
          'their photos; tap a meal for its details.',
      badge: Icons.history,
    ),
  ]);

  static const dietPlan = UserGuide('diet_plan', 'Using your diet plan', [
    GuideStep(
      Icons.restaurant_menu,
      'A plan that fits you',
      'Every day keeps within your energy, salt and sugar limits. Tap "Why this plan?" to see how it '
          'was made. Anything too much or too little for your body is shown in red.',
      badge: Icons.check_circle,
    ),
    GuideStep(
      Icons.touch_app,
      'Tap a food',
      'See why it was chosen, then change its portion, swap it, lock it to keep it, or remove it.',
    ),
    GuideStep(
      Icons.add_circle,
      'Add or remove foods',
      'Tap "Add food" under a meal, or the cross next to a food. You will see what changes before '
          'anything is changed. "Build my plan myself" lets you review all four meals in a draft before saving.',
    ),
    GuideStep(Icons.refresh, 'Ask for a new plan',
      'Tap refresh. Locked foods stay. A new week also keeps today\'s saved meals; '
          'use "Edit today\'s plan" to change them.'),
  ]);

  static const tracking = UserGuide('tracking', 'Recording your health readings', [
    GuideStep(
      Icons.monitor_heart,
      'Blood pressure',
      'Sit quietly for 5 minutes with your arm resting at heart level, then measure. Enter the top '
          '(systolic) and bottom (diastolic) numbers.',
    ),
    GuideStep(
      Icons.bloodtype,
      'Blood glucose',
      'Choose when you measured: before eating (fasting), after a meal, or at another time. This '
          'changes what counts as usual for you.',
    ),
    GuideStep(
      Icons.monitor_weight,
      'Body weight',
      'Weigh yourself at the same time each day, ideally in the morning before breakfast.',
    ),
    GuideStep(
      Icons.sync,
      'Readings from your watch',
      'Tap Connect once. Readings from Health Connect (your watch or other health apps) are then '
          'added by themselves.',
      badge: Icons.watch,
    ),
  ]);

  static const healthReport = UserGuide('health_report', 'Understanding your Health Report', [
    GuideStep(
      Icons.speed,
      'Your Health Score',
      'A number from 0 to 100 built from your readings, exercise and meals. 80 or more is Good; '
          'below 50 needs your attention.',
    ),
    GuideStep(
      Icons.warning_amber,
      'Readings that need attention',
      'A reading far from your usual range is marked yellow (Low), orange (Medium) or red (High). '
          'Red means please contact your doctor.',
    ),
    GuideStep(
      Icons.show_chart,
      'The 7-day forecast',
      'After 14 readings of one kind, the app estimates the next 7 days so you can act early.',
    ),
    GuideStep(
      Icons.health_and_safety,
      'Not a diagnosis',
      'The report helps you and your doctor talk about your health. It does not replace medical advice.',
    ),
  ]);

  static const reminders = UserGuide('reminders', 'Reminders and alerts', [
    GuideStep(
      Icons.alarm,
      'Set a reminder',
      'Use the switch to turn a reminder on or off, tap the time to change it, and tap the days it '
          'should ring.',
    ),
    GuideStep(
      Icons.restaurant,
      'Meals and readings',
      'Add reminders for breakfast, lunch and dinner, or one every evening to log your readings.',
      badge: Icons.monitor_heart,
    ),
    GuideStep(
      Icons.notifications_active,
      'Health alerts',
      'When a reading is unusual you get an alert here. Tap it to read what it means and what to do.',
    ),
  ]);

  static const all = [diet, dietPlan, tracking, healthReport, reminders];
}

/// A drawn picture for a guide page or an empty screen: the step's icon in a soft circle with a
/// small badge, in the app's colours.
class GuideIllustration extends StatelessWidget {
  final IconData icon;
  final IconData? badge;
  final double size;
  const GuideIllustration(this.icon, {super.key, this.badge, this.size = 150});

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: size,
          height: size,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppTokens.tint, AppTokens.successContainer],
            ),
          ),
        ),
        Positioned(
          left: size * 0.08,
          top: size * 0.14,
          child: Container(
            width: size * 0.12,
            height: size * 0.12,
            decoration: const BoxDecoration(shape: BoxShape.circle, color: AppTokens.cautionContainer),
          ),
        ),
        Container(
          width: size * 0.62,
          height: size * 0.62,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppTokens.surface,
            boxShadow: [
              BoxShadow(color: AppTokens.brandDeep.withValues(alpha: 0.12), blurRadius: 16, offset: const Offset(0, 6)),
            ],
          ),
          child: Icon(icon, size: size * 0.34, color: AppTokens.brandDeep),
        ),
        if (badge != null)
          Positioned(
            right: size * 0.1,
            bottom: size * 0.12,
            child: Container(
              width: size * 0.28,
              height: size * 0.28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTokens.cta,
                border: Border.all(color: AppTokens.surface, width: 3),
              ),
              child: Icon(badge, size: size * 0.15, color: Colors.white),
            ),
          ),
      ],
    ),
  );
}

/// Shows a picture guide as a swipeable sheet: picture, "Step 2 of 4", title, text, dots, and
/// Back / Next / Got it. Closing it records that the guide was seen.
class UserGuideSheet extends StatefulWidget {
  final UserGuide guide;
  const UserGuideSheet({super.key, required this.guide});

  static Future<void> show(BuildContext context, UserGuide guide) async {
    final guides = _guideViewModel(context);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppTokens.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (_) => UserGuideSheet(guide: guide),
    );
    await guides?.markSeen(guide.key);
  }

  @override
  State<UserGuideSheet> createState() => _UserGuideSheetState();
}

class _UserGuideSheetState extends State<UserGuideSheet> {
  final _pages = PageController();
  int _page = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _go(int i) =>
      _pages.animateToPage(i, duration: const Duration(milliseconds: 280), curve: Curves.easeOutCubic);

  @override
  Widget build(BuildContext context) {
    final steps = widget.guide.steps;
    final last = _page == steps.length - 1;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    tidy(widget.guide.title),
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppTokens.ink),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const OneLineText('Skip', alignment: Alignment.center, style: TextStyle(fontSize: 16)),
                ),
              ],
            ),
            SizedBox(
              height: 360,
              child: PageView.builder(
                controller: _pages,
                itemCount: steps.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (_, i) {
                  final s = steps[i];
                  return SingleChildScrollView(
                    child: Column(
                    children: [
                      const SizedBox(height: 12),
                      GuideIllustration(s.icon, badge: s.badge),
                      const SizedBox(height: 18),
                      OneLineText(
                        'Step ${i + 1} of ${steps.length}',
                        alignment: Alignment.center,
                        style: const TextStyle(fontSize: 14, color: AppTokens.inkMuted, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        tidy(s.title),
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w700, color: AppTokens.ink),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        tidy(s.text),
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 17, height: 1.4, color: AppTokens.ink),
                      ),
                    ],
                    ),
                  );
                },
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < steps.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: i == _page ? 22 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: i == _page ? AppTokens.brandDeep : AppTokens.cardBorder,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                if (_page > 0) ...[
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(54), shape: const StadiumBorder()),
                      onPressed: () => _go(_page - 1),
                      child: const OneLineText('Back', alignment: Alignment.center, style: TextStyle(fontSize: 17)),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(54),
                      backgroundColor: AppTokens.brandDeep,
                      shape: const StadiumBorder(),
                    ),
                    onPressed: last ? () => Navigator.of(context).pop() : () => _go(_page + 1),
                    child: OneLineText(last ? 'Got it' : 'Next', alignment: Alignment.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

UserGuideViewModel? _guideViewModel(BuildContext context) {
  try {
    return context.read<UserGuideViewModel>();
  } on ProviderNotFoundException {
    return null; // tests and screens outside the app shell: no first-visit guides
  }
}

/// Opens [guide] by itself the first time its screen is used on this phone.
Future<void> showGuideOnce(BuildContext context, UserGuide guide) async {
  final guides = _guideViewModel(context);
  if (guides == null) return;
  if (!await guides.shouldShow(guide.key)) return;
  if (!context.mounted) return;
  await UserGuideSheet.show(context, guide);
}

/// Profile > Picture guides: every guide opens by itself again the next time its screen is used.
Future<bool> showAllGuidesAgain(BuildContext context) async {
  final guides = _guideViewModel(context);
  if (guides == null) return false;
  await guides.showAllAgain(Guides.all.map((g) => g.key));
  return true;
}

/// The "?" button that opens a screen's picture guide at any time.
class HelpButton extends StatelessWidget {
  final UserGuide guide;
  final Color color;
  const HelpButton({super.key, required this.guide, this.color = Colors.white});

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: 'How to use this screen',
    onPressed: () => UserGuideSheet.show(context, guide),
    icon: Icon(Icons.help_outline, color: color, size: 28),
  );
}

/// An empty list explained with a picture, what it will show, and what to do next.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final IconData? badge;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.badge,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
    decoration: BoxDecoration(
      color: AppTokens.surface,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: AppTokens.cardBorder),
    ),
    child: Column(
      children: [
        GuideIllustration(icon, badge: badge, size: 96),
        const SizedBox(height: 12),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppTokens.ink),
        ),
        const SizedBox(height: 4),
        Text(
          tidy(message),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 15, height: 1.35, color: AppTokens.inkMuted),
        ),
        if (actionLabel != null && onAction != null) ...[
          const SizedBox(height: 8),
          TextButton(onPressed: onAction, child: OneLineText(actionLabel!, alignment: Alignment.center, style: const TextStyle(fontSize: 16))),
        ],
      ],
    ),
  );
}
