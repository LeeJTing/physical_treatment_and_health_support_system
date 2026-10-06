/// Result of every repository and service call. No method throws to its
/// caller; exceptions are caught at the boundary and turned into [Failure].
sealed class Result<T> {
  const Result();

  bool get isSuccess => this is Success<T>;

  /// Returns the data on success, or null on failure.
  T? get dataOrNull => switch (this) {
    Success<T>(:final data) => data,
    Failure<T>() => null,
  };
}

class Success<T> extends Result<T> {
  final T data;
  const Success(this.data);
}

class Failure<T> extends Result<T> {
  final String message;
  final String? code;
  final Object? cause;
  const Failure(this.message, {this.code, this.cause});

  /// Re-types a failure so it can be passed up through a different `Result<T>`.
  Failure<R> cast<R>() => Failure<R>(message, code: code, cause: cause);
}

/// Wraps an async body so any thrown exception becomes a [Failure].
Future<Result<T>> guard<T>(
  Future<T> Function() body, {
  String message = 'Something went wrong. Please try again later.',
  String? code,
}) async {
  try {
    return Success<T>(await body());
  } catch (e) {
    return Failure<T>(message, code: code, cause: e);
  }
}
