import 'package:physical_treatment_and_health_support_system/model/result.dart';
import 'package:physical_treatment_and_health_support_system/core/constants/app_constants.dart';
import 'package:physical_treatment_and_health_support_system/shared_client/api_client/api_client.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/health_profile.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/chatbot_service/chat_reply.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/recommendation_service/recommendation.dart';

/// Sends the patient's question and the plan it concerns to the AI server, where the keyword
/// rules and their predefined responses are held (Table 4.70). The patient's conditions,
/// limitations and risk level go with every question so the reply can be filtered by health
/// condition (Table 4.2.2).
class ChatbotService {
  final ApiClient _api;
  final DateTime Function() _now;

  /// Treatment plan the conversation concerns, sent with every question (FR500_18).
  String? planId;

  ChatbotService(this._api, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  /// Question categories that belong to the plan (FR500_18). From 65 the
  /// plan topics are replaced by "Why plans stop at 65" (chat-rules-3.49).
  Future<Result<List<ChatCategory>>> categoriesFor(
    String? planId, {
    int? age,
  }) async {
    final res = await _api.get(
      AppConstants.chatCategoriesPath,
      query: {
        'plan_id': ?planId,
        'restriction': ?PlanRestriction.forAge(age)?.wire,
      },
    );
    if (res is Failure<Map<String, dynamic>>) {
      return Failure(Messages.dbUnavailable, code: res.code, cause: res.cause);
    }
    return guard(
      () async => [
        for (final c in (res.dataOrNull!['categories'] as List))
          ChatCategory.fromJson(c as Map<String, dynamic>),
      ],
    );
  }

  /// Sends a typed question or a tapped category; the server matches it and returns the
  /// predefined response (FR500_19, FR500_20).
  Future<Result<ChatReply>> ask({
    String? text,
    String? category,
    ProfileSnapshot? profile,
    String? previousCategory,
  }) async {
    final p = profile?.profile;
    // The phone's own local time and time zone (no GPS, no location permission): the server
    // advises resting late at night and gives condition-specific timing.
    final local = _now();
    final res = await _api.post(AppConstants.chatPath, {
      'local_hour': local.hour,
      'local_minute': local.minute,
      'utc_offset_minutes': local.timeZoneOffset.inMinutes,
      'timezone': local.timeZoneName,
      // Lets "how many reps for that one?" continue the exercise asked about just before.
      'previous_category': ?previousCategory,
      'plan_id': planId,
      'category': ?category,
      if (text != null && text.trim().isNotEmpty) 'text': text.trim(),
      'conditions': [
        for (final c in p?.conditions ?? const []) c.conditionCode,
      ],
      'limitations': [
        for (final l in p?.limitations ?? const []) l.limitationCode,
      ],
      if (profile != null) 'risk_level': profile.riskLevel.db,
      // From 65 plans are paused: plan questions are answered with the reason
      // (Terms of Use, section 2) and a button to the age-limit page.
      'restriction': ?PlanRestriction.forAge(p?.age)?.wire,
    });
    if (res is Failure<Map<String, dynamic>>) {
      return Failure(Messages.dbUnavailable, code: res.code, cause: res.cause);
    }
    return guard(() async => ChatReply.fromJson(res.dataOrNull!));
  }

  /// False when the server matched no rule, which shows the categories again (FR500_22).
  bool isRecognised(ChatReply r) => r.isMatched;
}
