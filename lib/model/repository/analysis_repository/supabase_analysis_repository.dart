import 'package:physical_treatment_and_health_support_system/model/result.dart';
import 'package:physical_treatment_and_health_support_system/shared_client/supabase_provider/supabase_provider.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/anomaly_event.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/forecast.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/health_analysis.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/analysis_repository/i_analysis_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/supabase_guard.dart';

/// Supabase implementation of IAnalysisRepository (Table 4.83).
class SupabaseAnalysisRepository implements IAnalysisRepository {
  final SupabaseProvider _sb;

  SupabaseAnalysisRepository(this._sb);

  /// Insert plus is_current flip.
  @override
  Future<Result<void>> saveForecast(Forecast f) => supabaseGuard(() async {
    await _sb
        .from('forecast')
        .update({'is_current': false})
        .eq('account_id', f.accountId)
        .eq('metric_type', f.metricType.db)
        .eq('is_current', true);
    await _sb.from('forecast').insert(f.toJson());
  });

  @override
  Future<Result<Forecast?>> latestForecast(String accountId, MetricType m) =>
      supabaseGuard(() async {
        final row = await _sb
            .from('forecast')
            .select()
            .eq('account_id', accountId)
            .eq('metric_type', m.db)
            .eq('is_current', true)
            .order('generated_at', ascending: false)
            .limit(1)
            .maybeSingle();
        return row == null ? null : Forecast.fromJson(row);
      });

  @override
  Future<Result<void>> saveAnomaly(AnomalyEvent a) => supabaseGuard(() async {
    await _sb.from('anomaly_event').insert(a.toJson());
  });

  @override
  Future<Result<List<AnomalyEvent>>> anomalies(
    String accountId,
    DateTime from,
    DateTime to,
  ) => supabaseGuard(
    () async => (await _sb
            .from('anomaly_event')
            .select()
            .eq('account_id', accountId)
            .gte('detected_at', from.toUtc().toIso8601String())
            .lte('detected_at', to.toUtc().toIso8601String())
            .order('detected_at', ascending: false))
        .map(AnomalyEvent.fromJson)
        .toList(),
  );

  /// Upsert on (account_id, analysis_date).
  @override
  Future<Result<void>> saveAnalysis(HealthAnalysis h) => supabaseGuard(() async {
    final row = h.toJson()..remove('analysis_id');
    await _sb.from('health_analysis').upsert(row, onConflict: 'account_id,analysis_date');
  });

  @override
  Future<Result<HealthAnalysis?>> latestAnalysis(String accountId) =>
      supabaseGuard(() async {
        final row = await _sb
            .from('health_analysis')
            .select()
            .eq('account_id', accountId)
            .order('analysis_date', ascending: false)
            .limit(1)
            .maybeSingle();
        return row == null ? null : HealthAnalysis.fromJson(row);
      });

  @override
  Future<Result<List<HealthAnalysis>>> analysisHistory(
    String accountId,
    DateTime from,
    DateTime to,
  ) => supabaseGuard(
    () async => (await _sb
            .from('health_analysis')
            .select()
            .eq('account_id', accountId)
            .gte('analysis_date', from.toIso8601String().substring(0, 10))
            .lte('analysis_date', to.toIso8601String().substring(0, 10))
            .order('analysis_date'))
        .map(HealthAnalysis.fromJson)
        .toList(),
  );
}
