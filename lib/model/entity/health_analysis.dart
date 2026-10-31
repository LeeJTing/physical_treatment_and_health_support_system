import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';

/// One factor of the Health Score (FR400_022): its 0-100 sub-score, its weight and the points
/// it adds, with a note in the patient's units.
class ScoreFactor {
  final String key;
  final String label;
  final int subScore;
  final double weight;
  final double points;
  final String note;

  const ScoreFactor({
    required this.key,
    required this.label,
    required this.subScore,
    required this.weight,
    required this.points,
    required this.note,
  });
}

/// Predicted risk for one declared condition (FR400_026 to FR400_028).
class ConditionRisk {
  final String conditionCode;
  final String conditionName;

  /// Low, Moderate or High; null when withheld.
  final String? risk;
  final bool withheld;
  final List<String> topFactors;

  /// Why it is withheld (M9: "A risk indication for [condition] needs [metric] readings.").
  final String? message;

  const ConditionRisk({
    required this.conditionCode,
    required this.conditionName,
    this.risk,
    this.withheld = false,
    this.topFactors = const [],
    this.message,
  });
}

/// The daily Health Score and the per-condition risk prediction that goes with it (Table 4.43;
/// FR400_020 to FR400_029). One row per patient per day, rewritten whenever a reading, an exercise
/// session or a meal is recorded (FR400_024, FR400_030).
class HealthAnalysis {
  final String analysisId;
  final String accountId;
  final DateTime analysisDate;

  /// Null when the feature set is too sparse (FR400_021).
  final int? healthScore;
  final ScoreBand? scoreBand;
  final Map<String, dynamic>? factorContributions;

  /// Per declared condition: risk, top three factors, model version and input window (FR400_029).
  final Map<String, dynamic>? conditionRisks;
  final PeriodComparison? periodComparison;
  final String? summaryText;
  final String modelVersion;

  /// What a withheld score still needs, as the server lists it ("2 more readings"). Not stored:
  /// a stored withheld row shows the general M8 message.
  final List<String> missingData;

  const HealthAnalysis({
    required this.analysisId,
    required this.accountId,
    required this.analysisDate,
    this.healthScore,
    this.scoreBand,
    this.factorContributions,
    this.conditionRisks,
    this.periodComparison,
    this.summaryText,
    required this.modelVersion,
    this.missingData = const [],
  });

  /// Maps a score onto its band (C12, FR400_023).
  static ScoreBand bandFor(int score) => ScoreBand.forScore(score);

  /// True when the feature set is too sparse to score (FR400_021).
  bool isWithheld() => healthScore == null;

  /// Factors, the largest contribution first (FR400_022).
  List<ScoreFactor> factors() {
    final f = factorContributions ?? const {};
    final out = <ScoreFactor>[
      for (final e in f.entries)
        if (e.value is Map)
          ScoreFactor(
            key: e.key,
            label: (e.value['label'] ?? e.key) as String,
            subScore: ((e.value['sub_score'] ?? 0) as num).toInt(),
            weight: ((e.value['weight'] ?? 0) as num).toDouble(),
            points: ((e.value['points'] ?? 0) as num).toDouble(),
            note: (e.value['note'] ?? '') as String,
          ),
    ];
    out.sort((a, b) => b.points.compareTo(a.points));
    return out;
  }

  /// Factors contributing most to the score (FR400_022).
  List<String> topFactors() => factors().take(3).map((f) => f.label).toList();

  /// Every declared condition's prediction (keys starting with "_" are bookkeeping).
  List<ConditionRisk> risks() {
    final r = conditionRisks ?? const {};
    return [
      for (final e in r.entries)
        if (!e.key.startsWith('_') && e.value is Map)
          ConditionRisk(
            conditionCode: e.key,
            conditionName: (e.value['condition_name'] ?? e.key) as String,
            risk: e.value['risk'] as String?,
            withheld: (e.value['withheld'] ?? false) as bool,
            topFactors: ((e.value['top_factors'] as List?) ?? const [])
                .cast<String>(),
            message: e.value['message'] as String?,
          ),
    ];
  }

  /// Predicted risk for one declared condition (FR400_026).
  String? riskFor(String conditionCode) =>
      risks().where((r) => r.conditionCode == conditionCode).firstOrNull?.risk;

  Map<String, dynamic> toJson() => {
    'analysis_id': analysisId,
    'account_id': accountId,
    'analysis_date': analysisDate.toIso8601String().substring(0, 10),
    'health_score': healthScore,
    'score_band': scoreBand?.db,
    'factor_contributions': factorContributions,
    'condition_risks': conditionRisks,
    'period_comparison': periodComparison?.db,
    'summary_text': summaryText,
    'model_version': modelVersion,
  };

  factory HealthAnalysis.fromJson(Map<String, dynamic> j) => HealthAnalysis(
    analysisId: j['analysis_id'] as String,
    accountId: j['account_id'] as String,
    analysisDate: DateTime.parse(j['analysis_date'] as String),
    healthScore: (j['health_score'] as num?)?.toInt(),
    scoreBand: ScoreBand.fromDb(j['score_band'] as String?),
    factorContributions: j['factor_contributions'] == null
        ? null
        : Map<String, dynamic>.from(j['factor_contributions'] as Map),
    conditionRisks: j['condition_risks'] == null
        ? null
        : Map<String, dynamic>.from(j['condition_risks'] as Map),
    periodComparison: PeriodComparison.fromDb(j['period_comparison'] as String?),
    summaryText: j['summary_text'] as String?,
    modelVersion: j['model_version'] as String,
  );
}
