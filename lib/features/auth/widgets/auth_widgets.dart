import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:physical_treatment_and_health_support_system/core/themes/design_tokens.dart';

/// Dark green header band with the logo, from the Figma "Login Screen".
/// [heightFactor] is the share of the screen height (0.38 on login, shorter elsewhere).
class AuthHeader extends StatelessWidget {
  final double heightFactor;
  final bool showSubtitle;
  final Widget? leading;

  const AuthHeader({
    super.key,
    this.heightFactor = 0.38,
    this.showSubtitle = true,
    this.leading,
  });

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.sizeOf(context).height * heightFactor;
    final compact = heightFactor < 0.3;
    return Container(
      height: h,
      width: double.infinity,
      decoration: const BoxDecoration(
        color: AppTokens.brandDeep,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
      ),
      child: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            if (leading != null) Positioned(left: 4, top: 4, child: leading!),
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: compact ? 56 : 80,
                      height: compact ? 56 : 80,
                      decoration: const BoxDecoration(
                        color: AppTokens.brandDeepAccent,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.monitor_heart,
                        color: Colors.white,
                        size: compact ? 30 : 42,
                      ),
                    ),
                    SizedBox(height: compact ? 10 : 18),
                    Text(
                      'HealthGuide',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: compact ? 24 : 30,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (showSubtitle) ...[
                      const SizedBox(height: 8),
                      const Text(
                        'AI-Assisted Physical Treatment and Health Support',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppTokens.onBrandMuted,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Welcome back" heading with its grey subtitle.
class AuthTitle extends StatelessWidget {
  final String title;
  final String? subtitle;
  const AuthTitle(this.title, {super.key, this.subtitle});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: const TextStyle(
          color: AppTokens.ink,
          fontSize: 26,
          fontWeight: FontWeight.w700,
        ),
      ),
      if (subtitle != null) ...[
        const SizedBox(height: 4),
        Text(
          subtitle!,
          style: const TextStyle(color: AppTokens.inkMuted, fontSize: 15),
        ),
      ],
    ],
  );
}

/// Upper-case label above a white outlined field (Figma "EMAIL ADDRESS").
/// The error shows under the field that is wrong (FR100_028).
class LabeledField extends StatefulWidget {
  final String label;
  final TextEditingController controller;
  final String? Function(String?)? validator;
  final bool obscure;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final String? helper;
  final String? hint;
  final List<String>? autofillHints;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final int? maxLength;
  final TextStyle? style;
  final TextAlign textAlign;

  const LabeledField({
    super.key,
    required this.label,
    required this.controller,
    this.validator,
    this.obscure = false,
    this.keyboardType,
    this.textInputAction,
    this.helper,
    this.hint,
    this.autofillHints,
    this.inputFormatters,
    this.onChanged,
    this.onSubmitted,
    this.maxLength,
    this.style,
    this.textAlign = TextAlign.start,
  });

  @override
  State<LabeledField> createState() => _LabeledFieldState();
}

class _LabeledFieldState extends State<LabeledField> {
  late bool _hidden = widget.obscure;

  static OutlineInputBorder _border(Color c, [double w = 1.5]) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppTokens.radiusField),
        borderSide: BorderSide(color: c, width: w),
      );

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        widget.label.toUpperCase(),
        style: const TextStyle(
          color: AppTokens.inkMuted,
          fontSize: 13,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.8,
        ),
      ),
      const SizedBox(height: 8),
      TextFormField(
        controller: widget.controller,
        validator: widget.validator,
        obscureText: _hidden,
        keyboardType: widget.keyboardType,
        textInputAction: widget.textInputAction,
        autofillHints: widget.autofillHints,
        inputFormatters: widget.inputFormatters,
        onChanged: widget.onChanged,
        onFieldSubmitted: widget.onSubmitted,
        maxLength: widget.maxLength,
        textAlign: widget.textAlign,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        style:
            widget.style ?? const TextStyle(color: AppTokens.ink, fontSize: 17),
        cursorColor: AppTokens.brandDeep,
        // Every colour is fixed: with the phone in dark mode the theme's defaults
        // were white text on these light screens.
        decoration: InputDecoration(
          filled: true,
          fillColor: AppTokens.surface,
          hintText: widget.hint,
          hintStyle: const TextStyle(color: AppTokens.inkMuted, fontSize: 16),
          errorStyle: const TextStyle(color: AppTokens.cta, fontSize: 14),
          helperMaxLines: 3,
          errorMaxLines: 3,
          counterText: '',
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 19,
          ),
          enabledBorder: _border(AppTokens.outline),
          focusedBorder: _border(AppTokens.brandDeep, 2),
          errorBorder: _border(AppTokens.cta),
          focusedErrorBorder: _border(AppTokens.cta, 2),
          suffixIcon: widget.obscure
              ? IconButton(
                  tooltip: _hidden ? 'Show password' : 'Hide password',
                  icon: Icon(
                    _hidden
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    color: AppTokens.inkMuted,
                  ),
                  onPressed: () => setState(() => _hidden = !_hidden),
                )
              : null,
        ),
      ),
      // Below the field and lined up with the label (InputDecoration.helperText is
      // indented to the text inside the field).
      if (widget.helper != null)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            widget.helper!,
            style: const TextStyle(color: AppTokens.inkMuted, fontSize: 14),
          ),
        ),
    ],
  );
}

/// Full-width, fully rounded orange button ("Log In", "Create account").
class PillButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  const PillButton({
    super.key,
    required this.label,
    this.onPressed,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    height: 56,
    child: FilledButton(
      onPressed: busy ? null : onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: AppTokens.cta,
        // Disabled: grey with dark text, readable (white on pale orange was not).
        disabledBackgroundColor: AppTokens.cardBorder,
        foregroundColor: Colors.white,
        disabledForegroundColor: AppTokens.inkMuted,
        shape: const StadiumBorder(),
        textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
      ),
      child: busy
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: AppTokens.brandDeep, // on the grey disabled background
              ),
            )
          : Text(label),
    ),
  );
}

/// White, outlined, fully rounded button ("Continue with Google").
class OutlinedPillButton extends StatelessWidget {
  final String label;
  final Widget? icon;
  final VoidCallback? onPressed;
  final bool busy;
  const OutlinedPillButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    height: 56,
    child: OutlinedButton(
      onPressed: busy ? null : onPressed,
      style: OutlinedButton.styleFrom(
        backgroundColor: AppTokens.surface,
        foregroundColor: AppTokens.ink,
        side: const BorderSide(color: AppTokens.outline, width: 1.5),
        shape: const StadiumBorder(),
        textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
      ),
      child: busy
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: AppTokens.brandDeep,
              ),
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[icon!, const SizedBox(width: 12)],
                // Flexible so large text scaling ellipsises instead of overflowing.
                Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
              ],
            ),
    ),
  );
}

/// The multi-coloured "G" mark, drawn as text so no image asset is needed. Its colours
/// are Google's brand colours (sign-in branding rules), not app tokens.
class GoogleMark extends StatelessWidget {
  const GoogleMark({super.key});

  @override
  Widget build(BuildContext context) => ShaderMask(
    shaderCallback: (r) => const SweepGradient(
      colors: [
        Color(0xFF4285F4),
        Color(0xFF34A853),
        Color(0xFFFBBC05),
        Color(0xFFEA4335),
        Color(0xFF4285F4),
      ],
    ).createShader(r),
    child: const Text(
      'G',
      style: TextStyle(
        fontSize: 26,
        fontWeight: FontWeight.w800,
        color: Colors.white,
      ),
    ),
  );
}

/// Banner for a failure message, in the warning colours.
class AuthErrorBanner extends StatelessWidget {
  final String message;
  final Widget? action;
  const AuthErrorBanner(this.message, {super.key, this.action});

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppTokens.warnContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.error_outline, color: AppTokens.onWarn),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(color: AppTokens.onWarn, fontSize: 15),
                ),
              ),
            ],
          ),
          if (action != null)
            Align(alignment: Alignment.centerRight, child: action!),
        ],
      ),
    ),
  );
}
