import 'package:flutter/material.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/meal_log.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/meal_log_view_model/meal_log_view_model.dart';

class MealQuantityDialog extends StatefulWidget {
  final MealItem item;
  final MealLogViewModel vm;
  const MealQuantityDialog({super.key, required this.item, required this.vm});
  static Future<void> show(
    BuildContext context,
    MealLogViewModel vm,
    MealItem item,
  ) => showDialog<void>(
    context: context,
    builder: (_) => MealQuantityDialog(item: item, vm: vm),
  );
  @override
  State<MealQuantityDialog> createState() => _MealQuantityDialogState();
}

class _MealQuantityDialogState extends State<MealQuantityDialog> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _count, _grams;
  String? _error;
  @override
  void initState() {
    super.initState();
    _count = TextEditingController(
      text: widget.item.recognitionDetails?.count?.toString() ?? '',
    );
    _grams = TextEditingController(
      text: widget.item.portionSizeG.toStringAsFixed(0),
    );
  }

  @override
  void dispose() {
    _count.dispose();
    _grams.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Review food quantity'),
    content: SingleChildScrollView(
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.item.food.foodName),
            const SizedBox(height: 10),
            const Text(
              'Photo quantities are estimates. Check the count and total edible weight.',
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _count,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: widget.item.recognitionDetails?.unit == 'serving'
                    ? 'Servings (optional)'
                    : 'Whole items / pieces (optional)',
                helperText: 'Leave blank if the count is unknown.',
              ),
              validator: (s) => s!.trim().isEmpty
                  ? null
                  : int.tryParse(s) != null &&
                        int.parse(s) >= 1 &&
                        int.parse(s) <= 100
                  ? null
                  : 'Enter a whole number from 1 to 100.',
              onChanged: (s) {
                final n = int.tryParse(s);
                final previous = widget.item.recognitionDetails?.count;
                if (n != null && n > 0 && previous != null && previous > 0) {
                  _grams.text = (widget.item.portionSizeG / previous * n)
                      .toStringAsFixed(0);
                }
              },
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _grams,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Total edible weight (g)',
                helperText: 'Total for all pieces, not weight per piece.',
              ),
              validator: (value) => MealLogViewModel.checkPortion(value ?? ''),
            ),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (!_form.currentState!.validate()) return;
          final e = widget.vm.confirmQuantity(
            widget.item,
            int.tryParse(_count.text.trim()),
            double.parse(_grams.text.trim().replaceAll(',', '.')),
          );
          if (e == null) {
            Navigator.pop(context);
          } else {
            setState(() => _error = e);
          }
        },
        child: const Text('Confirm quantity'),
      ),
    ],
  );
}
