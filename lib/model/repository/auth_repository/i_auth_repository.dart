import 'package:physical_treatment_and_health_support_system/model/result.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/account.dart';

/// Contract for authentication, wrapping Supabase Auth (Table 4.54).
abstract interface class IAuthRepository {
  /// The signed-in account, or null when no session is stored (FR100_024/025).
  Future<Result<Account?>> currentAccount();

  /// Creates the unverified account and emails the 6-digit code (FR100_001, 012).
  Future<Result<void>> register(String email, String password, String username);

  /// Confirms the emailed code and activates the account (FR100_013, 014).
  Future<Result<Account>> verify(String email, String code);

  /// Issues a replacement verification code (FR100_015).
  Future<Result<void>> resendCode(String email);

  Future<Result<Account>> login(String email, String password);

  /// Starts the Google OAuth flow (FR100_018). The session arrives through
  /// the auth-state stream once the browser redirects back.
  Future<Result<void>> signInWithGoogle();

  /// True when the signed-in account was created by Google Sign-In and has no username and
  /// password of the patient's own yet (FR100_022).
  Future<Result<bool>> needsAccountSetup();

  /// Saves the username and password of an account created by Google Sign-In (FR100_022).
  Future<Result<Account>> completeAccountSetup(String username, String password);

  /// Account setup cancelled: signs out and removes the unfinished account (FR100_023).
  Future<Result<void>> discardIncompleteAccount();

  /// True right after Google was linked to an existing email account (FR100_021, UC100 M12).
  Future<Result<bool>> googleJustLinked();

  /// Sends a 6-digit reset code; the same reply whether or not the address exists (FR100_037, 038).
  Future<Result<void>> requestPasswordReset(String email);

  Future<Result<void>> confirmPasswordReset(
    String email,
    String code,
    String newPassword,
  );

  /// Replaces the signed-in patient's password after checking the current one (FR100_061).
  Future<Result<void>> changePassword(String currentPassword, String newPassword);

  Future<Result<void>> signOut();

  /// Deletes the signed-in account and all its data, then signs out
  /// ("Delete my account", Privacy Notice section 5; 11 Oct).
  Future<Result<void>> deleteAccount();
}
