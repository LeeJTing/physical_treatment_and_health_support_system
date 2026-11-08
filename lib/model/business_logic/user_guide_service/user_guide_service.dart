import 'package:physical_treatment_and_health_support_system/device_platform/local_settings/local_settings.dart';
import 'package:physical_treatment_and_health_support_system/model/result.dart';

/// Remembers, on this phone only, which picture guides the patient has seen, so a guide opens by
/// itself the first time a screen is used and afterwards only from its help button.
class UserGuideService {
  static const _prefix = 'guide_seen_';
  final LocalSettings _settings;

  const UserGuideService(this._settings);

  /// Whether the guide named [key] was already shown on this phone.
  Future<Result<bool>> hasSeen(String key) async {
    try {
      return Success((await _settings.read('$_prefix$key')) == '1');
    } catch (e) {
      return Failure('Guide state unavailable', code: 'local', cause: e);
    }
  }

  /// Records that the guide named [key] was shown.
  Future<Result<void>> markSeen(String key) async {
    try {
      await _settings.write('$_prefix$key', '1');
      return const Success(null);
    } catch (e) {
      return Failure('Guide state not saved', code: 'local', cause: e);
    }
  }

  /// Shows every guide again the next time each screen opens ("Show the guides again").
  Future<Result<void>> resetAll(Iterable<String> keys) async {
    try {
      for (final k in keys) {
        await _settings.remove('$_prefix$k');
      }
      return const Success(null);
    } catch (e) {
      return Failure('Guide state not reset', code: 'local', cause: e);
    }
  }
}
