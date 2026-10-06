import 'package:flutter/material.dart';

/// Full-width button with a large touch target (48 dp+) for elderly users.
class PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool busy;

  const PrimaryButton({super.key, required this.label, this.onPressed, this.busy = false});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        height: 52,
        child: FilledButton(
          onPressed: busy ? null : onPressed,
          child: busy
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
              : Text(label, style: const TextStyle(fontSize: 17)),
        ),
      );
}
