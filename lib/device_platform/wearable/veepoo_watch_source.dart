import 'package:flutter/services.dart';
import 'package:physical_treatment_and_health_support_system/device_platform/health_connect/health_data_source.dart';

class WatchDevice {
  final String address;
  final String name;
  const WatchDevice(this.address, this.name);
}

class WatchHistory {
  final String deviceName;
  final List<HealthRecord> readings;
  final List<String> supportedTypes;
  const WatchHistory(this.deviceName, this.readings, {this.supportedTypes = const ['BLOOD_PRESSURE']});
}

class WatchConnection {
  final WatchDevice device;
  final DateTime? lastSync;
  const WatchConnection(this.device, this.lastSync);
}

/// Reads records and remembers a per-account connection with a Keystore-protected PIN.
class VeepooWatchSource {
  static const _channel = MethodChannel('apths/veepoo');

  Future<List<WatchDevice>> scan() async {
    final rows = await _channel.invokeListMethod<dynamic>('scan') ?? [];
    return [for (final row in rows) WatchDevice(row['address'] as String, row['name'] as String)];
  }

  Future<WatchHistory> read(WatchDevice device, {String pin = '0000'}) async {
    final response = (await _channel.invokeMapMethod<String, dynamic>('readHistory', {
      'address': device.address,
      'name': device.name,
      'pin': pin,
    }))!;
    return _history(response);
  }

  WatchHistory _history(Map<String, dynamic> response) => WatchHistory(response['deviceName'] as String, [
    for (final row in response['readings'] as List)
      HealthRecord(
        row['metric'] as String,
        (row['value'] as num).toDouble(),
        DateTime.fromMillisecondsSinceEpoch((row['at'] as num).toInt()),
        secondary: (row['secondary'] as num?)?.toDouble(),
      ),
  ], supportedTypes: List<String>.from(response['supportedTypes'] as List));

  Future<WatchConnection?> connection(String accountId) async {
    try {
      final value = await _channel.invokeMapMethod<String, dynamic>('connection', {'accountId': accountId});
      if (value == null) return null;
      return WatchConnection(
        WatchDevice(value['address'] as String, value['name'] as String),
        value['lastSync'] == null ? null : DateTime.fromMillisecondsSinceEpoch((value['lastSync'] as num).toInt()),
      );
    } on MissingPluginException {
      return null;
    }
  }

  Future<void> remember(String accountId, WatchDevice device, String pin) => _channel.invokeMethod<void>('remember', {
    'accountId': accountId,
    'address': device.address,
    'name': device.name,
    'pin': pin,
  });

  Future<WatchHistory> readConnected(String accountId) async =>
      _history((await _channel.invokeMapMethod<String, dynamic>('readConnected', {'accountId': accountId}))!);

  Future<void> markSynced(String accountId, DateTime at) =>
      _channel.invokeMethod<void>('markSynced', {'accountId': accountId, 'at': at.millisecondsSinceEpoch});

  Future<void> forget(String accountId) => _channel.invokeMethod<void>('forget', {'accountId': accountId});

  Future<void> cancel() async {
    try {
      await _channel.invokeMethod<void>('cancel');
    } on MissingPluginException {
      // No Bluetooth adapter on the host running widget tests.
    }
  }
}
