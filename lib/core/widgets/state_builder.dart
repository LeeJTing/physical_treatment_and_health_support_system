import 'package:flutter/material.dart';

import 'package:physical_treatment_and_health_support_system/core/base/ui_state.dart';

/// Renders a [UiState] so no View writes its own loading/error branching.
class StateBuilder<T> extends StatelessWidget {
  final UiState<T> state;
  final Widget Function(T data) onSuccess;
  final Widget Function(String message)? onError;
  final Widget? idle;

  const StateBuilder({
    super.key,
    required this.state,
    required this.onSuccess,
    this.onError,
    this.idle,
  });

  @override
  Widget build(BuildContext context) => switch (state) {
    Idle<T>() => idle ?? const SizedBox.shrink(),
    Loading<T>() => const Center(child: CircularProgressIndicator()),
    UiSuccess<T>(:final data) => onSuccess(data),
    UiError<T>(:final message) =>
      onError?.call(message) ??
          Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(message, textAlign: TextAlign.center),
            ),
          ),
  };
}
