import 'package:flutter/material.dart';

import 'package:physical_treatment_and_health_support_system/core/themes/design_tokens.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/food_item.dart';
import 'package:physical_treatment_and_health_support_system/view/diet_view/widgets/diet_widgets.dart';
import 'package:physical_treatment_and_health_support_system/view/common/tidy_text.dart';

/// Search the food catalogue by name, in Malay or English, and pick one (UC800 A2 step 2, A3;
/// FR700_006, FR700_050). [suggested] are shown first (the recogniser's other likely foods);
/// [suggestedLater] fills them in when they arrive, so the sheet opens without waiting.
class FoodSearchSheet extends StatefulWidget {
  final Future<List<FoodItem>> Function(String term) search;
  final List<FoodItem> suggested;
  final Future<List<FoodItem>>? suggestedLater;
  final String title;
  const FoodSearchSheet({
    super.key,
    required this.search,
    this.suggested = const [],
    this.suggestedLater,
    this.title = 'Choose the food',
  });

  static Future<FoodItem?> show(
    BuildContext context, {
    required Future<List<FoodItem>> Function(String) search,
    List<FoodItem> suggested = const [],
    Future<List<FoodItem>>? suggestedLater,
    String title = 'Choose the food',
  }) => showModalBottomSheet<FoodItem>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppTokens.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => FractionallySizedBox(
      heightFactor: 0.9,
      child: FoodSearchSheet(search: search, suggested: suggested, suggestedLater: suggestedLater, title: title),
    ),
  );

  @override
  State<FoodSearchSheet> createState() => _FoodSearchSheetState();
}

class _FoodSearchSheetState extends State<FoodSearchSheet> {
  List<FoodItem> _results = const [];
  late List<FoodItem> _suggested = widget.suggested;
  String _term = '';
  bool _searching = true;

  @override
  void initState() {
    super.initState();
    _run('');
    widget.suggestedLater?.then((s) {
      if (mounted) setState(() => _suggested = [..._suggested, ...s]);
    });
  }

  /// A new search term: shows the progress bar, then the results.
  void _onTerm(String t) {
    setState(() => _searching = true);
    _run(t);
  }

  Future<void> _run(String t) async {
    _term = t;
    final r = await widget.search(t);
    if (mounted && t == _term) {
      setState(() {
        _results = r;
        _searching = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.viewInsetsOf(context).bottom),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OneLineText(widget.title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppTokens.ink)),
        const SizedBox(height: 12),
        TextField(
          autofocus: widget.suggested.isEmpty && widget.suggestedLater == null,
          onChanged: _onTerm,
          style: const TextStyle(fontSize: 18),
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search),
            hintText: 'e.g. nasi lemak, roti canai, teh tarik',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppTokens.radiusField)),
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: 4,
          child: _searching ? const LinearProgressIndicator(color: AppTokens.brandDeepAccent) : null,
        ),
        const SizedBox(height: 4),
        Expanded(
          child: ListView(
            children: [
              if (_term.isEmpty && _suggested.isNotEmpty) ...[
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 6),
                  child: OneLineText('Did you mean', style: TextStyle(fontSize: 15, color: AppTokens.inkMuted)),
                ),
                for (final f in _suggested) FoodTile(food: f, onTap: () => Navigator.pop(context, f)),
                const Divider(),
              ],
              for (final f in _results) FoodTile(food: f, onTap: () => Navigator.pop(context, f)),
              if (_results.isEmpty && !_searching)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No food found. Try another\u00A0name.', style: TextStyle(fontSize: 16, color: AppTokens.inkMuted)),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}
