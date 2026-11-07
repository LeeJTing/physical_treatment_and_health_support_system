import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import 'package:physical_treatment_and_health_support_system/core/routes/routes.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/ui_state.dart';
import 'package:physical_treatment_and_health_support_system/core/constants/app_constants.dart';
import 'package:physical_treatment_and_health_support_system/shared_client/api_client/api_client.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/chatbot_service/chatbot_service.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/risk_assessment_service/risk_assessment_service.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/health_profile.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/lookups.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/patient_treatment_plan.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/auth_repository/fake_auth_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/profile_repository/fake_profile_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/treatment_repository/fake_treatment_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/chatbot_service/chat_reply.dart';
import 'package:physical_treatment_and_health_support_system/view/planning_view/chat_view.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/chat_view_model/chat_view_model.dart';

final String catalogueJson = File(
  'assets/seed/catalogue.json',
).readAsStringSync();

/// Stand-in for /chat: records what the app sends and answers like the real server.
class FakeChatServer {
  final List<Map<String, dynamic>> asked = [];
  bool categoriesFail = false;

  /// While set, /chat waits for it before answering.
  Completer<void>? hold;
  static const cats = [
    {'key': 'plan_exercises', 'title': 'What is in my plan'},
    {'key': 'pain_or_discomfort', 'title': 'Pain or discomfort'},
  ];

  late final client = MockClient((req) async {
    if (req.url.path.endsWith('/chat/categories')) {
      if (categoriesFail) {
        return http.Response(
          '{"error":{"code":"error","message":"down"}}',
          500,
        );
      }
      return http.Response(
        jsonEncode({
          'plan_id': req.url.queryParameters['plan_id'],
          'categories': cats,
          'rules_version': 'test',
        }),
        200,
      );
    }
    final body = jsonDecode(req.body) as Map<String, dynamic>;
    asked.add(body);
    await hold?.future;
    final text = (body['text'] ?? '') as String;
    if (text.contains('France')) {
      return http.Response(
        jsonEncode({
          'answer': Messages.questionNotRecognised,
          'category': null,
          'title': null,
          'is_matched': false,
          'matched_by': null,
          'follow_ups': [],
          'notes': [],
          'categories': cats,
          'rules_version': 'test',
        }),
        200,
      );
    }
    final pain = text.contains('hurt');
    // Answers that name two screens carry two buttons (chat-rules-3.48).
    final buttons = text.contains('password')
        ? [
            {'key': 'open_profile', 'label': 'Open Profile'},
            {'key': 'open_reset_password', 'label': 'Reset by email'},
          ]
        : text.contains('two plans')
        ? [
            {'key': 'open_planning', 'label': 'Open treatment planning'},
            {'key': 'open_treatment', 'label': 'Open my treatment plan'},
          ]
        : const <Map<String, String>>[];
    return http.Response(
      jsonEncode({
        'answer': pain
            ? 'Some soreness is normal.\n\nBecause you have high blood pressure: breathe out.'
            : 'Your plan has 3 exercises.',
        'category': pain
            ? 'pain_or_discomfort'
            : (body['category'] ?? 'plan_exercises'),
        'title': 'x',
        'is_matched': true,
        'matched_by': body['category'] != null ? 'category' : 'keyword',
        'follow_ups': pain
            ? [
                {'key': 'pain_mild', 'title': 'Mild soreness or tiredness'},
              ]
            : [],
        'notes': pain
            ? ['Because you have high blood pressure: breathe out.']
            : [],
        'categories': cats,
        'rules_version': 'test',
        'actions': buttons,
      }),
      200,
    );
  });
}

class Harness {
  final server = FakeChatServer();
  final auth = FakeAuthRepository();
  final profiles = FakeProfileRepository();
  final treatments = FakeTreatmentRepository.fromJson(catalogueJson);
  late final ChatViewModel vm = ChatViewModel(
    ChatbotService(
      ApiClient(
        baseUrl: 'http://ai',
        tokenProvider: () => 'dev-token',
        httpClient: server.client,
      ),
      now: () => DateTime(2026, 10, 7, 23, 40), // late at night on the phone
    ),
    RiskAssessmentService(auth, profiles),
    treatments,
  );

  Future<void> signInWithPlan() async {
    final account = (await auth.login(
      'demo@apths.test',
      'password123',
    )).dataOrNull!;
    final p = HealthProfile(
      profileId: 'p1',
      accountId: account.accountId,
      age: 66,
      gender: Gender.female,
      weightKg: 60,
      heightCm: 155,
      conditions: [LookupSeed.conditions.first], // HYPERTENSION
      updatedAt: DateTime.now(),
    );
    await profiles.saveProfile(p, p.generateSafetyLimit());
    final plan = (await treatments.getCatalogue()).dataOrNull!.first;
    await treatments.assignPlan(
      PatientTreatmentPlan(
        patientPlanId: 'pp1',
        accountId: account.accountId,
        plan: plan,
        selectedAt: DateTime.now(),
      ),
    );
  }
}

void main() {
  group('ChatViewModel', () {
    test(
      'loads the categories of the patient\'s active plan (FR500_18)',
      () async {
        final h = Harness();
        await h.signInWithPlan();
        await h.vm.loadCategories();
        expect(h.vm.categories, isA<UiSuccess<List<ChatCategory>>>());
        expect(h.vm.planId, isNotNull);
        expect(h.vm.messages.single.message.messageText, ChatViewModel.welcome);
      },
    );

    test(
      'sends plan, conditions and risk level with each question (Table 4.2.2)',
      () async {
        final h = Harness();
        await h.signInWithPlan();
        await h.vm.loadCategories();
        await h.vm.ask('my knee hurts');
        final sent = h.server.asked.single;
        expect(sent['plan_id'], h.vm.planId);
        expect(sent['conditions'], ['HYPERTENSION']);
        expect(
          sent['risk_level'],
          'High',
        ); // a cardiovascular condition gives High risk
        final reply = h.vm.messages.last.reply!;
        expect(reply.followUps.single.key, 'pain_mild');
        expect(reply.mainAnswer, 'Some soreness is normal.');
        expect(reply.notes, hasLength(1));
      },
    );

    test('stores both sides of each turn as chat_message rows', () async {
      final h = Harness();
      await h.signInWithPlan();
      await h.vm.loadCategories();
      await h.vm.ask('what is the capital of France');
      expect(h.treatments.chat, hasLength(2));
      expect(h.treatments.chat.first.sender, MessageSender.patient);
      expect(
        h.treatments.chat.every((m) => !m.isMatched),
        isTrue,
      ); // unmatched -> backlog (Table 4.99)
      expect(h.treatments.chat.every((m) => m.patientPlanId == 'pp1'), isTrue);
      expect(
        h.vm.messages.last.message.messageText,
        Messages.questionNotRecognised,
      );
    });

    test('a tapped category is sent as a category, not as text', () async {
      final h = Harness();
      await h.signInWithPlan();
      await h.vm.loadCategories();
      await h.vm.choose(
        const ChatCategory('plan_exercises', 'What is in my plan'),
      );
      expect(h.server.asked.single['category'], 'plan_exercises');
      expect(h.server.asked.single.containsKey('text'), isFalse);
      expect(h.vm.messages[1].message.messageText, 'What is in my plan');
    });

    test(
      'category loading failure shows the M5 message with retry (UC400 E3)',
      () async {
        final h = Harness()..server.categoriesFail = true;
        await h.signInWithPlan();
        await h.vm.loadCategories();
        expect(h.vm.categoriesFailed, isTrue);
        expect(h.vm.categoriesError, Messages.dbUnavailable);
        h.server.categoriesFail = false;
        await h.vm.retry();
        expect(h.vm.categoriesFailed, isFalse);
      },
    );

    test('empty input is ignored', () async {
      final h = Harness();
      await h.signInWithPlan();
      await h.vm.loadCategories();
      await h.vm.ask('   ');
      expect(h.server.asked, isEmpty);
    });
  });

  testWidgets(
    'ChatView shows topics, answers, follow-ups and the exit button',
    (tester) async {
      final h = Harness();
      await tester.runAsync(() async {
        await h.signInWithPlan();
        await h.vm.loadCategories();
      });
      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider.value(
            value: h.vm,
            child: const ChatView(),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Chat bot'), findsOneWidget);
      // FR500_23: one way out, the back arrow (Elwin, 23 Oct: no second "Exit chatbot").
      expect(find.byTooltip('Back'), findsOneWidget);
      expect(find.text('Exit chatbot'), findsNothing);
      expect(
        find.text('Pain or discomfort'),
        findsOneWidget,
      ); // topic chip (FR500_18)
      expect(find.text(ChatViewModel.welcome), findsOneWidget);

      await tester.runAsync(() => h.vm.ask('my knee hurts'));
      await tester.pumpAndSettle();
      expect(find.text('Some soreness is normal.'), findsOneWidget);
      expect(
        find.text('Mild soreness or tiredness'),
        findsOneWidget,
      ); // decision-tree option
      expect(
        find.textContaining('high blood pressure'),
        findsOneWidget,
      ); // condition note
    },
  );

  testWidgets(
    'the send key while an answer is coming keeps the question in the box',
    (tester) async {
      final h = Harness();
      await tester.runAsync(() async {
        await h.signInWithPlan();
        await h.vm.loadCategories();
      });
      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider.value(
            value: h.vm,
            child: const ChatView(),
          ),
        ),
      );
      await tester.pump();
      h.server.hold = Completer<void>();
      final first = h.vm.ask('my knee hurts');
      await tester.pump();
      expect(h.vm.sending, isTrue);

      await tester.enterText(find.byType(TextField), 'is that normal');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pump();
      String box() =>
          tester.widget<TextField>(find.byType(TextField)).controller!.text;
      expect(box(), 'is that normal'); // before: cleared and never sent
      expect(h.server.asked, hasLength(1));

      h.server.hold!.complete();
      await tester.runAsync(() => first);
      await tester.pump();
      await tester.tap(find.byTooltip('Send'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      expect(box(), isEmpty);
      expect(h.server.asked.last['text'], 'is that normal');
    },
  );

  testWidgets('topic and follow-up chips are at least 48 px tall', (
    tester,
  ) async {
    final h = Harness();
    await tester.runAsync(() async {
      await h.signInWithPlan();
      await h.vm.loadCategories();
      await h.vm.ask('my knee hurts');
    });
    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider.value(
          value: h.vm,
          child: const ChatView(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (final chip in ['Pain or discomfort', 'Mild soreness or tiredness']) {
      final box = find.ancestor(
        of: find.text(chip),
        matching: find.byType(InkWell),
      );
      expect(tester.getSize(box.first).height, greaterThanOrEqualTo(48));
    }
  });

  testWidgets(
    'a button opens its screen above the chat, so Back returns to the chat; '
    'the screen the chat came from is not stacked twice',
    (tester) async {
      final h = Harness();
      await tester.runAsync(() async {
        await h.signInWithPlan();
        await h.vm.loadCategories();
      });
      Widget page(String text) => Scaffold(
        appBar: AppBar(),
        body: Center(child: Text(text)),
      );
      await tester.pumpWidget(
        MaterialApp(
          initialRoute: Routes.treatmentPlanning,
          routes: {
            Routes.treatmentPlanning: (c) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.of(c).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ChangeNotifierProvider.value(
                        value: h.vm,
                        child: const ChatView(
                          openedFrom: Routes.treatmentPlanning,
                        ),
                      ),
                    ),
                  ),
                  child: const Text('PLANNING PAGE'),
                ),
              ),
            ),
            Routes.healthProfile: (_) => page('PROFILE PAGE'),
            Routes.resetPassword: (_) => page('RESET PAGE'),
            Routes.physicalTreatment: (_) => page('TREATMENT PAGE'),
          },
        ),
      );
      await tester.tap(find.text('PLANNING PAGE'));
      await tester.pumpAndSettle();

      await tester.runAsync(() => h.vm.ask('how do i change my password'));
      await tester.pumpAndSettle();
      for (final (button, screen) in [
        ('Open Profile', 'PROFILE PAGE'),
        ('Reset by email', 'RESET PAGE'),
      ]) {
        await tester.tap(find.text(button));
        await tester.pumpAndSettle();
        expect(find.text(screen), findsOneWidget);
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.text('Chat bot'), findsOneWidget, reason: button);
      }

      await tester.runAsync(
        () => h.vm.ask('can i follow two plans at the same time'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open my treatment plan'));
      await tester.pumpAndSettle();
      expect(find.text('TREATMENT PAGE'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      // The chat was opened from the planning page: go back to it.
      await tester.tap(find.text('Open treatment planning'));
      await tester.pumpAndSettle();
      expect(find.text('PLANNING PAGE'), findsOneWidget);
      expect(find.text('Chat bot'), findsNothing);
    },
  );

  group('Report this answer (Elwin, 11 Oct)', () {
    test(
      'saves the question, the answer, what matched and the patient note',
      () async {
        final h = Harness();
        await h.signInWithPlan();
        await h.vm.loadCategories();
        await h.vm.ask('my knee hurts');
        final answer = h.vm.messages.last;
        expect(h.vm.canReport(answer), isTrue);
        expect(
          h.vm.canReport(h.vm.messages.first),
          isFalse,
        ); // the welcome line

        final res = await h.vm.report(
          answer,
          expected: '  I meant pain after the exercise  ',
          wantedCategory: 'pain_or_discomfort',
        );
        expect(res.isSuccess, isTrue);
        final r = h.treatments.chatReports.single;
        expect(r.questionText, 'my knee hurts');
        expect(r.answerText, answer.message.messageText);
        expect(r.answerCategory, 'pain_or_discomfort');
        expect(r.matchedBy, 'keyword');
        expect(r.expectedText, 'I meant pain after the exercise');
        expect(r.wantedCategory, 'pain_or_discomfort');
        expect(r.toJson()['status'], 'NEW');
        // Linked to the stored chat_message rows.
        expect(
          r.questionMessageId,
          h.vm.questionFor(answer)!.message.messageId,
        );
        expect(r.answerMessageId, answer.message.messageId);
        expect(
          h.treatments.chat.map((m) => m.messageId),
          containsAll([r.questionMessageId, r.answerMessageId]),
        );
        // Once per answer.
        expect(h.vm.isReported(answer), isTrue);
        expect(h.vm.canReport(answer), isFalse);
        expect((await h.vm.report(answer)).isSuccess, isFalse);
        expect(h.treatments.chatReports, hasLength(1));
      },
    );

    test(
      'an empty note is left out, and a long one is cut to 500 characters',
      () async {
        final h = Harness();
        await h.signInWithPlan();
        await h.vm.loadCategories();
        await h.vm.ask('what is in my plan');
        await h.vm.report(h.vm.messages.last, expected: '   ');
        expect(h.treatments.chatReports.single.expectedText, isNull);
        await h.vm.ask('and the reps');
        await h.vm.report(h.vm.messages.last, expected: 'x' * 900);
        expect(h.treatments.chatReports.last.expectedText!.length, 500);
        // An emoji across the cut stays whole (audit, 23 Oct): 500 characters as the database
        // counts them, and no half character it would refuse.
        await h.vm.ask('and how often');
        await h.vm.report(h.vm.messages.last, expected: 'x' * 499 + '😀' * 3);
        final cut = h.treatments.chatReports.last.expectedText!;
        expect(cut.runes.length, 500);
        expect(cut.endsWith('😀'), isTrue);
      },
    );

    testWidgets(
      'the link opens the sheet, sends the report and says thank you',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);
        final h = Harness();
        await tester.runAsync(() async {
          await h.signInWithPlan();
          await h.vm.loadCategories();
          await h.vm.ask('my knee hurts');
        });
        await tester.pumpWidget(
          MaterialApp(
            home: ChangeNotifierProvider.value(
              value: h.vm,
              child: const ChatView(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.text('Report this answer'),
          findsOneWidget,
        ); // not on the welcome
        await tester.tap(find.text('Report this answer'));
        await tester.pumpAndSettle();
        expect(
          find.text('You asked: \u201cmy knee hurts\u201d'),
          findsOneWidget,
        );
        await tester.enterText(find.byType(TextField).last, 'Something else');
        await tester.runAsync(() async {
          await tester.tap(find.text('Send report'));
          await Future<void>.delayed(const Duration(milliseconds: 50));
        });
        await tester.pumpAndSettle();
        expect(find.text(Messages.chatReportSent), findsOneWidget);
        expect(find.text('Reported, thank you'), findsOneWidget);
        expect(find.text('Report this answer'), findsNothing);
        expect(h.treatments.chatReports.single.expectedText, 'Something else');
      },
    );
  });

  test(
    'a reply can carry a button (chat-rules-3.2), and older replies without one still parse',
    () {
      final withButton = ChatReply.fromJson({
        'answer': 'You can set a new password...',
        'category': 'forgot_password',
        'is_matched': true,
        'matched_by': 'keyword',
        'action': {'key': 'open_reset_password', 'label': 'Reset password'},
      });
      expect(withButton.action?.key, 'open_reset_password');
      expect(withButton.action?.label, 'Reset password');
      final plain = ChatReply.fromJson({
        'answer': 'Hello!',
        'is_matched': true,
      });
      expect(plain.action, isNull);
      expect(plain.actions, isEmpty);
      expect(
        withButton.actions.single.key,
        'open_reset_password',
      ); // older server: "action" only

      final two = ChatReply.fromJson({
        'answer': 'a',
        'category': 'change_password',
        'title': 't',
        'is_matched': true,
        'matched_by': 'keyword',
        'follow_ups': [],
        'notes': [],
        'categories': [],
        'action': {'key': 'open_profile', 'label': 'Open Profile'},
        'actions': [
          {'key': 'open_profile', 'label': 'Open Profile'},
          {'key': 'open_reset_password', 'label': 'Reset by email'},
        ],
      });
      expect(
        [for (final a in two.actions) a.key],
        ['open_profile', 'open_reset_password'],
      );
    },
  );

  test(
    "every question carries the phone's local time and time zone (late-night advice)",
    () async {
      final h = Harness();
      await h.signInWithPlan();
      await h.vm.loadCategories();
      await h.vm.ask('can I exercise now');
      final sent = h.server.asked.last;
      expect(sent['local_hour'], 23);
      expect(sent['local_minute'], 40);
      expect(sent.containsKey('utc_offset_minutes'), isTrue);
      expect(sent.containsKey('timezone'), isTrue);
    },
  );

  test('a follow-up carries the topic of the previous answer', () async {
    final h = Harness();
    await h.signInWithPlan();
    await h.vm.loadCategories();
    await h.vm.ask('my knee hurts');
    expect(h.server.asked.first.containsKey('previous_category'), isFalse);
    await h.vm.ask('is that normal');
    expect(h.server.asked.last['previous_category'], 'pain_or_discomfort');
  });

  test('the main answer keeps its own paragraphs; only the notes go to the box', () {
    // A condition answer has a paragraph per condition and a closing one; the notes come last.
    final reply = ChatReply.fromJson({
      'answer':
          'With high blood pressure, exercise helps.\n\nCheck with your doctor before doing more.'
          '\n\nNote: It is late.\nNote: Your risk level is High.',
      'is_matched': true,
      'notes': ['It is late.', 'Your risk level is High.'],
    });
    expect(
      reply.mainAnswer,
      'With high blood pressure, exercise helps.\n\nCheck with your doctor before doing more.',
    );
  });
}
