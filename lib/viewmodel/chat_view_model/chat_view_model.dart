import 'package:physical_treatment_and_health_support_system/viewmodel/base_view_model.dart';
import 'package:physical_treatment_and_health_support_system/model/result.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/ui_state.dart';
import 'package:physical_treatment_and_health_support_system/core/constants/app_constants.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/chatbot_service/chatbot_service.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/risk_assessment_service/risk_assessment_service.dart';
import 'package:physical_treatment_and_health_support_system/core/utils/id_utils.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/chat_message.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/chat_report.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/health_profile.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/treatment_repository/i_treatment_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/chatbot_service/chat_reply.dart';

/// One line in the chat: the stored message plus what the screen offers under it.
class ChatEntry {
  final ChatMessage message;
  final ChatReply? reply; // set on system messages that came from the server

  const ChatEntry(this.message, [this.reply]);

  bool get fromPatient => message.fromPatient;
}

/// Rehabilitation chatbot state, scoped to the patient's active treatment plan (Table 4.45).
class ChatViewModel extends BaseViewModel {
  final ChatbotService _chatbot;
  final RiskAssessmentService _riskAssessment;
  final ITreatmentRepository _repo;

  ChatViewModel(this._chatbot, this._riskAssessment, this._repo);

  static const welcome =
      'Hello! I can answer questions about your rehabilitation plan. '
      'Choose a topic below or type your question.';

  ProfileSnapshot? _snapshot;
  String? _patientPlanId;

  /// The plan the conversation is about (FR500_18); null before any plan is selected.
  String? get planId => _chatbot.planId;

  /// The profile age, for the age-limit page the chat can open.
  int? get age => _snapshot?.profile?.age;

  final List<ChatEntry> _messages = [];

  /// Transcript in order.
  List<ChatEntry> get messages => List.unmodifiable(_messages);

  UiState<List<ChatCategory>> _categories = const Idle();
  UiState<List<ChatCategory>> get categories => _categories;

  bool _sending = false;
  bool get sending => _sending;

  /// chat_message rows that were stored, so a report links only to saved rows.
  final Set<String> _saved = {};

  /// Answers already reported in this chat (by message id).
  final Set<String> _reported = {};

  /// A server answer can be reported once; not the welcome or an error line.
  bool canReport(ChatEntry e) =>
      !e.fromPatient &&
      e.reply != null &&
      _snapshot?.accountId != null &&
      !_reported.contains(e.message.messageId);

  bool isReported(ChatEntry e) => _reported.contains(e.message.messageId);

  /// The patient's question an answer replies to.
  ChatEntry? questionFor(ChatEntry answer) {
    final i = _messages.indexOf(answer);
    for (var j = i - 1; j >= 0; j--) {
      if (_messages[j].fromPatient) return _messages[j];
    }
    return null;
  }

  /// Reports that [answer] was wrong or unhelpful (Elwin, 11 Oct): saved as
  /// NEW in chat_report with the question, the answer, what the chatbot
  /// matched, and the patient's optional note and topic. A reviewer turns it
  /// into a rule change; nothing in the knowledge base changes by itself.
  Future<Result<void>> report(
    ChatEntry answer, {
    String? expected,
    String? wantedCategory,
  }) async {
    final accountId = _snapshot?.accountId;
    final question = questionFor(answer);
    if (accountId == null || question == null || !canReport(answer)) {
      return const Failure(Messages.chatReportFailed);
    }
    final note = expected?.trim() ?? '';
    final r = ChatReport(
      reportId: newId(),
      accountId: accountId,
      questionMessageId: _saved.contains(question.message.messageId)
          ? question.message.messageId
          : null,
      answerMessageId: _saved.contains(answer.message.messageId)
          ? answer.message.messageId
          : null,
      questionText: _clip(
        question.message.messageText,
        ChatReport.maxQuestionLength,
      ),
      answerText: answer.message.messageText,
      answerCategory: answer.reply?.category,
      matchedBy: answer.reply?.matchedBy,
      expectedText: note.isEmpty
          ? null
          : _clip(note, ChatReport.maxExpectedLength),
      wantedCategory: wantedCategory,
      createdAt: DateTime.now(),
    );
    final res = await _repo.saveChatReport(r);
    if (res.isSuccess) {
      _reported.add(answer.message.messageId);
      notifyListeners();
      return const Success(null);
    }
    return const Failure(Messages.chatReportFailed);
  }

  /// At most [max] characters as the database counts them (char_length: code points). Cut by
  /// code points, so an emoji at the cut is never split into half a character, which the
  /// database refuses (audit, 23 Oct).
  static String _clip(String s, int max) => s.runes.length <= max
      ? s
      : String.fromCharCodes(s.runes.take(max));

  /// Loads the patient's profile and active plan, then the question categories that belong
  /// to that plan (FR500_18). A failure shows the M5 message with a retry (UC400 E3).
  Future<void> loadCategories() async {
    _categories = const Loading();
    notifyListeners();
    final snap = await _riskAssessment.retrieve();
    if (snap case Success(:final data)) {
      _snapshot = data;
      final accountId = data.accountId;
      if (accountId != null) {
        final active = (await _repo.getActivePlan(accountId)).dataOrNull;
        _chatbot.planId = active?.plan.planId;
        _patientPlanId = active?.patientPlanId;
      }
    }
    final res = await _chatbot.categoriesFor(
      _chatbot.planId,
      age: _snapshot?.profile?.age,
    );
    _categories = switch (res) {
      Success(:final data) => UiSuccess(data),
      Failure(:final message) => UiError(message),
    };
    if (_messages.isEmpty && res.isSuccess) {
      _messages.add(ChatEntry(_system(welcome, isMatched: true)));
    }
    notifyListeners();
  }

  /// Matches typed input and appends the response (FR500_19, FR500_20, FR500_21).
  Future<void> ask(String text) async {
    final t = text.trim();
    if (t.isEmpty || _sending) return;
    await _send(shown: t, text: t);
  }

  /// A tapped category or follow-up option.
  Future<void> choose(ChatCategory c) async {
    if (_sending) return;
    await _send(shown: c.title, category: c.key);
  }

  Future<void> _send({
    required String shown,
    String? text,
    String? category,
  }) async {
    _sending = true;
    // Topic of the last answer, for follow-ups such as "how many reps for that one?".
    final previous = _messages.reversed
        .map((e) => e.reply?.category)
        .firstWhere((c) => c != null, orElse: () => null);
    final question = _patient(shown, category);
    _messages.add(ChatEntry(question));
    notifyListeners();

    final res = await _chatbot.ask(
      text: text,
      category: category,
      profile: _snapshot,
      previousCategory: previous,
    );
    final ChatEntry answer = switch (res) {
      Success(:final data) => ChatEntry(
        _system(
          data.answer,
          category: data.category,
          isMatched: _chatbot.isRecognised(data),
        ),
        data,
      ),
      Failure(:final message) => ChatEntry(_system(message, isMatched: false)),
    };
    _messages.add(answer);
    if (res case Success(:final data) when data.categories.isNotEmpty) {
      _categories = UiSuccess(data.categories);
    }
    _sending = false;
    notifyListeners();

    // Stored as chat_message rows; an unmatched question is the backlog for new rules
    // (Table 4.99). A failed save does not interrupt the conversation.
    if (res.isSuccess && _snapshot?.accountId != null) {
      final q = await _repo.saveChatMessage(
        question.withMatched(answer.message.isMatched),
      );
      if (q.isSuccess) _saved.add(question.messageId);
      final a = await _repo.saveChatMessage(answer.message);
      if (a.isSuccess) _saved.add(answer.message.messageId);
    }
  }

  ChatMessage _patient(String text, String? category) => ChatMessage(
    messageId: newId(),
    accountId: _snapshot?.accountId ?? '',
    patientPlanId: _patientPlanId,
    sender: MessageSender.patient,
    questionCategory: category,
    messageText: text,
    createdAt: DateTime.now(),
  );

  ChatMessage _system(
    String text, {
    String? category,
    required bool isMatched,
  }) => ChatMessage(
    messageId: newId(),
    accountId: _snapshot?.accountId ?? '',
    patientPlanId: _patientPlanId,
    sender: MessageSender.system,
    questionCategory: category,
    messageText: text,
    isMatched: isMatched,
    createdAt: DateTime.now(),
  );

  /// Dismisses the chat panel (FR500_23). The transcript is already stored.
  void close() {
    _messages.clear();
    _saved.clear();
    _reported.clear();
    _categories = const Idle();
  }

  /// Retry after the categories could not be loaded.
  Future<void> retry() => loadCategories();

  bool get categoriesFailed => _categories is UiError;
  String get categoriesError => switch (_categories) {
    UiError(:final message) => message,
    _ => Messages.dbUnavailable,
  };
}

extension on ChatMessage {
  ChatMessage withMatched(bool matched) => ChatMessage(
    messageId: messageId,
    accountId: accountId,
    patientPlanId: patientPlanId,
    sender: sender,
    questionCategory: questionCategory,
    messageText: messageText,
    isMatched: matched,
    createdAt: createdAt,
  );
}
