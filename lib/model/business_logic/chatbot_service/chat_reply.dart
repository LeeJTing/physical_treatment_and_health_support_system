/// A question category or follow-up option from the chatbot (FR500_18).
class ChatCategory {
  final String key;
  final String title;

  const ChatCategory(this.key, this.title);

  factory ChatCategory.fromJson(Map<String, dynamic> j) =>
      ChatCategory(j['key'] as String, j['title'] as String);

  @override
  bool operator ==(Object other) => other is ChatCategory && other.key == key;
  @override
  int get hashCode => key.hashCode;
}

/// A button offered under an answer, e.g. "Reset password" (chat-rules-3.2). The view maps
/// [key] to a screen.
class ChatAction {
  final String
  key; // open_reset_password | open_planning | open_profile | open_treatment | open_reminders | open_history
  final String label;

  const ChatAction(this.key, this.label);

  static ChatAction? fromJson(Object? j) => j is Map<String, dynamic>
      ? ChatAction(j['key'] as String, j['label'] as String)
      : null;
}

/// The /chat response: the predefined answer and what to offer next.
class ChatReply {
  final String answer;
  final String? category;
  final String? title;
  final bool isMatched; // false -> "Question not recognised" (FR500_22)
  final String?
  matchedBy; // red_flag | category | keyword | similar_question | keyword_overlap
  final List<ChatCategory>
  followUps; // decision-tree options, e.g. after a pain question
  final List<String>
  notes; // condition-specific lines, already part of [answer]
  final List<ChatCategory>
  categories; // shown again after every reply (FR500_21, FR500_22)
  final ChatAction? action; // optional button under the answer

  /// Every button under the answer, [action] first (chat-rules-3.48: a second one when the answer
  /// names a second screen, e.g. Open Profile and Reset by email).
  final List<ChatAction> actions;

  const ChatReply({
    required this.answer,
    this.category,
    this.title,
    required this.isMatched,
    this.matchedBy,
    this.followUps = const [],
    this.notes = const [],
    this.categories = const [],
    this.action,
    this.actions = const [],
  });

  bool get isUrgent => matchedBy == 'red_flag';

  /// The answer without the condition notes, which the chat shows in their own box.
  String get mainAnswer {
    if (notes.isEmpty) return answer;
    final cut = answer.indexOf('\n\n');
    return cut < 0 ? answer : answer.substring(0, cut);
  }

  static List<ChatCategory> _cats(Object? v) => [
    for (final c in (v as List? ?? const []))
      ChatCategory.fromJson(c as Map<String, dynamic>),
  ];

  factory ChatReply.fromJson(Map<String, dynamic> j) => ChatReply(
    answer: j['answer'] as String,
    category: j['category'] as String?,
    title: j['title'] as String?,
    isMatched: (j['is_matched'] ?? false) as bool,
    matchedBy: j['matched_by'] as String?,
    followUps: _cats(j['follow_ups']),
    notes: [for (final n in (j['notes'] as List? ?? const [])) n as String],
    categories: _cats(j['categories']),
    action: ChatAction.fromJson(j['action']),
    actions: _actions(j),
  );
}

/// "actions" from chat-rules-3.48, or the single "action" from an older server.
List<ChatAction> _actions(Map<String, dynamic> j) {
  final list = j['actions'];
  if (list is List && list.isNotEmpty) {
    return [for (final a in list) ?ChatAction.fromJson(a)];
  }
  final one = ChatAction.fromJson(j['action']);
  return one == null ? const [] : [one];
}
