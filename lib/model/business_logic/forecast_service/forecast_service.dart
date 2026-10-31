import 'package:physical_treatment_and_health_support_system/core/constants/app_constants.dart';
import 'package:physical_treatment_and_health_support_system/core/utils/id_utils.dart';
import 'package:physical_treatment_and_health_support_system/model/result.dart';
import 'package:physical_treatment_and_health_support_system/shared_client/api_client/api_client.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/biometric_reading.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/forecast.dart';

/// Calls the time-series endpoint /forecast and decodes the projection (Table 4.95). Only the
/// readings leave the phone, without the account id (FR400_036); the request carries the session
/// token (FR400_037) and is abandoned after 30 s (FR400_038).
class ForecastService {
  final ApiClient _api;

  /// Below this the forecast is withheld (FR400_003).
  final int minReadings = AppConstants.forecastMinReadings;

  ForecastService(this._api);

  /// Guards the minimum sample size (FR400_003).
  bool canForecast(int readingCount) => readingCount >= minReadings;

  /// A 7-day projection from the patient's own history (FR400_002). The result keeps the model
  /// version (FR400_007); a withheld forecast has no points.
  Future<Result<Forecast>> forecast(
    String accountId,
    MetricType m,
    List<BiometricReading> history,
  ) async {
    final rs = history.where((r) => r.metricType == m).toList();
    final res = await _api.post(
      AppConstants.forecastPath,
      {
        'metric_type': m.db,
        'readings': rs.map((r) => r.toAnalysisJson()).toList(),
        'horizon_days': 7,
      },
      timeout: AppConstants.analysisTimeout,
    );
    if (res case Failure(:final code, :final cause)) {
      return Failure(Messages.analysisUnavailable, code: code, cause: cause);
    }
    final b = res.dataOrNull!;
    return Success(
      Forecast(
        forecastId: newId(),
        accountId: accountId,
        metricType: m,
        predictedValues: {
          'points': b['points'] ?? const [],
          'last_reading_date': b['last_reading_date'],
          'horizon_days': b['horizon_days'],
        },
        inputReadingCount: ((b['input_reading_count'] ?? rs.length) as num).toInt(),
        modelVersion: (b['model_version'] ?? '') as String,
        generatedAt: DateTime.now(),
      ),
    );
  }
}
