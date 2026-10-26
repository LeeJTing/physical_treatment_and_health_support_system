import 'package:flutter/material.dart';

import 'package:physical_treatment_and_health_support_system/core/themes/design_tokens.dart';

/// One answer of a single-choice question: [value] with its wording.
class ChoiceItem<T> {
  final T value;
  final String title;
  final String? hint;
  final IconData? icon;

  const ChoiceItem(this.value, this.title, {this.hint, this.icon});
}

/// Full-width answer card: icon, title, one-line hint, and a tick when
/// chosen. Chosen is shown by the tick and a thicker border as well as the
/// fill, so colour is not the only cue. At least 48 px tall for older users.
class ChoiceCard extends StatelessWidget {
  final String title;
  final String? hint;
  final IconData? icon;
  final bool selected;
  final VoidCallback onTap;

  const ChoiceCard({
    super.key,
    required this.title,
    this.hint,
    this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppTokens.radiusCard);
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? AppTokens.accentContainer : AppTokens.surface,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(
            color: selected ? AppTokens.primary : AppTokens.border,
            width: selected ? 2 : 1.5,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  if (icon != null) ...[
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: selected
                            ? AppTokens.surface
                            : AppTokens.accentContainer,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(icon, size: 22, color: AppTokens.primary),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: AppTokens.text,
                          ),
                        ),
                        if (hint != null)
                          Text(
                            hint!,
                            style: const TextStyle(
                              fontSize: 14,
                              color: AppTokens.textMuted,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  ExcludeSemantics(
                    child: Icon(
                      selected
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      size: 24,
                      color: selected ? AppTokens.primary : AppTokens.border,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A single-choice question answered with [ChoiceCard]s, one per row.
/// [optional] adds '(optional)' to the title; tapping the chosen card again
/// then clears the answer.
class ChoiceCardGroup<T> extends StatelessWidget {
  final String title;
  final List<ChoiceItem<T>> items;
  final T? value;
  final ValueChanged<T?> onChanged;
  final bool optional;

  const ChoiceCardGroup({
    super.key,
    required this.title,
    required this.items,
    required this.value,
    required this.onChanged,
    this.optional = false,
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text.rich(
        TextSpan(
          text: title,
          children: [
            if (optional)
              const TextSpan(
                text: '  (optional)',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppTokens.textMuted,
                ),
              ),
          ],
        ),
        style: const TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: AppTokens.text,
        ),
      ),
      const SizedBox(height: 10),
      for (final (i, item) in items.indexed) ...[
        if (i > 0) const SizedBox(height: 8),
        ChoiceCard(
          title: item.title,
          hint: item.hint,
          icon: item.icon,
          selected: value == item.value,
          onTap: () =>
              onChanged(optional && value == item.value ? null : item.value),
        ),
      ],
    ],
  );
}
