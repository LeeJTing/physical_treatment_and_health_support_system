import 'package:physical_treatment_and_health_support_system/core/base/base_view_model.dart';
import 'package:physical_treatment_and_health_support_system/core/base/result.dart';
import 'package:physical_treatment_and_health_support_system/core/routes/routes.dart';
import 'package:physical_treatment_and_health_support_system/core/services/reminder_service.dart';
import 'package:physical_treatment_and_health_support_system/data/repository/interfaces/i_auth_repository.dart';
import 'package:physical_treatment_and_health_support_system/data/repository/interfaces/i_profile_repository.dart';

/// Decides the first screen (FR100_024, FR100_025, FR100_035):
/// no stored session -> login; signed in without a complete profile -> profile; else home.
class StartupViewModel extends BaseViewModel {
  final IAuthRepository _auth;
  final IProfileRepository _profiles;
  final ReminderService? _reminders;

  StartupViewModel(this._auth, this._profiles, [this._reminders]);

  Future<String> decideRoute() async {
    final account = (await _auth.currentAccount()).dataOrNull;
    if (account == null) return Routes.loginScreen;
    // Refresh the device's reminder schedule; it must not block start-up.
    _reminders?.sync(account.accountId).ignore();
    final profile = await _profiles.getProfile(account.accountId);
    return switch (profile) {
      Success(:final data) when data == null || !data.isComplete => Routes.healthProfile,
      // A read failure still opens the app; ProfileInfoService applies the fail-safe limits.
      _ => Routes.home,
    };
  }
}
