import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:physical_treatment_and_health_support_system/device_platform/wearable/veepoo_watch_source.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/health_connect_service/health_connect_service.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/monitoring_view_model/monitoring_view_model.dart';
import 'support/demo_environment.dart';
import 'package:physical_treatment_and_health_support_system/device_platform/health_connect/health_data_source.dart';

/// Explicit live-watch acceptance target. Imported records stay in disposable repositories.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Read the nearby KS02 or K202 and reject a repeated import', (t) async {
    if (!const bool.fromEnvironment('E2E_TESTING')) throw StateError('Use the isolated E2E_TESTING package.');
    final env = await DemoEnvironment.create();
    await t.pumpWidget(const MaterialApp(home: Scaffold(body: Text('Testing automatic watch sync'))));
    env.biometrics.readings.clear();
    final source = VeepooWatchSource();
    addTearDown(source.cancel);
    final vm = MonitoringViewModel(env.biometrics, HealthConnectService(env.health), env.auth, env.treatments);
    addTearDown(vm.dispose);
    await vm.load();
    await t.pumpAndSettle();
    final devices = await source.scan();
    expect(devices, isNotEmpty, reason: 'Close H Band and keep the watch nearby.');
    final history = await source.read(devices.first);
    expect(history.deviceName.contains('\u0000'), isFalse);
    debugPrint(
      'WATCH_ACCEPTANCE device=${history.deviceName} supported=${history.supportedTypes} '
      'pressure=${history.readings.where((r) => r.metric == 'BLOOD_PRESSURE').length} '
      'glucose=${history.readings.where((r) => r.metric == 'BLOOD_GLUCOSE').length}',
    );
    expect(history.readings, isNotEmpty, reason: 'Record blood pressure on the watch before the test.');
    addTearDown(() => source.forget(env.accountId));
    final saved = await vm.enableWatchSync(devices.first, '0000', history);
    expect(saved, greaterThan(0), reason: vm.takeMessage());
    expect(env.biometrics.readings.every((r) => r.sourceDevice == history.deviceName), isTrue);
    expect(await vm.importWatchHistory(history), 0);
    debugPrint('WATCH_ACCEPTANCE saved=$saved repeat=0');
    final restored = MonitoringViewModel(env.biometrics, HealthConnectService(env.health), env.auth, env.treatments);
    addTearDown(restored.dispose);
    await restored.load();
    expect(restored.watchConnection!.device.name, history.deviceName);
    final previousSync = restored.watchConnection!.lastSync!;
    env.health.granted = true;
    env.health.records.add(HealthRecord('BODY_WEIGHT', 66, DateTime.now().subtract(const Duration(hours: 2))));
    await env.biometrics.setHealthSourceConnected(env.accountId, true);
    restored.startAutoSync(every: const Duration(seconds: 1));
    final deadline = DateTime.now().add(const Duration(seconds: 100));
    while (restored.watchConnection!.lastSync!.compareTo(previousSync) <= 0 && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    restored.stopAutoSync();
    expect(restored.watchConnection!.lastSync!.isAfter(previousSync), isTrue);
    expect(env.biometrics.readings.any((r) => r.metricType.db == 'BODY_WEIGHT'), isTrue);
    final keys = env.biometrics.readings.map((r) => r.duplicateKey()).toList();
    expect(keys.toSet(), hasLength(keys.length));
    debugPrint('WATCH_AUTO restore=true scheduled_sync=true weight_fixture=true duplicates=0');
  }, timeout: const Timeout(Duration(minutes: 3)));
}
