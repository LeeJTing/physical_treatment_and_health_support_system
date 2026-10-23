// "My treatment plan" says when the plan being followed no longer fits the profile, as Home
// does (audit, 23 Oct): before, only Home's first notice said so.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:physical_treatment_and_health_support_system/core/utils/id_utils.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/risk_assessment_service/risk_assessment_service.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/health_profile.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/lookups.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/profile_repository/fake_profile_repository.dart';
import 'package:physical_treatment_and_health_support_system/view/treatment_view/treatment_view.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/treatment_view_model/treatment_view_model.dart';

import 'treatment_test.dart' show Harness;

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('apths'));
  tearDown(() => tmp.deleteSync(recursive: true));

  Future<TreatmentViewModel> withProfile(
    Harness h,
    List<HealthCondition> conditions,
  ) async {
    await h.setUp(tmp);
    final profiles = FakeProfileRepository();
    final p = HealthProfile(
      profileId: newId(),
      accountId: h.vm.activePlan!.accountId,
      age: 50,
      gender: Gender.female,
      weightKg: 60,
      heightCm: 160,
      conditions: conditions,
      updatedAt: DateTime.now(),
    );
    await profiles.saveProfile(p, p.generateSafetyLimit());
    final vm = TreatmentViewModel(
      h.treatments,
      h.pose,
      h.auth,
      null,
      null,
      RiskAssessmentService(h.auth, profiles),
    );
    await vm.loadPlan();
    return vm;
  }

  final heart = LookupSeed.conditions
      .firstWhere((c) => c.needsClearance)
      .withStatus(controlled: false);

  test('a condition waiting for a doctor OK is listed for the plan', () async {
    final vm = await withProfile(Harness(), [heart]);
    expect(vm.planIssues.map((i) => i.code), contains('clearance_now'));
  });

  test('nothing when the plan still fits', () async {
    final vm = await withProfile(Harness(), const []);
    expect(vm.planIssues, isEmpty);
  });

  testWidgets('the warning is shown above the progress', (tester) async {
    tester.view.physicalSize = const Size(1080, 4800);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final h = Harness();
    late TreatmentViewModel vm;
    await tester.runAsync(() async => vm = await withProfile(h, [heart]));
    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider.value(
          value: vm,
          child: const TreatmentView(),
        ),
      ),
    );
    await tester.runAsync(
      vm.loadPlan,
    ); // the post-frame load, finished for real
    await tester.pump();
    expect(
      find.textContaining('Check with your doctor before you go on'),
      findsOneWidget,
    );
  });
}
