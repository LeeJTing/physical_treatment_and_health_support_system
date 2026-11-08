import 'package:flutter/material.dart';

import 'package:physical_treatment_and_health_support_system/core/themes/design_tokens.dart';
import 'package:physical_treatment_and_health_support_system/core/utils/body_regions.dart';
import 'package:physical_treatment_and_health_support_system/view/planning_view/widgets/body_map.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/rehab_info.dart';
import 'package:physical_treatment_and_health_support_system/view/common/choice_card.dart';
import 'package:physical_treatment_and_health_support_system/view/common/rehab_labels.dart';
import 'package:physical_treatment_and_health_support_system/view/planning_view/widgets/planning_widgets.dart';

/// The answers so far. Kept by the caller, so a sheet closed by mistake (a swipe down at its top
/// closes it) opens again with them (emulator, 24 Oct: four answers were lost that way).
class RehabDraft {
  Set<String> regions = {};
  String? listArea;
  RecoveryStage? stage;
  MobilityLevel? mobility;
  String? goal;
  String? pace;
}

/// Asks the four FR500_03 questions, and an optional pace, before recommending. Returns null when
/// the patient closes the sheet; the answers stay in [draft]. There is no Figma screen for this
/// step, so it reuses the planning screens' tokens.
Future<RehabInfo?> showRehabQuestionnaire(
  BuildContext context, {
  RehabDraft? draft,
}) => showModalBottomSheet<RehabInfo>(
  context: context,
  isScrollControlled: true,
  backgroundColor: AppTokens.background,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
  ),
  builder: (_) => RehabQuestionnaireSheet(draft: draft),
);

class RehabQuestionnaireSheet extends StatefulWidget {
  /// Where the answers are kept; a new one when not given.
  final RehabDraft? draft;

  const RehabQuestionnaireSheet({super.key, this.draft});

  @override
  State<RehabQuestionnaireSheet> createState() =>
      _RehabQuestionnaireSheetState();
}

class _RehabQuestionnaireSheetState extends State<RehabQuestionnaireSheet> {
  late final RehabDraft _d = widget.draft ?? RehabDraft();

  /// Regions tapped on the body map (ids of both views).
  Set<String> get _regions => _d.regions;
  set _regions(Set<String> v) => _d.regions = v;

  /// Area chosen from the fallback list instead of the map.
  String? get _listArea => _d.listArea;
  set _listArea(String? v) => _d.listArea = v;

  /// The one affected body area sent to /recommend (FR500_03).
  String? get _area =>
      _listArea ??
      BodyRegions.areaFor([for (final id in _regions) ?BodyRegions.byId[id]]);

  RecoveryStage? get _stage => _d.stage;
  set _stage(RecoveryStage? v) => _d.stage = v;
  MobilityLevel? get _mobility => _d.mobility;
  set _mobility(MobilityLevel? v) => _d.mobility = v;
  String? get _goal => _d.goal;
  set _goal(String? v) => _d.goal = v;

  /// Optional: SLOW, MEDIUM or FAST.
  String? get _pace => _d.pace;
  set _pace(String? v) => _d.pace = v;

  bool get _complete =>
      _area != null && _stage != null && _mobility != null && _goal != null;

  /// Fallback for patients who cannot find the place on the figure: the
  /// original eight body-area options.
  Future<void> _chooseFromList() async {
    final area = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Which area needs rehabilitation?'),
        children: [
          for (final e in RehabLabels.bodyArea.entries)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(e.key),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(e.value, style: const TextStyle(fontSize: 16)),
              ),
            ),
        ],
      ),
    );
    if (area != null) {
      setState(() {
        _listArea = area;
        _regions = {};
      });
    }
  }

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
            padding: const EdgeInsets.fromLTRB(
              AppTokens.gutter,
              12,
              AppTokens.gutter,
              8,
            ),
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppTokens.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'About your rehabilitation',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: AppTokens.text,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Four quick questions, and one optional, so we can match the right plans.',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppTokens.accent,
                ),
              ),
              _Question(
                title: 'Which area needs rehabilitation?',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    BodyMap(
                      selected: _regions,
                      onChanged: (s) => setState(() {
                        _regions = s;
                        _listArea = null;
                      }),
                    ),
                    if (_listArea != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          'Chosen from the list: ${RehabLabels.area(_listArea!)}',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: AppTokens.accent,
                          ),
                        ),
                      ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        style: TextButton.styleFrom(
                          foregroundColor: AppTokens.accent,
                          minimumSize: const Size(48, AppTokens.minTarget),
                          textStyle: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        onPressed: _chooseFromList,
                        child: const Text("Can't find it? Choose from a list"),
                      ),
                    ),
                  ],
                ),
              ),
              // Same reusable answer cards for every question (Elwin, 9 Oct).
              _gap,
              ChoiceCardGroup<RecoveryStage>(
                title: 'How far along is your recovery?',
                value: _stage,
                onChanged: (v) => setState(() => _stage = v),
                items: [
                  for (final e in RehabLabels.stage.entries)
                    ChoiceItem(
                      e.key,
                      e.value.$1,
                      hint: e.value.$2,
                      icon: RehabLabels.stageIcon[e.key],
                    ),
                ],
              ),
              _gap,
              ChoiceCardGroup<MobilityLevel>(
                title: 'How well can you move?',
                value: _mobility,
                onChanged: (v) => setState(() => _mobility = v),
                items: [
                  for (final e in RehabLabels.mobility.entries)
                    ChoiceItem(
                      e.key,
                      e.value.$1,
                      hint: e.value.$2,
                      icon: RehabLabels.mobilityIcon[e.key],
                    ),
                ],
              ),
              _gap,
              ChoiceCardGroup<String>(
                title: 'What is your main goal?',
                value: _goal,
                onChanged: (v) => setState(() => _goal = v),
                items: [
                  for (final e in RehabLabels.goal.entries)
                    ChoiceItem(
                      e.key,
                      e.value,
                      hint: RehabLabels.goalHint[e.key],
                      icon: RehabLabels.goalIcon[e.key],
                    ),
                ],
              ),
              _gap,
              ChoiceCardGroup<String>(
                title: 'How fast would you like to go?',
                optional: true,
                value: _pace,
                onChanged: (v) => setState(() => _pace = v),
                items: [
                  for (final e in RehabLabels.pace.entries)
                    ChoiceItem(
                      e.key,
                      e.value.$1,
                      hint: e.value.$2,
                      icon: e.value.$3,
                    ),
                ],
              ),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppTokens.gutter,
              8,
              AppTokens.gutter,
              AppTokens.gutter,
            ),
            child: TokenButton(
              label: 'Find my plans',
              color: AppTokens.primary,
              onPressed: _complete
                  ? () => Navigator.of(context).pop(
                      RehabInfo(
                        affectedBodyArea: _area!,
                        recoveryStage: _stage!,
                        mobilityLevel: _mobility!,
                        goal: _goal!,
                        pace: _pace,
                        // Only from the map: a list choice has no parts.
                        focusParts: _listArea != null
                            ? const []
                            : BodyRegions.focusParts([
                                for (final id in _regions)
                                  ?BodyRegions.byId[id],
                              ]),
                      ),
                    )
                  : null,
            ),
          ),
        ),
      ],
    ),
  );
}

const _gap = SizedBox(height: 24);

/// The body-map question: title above a custom answer area.
class _Question extends StatelessWidget {
  final String title;
  final Widget child;
  const _Question({required this.title, required this.child});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: AppTokens.text,
          ),
        ),
        const SizedBox(height: 10),
        child,
      ],
    ),
  );
}
