import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';

/// One predicted day of a [Forecast]: the value and its band (about 80 %).
class ForecastPoint {
  final DateTime date;
  final double value;
  final double lower;
  final double upper;

  /// Diastolic, for blood pressure.
  final double? secondaryValue;

  const ForecastPoint({
    required this.date,
    required this.value,
    required this.lower,
    required this.upper,
    this.secondaryValue,
  });

  factory ForecastPoint.fromJson(Map<String, dynamic> j) => ForecastPoint(
    date: DateTime.parse(j['date'] as String),
    value: (j['value'] as num).toDouble(),
    lower: (j['lower'] as num? ?? j['value'] as num).toDouble(),
    upper: (j['upper'] as num? ?? j['value'] as num).toDouble(),
    secondaryValue: (j['secondary_value'] as num?)?.toDouble(),
  );

  Map<String, dynamic> toJson() => {
    'date': date.toIso8601String().substring(0, 10),
    'value': value,
    'lower': lower,
    'upper': upper,
    'secondary_value': secondaryValue,
  };
}

/// One generated forecast for one metric (Table 4.42; FR400_002 to FR400_008).
class Forecast {
  /// Below this many readings the forecast is withheld (UC600 C1, FR400_003).
  static const int minReadings = 14;

  final String forecastId;
  final String accountId;
  final MetricType metricType;

  /// The predicted points as stored in forecast.predicted_values (jsonb).
  final Map<String, dynamic> predictedValues;
  final int inputReadingCount;
  final String modelVersion;
  final bool isCurrent;
  final DateTime generatedAt;

  const Forecast({
    required this.forecastId,
    required this.accountId,
    required this.metricType,
    required this.predictedValues,
    required this.inputReadingCount,
    required this.modelVersion,
    this.isCurrent = true,
    required this.generatedAt,
  });

  /// True when fewer than 14 readings were available (FR400_003).
  bool isWithheld() => inputReadingCount < minReadings;

  /// Predicted values decoded for the chart (FR400_004).
  List<ForecastPoint> points() =>
      ((predictedValues['points'] as List?) ?? const [])
          .map((p) => ForecastPoint.fromJson(Map<String, dynamic>.from(p as Map)))
          .toList();

  /// How far ahead the projection runs.
  int horizonDays() => points().length;

  Map<String, dynamic> toJson() => {
    'forecast_id': forecastId,
    'account_id': accountId,
    'metric_type': metricType.db,
    'predicted_values': predictedValues,
    'input_reading_count': inputReadingCount,
    'model_version': modelVersion,
    'is_current': isCurrent,
    'generated_at': generatedAt.toUtc().toIso8601String(),
  };

  factory Forecast.fromJson(Map<String, dynamic> j) => Forecast(
    forecastId: j['forecast_id'] as String,
    accountId: j['account_id'] as String,
    metricType: MetricType.fromDb(j['metric_type'] as String?),
    predictedValues: Map<String, dynamic>.from(j['predicted_values'] as Map),
    inputReadingCount: (j['input_reading_count'] as num).toInt(),
    modelVersion: j['model_version'] as String,
    isCurrent: (j['is_current'] ?? true) as bool,
    generatedAt: DateTime.parse(j['generated_at'] as String).toLocal(),
  );
}
