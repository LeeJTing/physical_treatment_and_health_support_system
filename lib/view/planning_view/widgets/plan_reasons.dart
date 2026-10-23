import 'package:flutter/material.dart';

import 'package:physical_treatment_and_health_support_system/core/constants/evidence_sources.dart';
import 'package:physical_treatment_and_health_support_system/core/themes/design_tokens.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/recommendation_service/recommendation.dart';

/// The reasons for one plan ("Why this plan" / "Why not"), each with the
/// sources behind its rule or "App safety rule" (11 Oct); a reason that only
/// describes the match has no label (24 Oct).
class ReasonList extends StatelessWidget {
  final List<PlanReason> reasons;

  /// Ticks for "why this plan", crosses for "why not".
  final bool positive;

  const ReasonList(this.reasons, {super.key, this.positive = true});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final r in reasons)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                positive ? Icons.check_circle_outline : Icons.remove_circle_outline,
                size: 18,
                color: positive ? AppTokens.accent : AppTokens.caution,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.text,
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.35,
                        color: AppTokens.textBody,
                      ),
                    ),
                    if (r.sources.isNotEmpty || !r.describesMatch) ...[
                      const SizedBox(height: 2),
                      InkWell(
                        onTap: r.sources.isEmpty
                            ? null
                            : () => showSources(context, r.sources),
                        child: Text(
                          r.sources.isEmpty
                              ? EvidenceSources.appRuleLabel
                              : 'Source: ${EvidenceSources.cite(r.sources)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppTokens.textMuted,
                            decoration: r.sources.isEmpty
                                ? null
                                : TextDecoration.underline,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
    ],
  );
}

Widget _sheet(BuildContext context, String title, List<Widget> children) =>
    DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (context, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(
          AppTokens.gutter,
          12,
          AppTokens.gutter,
          24,
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
          Text(
            title,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: AppTokens.text,
            ),
          ),
          ...children,
        ],
      ),
    );

Future<void> _show(BuildContext context, Widget Function(BuildContext) b) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTokens.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: b,
    );

/// The full references for [keys], with what each is used for.
Future<void> showSources(BuildContext context, List<String> keys) => _show(
  context,
  (ctx) => _sheet(ctx, 'Sources', [
    const SizedBox(height: 4),
    const Text(
      'The papers and guidelines behind this rule.',
      style: TextStyle(fontSize: 14, color: AppTokens.textMuted),
    ),
    for (final k in keys)
      if (EvidenceSources.all[k] case final s?)
        Padding(
          padding: const EdgeInsets.only(top: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                s.short,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppTokens.text,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                s.usedFor,
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.35,
                  color: AppTokens.textBody,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                s.reference,
                style: const TextStyle(
                  fontSize: 12,
                  height: 1.35,
                  color: AppTokens.textMuted,
                ),
              ),
            ],
          ),
        ),
  ]),
);

/// "Why not other plans": every plan the recommender left out, with its reasons.
Future<void> showWhyNot(BuildContext context, List<ExcludedPlan> excluded) =>
    _show(
      context,
      (ctx) => _sheet(ctx, 'Why not other plans', [
        const SizedBox(height: 4),
        const Text(
          'These plans were left out for you. Rules backed by guidelines show '
          'their source; the others are this app\'s own safety rules.',
          style: TextStyle(fontSize: 14, height: 1.35, color: AppTokens.textMuted),
        ),
        for (final e in excluded)
          Container(
            margin: const EdgeInsets.only(top: AppTokens.gap),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTokens.surface,
              borderRadius: BorderRadius.circular(AppTokens.radiusCard),
              border: Border.all(color: AppTokens.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  e.plan.planName,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppTokens.text,
                  ),
                ),
                ReasonList(e.why, positive: false),
              ],
            ),
          ),
      ]),
    );
