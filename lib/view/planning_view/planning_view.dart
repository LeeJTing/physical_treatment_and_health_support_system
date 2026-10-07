import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:physical_treatment_and_health_support_system/core/themes/design_tokens.dart';
import 'package:physical_treatment_and_health_support_system/view/planning_view/chat_view.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/chat_view_model/chat_view_model.dart';
import 'package:physical_treatment_and_health_support_system/view/planning_view/recommended_plans_view.dart';
import 'package:physical_treatment_and_health_support_system/view/planning_view/rehab_questionnaire_sheet.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/planning_view_model/planning_view_model.dart';
import 'package:physical_treatment_and_health_support_system/view/planning_view/widgets/planning_widgets.dart';

/// AI-assisted planning page (UI Design "AI-Assisted Physical Treatment
/// Planning Page"; FR500_01): retrieve a plan or open the chat bot, with a
/// short explanation of how the recommendation works.
class PlanningView extends StatelessWidget {
  const PlanningView({super.key});

  Future<void> _retrieve(BuildContext context) async {
    final rehab = await showRehabQuestionnaire(context);
    if (rehab == null || !context.mounted) return;
    final vm = context.read<PlanningViewModel>();
    vm.recommend(rehab);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChangeNotifierProvider.value(
          value: vm,
          child: const RecommendedPlansView(),
        ),
      ),
    );
  }

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
            title: 'AI-assisted planning',
            subtitle: 'Get a plan or ask a question',
            onBack: () => Navigator.of(context).maybePop(),
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ActionCard(
                  filled: true,
                  icon: Icons.assignment_outlined,
                  title: 'Retrieve physical treatment',
                  subtitle: 'Generate exercises based on your health profile',
                  onTap: () => _retrieve(context),
                ),
                const SizedBox(height: AppTokens.gap),
                ActionCard(
                  icon: Icons.chat_bubble_outline,
                  title: 'Chat bot',
                  subtitle: 'Ask rehabilitation-related questions',
                  // FR500_17: the chatbot opens within the planning module.
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ChangeNotifierProvider(
                        create: (c) =>
                            ChatViewModel(c.read(), c.read(), c.read()),
                        child: const ChatView(),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                const Text(
                  'How it works',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: AppTokens.text,
                  ),
                ),
                const SizedBox(height: AppTokens.gap),
                const StepCard(
                  number: 1,
                  text:
                      'We check your health profile, physical limitations, and safety limits.',
                ),
                const SizedBox(height: AppTokens.gap),
                const StepCard(
                  number: 2,
                  text:
                      'We match it against available treatment plans and score how suitable each one is.',
                ),
                const SizedBox(height: AppTokens.gap),
                const StepCard(
                  number: 3,
                  text:
                      'You get the top 3 suggestions to review, customise, and choose from.',
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
