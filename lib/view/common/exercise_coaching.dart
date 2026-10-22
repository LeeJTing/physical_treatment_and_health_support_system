import 'dart:convert';

import 'package:flutter/services.dart';

import 'package:physical_treatment_and_health_support_system/model/entity/exercise.dart';

/// One numbered step of the guide; [phase] picks the still of the animation shown beside it
/// (start, go, top or back), or none.
class CoachStep {
  final String text;
  final String? phase;
  const CoachStep(this.text, {this.phase});
}

/// A mistake the posture check looks for: [wrong] is what it means, [right] the server's own
/// "do this" sentence for it (test/guide_coaching_test.dart keeps them equal).
class CoachMistake {
  final String label;
  final String wrong;
  final String right;
  const CoachMistake(this.label, this.wrong, this.right);
}

/// The guide's words for one exercise (Elwin, 23 Oct: a first-time user must be shown, step by
/// step, what to do). Hand-written for an exercise in `assets/guides/coaching/<pose_key>.json`;
/// otherwise made from the exercise's instruction text, so every exercise has a guide.
class ExerciseCoaching {
  /// The joint to watch, drawn with a ring and an arc from [focusFrom] to [focusTo]
  /// (landmark names without a side, e.g. knee, hip, ankle).
  final String? focusJoint;
  final String? focusFrom;
  final String? focusTo;

  /// The point whose movement the arrow shows (e.g. hip).
  final String? mover;

  /// Caption for each part of a repetition: start, go, top, back.
  final Map<String, String> captions;

  /// Short spoken cues while recording, for go and back.
  final Map<String, String> say;
  final List<CoachStep> steps;
  final List<String> safety;
  final List<CoachMistake> mistakes;

  /// Set-up lines for this exercise, said before the general phone placement.
  final List<String> setup;

  /// True when written for this exercise, not made from its instruction text.
  final bool tailored;

  const ExerciseCoaching({
    this.focusJoint,
    this.focusFrom,
    this.focusTo,
    this.mover,
    this.captions = const {},
    this.say = const {},
    required this.steps,
    this.safety = const [],
    this.mistakes = const [],
    this.setup = const [],
    this.tailored = false,
  });

  factory ExerciseCoaching.fromJson(Map<String, dynamic> j) {
    final focus = j['focus'] as Map<String, dynamic>?;
    Map<String, String> strings(Object? m) => {
      for (final e in ((m as Map<String, dynamic>?) ?? const {}).entries)
        e.key: e.value as String,
    };
    return ExerciseCoaching(
      focusJoint: focus?['joint'] as String?,
      focusFrom: focus?['from'] as String?,
      focusTo: focus?['to'] as String?,
      mover: j['mover'] as String?,
      captions: strings(j['captions']),
      say: strings(j['say']),
      steps: [
        for (final s in j['steps'] as List)
          CoachStep(s['text'] as String, phase: s['phase'] as String?),
      ],
      safety: [for (final s in (j['safety'] as List?) ?? const []) s as String],
      mistakes: [
        for (final m in (j['mistakes'] as List?) ?? const [])
          CoachMistake(
            m['label'] as String,
            m['wrong'] as String,
            m['right'] as String,
          ),
      ],
      setup: [for (final s in (j['setup'] as List?) ?? const []) s as String],
      tailored: true,
    );
  }

  /// From the catalogue's instruction text: one step per sentence before "Safety:", one
  /// safety point per part after it.
  factory ExerciseCoaching.fromInstruction(Exercise e) {
    final text = e.steps;
    final at = text.indexOf('Safety:');
    final how = at < 0 ? text : text.substring(0, at);
    final safe = at < 0 ? '' : text.substring(at + 'Safety:'.length);
    String sentence(String s) {
      final t = s.trim();
      if (t.isEmpty) return t;
      final cap = '${t[0].toUpperCase()}${t.substring(1)}';
      return cap.endsWith('.') ? cap : '$cap.';
    }

    return ExerciseCoaching(
      steps: [
        for (final s in how.split(RegExp(r'(?<=\.)\s+')))
          if (s.trim().isNotEmpty) CoachStep(sentence(s)),
      ],
      safety: [
        for (final s in safe.split(RegExp(r'[;.]\s*')))
          if (s.trim().isNotEmpty) sentence(s),
      ],
    );
  }

  static final Map<String, Future<ExerciseCoaching?>> _cache = {};

  /// The hand-written guide for [poseKey], or null when there is none.
  static Future<ExerciseCoaching?> load(AssetBundle bundle, String poseKey) =>
      _cache.putIfAbsent(poseKey, () async {
        try {
          final text = await bundle.loadString(
            'assets/guides/coaching/$poseKey.json',
          );
          return ExerciseCoaching.fromJson(
            jsonDecode(text) as Map<String, dynamic>,
          );
        } catch (_) {
          return null;
        }
      });

  /// The hand-written guide for [e] when there is one, else one from its instruction text.
  static Future<ExerciseCoaching> forExercise(
    AssetBundle bundle,
    Exercise e,
  ) async {
    final key = e.poseKey;
    final written = key == null ? null : await load(bundle, key);
    return written ?? ExerciseCoaching.fromInstruction(e);
  }
}
