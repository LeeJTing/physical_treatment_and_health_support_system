// Health conditions added on 11 Oct: 17 conditions, a status question for some, a doctor's OK before
// a plan for some, a per-condition risk rule, and exercise positions the AI server can rule out.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:physical_treatment_and_health_support_system/core/constants/app_constants.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/recommendation_service/recommendation.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/recommendation_service/recommendation_service.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/risk_assessment_service/risk_assessment_service.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/exercise.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/health_profile.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/lookups.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/rehab_info.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/auth_repository/fake_auth_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/notification_repository/fake_notification_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/profile_repository/fake_profile_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/treatment_repository/fake_treatment_repository.dart';
import 'package:physical_treatment_and_health_support_system/shared_client/api_client/api_client.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/planning_view_model/planning_view_model.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/profile_view_model/profile_view_model.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/ui_state.dart';

HealthCondition seed(String code, {bool controlled = true}) => LookupSeed.conditions
    .firstWhere((c) => c.conditionCode == code)
    .withStatus(controlled: controlled);

HealthProfile profileWith(List<HealthCondition> conditions, {int age = 40}) => HealthProfile(
  profileId: 'p1',
  accountId: 'a1',
  age: age,
  gender: Gender.female,
  weightKg: 60,
  heightCm: 160,
  conditions: conditions,
  updatedAt: DateTime(2026, 10, 1),
);

void main() {
  test('the app list matches supabase/seed/seed_lookups.sql', () {
    final sql = File('supabase/seed/seed_lookups.sql').readAsStringSync();
    final row = RegExp(
      r"\((\d+),\s*'([A-Z_]+)',\s*'((?:[^']|'')*)',\s*'([A-Z]+)',\s*(null|'((?:[^']|'')*)'),\s*(true|false)\)",
    );
    final rows = row.allMatches(sql).toList();
    expect(rows, hasLength(LookupSeed.conditions.length));
    for (final m in rows) {
      final c = LookupSeed.conditions.firstWhere(
        (c) => c.conditionId == int.parse(m.group(1)!),
      );
      expect(c.conditionCode, m.group(2));
      expect(c.conditionName, m.group(3)!.replaceAll("''", "'"));
      expect(c.category.db, m.group(4));
      expect(c.statusQuestion, m.group(6)?.replaceAll("''", "'"));
      expect(c.needsClearance, m.group(7) == 'true');
    }
  });

  group('risk level', () {
    test('one controlled condition is medium; not controlled is high', () {
      expect(profileWith([seed('ARTHRITIS')]).assignRiskLevel(), RiskLevel.medium);
      expect(
        profileWith([seed('ARTHRITIS', controlled: false)]).assignRiskLevel(),
        RiskLevel.high,
      );
    });

    test('neurological and cardiovascular conditions are always high', () {
      expect(profileWith([seed('PARKINSONS')]).assignRiskLevel(), RiskLevel.high);
      expect(profileWith([seed('HYPERTENSION')]).assignRiskLevel(), RiskLevel.high);
    });

    test('two conditions are high, as in the report', () {
      expect(
        profileWith([seed('ASTHMA'), seed('KIDNEY_DISEASE')]).assignRiskLevel(),
        RiskLevel.high,
      );
    });
  });

  test('a doctor\'s OK holds back plans only where it is needed', () {
    expect(seed('ASTHMA', controlled: false).blocksPlans, isTrue);
    expect(seed('ARTHRITIS', controlled: false).blocksPlans, isFalse);
    expect(PlanRestriction.forProfile(profileWith([seed('ASTHMA', controlled: false)])),
        PlanRestriction.clearanceNeeded);
    expect(PlanRestriction.forProfile(profileWith([seed('ASTHMA')])), isNull);
    // The age limit comes first.
    expect(PlanRestriction.forProfile(profileWith([seed('ASTHMA', controlled: false)], age: 70)),
        PlanRestriction.age65Plus);
  });

  test('every catalogue exercise has a body position for the AI server', () {
    final cat = jsonDecode(File('assets/seed/catalogue.json').readAsStringSync()) as Map<String, dynamic>;
    final exercises = [for (final e in cat['exercises'] as List) Exercise.fromJson(e as Map<String, dynamic>)];
    expect(exercises.every((e) => e.bodyPosition != null), isTrue);
    expect(exercises.firstWhere((e) => e.poseKey == 'glute_bridge').toJson()['body_position'], 'SUPINE');
  });

  group('planning', () {
    test('a condition waiting for a doctor\'s OK: no plan is requested, the conditions are named', () async {
      final calls = <http.Request>[];
      final auth = FakeAuthRepository();
      final profiles = FakeProfileRepository();
      final id = (await auth.login('demo@apths.test', 'password123')).dataOrNull!.accountId;
      final p = HealthProfile(
        profileId: 'p1',
        accountId: id,
        age: 40,
        gender: Gender.female,
        weightKg: 60,
        heightCm: 160,
        conditions: [seed('COPD', controlled: false), seed('ARTHRITIS')],
        updatedAt: DateTime.now(),
      );
      await profiles.saveProfile(p, p.generateSafetyLimit());
      final vm = PlanningViewModel(
        FakeTreatmentRepository.fromJson(File('assets/seed/catalogue.json').readAsStringSync()),
        RecommendationService(ApiClient(
          baseUrl: 'http://ai',
          tokenProvider: () => 'dev-token',
          httpClient: MockClient((r) async {
            calls.add(r);
            return http.Response('{}', 500);
          }),
        )),
        RiskAssessmentService(auth, profiles),
        FakeNotificationRepository(),
      );
      expect(await vm.checkRestriction(), PlanRestriction.clearanceNeeded);
      expect(vm.conditionsNeedingClearance.map((c) => c.conditionCode), ['COPD']);
      await vm.recommend(const RehabInfo(
        affectedBodyArea: 'BOTH_LEGS',
        recoveryStage: RecoveryStage.early,
        mobilityLevel: MobilityLevel.low,
        goal: 'MOBILITY',
      ));
      final r = (vm.recommendation as UiSuccess<Recommendation>).data;
      expect(r.restriction, PlanRestriction.clearanceNeeded);
      expect(calls, isEmpty);
    });
  });

  group('profile answers', () {
    late FakeAuthRepository auth;
    late FakeProfileRepository profiles;
    late ProfileViewModel vm;

    setUp(() async {
      auth = FakeAuthRepository();
      profiles = FakeProfileRepository();
      await auth.login('demo@apths.test', 'password123');
      vm = ProfileViewModel(profiles, auth, RiskAssessmentService(auth, profiles));
      await vm.loadProfile();
      vm.updateDraft(age: 40, gender: Gender.female, weightKg: 60, heightCm: 160);
    });

    test('a condition with a question must be answered before saving', () async {
      vm.toggleCondition(7); // ASTHMA
      expect(vm.unansweredConditions, {7});
      expect(await vm.saveProfile(), isFalse);
      expect((vm.saveState as UiError).message, Messages.conditionQuestionUnanswered);
      vm.setConditionControlled(7, false);
      expect(await vm.saveProfile(), isTrue);
      final saved = vm.profile!.conditions.single;
      expect([saved.conditionCode, saved.controlled, saved.blocksPlans], ['ASTHMA', false, true]);
      expect(vm.profile!.assignRiskLevel(), RiskLevel.high);
    });

    test('a condition without a question needs no answer', () async {
      vm.toggleCondition(6); // OSTEOPOROSIS
      expect(vm.unansweredConditions, isEmpty);
      expect(await vm.saveProfile(), isTrue);
    });

    test('"Other" must say what the condition is', () async {
      vm.toggleCondition(17);
      vm.setConditionControlled(17, true);
      expect(await vm.saveProfile(), isFalse);
      expect((vm.saveState as UiError).message, Messages.otherConditionNote);
      vm.setConditionNote(17, ' Lupus ');
      expect(await vm.saveProfile(), isTrue);
      expect(vm.profile!.conditions.single.note, 'Lupus');
    });

    test('changing only an answer counts as an unsaved change', () async {
      vm.toggleCondition(5); // ARTHRITIS
      vm.setConditionControlled(5, true);
      await vm.saveProfile();
      vm.startEdit();
      expect(vm.hasUnsavedChanges, isFalse);
      vm.setConditionControlled(5, false);
      expect(vm.hasUnsavedChanges, isTrue);
    });
  });
}
