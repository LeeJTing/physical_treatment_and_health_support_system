import 'package:flutter/services.dart';

class WatchDevice {
  final String address;
  final String name;
  const WatchDevice(this.address, this.name);
}

class WatchBloodPressure {
  final double systolic;
  final double diastolic;
  final DateTime at;
  const WatchBloodPressure(this.systolic, this.diastolic, this.at);
}

class WatchHistory {
  final String deviceName;
  final List<WatchBloodPressure> readings;
  const WatchHistory(this.deviceName, this.readings);
}

/// Reads existing watch records over Bluetooth. Saving is a separate, reviewed operation.
class VeepooWatchSource {
  static const _channel = MethodChannel('apths/veepoo');

  Future<List<WatchDevice>> scan() async {
    final rows = await _channel.invokeListMethod<dynamic>('scan') ?? [];
    return [for (final row in rows) WatchDevice(row['address'] as String, row['name'] as String)];
  }

  Future<WatchHistory> read(WatchDevice device, {String pin = '0000'}) async {
    final response = (await _channel.invokeMapMethod<String, dynamic>('readBloodPressure', {
      'address': device.address,
      'name': device.name,
      'pin': pin,
    }))!;
    return WatchHistory(response['deviceName'] as String, [
      for (final row in response['readings'] as List)
        WatchBloodPressure(
          (row['systolic'] as num).toDouble(),
          (row['diastolic'] as num).toDouble(),
          DateTime.fromMillisecondsSinceEpoch((row['at'] as num).toInt()),
        ),
    ]);
  }

  Future<void> cancel() async {
    try {
      await _channel.invokeMethod<void>('cancel');
    } on MissingPluginException {
      // No Bluetooth adapter on the host running widget tests.
    }
  }
}
