import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:physical_treatment_and_health_support_system/core/themes/design_tokens.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/health_profile.dart';

class SectionTitle extends StatelessWidget {
  final String text;
  const SectionTitle(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      color: AppTokens.ink,
      fontSize: 18,
      fontWeight: FontWeight.w700,
    ),
  );
}

/// White card with the initials, name, email and risk pill, overlapping the header band.
class IdentityCard extends StatelessWidget {
  final String username;
  final String email;
  final RiskLevel? risk;
  const IdentityCard({
    super.key,
    required this.username,
    required this.email,
    this.risk,
  });

  static String initials(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'[\s._-]+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      return parts.first
          .substring(0, parts.first.length.clamp(1, 2))
          .toUpperCase();
    }
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: AppTokens.surface,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: AppTokens.cardBorder),
    ),
    child: Row(
      children: [
        Container(
          width: 64,
          height: 64,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: AppTokens.tint,
            shape: BoxShape.circle,
          ),
          child: Text(
            initials(username),
            style: const TextStyle(
              color: AppTokens.brandDeep,
              fontSize: 24,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                username,
                style: const TextStyle(
                  color: AppTokens.ink,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                email,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppTokens.inkMuted, fontSize: 15),
              ),
              if (risk != null) ...[
                const SizedBox(height: 8),
                StatusPill(
                  'Risk level: ${risk!.db}',
                  good: risk == RiskLevel.low,
                ),
              ],
            ],
          ),
        ),
      ],
    ),
  );
}

/// Small rounded label: warning colours, or green when [good].
class StatusPill extends StatelessWidget {
  final String text;
  final bool good;
  const StatusPill(this.text, {super.key, this.good = false});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
    decoration: BoxDecoration(
      color: good ? AppTokens.successContainer : AppTokens.warnContainer,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      text,
      style: TextStyle(
        color: good ? AppTokens.good : AppTokens.onWarn,
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
    ),
  );
}

/// Age, gender, weight and height in a 2x2 grid, then BMI (FR100_046).
class StatsCard extends StatelessWidget {
  final HealthProfile? profile;
  const StatsCard({super.key, required this.profile});

  @override
  Widget build(BuildContext context) {
    final p = profile;
    String fmt(num? v, String unit) => v == null
        ? '-'
        : '${v % 1 == 0 ? v.toInt() : v.toStringAsFixed(1)} $unit';
    Widget cell(String label, String value) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: AppTokens.inkMuted, fontSize: 15),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            color: AppTokens.ink,
            fontSize: 22,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
      decoration: BoxDecoration(
        color: AppTokens.tint,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: cell('Age', fmt(p?.age, 'yrs'))),
              Expanded(child: cell('Gender', p?.gender?.db ?? '-')),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: cell('Weight', fmt(p?.weightKg, 'kg'))),
              Expanded(child: cell('Height', fmt(p?.heightCm, 'cm'))),
            ],
          ),
          if (p != null && p.calculateBmi() > 0) ...[
            const Divider(height: 24, color: AppTokens.cardBorder),
            BmiRow(bmi: p.calculateBmi()),
          ],
        ],
      ),
    );
  }
}

class BmiRow extends StatelessWidget {
  final double bmi;
  const BmiRow({super.key, required this.bmi});

  static String category(double bmi) => bmi < 18.5
      ? 'Underweight'
      : bmi < 25
      ? 'Normal'
      : bmi < 30
      ? 'Overweight'
      : 'Obese';

  @override
  Widget build(BuildContext context) {
    final c = category(bmi);
    return Row(
      children: [
        const Expanded(
          child: Text(
            'Body mass index',
            style: TextStyle(color: AppTokens.inkMuted, fontSize: 15),
          ),
        ),
        Text(
          bmi.toStringAsFixed(1),
          style: const TextStyle(
            color: AppTokens.ink,
            fontSize: 20,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(width: 12),
        StatusPill(c, good: c == 'Normal'),
      ],
    );
  }
}

/// Selectable condition / limitation chip. Tappable only when [onTap] is given (edit mode).
class ProfileChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final bool compact;
  const ProfileChip({
    super.key,
    required this.label,
    required this.selected,
    this.onTap,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final text = Text(
      label,
      textAlign: TextAlign.center,
      maxLines: compact ? 1 : null,
      softWrap: !compact,
      style: TextStyle(
        color: selected ? Colors.white : AppTokens.inkMuted,
        fontSize: compact ? 15 : 16,
        fontWeight: FontWeight.w500,
      ),
    );
    return Semantics(
      button: onTap != null,
      selected: selected,
      child: Material(
        color: selected ? AppTokens.brandDeep : AppTokens.surface,
        shape: StadiumBorder(
          side: BorderSide(
            color: selected ? AppTokens.brandDeep : AppTokens.outline,
            width: 1.5,
          ),
        ),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 8 : 18,
                vertical: 10,
              ),
              // Compact chips share half a row (Gender beside Age): a word that does not fit is
              // shrunk a little rather than broken ("Femal / e" on narrow phones).
              child: compact
                  ? Center(
                      widthFactor: 1,
                      child: FittedBox(fit: BoxFit.scaleDown, child: text),
                    )
                  : text,
            ),
          ),
        ),
      ),
    );
  }
}

enum BannerTone { warn, info }

/// Advisory banner (FR100_058) or an inline message.
class InfoBanner extends StatelessWidget {
  final String text;
  final IconData icon;
  final BannerTone tone;
  const InfoBanner(
    this.text, {
    super.key,
    this.icon = Icons.warning_amber_outlined,
    this.tone = BannerTone.warn,
  });

  @override
  Widget build(BuildContext context) {
    final warn = tone == BannerTone.warn;
    final fg = warn ? AppTokens.onWarn : AppTokens.brandDeep;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: warn ? AppTokens.warnContainer : AppTokens.tint,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: fg, size: 28),
          const SizedBox(width: 14),
          Expanded(
            child: Text(text, style: TextStyle(color: fg, fontSize: 16)),
          ),
        ],
      ),
    );
  }
}

/// "Change password", "Device connection", "Log out" rows.
class SettingsCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget? trailing;
  final bool danger;
  final VoidCallback onTap;
  const SettingsCard({
    super.key,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.danger = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Material(
    color: AppTokens.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: const BorderSide(color: AppTokens.cardBorder),
    ),
    child: InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 16, 14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: danger ? AppTokens.cta : AppTokens.ink,
                      fontSize: 19,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: AppTokens.inkMuted,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ),
            trailing ??
                const Icon(
                  Icons.chevron_right,
                  color: AppTokens.inkMuted,
                  size: 28,
                ),
          ],
        ),
      ),
    ),
  );
}

/// Numeric field for the edit mode of the stats card.
class NumberField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String? Function(String?) validator;
  final List<TextInputFormatter> formatters;
  final ValueChanged<String> onChanged;
  final bool forceError;
  const NumberField({
    super.key,
    required this.label,
    required this.controller,
    required this.validator,
    required this.formatters,
    required this.onChanged,
    this.forceError = false,
  });

  static OutlineInputBorder _b(Color c, [double w = 1.5]) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(AppTokens.radiusField),
    borderSide: BorderSide(color: c, width: w),
  );

  @override
  Widget build(BuildContext context) {
    // Marked by Save although its own range is fine (weight and height that do not match,
    // an age that does not fit the Terms): outlined, and the banner says why (audit, 23 Oct).
    final marked = forceError && validator(controller.text) == null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: AppTokens.inkMuted, fontSize: 15),
        ),
        const SizedBox(height: 6),
        Semantics(
          identifier: 'profile-${label.toLowerCase().split(' ').first}',
          child: TextFormField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: formatters,
            onChanged: onChanged,
            validator: validator,
            // After a failed Save, show the errors even on untouched fields.
            autovalidateMode: forceError
                ? AutovalidateMode.always
                : AutovalidateMode.onUserInteraction,
            style: const TextStyle(
              color: AppTokens.ink,
              fontSize: 20,
              fontWeight: FontWeight.w500,
            ),
            cursorColor: AppTokens.brandDeep,
            decoration: InputDecoration(
              filled: true,
              fillColor: AppTokens.surface,
              isDense: true,
              // The whole message, even in the narrow age box (29 Oct, emulator: "...outside the ac..."
              // was cut at three lines).
              errorMaxLines: 8,
              errorStyle: const TextStyle(color: AppTokens.cta, fontSize: 13),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 14,
              ),
              enabledBorder: marked ? _b(AppTokens.cta) : _b(AppTokens.outline),
              focusedBorder: marked
                  ? _b(AppTokens.cta, 2)
                  : _b(AppTokens.brandDeep, 2),
              errorBorder: _b(AppTokens.cta),
              focusedErrorBorder: _b(AppTokens.cta, 2),
            ),
          ),
        ),
      ],
    );
  }
}
