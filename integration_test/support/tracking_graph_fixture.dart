import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:physical_treatment_and_health_support_system/device_platform/wearable/veepoo_watch_source.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/health_connect_service/health_connect_service.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/user_guide_service/user_guide_service.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/biometric_reading.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';
import 'package:physical_treatment_and_health_support_system/view/monitoring_view/monitoring_view.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/monitoring_view_model/monitoring_view_model.dart';
import 'demo_environment.dart';

/// The production Tracking view with dated, disposable records and no automatic Bluetooth work.
class TrackingGraphFixture {
  final DemoEnvironment environment;
  final MonitoringViewModel viewModel;
  final DateTime importedAt;
  TrackingGraphFixture._(this.environment, this.viewModel, this.importedAt);

  static Future<TrackingGraphFixture> create() async {
    final env = await DemoEnvironment.create();
    env.biometrics.readings.clear();
    final now = DateTime.now();
    final importedAt = now.subtract(const Duration(minutes: 5));
    final latest = now.subtract(const Duration(hours: 1));
    for (final metric in MetricType.values) {
      for (var index = 0; index < 3; index++) {
        final imported = index != 1;
        await env.biometrics.insert(
          BiometricReading(
            readingId: 'graph-${metric.db}-$index',
            accountId: env.accountId,
            metricType: metric,
            primaryValue: switch (metric) {
              MetricType.bloodPressure => 120 + index * 4.0,
              MetricType.bloodGlucose => 5.5 + index * .3,
              MetricType.bodyWeight => 65 + index * .5,
            },
            secondaryValue: metric == MetricType.bloodPressure ? 80 + index * 2.0 : null,
            measurementContext: metric == MetricType.bloodGlucose ? MeasurementContext.random : null,
            recordedAt: latest.subtract(Duration(days: 4 - index * 2)),
            source: imported ? ReadingSource.imported : ReadingSource.manual,
            sourceDevice: imported && metric != MetricType.bodyWeight ? 'Demo watch' : null,
            importedAt: imported ? importedAt : null,
          ),
        );
      }
    }
    final vm = MonitoringViewModel(
      env.biometrics,
      HealthConnectService(env.health),
      env.auth,
      env.treatments,
      null,
      null,
      _NoSavedWatch(),
    );
    return TrackingGraphFixture._(env, vm, importedAt);
  }

  Widget get app => MultiProvider(
    providers: [
      ChangeNotifierProvider<MonitoringViewModel>.value(value: viewModel),
      Provider<UserGuideService>.value(value: UserGuideService(environment.settings)),
    ],
    child: const MaterialApp(debugShowCheckedModeBanner: false, home: MonitoringView(standalone: true)),
  );
}

class _NoSavedWatch extends VeepooWatchSource {
  @override
  Future<WatchConnection?> connection(String accountId) async => null;
  @override
  Future<void> cancel() async {}
}
