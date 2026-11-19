import 'package:flutter_test/flutter_test.dart';
import 'dart:async';
import 'package:physical_treatment_and_health_support_system/device_platform/health_connect/health_data_source.dart';
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
    final vm = MonitoringViewModel(env.biometrics, HealthConnectService(env.health), env.auth, env.treatments);
    addTearDown(vm.dispose);
    await vm.load();
    final history = WatchHistory('KS02 Pro', [
      HealthRecord('BLOOD_PRESSURE', 124, now.subtract(const Duration(hours: 2)), secondary: 80),
      HealthRecord('BLOOD_PRESSURE', 124, now.subtract(const Duration(hours: 2)), secondary: 80),
      HealthRecord('BLOOD_PRESSURE', 75, now.subtract(const Duration(hours: 1)), secondary: 100),
      HealthRecord('BLOOD_PRESSURE', 124, now.add(const Duration(days: 1)), secondary: 80),
      HealthRecord('BLOOD_GLUCOSE', 6.2, now.subtract(const Duration(hours: 2))),
    ]);
    env.biometrics.failNext = true;
    expect(await vm.importWatchHistory(history), isNull);
    expect(vm.importing, isFalse);
    expect(env.biometrics.readings, isEmpty);
    expect(await vm.importWatchHistory(history), 2);
    final saved = env.biometrics.readings.first;
    expect(BiometricReading.fromJson(saved.toJson()).sourceDevice, 'KS02 Pro');
    expect(saved.importedAt, isNotNull);
    expect(BiometricReading.fromJson(saved.toJson()).importedAt, saved.importedAt);
    expect(await vm.importWatchHistory(history), 0);
    expect(env.biometrics.readings, hasLength(2));
    expect(env.biometrics.readings.first.importedAt, saved.importedAt);
    expect(env.biometrics.sources, isEmpty);
    await env.auth.signOut();
    expect(await vm.importWatchHistory(history), isNull);
    expect(env.biometrics.readings, hasLength(2));
  });

  test('a remembered watch restores, retries and automatically imports all available app metrics', () async {
    final env = await DemoEnvironment.create();
    env.biometrics.readings.clear();
    final now = DateTime.now();
    final source = _WatchSource(
      WatchHistory(
        'KS02 Pro',
        [
          HealthRecord('BLOOD_PRESSURE', 124, now.subtract(const Duration(hours: 1)), secondary: 80),
          HealthRecord('BLOOD_GLUCOSE', 6.2, now.subtract(const Duration(hours: 1))),
        ],
        supportedTypes: ['BLOOD_PRESSURE', 'BLOOD_GLUCOSE'],
      ),
    );
    MonitoringViewModel model() => MonitoringViewModel(
      env.biometrics,
      HealthConnectService(env.health),
      env.auth,
      env.treatments,
      null,
      null,
      source,
    );
    final first = model();
    await first.load();
    expect(await first.enableWatchSync(const WatchDevice('AA:BB:CC:DD:EE:FF', 'KS02 Pro'), '0000', source.history), 2);
    first.dispose();
    final vm = model();
    addTearDown(vm.dispose);
    await vm.load();
    expect(vm.watchConnection!.device.name, 'KS02 Pro');
    source.failNext = true;
    final before = vm.watchConnection!.lastSync;
    await vm.syncNow();
    expect(vm.watchSyncMessage, contains('retry'));
    expect(vm.watchConnection!.lastSync, before);
    env.health.granted = true;
    env.health.records.add(HealthRecord('BODY_WEIGHT', 66, now.subtract(const Duration(minutes: 10))));
    await env.biometrics.setHealthSourceConnected(env.accountId, true);
    vm.startAutoSync(every: const Duration(milliseconds: 20));
    await Future<void>.delayed(const Duration(milliseconds: 90));
    vm.stopAutoSync();
    expect(source.reads, greaterThanOrEqualTo(2));
    expect(env.biometrics.readings.map((r) => r.metricType.db).toSet(), {
      'BLOOD_PRESSURE',
      'BLOOD_GLUCOSE',
      'BODY_WEIGHT',
    });
    expect(env.biometrics.readings, hasLength(3));
    await vm.disconnectWatch();
    final reads = source.reads;
    await vm.syncNow();
    expect(source.reads, reads);
    expect(vm.watchConnection, isNull);
    expect(source.connections, isEmpty);
  });

  test('watch polling imports new records with their first import time and never overlaps reads', () async {
    final env = await DemoEnvironment.create();
    env.biometrics.readings.clear();
    var clock = DateTime.now();
    final measured = clock.subtract(const Duration(hours: 1));
    final original = WatchHistory('Demo watch', [HealthRecord('BLOOD_GLUCOSE', 5.8, measured)]);
    final source = _WatchSource(original);
    final vm = MonitoringViewModel(
      env.biometrics,
      HealthConnectService(env.health),
      env.auth,
      env.treatments,
      null,
      () => clock,
      source,
    );
    addTearDown(vm.dispose);
    await vm.load();
    await vm.enableWatchSync(const WatchDevice('AA:BB:CC:DD:EE:FF', 'Demo watch'), '0000', original);
    final firstImport = env.biometrics.readings.single.importedAt;
    await vm.loadRange(clock.subtract(const Duration(days: 3)), clock.subtract(const Duration(days: 2)));
    final selectedEnd = vm.rangeEnd;
    source.pending = Completer<WatchHistory>();
    vm.startAutoSync(every: const Duration(hours: 1), watchEvery: const Duration(milliseconds: 5));
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(source.reads, 1);
    final inFlight = source.pending!;
    source.pending = null;
    inFlight.complete(original);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    clock = clock.add(const Duration(minutes: 1));
    source.history = WatchHistory('Demo watch', [
      ...original.readings,
      HealthRecord('BLOOD_GLUCOSE', 6.1, measured.add(const Duration(minutes: 15))),
    ]);
    await Future<void>.delayed(const Duration(milliseconds: 35));
    vm.stopAutoSync();
    expect(env.biometrics.readings, hasLength(2));
    expect(env.biometrics.readings.first.importedAt, firstImport);
    expect(env.biometrics.readings.last.importedAt, clock);
    expect(vm.rangeEnd, selectedEnd);
    expect(vm.data!.readings, isEmpty);
    expect(vm.watchSyncing, isFalse);
    final reads = source.reads;
    await Future<void>.delayed(const Duration(milliseconds: 15));
    expect(source.reads, reads);
  });

  test('disconnecting during a read discards the late response', () async {
    final env = await DemoEnvironment.create();
    env.biometrics.readings.clear();
    final source = _WatchSource(const WatchHistory('KS02 Pro', []));
    final vm = MonitoringViewModel(
      env.biometrics,
      HealthConnectService(env.health),
      env.auth,
      env.treatments,
      null,
      null,
      source,
    );
    addTearDown(vm.dispose);
    await vm.load();
    await vm.enableWatchSync(const WatchDevice('AA:BB:CC:DD:EE:FF', 'KS02 Pro'), '0000', source.history);
    source.pending = Completer<WatchHistory>();
    final running = vm.syncWatch();
    await Future<void>.delayed(Duration.zero);
    await vm.disconnectWatch();
    source.pending!.complete(
      WatchHistory('KS02 Pro', [
        HealthRecord('BLOOD_PRESSURE', 124, DateTime.now().subtract(const Duration(hours: 1)), secondary: 80),
      ]),
    );
    await running;
    expect(env.biometrics.readings, isEmpty);
    expect(vm.watchConnection, isNull);
  });
}

class _WatchSource extends VeepooWatchSource {
  WatchHistory history;
  final connections = <String, WatchConnection>{};
  int reads = 0;
  bool failNext = false;
  Completer<WatchHistory>? pending;
  _WatchSource(this.history);
  @override
  Future<WatchConnection?> connection(String accountId) async => connections[accountId];
  @override
  Future<void> remember(String accountId, WatchDevice device, String pin) async {
    connections[accountId] = WatchConnection(device, null);
  }

  @override
  Future<void> markSynced(String accountId, DateTime at) async {
    connections[accountId] = WatchConnection(connections[accountId]!.device, at);
  }

  @override
  Future<void> forget(String accountId) async {
    connections.remove(accountId);
  }

  @override
  Future<WatchHistory> readConnected(String accountId) async {
    reads++;
    if (failNext) {
      failNext = false;
      throw StateError('offline');
    }
    return pending?.future ?? history;
  }

  @override
  Future<void> cancel() async {}
}
