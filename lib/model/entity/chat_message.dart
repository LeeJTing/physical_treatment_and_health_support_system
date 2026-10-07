import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';

/// One turn of the rule-based rehabilitation chatbot (Table 4.22).
class ChatMessage {
  final String messageId;
  final String accountId;
  final String? patientPlanId;
  final MessageSender sender;
  final String? questionCategory;
  final String messageText;
  final bool isMatched;
  final DateTime createdAt;

  const ChatMessage({
    required this.messageId,
    required this.accountId,
    this.patientPlanId,
    required this.sender,
    this.questionCategory,
    required this.messageText,
    this.isMatched = true,
    required this.createdAt,
  });

  bool get fromPatient => sender == MessageSender.patient;

  Map<String, dynamic> toJson() => {
    'message_id': messageId,
    'account_id': accountId,
    'patient_plan_id': patientPlanId,
    'sender': sender.db,
    'question_category': questionCategory,
    'message_text': messageText,
    'is_matched': isMatched,
    'created_at': createdAt.toIso8601String(),
  };

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
    messageId: j['message_id'] as String,
    accountId: j['account_id'] as String,
    patientPlanId: j['patient_plan_id'] as String?,
    sender: MessageSender.fromDb(j['sender'] as String?),
    questionCategory: j['question_category'] as String?,
    messageText: j['message_text'] as String,
    isMatched: (j['is_matched'] ?? true) as bool,
    createdAt: DateTime.parse(j['created_at'] as String),
  );
}
