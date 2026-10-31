import 'package:physical_treatment_and_health_support_system/model/result.dart';
import 'package:physical_treatment_and_health_support_system/shared_client/supabase_provider/supabase_provider.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/biometric_reading.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/biometric_repository/i_biometric_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/supabase_guard.dart';

/// Supabase implementation of IBiometricRepository (Table 4.85). RLS scopes every row to the
/// signed-in account.
class SupabaseBiometricRepository implements IBiometricRepository {
  final SupabaseProvider _sb;

  SupabaseBiometricRepository(this._sb);

  @override
  Future<Result<void>> insert(BiometricReading r) => supabaseGuard(() async {
    await _sb.from('biometric_reading').insert(r.toJson());
  });

  /// The unique index on (account, metric, recorded_at) rejects an exact duplicate; readings within
  /// 5 minutes of a stored one are dropped here first (UC700 C11).
  @override
  Future<Result<int>> insertBatch(List<BiometricReading> rs) =>
      supabaseGuard(() async {
        if (rs.isEmpty) return 0;
        final sorted = [...rs]..sort((a, b) => a.recordedAt.compareTo(b.recordedAt));
        final from = sorted.first.recordedAt.subtract(const Duration(minutes: 5));
        final to = sorted.last.recordedAt.add(const Duration(minutes: 5));
        final stored = (await _sb
                .from('biometric_reading')
                .select()
                .gte('recorded_at', from.toUtc().toIso8601String())
                .lte('recorded_at', to.toUtc().toIso8601String()))
            .map(BiometricReading.fromJson)
            .toList();
        final keep = <BiometricReading>[];
        for (final r in sorted) {
          if (stored.any(r.duplicates) || keep.any(r.duplicates)) continue;
          keep.add(r);
        }
        if (keep.isEmpty) return 0;
        await _sb
            .from('biometric_reading')
            .upsert(
              keep.map((r) => r.toJson()).toList(),
              onConflict: 'account_id,metric_type,recorded_at',
              ignoreDuplicates: true,
            );
        return keep.length;
      });

  @override
  Future<Result<List<BiometricReading>>> findBetween(
    String accountId,
    DateTime a,
    DateTime b,
  ) => supabaseGuard(
    () async => (await _sb
            .from('biometric_reading')
            .select()
            .eq('account_id', accountId)
            .gte('recorded_at', a.toUtc().toIso8601String())
            .lte('recorded_at', b.toUtc().toIso8601String())
            .order('recorded_at'))
        .map(BiometricReading.fromJson)
        .toList(),
  );

  @override
  Future<Result<void>> delete(String readingId) => supabaseGuard(() async {
    await _sb.from('biometric_reading').delete().eq('reading_id', readingId);
  });

  @override
  Future<Result<({bool connected, DateTime? lastSync})>> healthSourceState(
    String accountId,
  ) => supabaseGuard(() async {
    final row = await _sb
        .from('account')
        .select('health_source_connected, health_source_last_sync')
        .eq('account_id', accountId)
        .maybeSingle();
    final last = row?['health_source_last_sync'] as String?;
    return (
      connected: (row?['health_source_connected'] ?? false) as bool,
      lastSync: last == null ? null : DateTime.parse(last).toLocal(),
    );
  });

  @override
  Future<Result<void>> setHealthSourceConnected(String accountId, bool on) =>
      supabaseGuard(() async {
        await _sb
            .from('account')
            .update({
              'health_source_connected': on,
              if (!on) 'health_source_last_sync': null,
            })
            .eq('account_id', accountId);
      });

  @override
  Future<Result<void>> recordImport(String accountId, DateTime at) =>
      supabaseGuard(() async {
        await _sb
            .from('account')
            .update({
              'health_source_connected': true,
              'health_source_last_sync': at.toUtc().toIso8601String(),
            })
            .eq('account_id', accountId);
      });
}
