import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import 'package:physical_treatment_and_health_support_system/core/base/ui_state.dart';
import 'package:physical_treatment_and_health_support_system/core/constants/app_constants.dart';
import 'package:physical_treatment_and_health_support_system/core/services/api_client.dart';
import 'package:physical_treatment_and_health_support_system/core/services/chatbot_service.dart';
import 'package:physical_treatment_and_health_support_system/core/services/profile_info_service.dart';
import 'package:physical_treatment_and_health_support_system/data/models/enums.dart';
import 'package:physical_treatment_and_health_support_system/data/models/health_profile.dart';
import 'package:physical_treatment_and_health_support_system/data/models/lookups.dart';
import 'package:physical_treatment_and_health_support_system/data/models/patient_treatment_plan.dart';
import 'package:physical_treatment_and_health_support_system/data/repository/fake/fake_auth_repository.dart';
import 'package:physical_treatment_and_health_support_system/data/repository/fake/fake_profile_repository.dart';
import 'package:physical_treatment_and_health_support_system/data/repository/fake/fake_treatment_repository.dart';
import 'package:physical_treatment_and_health_support_system/features/chat/model/chat_reply.dart';
import 'package:physical_treatment_and_health_support_system/features/chat/view/chat_view.dart';
import 'package:physical_treatment_and_health_support_system/features/chat/viewmodel/chat_view_model.dart';

final String catalogueJson = File('assets/seed/catalogue.json').readAsStringSync();

/// Stand-in for /chat: records what the app sends and answers like the real server.
class FakeChatServer {
  final List<Map<String, dynamic>> asked = [];
  bool categoriesFail = false;
  static const cats = [
    {'key': 'plan_exercises', 'title': 'What is in my plan'},
    {'key': 'pain_or_discomfort', 'title': 'Pain or discomfort'},
  ];

  late final client = MockClient((req) async {
    if (req.url.path.endsWith('/chat/categories')) {
      if (categoriesFail) return http.Response('{"error":{"code":"error","message":"down"}}', 500);
      return http.Response(jsonEncode({'plan_id': req.url.queryParameters['plan_id'], 'categories': cats,
                                       'rules_version': 'test'}), 200);
    }
    final body = jsonDecode(req.body) as Map<String, dynamic>;
    asked.add(body);
    final text = (body['text'] ?? '') as String;
    if (text.contains('France')) {
      return http.Response(jsonEncode({'answer': Messages.questionNotRecognised, 'category': null, 'title': null,
          'is_matched': false, 'matched_by': null, 'follow_ups': [], 'notes': [], 'categories': cats,
          'rules_version': 'test'}), 200);
    }
    final pain = text.contains('hurt');
    return http.Response(jsonEncode({
      'answer': pain ? 'Some soreness is normal.\n\nBecause you have high blood pressure: breathe out.' : 'Your plan has 3 exercises.',
      'category': pain ? 'pain_or_discomfort' : (body['category'] ?? 'plan_exercises'),
      'title': 'x', 'is_matched': true, 'matched_by': body['category'] != null ? 'category' : 'keyword',
      'follow_ups': pain ? [{'key': 'pain_mild', 'title': 'Mild soreness or tiredness'}] : [],
      'notes': pain ? ['Because you have high blood pressure: breathe out.'] : [],
      'categories': cats, 'rules_version': 'test',
    }), 200);
  });
}

class Harness {
  final server = FakeChatServer();
  final auth = FakeAuthRepository();
  final profiles = FakeProfileRepository();
  final treatments = FakeTreatmentRepository.fromJson(catalogueJson);
  late final ChatViewModel vm = ChatViewModel(
    ChatbotService(ApiClient(baseUrl: 'http://ai', tokenProvider: () => 'dev-token', httpClient: server.client)),
    ProfileInfoService(auth, profiles),
    treatments,
  );

  Future<void> signInWithPlan() async {
    final account = (await auth.login('demo@apths.test', 'password123')).dataOrNull!;
    final p = HealthProfile(
      profileId: 'p1', accountId: account.accountId, age: 66, gender: Gender.female, weightKg: 60, heightCm: 155,
      conditions: [LookupSeed.conditions.first], // HYPERTENSION
      updatedAt: DateTime.now(),
    );
    await profiles.saveProfile(p, p.generateSafetyLimit());
    final plan = (await treatments.getCatalogue()).dataOrNull!.first;
    await treatments.assignPlan(PatientTreatmentPlan(
        patientPlanId: 'pp1', accountId: account.accountId, plan: plan, selectedAt: DateTime.now()));
  }
}

void main() {
  group('ChatViewModel', () {
    test('loads the categories of the patient\'s active plan (FR500_18)', () async {
      final h = Harness();
      await h.signInWithPlan();
      await h.vm.loadCategories();
      expect(h.vm.categories, isA<UiSuccess<List<ChatCategory>>>());
      expect(h.vm.planId, isNotNull);
      expect(h.vm.messages.single.message.messageText, ChatViewModel.welcome);
    });

    test('sends plan, conditions and risk level with each question (Table 4.2.2)', () async {
      final h = Harness();
      await h.signInWithPlan();
      await h.vm.loadCategories();
      await h.vm.ask('my knee hurts');
      final sent = h.server.asked.single;
      expect(sent['plan_id'], h.vm.planId);
      expect(sent['conditions'], ['HYPERTENSION']);
      expect(sent['risk_level'], 'High');                 // a cardiovascular condition gives High risk
      final reply = h.vm.messages.last.reply!;
      expect(reply.followUps.single.key, 'pain_mild');
      expect(reply.mainAnswer, 'Some soreness is normal.');
      expect(reply.notes, hasLength(1));
    });

    test('stores both sides of each turn as chat_message rows', () async {
      final h = Harness();
      await h.signInWithPlan();
      await h.vm.loadCategories();
      await h.vm.ask('what is the capital of France');
      expect(h.treatments.chat, hasLength(2));
      expect(h.treatments.chat.first.sender, MessageSender.patient);
      expect(h.treatments.chat.every((m) => !m.isMatched), isTrue);   // unmatched -> backlog (Table 4.99)
      expect(h.treatments.chat.every((m) => m.patientPlanId == 'pp1'), isTrue);
      expect(h.vm.messages.last.message.messageText, Messages.questionNotRecognised);
    });

    test('a tapped category is sent as a category, not as text', () async {
      final h = Harness();
      await h.signInWithPlan();
      await h.vm.loadCategories();
      await h.vm.choose(const ChatCategory('plan_exercises', 'What is in my plan'));
      expect(h.server.asked.single['category'], 'plan_exercises');
      expect(h.server.asked.single.containsKey('text'), isFalse);
      expect(h.vm.messages[1].message.messageText, 'What is in my plan');
    });

    test('category loading failure shows the M5 message with retry (UC400 E3)', () async {
      final h = Harness()..server.categoriesFail = true;
      await h.signInWithPlan();
      await h.vm.loadCategories();
      expect(h.vm.categoriesFailed, isTrue);
      expect(h.vm.categoriesError, Messages.dbUnavailable);
      h.server.categoriesFail = false;
      await h.vm.retry();
      expect(h.vm.categoriesFailed, isFalse);
    });

    test('empty input is ignored', () async {
      final h = Harness();
      await h.signInWithPlan();
      await h.vm.loadCategories();
      await h.vm.ask('   ');
      expect(h.server.asked, isEmpty);
    });
  });

  testWidgets('ChatView shows topics, answers, follow-ups and the exit button', (tester) async {
    final h = Harness();
    await tester.runAsync(() async {
      await h.signInWithPlan();
      await h.vm.loadCategories();
    });
    await tester.pumpWidget(MaterialApp(
      home: ChangeNotifierProvider.value(value: h.vm, child: const ChatView()),
    ));
    await tester.pump();
    expect(find.text('Chat bot'), findsOneWidget);
    expect(find.text('Exit chatbot'), findsOneWidget);                       // FR500_23
    expect(find.text('Pain or discomfort'), findsOneWidget);                 // topic chip (FR500_18)
    expect(find.text(ChatViewModel.welcome), findsOneWidget);

    await tester.runAsync(() => h.vm.ask('my knee hurts'));
    await tester.pumpAndSettle();
    expect(find.text('Some soreness is normal.'), findsOneWidget);
    expect(find.text('Mild soreness or tiredness'), findsOneWidget);         // decision-tree option
    expect(find.textContaining('high blood pressure'), findsOneWidget);       // condition note
  });
}
