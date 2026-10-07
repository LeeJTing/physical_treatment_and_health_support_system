import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';

/// Login record for one patient (Table 4.4).
class Account {
  final String accountId;
  final String email;
  final String username;
  final AuthProvider authProvider;
  final bool isEmailVerified;
  final bool healthSourceConnected;
  final DateTime? healthSourceLastSync;
  final DateTime createdAt;

  const Account({
    required this.accountId,
    required this.email,
    required this.username,
    this.authProvider = AuthProvider.email,
    this.isEmailVerified = false,
    this.healthSourceConnected = false,
    this.healthSourceLastSync,
    required this.createdAt,
  });

  /// True when the email address has been verified (FR100_013).
  bool isActivated() => isEmailVerified;

  /// True when no successful import for 24 hours (FR200_013).
  bool importIsStale([DateTime? now]) {
    final last = healthSourceLastSync;
    if (!healthSourceConnected || last == null) return false;
    return (now ?? DateTime.now()).difference(last) >=
        const Duration(hours: 24);
  }

  factory Account.fromJson(Map<String, dynamic> j) => Account(
    accountId: j['account_id'] as String,
    email: j['email'] as String,
    username: (j['username'] ?? '') as String,
    authProvider: AuthProvider.fromDb(j['auth_provider'] as String?),
    isEmailVerified: (j['is_email_verified'] ?? false) as bool,
    healthSourceConnected: (j['health_source_connected'] ?? false) as bool,
    healthSourceLastSync: j['health_source_last_sync'] == null
        ? null
        : DateTime.parse(j['health_source_last_sync'] as String),
    createdAt: DateTime.parse(j['created_at'] as String),
  );

  /// password_hash is never sent from the app: Supabase Auth hashes it (FR100_009).
  Map<String, dynamic> toJson() => {
    'account_id': accountId,
    'email': email,
    'username': username,
    'auth_provider': authProvider.db,
    'is_email_verified': isEmailVerified,
    'health_source_connected': healthSourceConnected,
    'health_source_last_sync': healthSourceLastSync?.toIso8601String(),
    'created_at': createdAt.toIso8601String(),
  };

  Account copyWith({
    String? username,
    bool? isEmailVerified,
    AuthProvider? authProvider,
  }) => Account(
    accountId: accountId,
    email: email,
    username: username ?? this.username,
    authProvider: authProvider ?? this.authProvider,
    isEmailVerified: isEmailVerified ?? this.isEmailVerified,
    healthSourceConnected: healthSourceConnected,
    healthSourceLastSync: healthSourceLastSync,
    createdAt: createdAt,
  );
}
