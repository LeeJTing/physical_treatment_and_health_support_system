import 'package:physical_treatment_and_health_support_system/core/constants/app_constants.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/anomaly_detection_service/anomaly_detection_service.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/forecast_service/forecast_service.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/local_notification_service/local_notification_service.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/risk_assessment_service/risk_assessment_service.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/anomaly_event.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/biometric_reading.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/forecast.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/health_analysis.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/health_profile.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/meal_log.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/safety_limit.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/analysis_repository/i_analysis_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/auth_repository/i_auth_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/biometric_repository/i_biometric_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/meal_repository/i_meal_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/treatment_repository/activity_records.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/treatment_repository/i_treatment_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/result.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/base_view_model.dart';

/// The forecast of one metric as the report shows it: the history, and the forecast or why it is
/// withheld.
class MetricForecast {
  final MetricType metric;
  final List<BiometricReading> history;
  final Forecast? forecast;

  /// Fewer than 14 readings (A1, M2).
  final bool insufficient;

  /// The stored forecast is shown because regeneration failed (FR400_008).
  final bool stale;

  const MetricForecast({
    required this.metric,
    required this.history,
    this.forecast,
    this.insufficient = false,
    this.stale = false,
  });
}

/// Forecast, Health Score and anomaly state (Table 4.65; UC600 View Health Report). One instance
/// lives in the app shell, so Home's score card and the Health Report show the same analysis, and
/// it is run again after a reading, an exercise session or a meal is recorded (FR400_030).
class AnalysisViewModel extends BaseViewModel {
  final IAnalysisRepository _repo;
  final ForecastService _forecaster;
  final AnomalyDetectionService _detector;
  final RiskAssessmentService _risk;
  final IBiometricRepository _biometrics;
  final IMealRepository _meals;
  final ITreatmentRepository _treatments;
  final IAuthRepository _auth;
  final LocalNotificationService? _alerts;
  final DateTime Function() _now;

  AnalysisViewModel(
    this._repo,
    this._forecaster,
    this._detector,
    this._risk,
    this._biometrics,
    this._meals,
    this._treatments,
    this._auth, [
    this._alerts,
    DateTime Function()? now,
  ]) : _now = now ?? DateTime.now;

  String? _accountId;
  HealthProfile? profile;

  /// Today's score and per-condition risks.
  HealthAnalysis? analysis;
  Map<MetricType, MetricForecast> forecasts = {};

  /// Anomalies of the last 30 days, newest first (FR400_016).
  List<AnomalyEvent> anomalyHistory = const [];

  /// Anomalies found by the last run.
  List<AnomalyEvent> current = const [];

  /// 30-day baselines from the server, per metric.
  Map<String, dynamic> baselines = const {};

  /// Scores over the selected range (FR400_025).
  List<HealthAnalysis> trend = const [];
  int trendDays = 30;

  /// A High severity alert waiting for its full-screen warning (FR600_010); read with
  /// [takeHighAlert].
  AnomalyEvent? _highAlert;
  AnomalyEvent? takeHighAlert() {
    final a = _highAlert;
    _highAlert = null;
    return a;
  }

  /// E1/E2 notice shown above the report (M4, M5).
  String? notice;
  bool loaded = false;
  bool running = false;

  /// Reads the stored analysis, or the last one if the service is down (FR400_039), then runs the
  /// forecast and the analysis again (UC600 BF-2 to BF-30).
  Future<void> loadAnalysis() async {
    if (running) return;
    running = true;
    if (!loaded) setLoading(true);
    try {
      _accountId ??= (await _auth.currentAccount()).dataOrNull?.accountId;
      final id = _accountId;
      if (id == null) {
        notice = Messages.sessionExpired;
        return;
      }
      analysis ??= await _detector.lastStored(id);
      if (!loaded && analysis != null) {
        // UI first: the last stored report is shown at once while the new one is worked out.
        loaded = true;
        notifyListeners();
      }
      final snap = (await _risk.retrieve()).dataOrNull; // UC1000 (BF-8)
      profile = snap?.profile;
      final now = _now();
      final hist = await _biometrics.findBetween(id, now.subtract(const Duration(days: 120)), now);
      if (hist is Failure) {
        // E1: the cached forecasts and the last stored score.
        notice = Messages.healthRetrievalFailed;
        for (final m in MetricType.values) {
          final f = (await _repo.latestForecast(id, m)).dataOrNull;
          forecasts[m] = MetricForecast(metric: m, history: const [], forecast: f, stale: f != null);
        }
        return;
      }
      final readings = hist.dataOrNull!;
      notice = null;
      await _forecastAll(id, readings);
      final sessions = (await _treatments.completedSessions(
            id,
            now.subtract(const Duration(days: 30)),
            now,
          )).dataOrNull ??
          const <ActivityRecord>[];
      final meals = (await _meals.findMeals(id, now.subtract(const Duration(days: 30)), now)).dataOrNull ??
          const <MealLog>[];
      final out = await _detector.analyse(
        accountId: id,
        profile: profile,
        limit: snap?.safetyLimit ?? SafetyLimit.mostRestrictive(),
        history: readings,
        sessions: sessions,
        meals: meals,
        asOf: now,
      );
      final earlier = (await _repo.anomalies(id, now.subtract(const Duration(days: 30)), now)).dataOrNull ??
          const <AnomalyEvent>[];
      if (out case Success(:final data)) {
        analysis = data.analysis;
        baselines = data.baselines;
        await _repo.saveAnalysis(data.analysis); // once per day (FR400_024)
        current = data.anomalies;
        await _record(data.anomalies, earlier);
      } else {
        notice = Messages.analysisUnavailable; // E2: last forecast and score stay
      }
      anomalyHistory = (await _repo.anomalies(id, now.subtract(const Duration(days: 30)), now)).dataOrNull ??
          earlier;
      await scoreTrend(trendDays);
    } finally {
      running = false;
      loaded = true;
      setLoading(false);
    }
  }

  /// New anomalies only: one already recorded for the same reading is not alerted again.
  Future<void> _record(List<AnomalyEvent> found, List<AnomalyEvent> earlier) async {
    final seen = earlier.map((a) => a.dedupeKey()).toSet();
    for (final a in found) {
      if (!seen.add(a.dedupeKey())) continue;
      await _repo.saveAnomaly(a); // FR400_016
      await _alerts?.receiveAnomaly(a); // FR400_017, FR600_009, FR600_013
      if (a.isHighSeverity()) _highAlert ??= a; // FR600_010
    }
  }

  Future<void> _forecastAll(String id, List<BiometricReading> readings) async {
    for (final m in MetricType.values) {
      final hist = readings.where((r) => r.metricType == m).toList();
      if (!_forecaster.canForecast(hist.length)) {
        forecasts[m] = MetricForecast(metric: m, history: hist, insufficient: true); // A1
        continue;
      }
      final stored = (await _repo.latestForecast(id, m)).dataOrNull;
      // Regenerated when a reading was added or deleted since (FR400_005).
      final fresh = stored != null &&
          stored.inputReadingCount == hist.length &&
          !hist.last.recordedAt.isAfter(stored.generatedAt) &&
          _now().difference(stored.generatedAt) < const Duration(hours: 24);
      if (fresh) {
        forecasts[m] = MetricForecast(metric: m, history: hist, forecast: stored);
        continue;
      }
      final f = await _forecaster.forecast(id, m, hist);
      if (f case Success(:final data)) {
        await _repo.saveForecast(data); // FR400_007: with its model version
        forecasts[m] = MetricForecast(metric: m, history: hist, forecast: data);
      } else {
        notice = Messages.analysisUnavailable; // E2
        forecasts[m] = MetricForecast(metric: m, history: hist, forecast: stored, stale: stored != null);
      }
    }
  }

  /// Regenerates one metric after a reading changes (FR400_005).
  Future<void> refreshForecast(MetricType m) async {
    final id = _accountId;
    if (id == null) return;
    final now = _now();
    final hist = (await _biometrics.findBetween(id, now.subtract(const Duration(days: 120)), now))
            .dataOrNull ??
        const <BiometricReading>[];
    await _forecastAll(id, hist);
    notifyListeners();
  }

  /// Runs detection and forwards new events to M600 (FR400_017).
  Future<List<AnomalyEvent>> detectAnomalies() async {
    await loadAnalysis();
    return current;
  }

  /// True while the score trend of another range is being read.
  bool trendLoading = false;

  /// Score history for the trend (FR400_025). The chosen range is selected at once.
  Future<List<HealthAnalysis>> scoreTrend(int days) async {
    final id = _accountId;
    if (id == null) return const [];
    trendDays = days;
    trendLoading = true;
    notifyListeners();
    final now = _now();
    trend = (await _repo.analysisHistory(id, now.subtract(Duration(days: days - 1)), now)).dataOrNull ??
        const [];
    trendLoading = false;
    notifyListeners();
    return trend;
  }

  /// The newest reading of a metric, for Home's vitals.
  BiometricReading? latest(MetricType m) {
    final h = forecasts[m]?.history ?? const <BiometricReading>[];
    return h.isEmpty ? null : h.last;
  }

  /// Baseline range text from the server ("128-140 mmHg") or null.
  /// The forecast in words (FR400_004): where the metric is expected to be over the next 7 days,
  /// the likely range, whether it is heading up or down against the last 7 days, and whether the
  /// top of the range reaches a high reading (140 mmHg systolic, 10 mmol/L glucose). Null when
  /// there is no forecast.
  String? forecastSummary(MetricType m) {
    final mf = forecasts[m];
    final pts = mf?.forecast?.points() ?? const <ForecastPoint>[];
    if (pts.isEmpty) return null;
    final dp = m == MetricType.bloodPressure ? 0 : 1;
    String v(double x) => x.toStringAsFixed(dp);
    final end = pts.last;
    final lo = pts.map((p) => p.lower).reduce((a, b) => a < b ? a : b);
    final hi = pts.map((p) => p.upper).reduce((a, b) => a > b ? a : b);
    final mean = pts.map((p) => p.value).reduce((a, b) => a + b) / pts.length;
    final hist = mf!.history;
    final cut = _now().subtract(const Duration(days: 7));
    final week = hist.where((r) => r.recordedAt.isAfter(cut)).map((r) => r.primaryValue).toList();
    final step = switch (m) {
      MetricType.bloodPressure => 3.0,
      MetricType.bloodGlucose => 0.5,
      MetricType.bodyWeight => 0.5,
    };
    var trend = '';
    if (week.isNotEmpty) {
      final now = week.reduce((a, b) => a + b) / week.length;
      final d = end.value - now;
      trend = d > step
          ? ' It is heading up from about ${v(now)} this week.'
          : d < -step
          ? ' It is heading down from about ${v(now)} this week.'
          : ' It is expected to stay about where it is this week.';
    }
    final label = m == MetricType.bloodPressure ? 'systolic blood pressure' : m.label.toLowerCase();
    final bp = m == MetricType.bloodPressure && end.secondaryValue != null
        ? ' (diastolic about ${v(end.secondaryValue!)})'
        : '';
    final high = switch (m) {
      MetricType.bloodPressure => 140.0,
      MetricType.bloodGlucose => 10.0,
      MetricType.bodyWeight => double.infinity,
    };
    final warn = hi >= high
        ? ' On some days it may reach ${v(high)} ${m.unit} or more: keep taking your readings and follow your care plan.'
        : '';
    return 'Next 7 days: your $label is expected to be about ${v(mean)} ${m.unit}$bp, most likely between '
        '${v(lo)} and ${v(hi)}.$trend$warn';
  }

  String? usualRange(MetricType m) {
    final b = baselines[m.db];
    if (b is! Map) return null;
    final mean = (b['mean'] as num).toDouble();
    final sd = (b['sd'] as num).toDouble();
    final f = m == MetricType.bloodGlucose || m == MetricType.bodyWeight ? 1 : 0;
    return '${(mean - sd).toStringAsFixed(f)}-${(mean + sd).toStringAsFixed(f)} ${m.unit}';
  }
}
