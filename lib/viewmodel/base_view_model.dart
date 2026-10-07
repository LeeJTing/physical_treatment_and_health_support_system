import 'package:flutter/foundation.dart';

/// Abstract parent of every ViewModel (Table 4.33). Holds the loading and
/// error state each screen needs so it is written once.
abstract class BaseViewModel extends ChangeNotifier {
  bool _isLoading = false;
  String? _errorMessage;
  bool _isDisposed = false;

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  @protected
  bool get isDisposed => _isDisposed;

  void setLoading(bool v) {
    _isLoading = v;
    notifyListeners();
  }

  void setError(String? m) {
    _errorMessage = m;
    notifyListeners();
  }

  /// Wraps a command with loading and error handling so no ViewModel
  /// repeats it. Errors thrown inside [task] are shown as [errorMessage].
  @protected
  Future<void> run(
    Future<void> Function() task, {
    String fallbackError = 'Something went wrong. Please try again later.',
  }) async {
    _errorMessage = null;
    setLoading(true);
    try {
      await task();
    } catch (_) {
      _errorMessage = fallbackError;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Guarded against a late async result arriving after the screen closed,
  /// e.g. a slow /pose call ("ChangeNotifier was used after being disposed").
  @override
  void notifyListeners() {
    if (!_isDisposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }
}
