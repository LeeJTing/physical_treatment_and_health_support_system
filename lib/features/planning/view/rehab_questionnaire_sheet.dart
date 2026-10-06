import 'package:flutter/material.dart';

import 'package:physical_treatment_and_health_support_system/core/themes/design_tokens.dart';
import 'package:physical_treatment_and_health_support_system/data/models/enums.dart';
import 'package:physical_treatment_and_health_support_system/data/models/rehab_info.dart';
import 'package:physical_treatment_and_health_support_system/features/planning/model/rehab_labels.dart';
import 'package:physical_treatment_and_health_support_system/features/planning/widgets/planning_widgets.dart';

/// Asks the four FR500_03 questions before recommending. Returns null when
/// the patient closes the sheet. There is no Figma screen for this step, so
/// it reuses the planning screens' tokens.
Future<RehabInfo?> showRehabQuestionnaire(BuildContext context) => showModalBottomSheet<RehabInfo>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTokens.background,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => const RehabQuestionnaireSheet(),
    );

class RehabQuestionnaireSheet extends StatefulWidget {
  const RehabQuestionnaireSheet({super.key});

  @override
  State<RehabQuestionnaireSheet> createState() => _RehabQuestionnaireSheetState();
}

class _RehabQuestionnaireSheetState extends State<RehabQuestionnaireSheet> {
  String? _area;
  RecoveryStage? _stage;
  MobilityLevel? _mobility;
  String? _goal;

  bool get _complete => _area != null && _stage != null && _mobility != null && _goal != null;

  @override
  Widget build(BuildContext context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.9,
        maxChildSize: 0.95,
        builder: (context, controller) => Column(
          children: [
            Expanded(
              child: ListView(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(AppTokens.gutter, 12, AppTokens.gutter, 8),
                children: [
                  Center(
                    child: Container(
                        width: 40,
                        height: 4,
                        decoration:
                            BoxDecoration(color: AppTokens.border, borderRadius: BorderRadius.circular(2))),
                  ),
                  const SizedBox(height: 16),
                  const Text('About your rehabilitation',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: AppTokens.text)),
                  const SizedBox(height: 4),
                  const Text('Four quick questions so we can match the right plans.',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppTokens.accent)),
                  _Question(
                    title: 'Which area needs rehabilitation?',
                    options: [
                      for (final e in RehabLabels.bodyArea.entries)
                        _Option(e.value, selected: _area == e.key, onTap: () => setState(() => _area = e.key)),
                    ],
                  ),
                  _Question(
                    title: 'How far along is your recovery?',
                    options: [
                      for (final e in RehabLabels.stage.entries)
                        _Option(e.value.$1,
                            hint: e.value.$2,
                            selected: _stage == e.key,
                            onTap: () => setState(() => _stage = e.key)),
                    ],
                  ),
                  _Question(
                    title: 'How well can you move?',
                    options: [
                      for (final e in RehabLabels.mobility.entries)
                        _Option(e.value.$1,
                            hint: e.value.$2,
                            selected: _mobility == e.key,
                            onTap: () => setState(() => _mobility = e.key)),
                    ],
                  ),
                  _Question(
                    title: 'What is your main goal?',
                    options: [
                      for (final e in RehabLabels.goal.entries)
                        _Option(e.value, selected: _goal == e.key, onTap: () => setState(() => _goal = e.key)),
                    ],
                  ),
                ],
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(AppTokens.gutter, 8, AppTokens.gutter, AppTokens.gutter),
                child: TokenButton(
                  label: 'Find my plans',
                  color: AppTokens.primary,
                  onPressed: _complete
                      ? () => Navigator.of(context).pop(RehabInfo(
                            affectedBodyArea: _area!,
                            recoveryStage: _stage!,
                            mobilityLevel: _mobility!,
                            goal: _goal!,
                          ))
                      : null,
                ),
              ),
            ),
          ],
        ),
      );
}

class _Question extends StatelessWidget {
  final String title;
  final List<_Option> options;
  const _Question({required this.title, required this.options});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: AppTokens.text)),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: options),
          ],
        ),
      );
}

/// Selectable option: white with a border, dark green when chosen.
class _Option extends StatelessWidget {
  final String label;
  final String? hint;
  final bool selected;
  final VoidCallback onTap;
  const _Option(this.label, {this.hint, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => Semantics(
        selected: selected,
        button: true,
        child: Material(
          color: selected ? AppTokens.primary : AppTokens.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTokens.radiusButton),
            side: BorderSide(color: selected ? AppTokens.primary : AppTokens.border, width: 1.5),
          ),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppTokens.radiusButton),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: AppTokens.minTarget),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: selected ? Colors.white : AppTokens.text)),
                    if (hint != null)
                      Text(hint!,
                          style: TextStyle(
                              fontSize: 13, color: selected ? AppTokens.onPrimaryMuted : AppTokens.textMuted)),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}
