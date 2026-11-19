import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:physical_treatment_and_health_support_system/device_platform/wearable/veepoo_watch_source.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/health_connect_service/health_connect_service.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/monitoring_view_model/monitoring_view_model.dart';
import 'support/demo_app.dart';

/// Explicit live-watch acceptance target. Imported records stay in disposable repositories.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Read the nearby KS02 or K202 and reject a repeated import', (t) async {
    final env = await startDemo();
    env.biometrics.readings.clear();
    final source = VeepooWatchSource();
    addTearDown(source.cancel);
    final vm = MonitoringViewModel(
      env.biometrics,
      HealthConnectService(env.health),
      env.auth,
      env.treatments,
    );
    addTearDown(vm.dispose);
    await vm.load();
    await t.pumpAndSettle();
    final devices = await source.scan();
    expect(devices, isNotEmpty, reason: 'Close H Band and keep the watch nearby.');
    final history = await source.read(devices.first);
    expect(history.deviceName.contains('\u0000'), isFalse);
    debugPrint('WATCH_ACCEPTANCE device=${history.deviceName} returned=${history.readings.length}');
    expect(history.readings, isNotEmpty, reason: 'Record blood pressure on the watch before the test.');
    final saved = await vm.importWatchHistory(history);
    expect(saved, greaterThan(0), reason: vm.takeMessage());
    expect(env.biometrics.readings.every((r) => r.sourceDevice == history.deviceName), isTrue);
    expect(await vm.importWatchHistory(history), 0);
    debugPrint('WATCH_ACCEPTANCE saved=$saved repeat=0');
  }, timeout: const Timeout(Duration(minutes: 3)));
}
