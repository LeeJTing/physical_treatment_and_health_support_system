import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Wrong verification codes per issued code (FR100_016), kept in the app's own preferences like
/// [LoginAttempts] (bug list #12, 1 Nov): held only in memory before, so closing and opening the
/// app gave five new tries at the same code. Keys name the code, e.g. the email for the sign-up
/// code and `reset:<email>` for the password-reset code. Still per phone; Supabase also limits
/// how often a code can be checked.
class CodeAttempts {
  static const _key = 'apths.code.rejections';

  Future<Map<String, int>> _read() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw =
          jsonDecode(prefs.getString(_key) ?? '{}') as Map<String, dynamic>;
      return {for (final e in raw.entries) e.key: (e.value as num).toInt()};
    } catch (_) {
      return {}; // preferences unavailable or unreadable: nothing counted
    }
  }

  Future<void> _write(Map<String, int> all) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode(all));
    } catch (_) {
      // Preferences unavailable: the count lasts only while the app runs.
    }
  }

  /// Wrong codes entered for [key] since its code was issued.
  Future<int> count(String key) async => (await _read())[key] ?? 0;

  /// Counts one wrong code for [key].
  Future<void> add(String key) async {
    final all = await _read();
    all[key] = (all[key] ?? 0) + 1;
    await _write(all);
  }

  /// A new code was issued, or the code was accepted.
  Future<void> clear(String key) async {
    final all = await _read();
    if (all.remove(key) != null) await _write(all);
  }
}
