/// Who agreed: an adult, or a user aged 13 to 17 together with a parent or
/// guardian (Contracts Act 1950 s.11; PDP Regulations 2013).
enum TermsAgeGroup {
  adult('ADULT'),
  minor('MINOR');

  final String db;
  const TermsAgeGroup(this.db);
  static TermsAgeGroup fromDb(String? s) =>
      values.firstWhere((v) => v.db == s, orElse: () => adult);
}

/// One acceptance of the Terms of Use and Privacy Notice (table
/// terms_acceptance, 11 Oct; not in the Chapter 4 ERD). Kept as a record:
/// a new version adds a row, nothing is updated. The health-data consent is
/// a separate, explicit consent (PDPA 2010 s.40).
class TermsAcceptance {
  final String acceptanceId;
  final String accountId;
  final String termsVersion;
  final DateTime acceptedAt;
  final String language; // en | ms
  final bool healthDataConsent;
  final TermsAgeGroup ageGroup;
  final String? guardianName;
  final String? guardianRelationship; // PARENT | GUARDIAN

  const TermsAcceptance({
    required this.acceptanceId,
    required this.accountId,
    required this.termsVersion,
    required this.acceptedAt,
    required this.language,
    required this.healthDataConsent,
    required this.ageGroup,
    this.guardianName,
    this.guardianRelationship,
  });

  factory TermsAcceptance.fromJson(Map<String, dynamic> j) => TermsAcceptance(
    acceptanceId: j['acceptance_id'] as String,
    accountId: j['account_id'] as String,
    termsVersion: j['terms_version'] as String,
    acceptedAt: DateTime.parse(j['accepted_at'] as String),
    language: j['language'] as String? ?? 'en',
    healthDataConsent: j['health_data_consent'] as bool? ?? false,
    ageGroup: TermsAgeGroup.fromDb(j['age_group'] as String?),
    guardianName: j['guardian_name'] as String?,
    guardianRelationship: j['guardian_relationship'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'acceptance_id': acceptanceId,
    'account_id': accountId,
    'terms_version': termsVersion,
    'accepted_at': acceptedAt.toUtc().toIso8601String(),
    'language': language,
    'health_data_consent': healthDataConsent,
    'age_group': ageGroup.db,
    'guardian_name': guardianName,
    'guardian_relationship': guardianRelationship,
  };
}
