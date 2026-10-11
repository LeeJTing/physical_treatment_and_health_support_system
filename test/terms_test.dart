// Terms of Use and Privacy Notice (11 Oct): accepted after registration and at a sign-in when the
// version changed or a guardian must agree; explicit health-data consent; delete my account.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:physical_treatment_and_health_support_system/core/constants/app_constants.dart';
import 'package:physical_treatment_and_health_support_system/core/routes/routes.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/local_notification_service/local_notification_service.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/risk_assessment_service/risk_assessment_service.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/health_profile.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/reminder.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/terms_acceptance.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/auth_repository/fake_auth_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/notification_repository/fake_notification_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/profile_repository/fake_profile_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/terms_repository/fake_terms_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/treatment_repository/fake_treatment_repository.dart';
import 'package:physical_treatment_and_health_support_system/view/login_view/terms_view.dart';
import 'package:physical_treatment_and_health_support_system/view/login_view/widgets/auth_widgets.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/auth_view_model/auth_view_model.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/profile_view_model/profile_view_model.dart';

import 'reminders_test.dart' show FakeScheduler;

class Harness {
  final auth = FakeAuthRepository();
  final profiles = FakeProfileRepository();
  final terms = FakeTermsRepository();
  late final vm = AuthViewModel(auth, profiles, null, terms);

  Future<String> accountId() async => (await auth.login(
    'demo@apths.test',
    'password123',
  )).dataOrNull!.accountId;

  Future<String> profileAged(int age) async {
    final id = await accountId();
    final p = HealthProfile(
      profileId: 'p1',
      accountId: id,
      age: age,
      gender: Gender.female,
      weightKg: 50,
      heightCm: 155,
      updatedAt: DateTime.now(),
    );
    await profiles.saveProfile(p, p.generateSafetyLimit());
    await auth.signOut();
    return id;
  }

  TermsAcceptance accepted(
    String id, {
    String version = AppConstants.termsVersion,
    TermsAgeGroup group = TermsAgeGroup.adult,
  }) => TermsAcceptance(
    acceptanceId: 'x',
    accountId: id,
    termsVersion: version,
    acceptedAt: DateTime(2026, 10, 1),
    language: 'en',
    healthDataConsent: true,
    ageGroup: group,
  );
}

void main() {
  group('when the terms are asked for', () {
    test(
      'first sign-in: the terms come before the profile, and are not asked again',
      () async {
        final h = Harness();
        expect(await h.vm.login('demo@apths.test', 'password123'), isTrue);
        expect(h.vm.nextRoute, Routes.terms);
        expect(h.vm.termsReason, TermsReason.firstTime);

        expect(await h.vm.acceptTerms(language: 'ms', minor: false), isTrue);
        expect(h.vm.nextRoute, Routes.healthProfile); // no profile yet
        final row = h.terms.rows.single;
        expect(row.termsVersion, AppConstants.termsVersion);
        expect(row.healthDataConsent, isTrue);
        expect(row.language, 'ms');
        expect(row.ageGroup, TermsAgeGroup.adult);
        expect(row.guardianName, isNull);

        await h.auth.signOut();
        await h.vm.login('demo@apths.test', 'password123');
        expect(h.vm.nextRoute, Routes.healthProfile);
        expect(h.vm.termsReason, isNull);
      },
    );

    test('a new version is accepted again at the next sign-in', () async {
      final h = Harness();
      h.terms.rows.add(h.accepted(await h.accountId(), version: '0.9'));
      await h.auth.signOut();
      await h.vm.login('demo@apths.test', 'password123');
      expect(h.vm.nextRoute, Routes.terms);
      expect(h.vm.termsReason, TermsReason.updated);
    });

    test(
      'under 18 in the profile but accepted as an adult: a guardian must agree',
      () async {
        final h = Harness();
        h.terms.rows.add(h.accepted(await h.profileAged(15)));
        await h.vm.login('demo@apths.test', 'password123');
        expect(h.vm.termsReason, TermsReason.guardianNeeded);
        expect(h.vm.termsProfileAge, 15);

        expect(
          await h.vm.acceptTerms(
            language: 'en',
            minor: true,
            guardianName: ' Tan Mei Ling ',
            guardianRelationship: 'PARENT',
          ),
          isTrue,
        );
        final row = h.terms.rows.last;
        expect(row.ageGroup, TermsAgeGroup.minor);
        expect(row.guardianName, 'Tan Mei Ling');
        expect(row.guardianRelationship, 'PARENT');
      },
    );

    test(
      'the patient is not locked out when the acceptances cannot be read',
      () async {
        final h = Harness();
        h.terms.failNext = true;
        await h.vm.login('demo@apths.test', 'password123');
        expect(h.vm.nextRoute, Routes.healthProfile);
      },
    );

    test(
      'a failed save keeps the patient on the terms with a message',
      () async {
        final h = Harness();
        await h.vm.login('demo@apths.test', 'password123');
        h.terms.failNext = true;
        expect(await h.vm.acceptTerms(language: 'en', minor: false), isFalse);
        expect(h.terms.rows, isEmpty);
      },
    );

    test('declining signs out', () async {
      final h = Harness();
      await h.vm.login('demo@apths.test', 'password123');
      await h.vm.declineTerms();
      expect(h.vm.nextRoute, Routes.loginScreen);
      expect((await h.auth.currentAccount()).dataOrNull, isNull);
    });
  });

  test(
    'the text: same version as the app, the same sections in English and Malay',
    () {
      final doc =
          jsonDecode(File('assets/legal/terms.json').readAsStringSync())
              as Map<String, dynamic>;
      expect(doc['version'], AppConstants.termsVersion);
      expect(doc['contact'], 'elwinksy-wm23@student.tarc.edu.my');
      final en = doc['en'] as Map<String, dynamic>,
          ms = doc['ms'] as Map<String, dynamic>;
      expect((ms['ui'] as Map).keys.toSet(), (en['ui'] as Map).keys.toSet());
      final es = en['sections'] as List, mss = ms['sections'] as List;
      expect(mss.length, es.length);
      for (var i = 0; i < es.length; i++) {
        expect(
          (mss[i]['paragraphs'] as List).length,
          (es[i]['paragraphs'] as List).length,
        );
      }
      final all = jsonEncode(en);
      for (final must in [
        '13 or older',
        'under 65',
        'Singapore',
        '72 hours',
        '7 days',
        '2 years',
        'Delete my account',
        'Personal Data Protection Act 2010',
        '999',
      ]) {
        expect(all, contains(must));
      }
    },
  );

  testWidgets(
    'the screen: age group, guardian for 13 to 17, two separate ticks, Malay',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 6000);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final h = Harness();
      await tester.runAsync(() async {
        await rootBundle.loadString(
          'assets/legal/terms.json',
        ); // cached for the screen
        await h.vm.login('demo@apths.test', 'password123');
      });
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: h.vm,
          child: MaterialApp(
            routes: {
              '/': (_) => const TermsView(),
              Routes.healthProfile: (_) => const Text('route:profile'),
            },
          ),
        ),
      );
      // The cached text future was made in real time (runAsync above), so the
      // screen's await resumes on the real event loop: let it run once.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Terms of Use and Privacy Notice'), findsOneWidget);
      // The screen is a ListView with the whole legal text, built lazily: a
      // widget far up or down is not in the tree until scrolled to.
      final list = find.byType(Scrollable).first;
      Future<void> reveal(Finder f) async {
        if (f.evaluate().isEmpty) {
          try {
            await tester.scrollUntilVisible(f, 600, scrollable: list);
          } on StateError {
            await tester.scrollUntilVisible(f, -600, scrollable: list);
          }
        }
        await tester.ensureVisible(f);
        await tester.pumpAndSettle();
      }

      final acceptButton = find.widgetWithText(
        PillButton,
        'Agree and continue',
      );
      Future<PillButton> accept() async {
        await reveal(acceptButton);
        return tester.widget<PillButton>(acceptButton);
      }

      expect((await accept()).onPressed, isNull);

      Future<void> tap(Finder f) async {
        await reveal(f);
        await tester.tap(f);
        await tester.pumpAndSettle();
      }

      await tap(find.text('13 to 17'));
      expect(find.text('Parent or guardian'), findsOneWidget);
      await tap(find.byKey(const Key('agree_terms')));
      await tap(find.byKey(const Key('consent_health')));
      expect(
        (await accept()).onPressed,
        isNull,
      ); // the guardian has not agreed yet
      await reveal(find.byType(TextFormField));
      await tester.enterText(find.byType(TextFormField), 'Tan Mei Ling');
      await tap(find.text('Parent'));
      await tap(find.byKey(const Key('guardian_declaration')));
      expect((await accept()).onPressed, isNotNull);

      await tap(find.text('Bahasa Melayu'));
      await reveal(find.text('Terma Penggunaan dan Notis Privasi'));
      expect(find.text('Terma Penggunaan dan Notis Privasi'), findsOneWidget);
      await tap(find.text('Setuju dan teruskan'));
      expect(find.text('route:profile'), findsOneWidget);
      final row = h.terms.rows.single;
      expect(
        [row.language, row.ageGroup, row.guardianRelationship],
        ['ms', TermsAgeGroup.minor, 'PARENT'],
      );
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'delete my account: the phone\'s reminders are cancelled, the account is gone',
    () async {
      final auth = FakeAuthRepository();
      final profiles = FakeProfileRepository();
      final notes = FakeNotificationRepository();
      final device = FakeScheduler();
      final local = LocalNotificationService(
        notes,
        FakeTreatmentRepository(const []),
        scheduler: device,
        now: () => DateTime(2026, 10, 12, 7),
      );
      final id = (await auth.login(
        'demo@apths.test',
        'password123',
      )).dataOrNull!.accountId;
      final r = Reminder(
        reminderId: 'r1',
        accountId: id,
        reminderType: ReminderType.healthLog,
        title: 'Log your readings',
        hour: 9,
        minute: 0,
      );
      await notes.saveReminder(r);
      await local.schedule(r);
      expect(device.pending, isNotEmpty);

      final vm = ProfileViewModel(
        profiles,
        auth,
        RiskAssessmentService(auth, profiles),
        local,
      );
      await vm.loadProfile();
      expect(await vm.deleteAccount(), isTrue);
      expect(device.pending, isEmpty);
      expect((await auth.currentAccount()).dataOrNull, isNull);
      expect(
        (await auth.login('demo@apths.test', 'password123')).isSuccess,
        isFalse,
      );
    },
  );
}
