import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:physical_treatment_and_health_support_system/device_platform/wearable/veepoo_watch_source.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/health_connect_service/health_connect_service.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/monitoring_view_model/monitoring_view_model.dart';
import 'support/demo_environment.dart';

/// Reads the real watch; import verification uses disposable in-memory records.
/// Never writes account records or changes watch settings.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Read saved watch history and report manual-history capabilities', (
    t,
  ) async {
    if (!const bool.fromEnvironment('E2E_TESTING')) {
      throw StateError('Use E2E_TESTING=true.');
    }
    await t.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(child: Text('Reading saved watch history')),
        ),
      ),
    );
    final source = VeepooWatchSource();
    addTearDown(source.cancel);
    final devices = await source.scan();
    const watchName = String.fromEnvironment(
      'WATCH_TEST_NAME',
      defaultValue: 'KS02 Pro',
    );
    final device = devices.singleWhere((d) => d.name == watchName);
    final history = await source.read(device);
    debugPrint('WATCH_DIAGNOSTIC ${jsonEncode(history.diagnostics)}');
    final recent = [...history.readings]..sort((a, b) => b.at.compareTo(a.at));
    if (const bool.fromEnvironment('WATCH_DIAGNOSTIC_VALUES')) {
      for (final row in recent.take(20)) {
        debugPrint(
          'WATCH_RETURNED ${row.metric} ${row.at.toIso8601String()} ${row.value}/${row.secondary}',
        );
      }
    }
    debugPrint(
      'WATCH_REPORTED_116_84 matches=${recent.where((r) => r.metric == 'BLOOD_PRESSURE' && r.value == 116 && r.secondary == 84).length}',
    );
    expect(history.supportedTypes, contains('BLOOD_PRESSURE'));
    expect(history.readings, isNotEmpty);
    expect(history.diagnostics.containsKey('manualHistorySupported'), isTrue);
    final env = await DemoEnvironment.create();
    env.biometrics.readings.clear();
    final vm = MonitoringViewModel(
      env.biometrics,
      HealthConnectService(env.health),
      env.auth,
      env.treatments,
    );
    addTearDown(vm.dispose);
    await vm.load();
    final saved = await vm.importWatchHistory(history);
    expect(saved, greaterThan(0));
    final reported = recent.where(
      (r) =>
          r.metric == 'BLOOD_PRESSURE' && r.value == 116 && r.secondary == 84,
    );
    for (final row in reported) {
      expect(
        env.biometrics.readings.any(
          (r) =>
              r.recordedAt == row.at &&
              r.primaryValue == row.value &&
              r.secondaryValue == row.secondary,
        ),
        isTrue,
      );
    }
    expect(await vm.importWatchHistory(history), 0);
    debugPrint(
      'WATCH_IMPORT saved=$saved reported_matches_kept=${reported.length} repeat=0',
    );
  }, timeout: const Timeout(Duration(minutes: 3)));
}
