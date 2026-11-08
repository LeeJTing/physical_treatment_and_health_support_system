import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:physical_treatment_and_health_support_system/core/themes/design_tokens.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/meal_log.dart';
import 'package:physical_treatment_and_health_support_system/view/diet_view/widgets/diet_widgets.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/meal_log_view_model/meal_log_view_model.dart';

/// The photo of a logged meal (FR700_009). It is downloaded from the private store the first time
/// it is shown, with a soft placeholder meanwhile; a meal entered without a photo shows a plate.
class MealPhoto extends StatefulWidget {
  final MealLogViewModel vm;
  final MealLog meal;
  final double size;
  final double? height;
  const MealPhoto({super.key, required this.vm, required this.meal, this.size = 64, this.height});

  @override
  State<MealPhoto> createState() => _MealPhotoState();
}

class _MealPhotoState extends State<MealPhoto> {
  @override
  void initState() {
    super.initState();
    widget.vm.fetchPhoto(widget.meal);
  }

  @override
  void didUpdateWidget(MealPhoto old) {
    super.didUpdateWidget(old);
    if (old.meal.mealId != widget.meal.mealId || old.meal.imageUri != widget.meal.imageUri) {
      widget.vm.fetchPhoto(widget.meal);
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.size;
    final h = widget.height ?? widget.size;
    final Uint8List? bytes = widget.vm.photoOf(widget.meal);
    final radius = BorderRadius.circular(w >= 120 ? 20 : 14);
    if (bytes != null) {
      return ClipRRect(
        borderRadius: radius,
        child: Image.memory(
          bytes,
          width: w,
          height: h,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          semanticLabel: 'Photo of this meal',
        ),
      );
    }
    final waiting = widget.vm.hasPhoto(widget.meal);
    return Container(
      width: w,
      height: h,
      decoration: BoxDecoration(color: AppTokens.tint, borderRadius: radius),
      alignment: Alignment.center,
      child: waiting
          ? SizedBox(
              width: w >= 120 ? 32 : 20,
              height: w >= 120 ? 32 : 20,
              child: const CircularProgressIndicator(strokeWidth: 2.5, color: AppTokens.brandDeepAccent),
            )
          : Icon(Icons.restaurant, size: w * 0.45, color: AppTokens.brandDeepAccent),
    );
  }
}

/// A logged meal in full: its photo, each food with its portion and verdict, and the meal's
/// nutrients (UC800 A5, FR700_014).
class MealDetailsSheet {
  static Future<void> show(BuildContext context, MealLogViewModel vm, MealLog meal) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: AppTokens.surface,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        builder: (ctx) => ListenableBuilder(
          listenable: vm,
          builder: (ctx, _) {
            final t = meal.consumedAt;
            return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.85,
              maxChildSize: 0.95,
              builder: (ctx, scroll) => ListView(
                controller: scroll,
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(color: AppTokens.cardBorder, borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '${meal.mealType.label} · ${t.day}/${t.month}/${t.year} '
                    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}',
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppTokens.ink),
                  ),
                  const SizedBox(height: 12),
                  if (vm.hasPhoto(meal))
                    LayoutBuilder(
                      builder: (ctx, c) => MealPhoto(vm: vm, meal: meal, size: c.maxWidth, height: 240),
                    )
                  else
                    const Text(
                      'This meal was entered without a photo.',
                      style: TextStyle(fontSize: 15, color: AppTokens.inkMuted),
                    ),
                  const SizedBox(height: 16),
                  for (final i in meal.items)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(i.food.foodName,
                                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: AppTokens.ink)),
                                Text('${i.portionSizeG.round()} g · ${fmtNum(i.energyKcal)} kcal',
                                    style: const TextStyle(fontSize: 14, color: AppTokens.inkMuted)),
                                for (final v in i.verdicts.where((v) => v.verdict != Verdict.suitable))
                                  Text(v.reasonText, style: const TextStyle(fontSize: 14, color: AppTokens.ink)),
                              ],
                            ),
                          ),
                          VerdictChip(i.worstVerdict()),
                        ],
                      ),
                    ),
                  const Divider(),
                  const Text('This meal', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  NutrientTable(meal.totals),
                  const DietDisclaimer(),
                ],
              ),
            );
          },
        ),
      );
}
