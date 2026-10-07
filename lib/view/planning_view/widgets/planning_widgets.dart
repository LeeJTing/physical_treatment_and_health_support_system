import 'package:flutter/material.dart';

import 'package:physical_treatment_and_health_support_system/core/themes/design_tokens.dart';

/// Back arrow, title and teal subtitle used at the top of the planning screens.
class PlanningHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback onBack;

  const PlanningHeader({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      IconButton(
        onPressed: onBack,
        tooltip: 'Back',
        icon: const Icon(Icons.arrow_back, color: AppTokens.text),
      ),
      const SizedBox(width: 4),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                  color: AppTokens.text,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppTokens.accent,
                ),
              ),
            ],
          ),
        ),
      ),
    ],
  );
}

/// Large tappable card with an icon, title and one-line explanation.
/// [filled] gives the dark green primary card; otherwise white with a dark outline.
class ActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool filled;
  final VoidCallback onTap;

  const ActionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    final fg = filled ? Colors.white : AppTokens.text;
    final sub = filled ? AppTokens.onPrimaryMuted : AppTokens.textMuted;
    return Semantics(
      button: true,
      child: Material(
        color: filled ? AppTokens.primary : AppTokens.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusCard),
          side: filled
              ? BorderSide.none
              : const BorderSide(color: AppTokens.primary, width: 1.5),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppTokens.radiusCard),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
            child: Row(
              children: [
                Icon(icon, color: fg, size: 24),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: fg,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: sub,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// White card with a numbered mint badge, used in "How it works".
class StepCard extends StatelessWidget {
  final int number;
  final String text;

  const StepCard({super.key, required this.number, required this.text});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppTokens.surface,
      borderRadius: BorderRadius.circular(AppTokens.radiusCard),
      border: Border.all(color: AppTokens.border),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: AppTokens.accentContainer,
            shape: BoxShape.circle,
          ),
          child: Text(
            '$number',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppTokens.accent,
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 16,
              height: 1.4,
              fontWeight: FontWeight.w500,
              color: AppTokens.text,
            ),
          ),
        ),
      ],
    ),
  );
}

/// Mint pill with teal text: body area, exercise count, frequency.
class InfoChip extends StatelessWidget {
  final String label;
  const InfoChip(this.label, {super.key});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: AppTokens.accentContainer,
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      label,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: AppTokens.accent,
      ),
    ),
  );
}

/// "92% match": green at 75% and above, amber below.
class MatchPill extends StatelessWidget {
  final double score;
  const MatchPill(this.score, {super.key});

  @override
  Widget build(BuildContext context) {
    final good = score >= 0.75;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: good ? AppTokens.goodContainer : AppTokens.cautionContainer,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '${(score * 100).round()}% match',
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: good ? AppTokens.good : AppTokens.caution,
        ),
      ),
    );
  }
}

/// Coloured banner for the UC400 / UC1000 messages shown above the plans.
class NoticeBanner extends StatelessWidget {
  final String message;
  final bool warning;
  const NoticeBanner(this.message, {super.key, this.warning = false});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: warning ? AppTokens.cautionContainer : AppTokens.accentContainer,
      borderRadius: BorderRadius.circular(AppTokens.radiusCard),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          warning ? Icons.info_outline : Icons.check_circle_outline,
          size: 20,
          color: warning ? AppTokens.caution : AppTokens.accent,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            message,
            style: TextStyle(
              fontSize: 14,
              height: 1.35,
              color: warning ? AppTokens.caution : AppTokens.accent,
            ),
          ),
        ),
      ],
    ),
  );
}

/// Full-width filled button with the 48 dp minimum touch target.
class TokenButton extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback? onPressed;
  final bool busy;

  const TokenButton({
    super.key,
    required this.label,
    required this.color,
    this.onPressed,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    height: AppTokens.minTarget,
    child: FilledButton(
      onPressed: busy ? null : onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        disabledBackgroundColor: color.withValues(alpha: 0.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusButton),
        ),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
      child: busy
          ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: Colors.white,
              ),
            )
          : Text(label),
    ),
  );
}
