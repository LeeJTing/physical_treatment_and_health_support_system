import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:physical_treatment_and_health_support_system/core/themes/design_tokens.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/diet_food_guidance.dart';

/// Same content is used in Diet review, Health insights and the weekly PDF.
class DietFoodGuidanceBody extends StatelessWidget {
  final DietFoodGuidance guidance;
  final DateTime? selectedDay;
  const DietFoodGuidanceBody(this.guidance, {super.key, this.selectedDay});

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Food choices for your next meals',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppTokens.ink,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          guidance.basis,
          style: const TextStyle(color: AppTokens.inkMuted, height: 1.4),
        ),
        const SizedBox(height: 16),
        const Text(
          'Weekly priorities',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppTokens.brandDeep,
          ),
        ),
        if (guidance.priorities.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'No supported food change identified for the recorded week. Check each day’s coverage below.',
            ),
          ),
        for (final p in guidance.priorities)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(p.detail, style: const TextStyle(height: 1.4)),
                Text(
                  'Evidence: ${p.dates.map((d) => DateFormat('d MMM').format(d)).join(', ')}',
                  style: const TextStyle(
                    color: AppTokens.inkMuted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 16),
        const Text(
          'Daily food review',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppTokens.brandDeep,
          ),
        ),
        for (final d in guidance.days.where(
          (d) =>
              selectedDay == null || DateUtils.isSameDay(d.date, selectedDay),
        ))
          ExpansionTile(
            key: PageStorageKey('food-guidance-${d.date.toIso8601String()}'),
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(bottom: 12),
            title: Text(
              DateFormat('EEE, d MMM').format(d.date),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text('${d.actions.length} food options to review'),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text(d.conclusion, style: const TextStyle(height: 1.4)),
              ),
              for (final a in d.actions)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(top: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: a.kind == FoodGuidanceKind.replace
                        ? AppTokens.dangerContainer
                        : AppTokens.tint,
                    borderRadius: BorderRadius.circular(AppTokens.radiusField),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        a.label,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: a.kind == FoodGuidanceKind.replace
                              ? AppTokens.onDanger
                              : AppTokens.brandDeep,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        a.portion,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(a.reason, style: const TextStyle(height: 1.4)),
                    ],
                  ),
                ),
            ],
          ),
      ],
    ),
  );
}
