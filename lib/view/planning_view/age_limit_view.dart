import 'package:flutter/material.dart';

import 'package:physical_treatment_and_health_support_system/core/constants/app_constants.dart';
import 'package:physical_treatment_and_health_support_system/core/themes/design_tokens.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/recommendation_service/recommendation.dart';
import 'package:physical_treatment_and_health_support_system/view/planning_view/widgets/plan_reasons.dart';
import 'package:physical_treatment_and_health_support_system/view/planning_view/widgets/planning_widgets.dart';

/// Why there is no exercise plan from 65 (Terms of Use, section 2): shown
/// instead of the questionnaire, on paused plans, and from the chat
/// assistant's "Why plans are paused" button. Every reason is one its
/// sources support (fyp-notes/Draft_Age_Explanations_Terms, part B).
class AgeLimitView extends StatelessWidget {
  /// The profile age, when known.
  final int? age;

  const AgeLimitView({super.key, this.age});

  static const limit = AppConstants.planAgeLimit;

  static const reasons = [
    PlanReason(
      'NO_SUPERVISION',
      'No health professional supervises this app. The home exercise '
          'programmes proven for people aged $limit and over were set up and '
          'followed by professionals: the Otago programme by trained '
          'instructors with home visits, and Vivifrail by a health '
          'professional after a physical test.',
      ['otago2003', 'vivifrail2019'],
    ),
    PlanReason(
      'SUPERVISION_BETTER',
      'Supervision gives better results for older adults: supervised '
          'training improves balance and muscle strength more than training '
          'alone.',
      ['lacroix2017'],
    ),
    PlanReason(
      'HEALTH_CHECK',
      'Health checks matter more with age. Programmes for older adults start '
          'with a check of conditions such as heart problems, high blood '
          'pressure or a recent fracture before exercise begins.',
      ['vivifrail2019'],
    ),
  ];

  static const stillGood = PlanReason(
    'STILL_GOOD',
    'Exercise is still good for you: strength and balance activity on several '
        'days a week is recommended for older adults. Please ask your doctor '
        'or a registered physiotherapist to set up a programme for you, or ask '
        'about a hospital or community rehabilitation service.',
    ['who2020', 'acsm2009'],
  );

  static const allSources = [
    'otago2003',
    'vivifrail2019',
    'lacroix2017',
    'who2020',
    'acsm2009',
  ];

  @override
  Widget build(BuildContext context) => Scaffold(
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
            title: 'Exercise plans',
            subtitle: 'For users under $limit',
            onBack: () => Navigator.of(context).maybePop(),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 8, top: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                NoticeBanner(
                  '${age == null ? '' : 'Your profile says you are $age. '}'
                  'This app does not create exercise plans for users aged '
                  '$limit and over, and a plan you already have is paused. '
                  'This is stated in our Terms of Use (section 2).',
                  warning: true,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Why',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: AppTokens.text,
                  ),
                ),
                const ReasonList(reasons, positive: false),
                const SizedBox(height: 16),
                const Text(
                  'What you can do',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: AppTokens.text,
                  ),
                ),
                const ReasonList([stillGood]),
                const SizedBox(height: 12),
                const Text(
                  'You can still use your health profile, health logging, '
                  'your past results, reminders to log your health readings '
                  'and the chat assistant. Nothing has been deleted.',
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.35,
                    color: AppTokens.textBody,
                  ),
                ),
                const SizedBox(height: 20),
                OutlinedButton(
                  onPressed: () => showSources(context, allSources),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(AppTokens.minTarget),
                  ),
                  child: const Text('Sources'),
                ),
                const SizedBox(height: AppTokens.gap),
                TokenButton(
                  label: 'OK',
                  color: AppTokens.primary,
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
