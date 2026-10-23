/// A patient's report that a chatbot answer was wrong or unhelpful (Elwin,
/// 11 Oct). Saved as NEW in chat_report; a reviewer reads it in the chat
/// backlog and, after a check, adds a rule or new wording to the knowledge
/// base (status ADDED or REJECTED). Not in the Chapter 4 class diagram
/// (PROJECT_STATE §11).
class ChatReport {
  final String reportId;
  final String accountId;

  /// The chat_message rows of the question and the answer, when they were
  /// saved; the texts below are kept either way.
  final String? questionMessageId;
  final String? answerMessageId;

  final String questionText;
  final String answerText;

  /// What the chatbot matched: the rule category and how it matched.
  final String? answerCategory;
  final String? matchedBy;

  /// The patient's own words: what they expected (optional).
  final String? expectedText;

  /// The topic the patient meant, if they picked one (optional).
  final String? wantedCategory;

  final DateTime createdAt;

  static const maxQuestionLength = 1000;
  static const maxExpectedLength = 500;

  const ChatReport({
    required this.reportId,
    required this.accountId,
    this.questionMessageId,
    this.answerMessageId,
    required this.questionText,
    required this.answerText,
    this.answerCategory,
    this.matchedBy,
    this.expectedText,
    this.wantedCategory,
    required this.createdAt,
  });

  /// The row for chat_report; status is always NEW from the app.
  Map<String, dynamic> toJson() => {
    'report_id': reportId,
    'account_id': accountId,
    'question_message_id': questionMessageId,
    'answer_message_id': answerMessageId,
    'question_text': questionText,
    'answer_text': answerText,
    'answer_category': answerCategory,
    'matched_by': matchedBy,
    'expected_text': expectedText,
    'wanted_category': wantedCategory,
    'status': 'NEW',
    'created_at': createdAt.toUtc().toIso8601String(),
  };
}
