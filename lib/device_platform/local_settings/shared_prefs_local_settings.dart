import 'package:shared_preferences/shared_preferences.dart';

import 'package:physical_treatment_and_health_support_system/device_platform/local_settings/local_settings.dart';

/// Android's SharedPreferences. Never throws: a storage problem only means the setting is not
/// remembered, and the build-time default is used.
class SharedPrefsLocalSettings implements LocalSettings {
  @override
  Future<String?> read(String key) async {
    try {
      return (await SharedPreferences.getInstance()).getString(key);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(String key, String value) async {
    try {
      await (await SharedPreferences.getInstance()).setString(key, value);
    } catch (_) {
      // Not remembered after a restart; the address still applies for this session.
    }
  }

  @override
  Future<void> remove(String key) async {
    try {
      await (await SharedPreferences.getInstance()).remove(key);
    } catch (_) {
      // Nothing to remove.
    }
  }
}
