import 'package:physical_treatment_and_health_support_system/model/result.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/anomaly_event.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/forecast.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/health_analysis.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/analysis_repository/i_analysis_repository.dart';

class FakeAnalysisRepository implements IAnalysisRepository {
  final List<Forecast> forecasts = [];
  final List<AnomalyEvent> anomalyLog = [];
  final List<HealthAnalysis> analyses = [];

  static String _day(DateTime d) => d.toIso8601String().substring(0, 10);

  @override
  Future<Result<void>> saveForecast(Forecast f) async {
    for (var i = 0; i < forecasts.length; i++) {
      final o = forecasts[i];
      if (o.accountId == f.accountId && o.metricType == f.metricType && o.isCurrent) {
        forecasts[i] = Forecast(
          forecastId: o.forecastId,
          accountId: o.accountId,
          metricType: o.metricType,
          predictedValues: o.predictedValues,
          inputReadingCount: o.inputReadingCount,
          modelVersion: o.modelVersion,
          isCurrent: false,
          generatedAt: o.generatedAt,
        );
      }
    }
    forecasts.add(f);
    return const Success(null);
  }

  @override
  Future<Result<Forecast?>> latestForecast(String accountId, MetricType m) async =>
      Success(
        forecasts
            .where((f) => f.accountId == accountId && f.metricType == m && f.isCurrent)
            .lastOrNull,
      );

  @override
  Future<Result<void>> saveAnomaly(AnomalyEvent a) async {
    anomalyLog.add(a);
    return const Success(null);
  }

  @override
  Future<Result<List<AnomalyEvent>>> anomalies(
    String accountId,
    DateTime from,
    DateTime to,
  ) async => Success(
    anomalyLog
        .where(
          (a) =>
              a.accountId == accountId &&
              !a.detectedAt.isBefore(from) &&
              !a.detectedAt.isAfter(to),
        )
        .toList()
      ..sort((a, b) => b.detectedAt.compareTo(a.detectedAt)),
  );

  @override
  Future<Result<void>> saveAnalysis(HealthAnalysis h) async {
    analyses.removeWhere(
      (x) => x.accountId == h.accountId && _day(x.analysisDate) == _day(h.analysisDate),
    );
    analyses.add(h);
    return const Success(null);
  }

  @override
  Future<Result<HealthAnalysis?>> latestAnalysis(String accountId) async {
    final mine = analyses.where((a) => a.accountId == accountId).toList()
      ..sort((a, b) => a.analysisDate.compareTo(b.analysisDate));
    return Success(mine.lastOrNull);
  }

  @override
  Future<Result<List<HealthAnalysis>>> analysisHistory(
    String accountId,
    DateTime from,
    DateTime to,
  ) async => Success(
    analyses
        .where(
          (a) =>
              a.accountId == accountId &&
              _day(a.analysisDate).compareTo(_day(from)) >= 0 &&
              _day(a.analysisDate).compareTo(_day(to)) <= 0,
        )
        .toList()
      ..sort((a, b) => a.analysisDate.compareTo(b.analysisDate)),
  );
}
