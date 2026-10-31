import 'package:flutter_test/flutter_test.dart';

import 'package:physical_treatment_and_health_support_system/core/constants/app_constants.dart';
import 'package:physical_treatment_and_health_support_system/device_platform/health_connect/health_data_source.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/health_connect_service/health_connect_service.dart';

/// A failed Health Connect connection says what is wrong and offers the fix (FR100_062, FR100_063).
class _Refusing extends FakeHealthDataSource {
  @override
  Future<bool> requestRead() async => false;
}

void main() {
  test('not installed or too old: install message and the Play Store fix', () async {
    final src = FakeHealthDataSource(available: false);
    final hs = HealthConnectService(src);
    final a = await hs.connect();
    expect(a.connected, isFalse);
    expect(a.message, Messages.healthConnectInstall);
    expect(a.fix, HealthFix.install);
    await hs.applyFix(a.fix!);
    expect(src.installRequested, isTrue);
  });

  test('access refused: the steps and the permission page fix', () async {
    final src = _Refusing();
    final hs = HealthConnectService(src);
    final a = await hs.connect();
    expect(a.message, Messages.healthPermissionSteps);
    expect(a.fix, HealthFix.openSettings);
    await hs.applyFix(a.fix!);
    expect(src.settingsOpened, isTrue);
  });

  test('granted: connected, no message', () async {
    final a = await HealthConnectService(FakeHealthDataSource()).connect();
    expect(a.connected, isTrue);
    expect(a.fix, isNull);
  });
}
