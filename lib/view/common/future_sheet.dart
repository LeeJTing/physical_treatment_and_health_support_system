import 'package:flutter/material.dart';

import 'package:physical_treatment_and_health_support_system/core/themes/design_tokens.dart';

/// Opens a bottom sheet at once and fills it when [future] completes, so a tap answers
/// immediately instead of waiting for the database or the AI server. While it loads, the sheet
/// shows [title], a spinner and [loadingText]; [builder] then builds the content.
Future<R?> showFutureSheet<T, R>({
  required BuildContext context,
  required Future<T> future,
  required String title,
  required Widget Function(BuildContext ctx, T data) builder,
  String loadingText = 'Loading...',
  String? subtitle,
}) => showModalBottomSheet<R>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: AppTokens.surface,
  shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
  builder: (ctx) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppTokens.ink)),
          if (subtitle != null) Text(subtitle, style: const TextStyle(color: AppTokens.inkMuted)),
          const SizedBox(height: 8),
          Flexible(
            child: FutureBuilder<T>(
              future: future,
              builder: (ctx, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 28),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(color: AppTokens.brandDeepAccent),
                        const SizedBox(height: 12),
                        Text(loadingText, style: const TextStyle(fontSize: 16, color: AppTokens.inkMuted)),
                      ],
                    ),
                  );
                }
                if (snap.hasError || !snap.hasData) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Text(
                      'This could not be loaded. Please try again.',
                      style: TextStyle(fontSize: 16, color: AppTokens.inkMuted),
                    ),
                  );
                }
                return SingleChildScrollView(child: builder(ctx, snap.data as T));
              },
            ),
          ),
        ],
      ),
    ),
  ),
);
