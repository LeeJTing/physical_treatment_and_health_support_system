import 'package:physical_treatment_and_health_support_system/model/business_logic/server_connection_service/server_connection_service.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/server_connection_service/server_status.dart';
import 'package:physical_treatment_and_health_support_system/model/result.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/base_view_model.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/ui_state.dart';

/// Profile > AI server: which laptop server the app uses, and whether it answers.
class ServerSettingsViewModel extends BaseViewModel {
  final ServerConnectionService _service;

  ServerSettingsViewModel(this._service);

  /// Result of the last Test connection (Idle before the first one).
  UiState<ServerStatus> status = const Idle();

  /// Shown under the buttons after Save / Use default.
  String? notice;

  String get address => _service.address;
  String get defaultAddress => _service.defaultAddress;
  bool get usingDefault => _service.usingDefault;

  /// Checks the typed address (or the current one) without changing anything.
  Future<void> test([String? input]) async {
    notice = null;
    status = const Loading();
    notifyListeners();
    final res = await _service.test(input);
    status = switch (res) {
      Success(:final data) => UiSuccess(data),
      Failure(:final message) => UiError(message),
    };
    notifyListeners();
  }

  /// Tests the address, then saves it even when the laptop is off right now (the patient may set it
  /// up before starting the server), saying so.
  Future<void> save(String input) async {
    await test(input);
    final res = await _service.save(input);
    notice = switch (res) {
      Success(:final data) => status is UiSuccess
          ? 'Saved. The app now uses $data.'
          : 'Saved $data, but it did not answer yet. Start the server on the laptop and test again.',
      Failure(:final message) => message,
    };
    notifyListeners();
  }

  Future<void> useDefault() async {
    await _service.reset();
    await test();
    notice = 'Back to the built-in address ${_service.defaultAddress}.';
    notifyListeners();
  }
}
