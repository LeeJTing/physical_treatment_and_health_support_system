import 'package:flutter/material.dart';

import 'package:physical_treatment_and_health_support_system/core/themes/design_tokens.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/food_item.dart';
import 'package:physical_treatment_and_health_support_system/view/diet_view/widgets/diet_widgets.dart';

/// Search the food catalogue by name, in Malay or English, and pick one (UC800 A2 step 2, A3;
/// FR700_006, FR700_050). [suggested] are shown first (the recogniser's other likely foods).
class FoodSearchSheet extends StatefulWidget {
  final Future<List<FoodItem>> Function(String term) search;
  final List<FoodItem> suggested;
  final String title;
  const FoodSearchSheet({super.key, required this.search, this.suggested = const [], this.title = 'Choose the food'});

  static Future<FoodItem?> show(
    BuildContext context, {
    required Future<List<FoodItem>> Function(String) search,
    List<FoodItem> suggested = const [],
    String title = 'Choose the food',
  }) => showModalBottomSheet<FoodItem>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppTokens.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => FractionallySizedBox(
      heightFactor: 0.9,
      child: FoodSearchSheet(search: search, suggested: suggested, title: title),
    ),
  );

  @override
  State<FoodSearchSheet> createState() => _FoodSearchSheetState();
}

class _FoodSearchSheetState extends State<FoodSearchSheet> {
  List<FoodItem> _results = const [];
  String _term = '';

  @override
  void initState() {
    super.initState();
    _run('');
  }

  Future<void> _run(String t) async {
    _term = t;
    final r = await widget.search(t);
    if (mounted && t == _term) setState(() => _results = r);
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.viewInsetsOf(context).bottom),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppTokens.ink)),
        const SizedBox(height: 12),
        TextField(
          autofocus: widget.suggested.isEmpty,
          onChanged: _run,
          style: const TextStyle(fontSize: 18),
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search),
            hintText: 'e.g. nasi lemak, roti canai, teh tarik',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppTokens.radiusField)),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ListView(
            children: [
              if (_term.isEmpty && widget.suggested.isNotEmpty) ...[
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 6),
                  child: Text('Did you mean', style: TextStyle(fontSize: 15, color: AppTokens.inkMuted)),
                ),
                for (final f in widget.suggested) FoodTile(food: f, onTap: () => Navigator.pop(context, f)),
                const Divider(),
              ],
              for (final f in _results) FoodTile(food: f, onTap: () => Navigator.pop(context, f)),
              if (_results.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No food found. Try another name.', style: TextStyle(fontSize: 16, color: AppTokens.inkMuted)),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}
