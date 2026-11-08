import 'package:flutter/material.dart';

import 'package:physical_treatment_and_health_support_system/core/themes/design_tokens.dart';
import 'package:physical_treatment_and_health_support_system/view/common/tidy_text.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/diet_planner_service/plan_change.dart';
import 'package:physical_treatment_and_health_support_system/view/diet_view/widgets/diet_widgets.dart';
import 'package:physical_treatment_and_health_support_system/view/diet_view/widgets/food_picture.dart';

/// One planned amount against its limit, as a bar: green under 80 %, amber from 80 % to 100 %,
/// red above (the same bands as the suitability verdicts).
class PlanBar extends StatelessWidget {
  final String label;
  final double value;
  final double limit;
  final String unit;
  final int decimals;

  /// For energy the target is to be reached, not avoided: the bar stays green up to 100 %.
  final bool isTarget;
  const PlanBar({
    super.key,
    required this.label,
    required this.value,
    required this.limit,
    required this.unit,
    this.decimals = 0,
    this.isTarget = false,
  });

  @override
  Widget build(BuildContext context) {
    final r = limit <= 0 ? 0.0 : value / limit;
    final colour = r > 1.0
        ? AppTokens.danger
        : (!isTarget && r >= 0.8)
        ? AppTokens.caution
        : AppTokens.good;
    String f(double x) => decimals == 0 ? fmtNum(x) : x.toStringAsFixed(decimals);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: OneLineText(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTokens.ink)),
              ),
              const SizedBox(width: 8),
              Flexible(
                flex: 2,
                child: OneLineText(
                  '${f(value)} of ${f(limit)} $unit',
                  alignment: Alignment.centerRight,
                  style: TextStyle(fontSize: 14, color: r > 1.0 ? AppTokens.onDanger : AppTokens.inkMuted),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: r.clamp(0.0, 1.0),
              minHeight: 10,
              color: colour,
              backgroundColor: AppTokens.tint,
            ),
          ),
        ],
      ),
    );
  }
}

/// The picture for a reason of the plan's explanation.
IconData reasonIcon(String kind) => switch (kind) {
  'energy' => Icons.local_fire_department,
  'plate' => Icons.pie_chart,
  'limits' => Icons.verified_user,
  'profile' => Icons.favorite,
  'preference' => Icons.thumb_up,
  'needs' => Icons.fitness_center,
  'lock' => Icons.lock,
  _ => Icons.info,
};

class PlanReasonTile extends StatelessWidget {
  final PlanReason reason;
  const PlanReasonTile(this.reason, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: reason.ok ? AppTokens.successContainer : AppTokens.dangerContainer,
            shape: BoxShape.circle,
          ),
          child: Icon(
            reason.ok ? reasonIcon(reason.kind) : Icons.warning_amber_rounded,
            size: 20,
            color: reason.ok ? AppTokens.good : AppTokens.danger,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tidy(reason.title),
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: reason.ok ? AppTokens.ink : AppTokens.danger,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                tidy(reason.text),
                style: TextStyle(
                  fontSize: 14,
                  height: 1.35,
                  color: reason.ok ? AppTokens.inkMuted : AppTokens.onDanger,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

/// The lines of an effect or an explanation, each with a bullet. Lines that warn of too much, too
/// little or something not good for the body are gathered in a red "Watch out" box under the others,
/// so they cannot be missed.
class EffectList extends StatelessWidget {
  final List<PlanNote> lines;
  final IconData bullet;
  const EffectList(this.lines, {super.key, this.bullet = Icons.arrow_right_alt});

  @override
  Widget build(BuildContext context) {
    final info = lines.where((l) => !l.warn).toList();
    final warn = lines.where((l) => l.warn).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final l in info)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 3, right: 8),
                  child: Icon(bullet, size: 18, color: AppTokens.brandDeepAccent),
                ),
                Expanded(child: Text(tidy(l.text), style: const TextStyle(fontSize: 15, height: 1.35, color: AppTokens.ink))),
              ],
            ),
          ),
        if (warn.isNotEmpty) WatchOutBox(warn),
      ],
    );
  }
}

/// Warnings in red: too much, too little, or not good for the body, with what it does to the body.
class WatchOutBox extends StatelessWidget {
  final List<PlanNote> lines;
  final String title;

  /// Shown under the lines, e.g. "Plan the rest of today".
  final Widget? action;
  const WatchOutBox(this.lines, {super.key, this.title = 'Watch out', this.action});

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(top: 4, bottom: 4),
    padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
    decoration: BoxDecoration(
      color: AppTokens.dangerContainer,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppTokens.danger),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: AppTokens.danger, size: 22),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                tidy(title),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppTokens.onDanger),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        for (final l in lines)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 3, right: 8),
                  child: Icon(Icons.error, size: 16, color: AppTokens.danger),
                ),
                Expanded(
                  child: Text(
                    tidy(l.text),
                    style: const TextStyle(fontSize: 15, height: 1.35, color: AppTokens.onDanger, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        ?action,
      ],
    ),
  );
}

/// Asks the patient to confirm a change to the plan and says what will happen (A5.1 step 3). For
/// an add or a portion change, [rebuild] works the change out again for another portion, chosen
/// with half to one and a half servings. A change the safety gate rejects cannot be
/// confirmed. Returns the confirmed change, or null.
class PlanChangeDialog extends StatefulWidget {
  final PlanChange initial;
  final PlanChange? Function(double grams)? rebuild;
  final double? servingG;
  final double? startG;
  final String confirmLabel;
  final IconData icon;
  final String? role;
  final bool destructive;

  /// A portion change: confirming needs a portion other than [startG].
  final bool needsNewPortion;

  const PlanChangeDialog({
    super.key,
    required this.initial,
    this.rebuild,
    this.servingG,
    this.startG,
    required this.confirmLabel,
    required this.icon,
    this.role,
    this.destructive = false,
    this.needsNewPortion = false,
  });

  static Future<PlanChange?> show(
    BuildContext context, {
    required PlanChange change,
    PlanChange? Function(double grams)? rebuild,
    double? servingG,
    double? startG,
    required String confirmLabel,
    required IconData icon,
    String? role,
    bool destructive = false,
    bool needsNewPortion = false,
  }) => showDialog<PlanChange>(
    context: context,
    builder: (_) => PlanChangeDialog(
      initial: change,
      rebuild: rebuild,
      servingG: servingG,
      startG: startG,
      confirmLabel: confirmLabel,
      icon: icon,
      role: role,
      destructive: destructive,
      needsNewPortion: needsNewPortion,
    ),
  );

  @override
  State<PlanChangeDialog> createState() => _PlanChangeDialogState();
}

class _PlanChangeDialogState extends State<PlanChangeDialog> {
  late PlanChange _c = widget.initial;
  late double? _grams = widget.startG;

  void _portion(double g) {
    final c = widget.rebuild?.call(g);
    if (c == null) return;
    setState(() {
      _c = c;
      _grams = g;
    });
  }

  bool get _unchanged =>
      widget.needsNewPortion && _grams != null && widget.startG != null && (_grams! - widget.startG!).abs() < 1;

  @override
  Widget build(BuildContext context) {
    final serving = widget.servingG;
    final options = serving == null
        ? const <(String, double)>[]
        : [
            ('½', serving * 0.5),
            ('¾', serving * 0.75),
            ('1', serving),
            ('1¼', serving * 1.25),
            ('1½', serving * 1.5),
          ];
    return AlertDialog(
      backgroundColor: AppTokens.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      icon: widget.role != null
          ? FoodRoleAvatar(widget.role!, size: 56)
          : Icon(widget.icon, size: 36, color: widget.destructive ? AppTokens.danger : AppTokens.brandDeep),
      title: Text(tidy(_c.title), textAlign: TextAlign.center, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (options.isNotEmpty && widget.rebuild != null) ...[
              const Text('How many servings?', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppTokens.ink)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final (label, g) in options)
                    ChoiceChip(
                      label: OneLineText('$label (${g.round()} g)'),
                      selected: _grams != null && (_grams! - g).abs() < 1,
                      onSelected: (_) => _portion(g),
                    ),
                ],
              ),
              const SizedBox(height: 12),
            ],
            if (_unchanged)
              const Text(
                'Choose a portion above to see what\u00A0changes.',
                style: TextStyle(fontSize: 15, color: AppTokens.inkMuted),
              )
            else ...[
              const Text('What will happen', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppTokens.ink)),
              const SizedBox(height: 6),
              EffectList(_c.effects),
            ],
            if (!_c.allowed && !_unchanged) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: AppTokens.dangerContainer, borderRadius: BorderRadius.circular(14)),
                child: Text(
                  tidy(
                    'This cannot be done: it would go over your ${_c.problems.join(', ')}. '
                    '${widget.rebuild != null ? 'Try a smaller portion or another food.' : 'Try another food.'}',
                  ),
                  style: const TextStyle(fontSize: 15, color: AppTokens.onDanger, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ],
        ),
      ),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: widget.destructive ? AppTokens.danger : AppTokens.brandDeep,
            minimumSize: const Size(120, AppTokens.minTarget),
          ),
          onPressed: _c.allowed && !_unchanged ? () => Navigator.pop(context, _c) : null,
          child: OneLineText(widget.confirmLabel, alignment: Alignment.center),
        ),
      ],
    );
  }
}

/// Asks the patient to confirm an action that changes the whole plan and says what will happen.
Future<bool> confirmEffects(
  BuildContext context, {
  required String title,
  required IconData icon,
  required List<String> effects,
  required String confirmLabel,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTokens.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        icon: Icon(icon, size: 36, color: AppTokens.brandDeep),
        title: Text(tidy(title), textAlign: TextAlign.center, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('What will happen', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppTokens.ink)),
              const SizedBox(height: 6),
              EffectList([for (final e in effects) PlanNote(e)]),
            ],
          ),
        ),
        actionsAlignment: MainAxisAlignment.spaceBetween,
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppTokens.brandDeep,
              minimumSize: const Size(120, AppTokens.minTarget),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: OneLineText(confirmLabel, alignment: Alignment.center),
          ),
        ],
      ),
    ) ??
    false;
