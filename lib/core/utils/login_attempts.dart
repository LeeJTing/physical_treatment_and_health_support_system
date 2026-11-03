import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:physical_treatment_and_health_support_system/core/constants/app_constants.dart';

/// Failed log-ins per email on this phone (FR100_031: five in 15 minutes lock the account
/// for 15 minutes). Kept in the app's own preferences (audit, 23 Oct): held only in memory
/// before, so closing and opening the app reset the count. Still per phone; a lock across
/// phones needs the server (Supabase), not this app.
class LoginAttempts {
  static const _key = 'apths.login.failures';
  final DateTime Function() _now;

  LoginAttempts({DateTime Function()? now}) : _now = now ?? DateTime.now;

  Future<Map<String, List<DateTime>>> _read() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw =
          jsonDecode(prefs.getString(_key) ?? '{}') as Map<String, dynamic>;
      return {
        for (final e in raw.entries)
          e.key: [for (final t in e.value as List) DateTime.parse(t as String)],
      };
    } catch (_) {
      return {}; // preferences unavailable or unreadable: nothing counted
    }
  }

  Future<void> _write(Map<String, List<DateTime>> all) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _key,
        jsonEncode({
          for (final e in all.entries)
            if (e.value.isNotEmpty)
              e.key: [for (final t in e.value) t.toIso8601String()],
        }),
      );
    } catch (_) {
      // Preferences unavailable: the count lasts only while the app runs.
    }
  }

  /// The failures of the last 15 minutes for [email]; older ones are dropped.
  Future<List<DateTime>> _recent(
    Map<String, List<DateTime>> all,
    String email,
  ) async {
    final cutoff = _now().subtract(AppConstants.loginLockout);
    final recent = [
      for (final t in all[email] ?? const <DateTime>[])
        if (t.isAfter(cutoff)) t,
    ];
    all[email] = recent;
    return recent;
  }

  // When each lock ends. The lock runs for 15 minutes from the failure that set it (bug list #1,
  // 1 Nov): it used to end once the OLDEST of the five failures was 15 minutes old, so five
  // failures 3 minutes apart locked the account for only 3 minutes.
  static const _locksKey = 'apths.login.locks';

  Future<Map<String, DateTime>> _readLocks() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw =
          jsonDecode(prefs.getString(_locksKey) ?? '{}')
              as Map<String, dynamic>;
      return {
        for (final e in raw.entries) e.key: DateTime.parse(e.value as String),
      };
    } catch (_) {
      return {};
    }
  }

  Future<void> _writeLocks(Map<String, DateTime> locks) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _locksKey,
        jsonEncode({
          for (final e in locks.entries) e.key: e.value.toIso8601String(),
        }),
      );
    } catch (_) {
      // Preferences unavailable: the lock lasts only while the app runs.
    }
  }

  /// True while [email] is locked out on this phone.
  Future<bool> locked(String email) async {
    final locks = await _readLocks();
    final until = locks[email];
    if (until == null) return false;
    if (_now().isBefore(until)) return true;
    // The lock is over: counting starts again.
    locks.remove(email);
    await _writeLocks(locks);
    await clear(email);
    return false;
  }

  /// Counts a wrong password; true when this one locks the account.
  Future<bool> recordFailure(String email) async {
    final all = await _read();
    final recent = await _recent(all, email)
      ..add(_now());
    all[email] = recent;
    await _write(all);
    if (recent.length < AppConstants.maxLoginFailures) return false;
    final locks = await _readLocks();
    locks[email] = _now().add(AppConstants.loginLockout);
    await _writeLocks(locks);
    return true;
  }

  /// A successful log-in clears the count.
  Future<void> clear(String email) async {
    final all = await _read()
      ..remove(email);
    await _write(all);
    final locks = await _readLocks();
    if (locks.remove(email) != null) await _writeLocks(locks);
  }
}
