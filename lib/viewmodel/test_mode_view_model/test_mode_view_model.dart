import 'package:flutter/foundation.dart';

import 'package:physical_treatment_and_health_support_system/viewmodel/base_view_model.dart';

/// Testing mode (Elwin, 20 Oct): any exercise can be recorded and checked at
/// once, without a plan, the one-exercise-per-day rule or a rest day, and
/// nothing is saved. For testing the posture check; never for patients.
///
/// Only a debug build (what the laptop installs with `flutter run`) or a build
/// made with `--dart-define=TEST_MODE=true` offers it. It is off each time the
/// app starts.
class TestModeViewModel extends BaseViewModel {
  static const bool available =
      kDebugMode || bool.fromEnvironment('TEST_MODE');

  bool _enabled = false;
  bool get enabled => available && _enabled;

  void setEnabled(bool on) {
    _enabled = on;
    notifyListeners();
  }
}
