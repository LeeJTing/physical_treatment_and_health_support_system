import 'package:physical_treatment_and_health_support_system/model/result.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/anomaly_event.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/forecast.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/health_analysis.dart';

/// Contract for forecasts, anomalies and the daily analysis (Table 4.75).
abstract interface class IAnalysisRepository {
  /// Stores a run and supersedes the previous current one of the metric.
  Future<Result<void>> saveForecast(Forecast f);

  /// The forecast in force, shown when regeneration fails (FR400_008, FR400_018).
  Future<Result<Forecast?>> latestForecast(String accountId, MetricType m);

  /// Appends to the anomaly history (FR400_016).
  Future<Result<void>> saveAnomaly(AnomalyEvent a);

  /// The anomaly history, newest first.
  Future<Result<List<AnomalyEvent>>> anomalies(
    String accountId,
    DateTime from,
    DateTime to,
  );

  /// Upserts the once-per-day row (FR400_024).
  Future<Result<void>> saveAnalysis(HealthAnalysis h);

  /// The newest stored analysis, shown while the service is unavailable (FR400_039).
  Future<Result<HealthAnalysis?>> latestAnalysis(String accountId);

  /// Daily scores in a range, oldest first, for the trend (FR400_025).
  Future<Result<List<HealthAnalysis>>> analysisHistory(
    String accountId,
    DateTime from,
    DateTime to,
  );
}
