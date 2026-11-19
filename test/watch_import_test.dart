import 'package:flutter_test/flutter_test.dart';
import 'package:physical_treatment_and_health_support_system/device_platform/wearable/veepoo_watch_source.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/health_connect_service/health_connect_service.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/biometric_reading.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/monitoring_view_model/monitoring_view_model.dart';
import '../integration_test/support/demo_environment.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('watch imports keep provenance, reject invalid data and skip duplicates on retry', () async {
    final env = await DemoEnvironment.create();
    env.biometrics.readings.clear();
    final now = DateTime.now();
    final vm = MonitoringViewModel(
      env.biometrics, HealthConnectService(env.health), env.auth, env.treatments,
    );
    addTearDown(vm.dispose);
    await vm.load();
    final history = WatchHistory('KS02 Pro', [
      WatchBloodPressure(124, 80, now.subtract(const Duration(hours: 2))),
      WatchBloodPressure(124, 80, now.subtract(const Duration(hours: 2))),
      WatchBloodPressure(75, 100, now.subtract(const Duration(hours: 1))),
      WatchBloodPressure(124, 80, now.add(const Duration(days: 1))),
    ]);
    env.biometrics.failNext = true;
    expect(await vm.importWatchHistory(history), isNull);
    expect(vm.importing, isFalse);
    expect(env.biometrics.readings, isEmpty);
    expect(await vm.importWatchHistory(history), 1);
    final saved = env.biometrics.readings.single;
    expect(BiometricReading.fromJson(saved.toJson()).sourceDevice, 'KS02 Pro');
    expect(await vm.importWatchHistory(history), 0);
    expect(env.biometrics.readings, hasLength(1));
    expect(env.biometrics.sources, isEmpty);
    await env.auth.signOut();
    expect(await vm.importWatchHistory(history), isNull);
    expect(env.biometrics.readings, hasLength(1));
  });
}
