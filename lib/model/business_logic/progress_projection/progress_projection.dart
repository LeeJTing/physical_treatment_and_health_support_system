import 'dart:math' as math;

/// One scored attempt: when, and its posture accuracy (0-100).
typedef ScorePoint = ({DateTime at, double accuracy});

/// The outlook on the posture result screen (Elwin, 10 Nov): the patient's own scores in the plan,
/// a straight-line projection of them, and when the plan should be finished at their pace. It is
/// an estimate from the app's own data, not a medical prediction, and the screen says so.
class ProgressProjection {
  /// Scored attempts, oldest first.
  final List<ScorePoint> past;

  /// Projected score on [finishDate] (clamped to 0-100).
  final double projectedAtFinish;

  /// When the plan should be finished at the current pace.
  final DateTime finishDate;

  /// Exercises still to pass after this attempt.
  final int remainingExercises;

  /// Average tries per exercise used for the pace (1 to [maxTries]).
  final double triesPerExercise;

  /// When the line first reaches the pass mark, or null if it is already above it or never does.
  final DateTime? reachesPassMark;

  const ProgressProjection({
    required this.past,
    required this.projectedAtFinish,
    required this.finishDate,
    required this.remainingExercises,
    required this.triesPerExercise,
    this.reachesPassMark,
  });

  /// Only the last [window] attempts set the trend, so an early bad week does not drag it down.
  static const window = 5;

  /// [past]: scored attempts of the plan (any order). [completedExercises] and [totalExercises]:
  /// the plan's pathway after this attempt. [sessionsPerWeek]: the plan's frequency.
  /// [maxTries]: tries before the plan moves on anyway (AppConstants.triesBeforeMovingOn).
  static ProgressProjection compute({
    required List<ScorePoint> past,
    required int completedExercises,
    required int totalExercises,
    required int sessionsPerWeek,
    required DateTime now,
    int maxTries = 3,
    double passMark = 80,
  }) {
    final points = [...past]..sort((a, b) => a.at.compareTo(b.at));
    final remaining = math.max(0, totalExercises - completedExercises);
    // Pace: tries needed per exercise so far (at least 1, at most maxTries), one try per session.
    final tries = completedExercises == 0
        ? 1.0
        : (points.length / completedExercises).clamp(1.0, maxTries.toDouble());
    final daysPerSession = 7 / math.max(1, sessionsPerWeek);
    final finish = now.add(
      Duration(hours: (remaining * tries * daysPerSession * 24).round()),
    );

    // Least squares over the last [window] attempts, in days from the first of them.
    final recent = points.length > window
        ? points.sublist(points.length - window)
        : points;
    double slope = 0, intercept = recent.isEmpty ? 0 : recent.last.accuracy;
    if (recent.length >= 2) {
      final t0 = recent.first.at;
      final xs = [for (final p in recent) p.at.difference(t0).inHours / 24];
      final ys = [for (final p in recent) p.accuracy];
      final mx = xs.reduce((a, b) => a + b) / xs.length;
      final my = ys.reduce((a, b) => a + b) / ys.length;
      var sxx = 0.0, sxy = 0.0;
      for (var i = 0; i < xs.length; i++) {
        sxx += (xs[i] - mx) * (xs[i] - mx);
        sxy += (xs[i] - mx) * (ys[i] - my);
      }
      if (sxx > 0) {
        slope = sxy / sxx;
        // The projected line starts at the latest score, where the patient is now, and takes
        // its direction from the recent attempts.
        intercept = ys.last;
      }
    }
    final last = recent.isEmpty ? now : recent.last.at;
    double at(DateTime t) =>
        (intercept + slope * (t.difference(last).inHours / 24)).clamp(0, 100);

    DateTime? reaches;
    final current = recent.isEmpty ? 0.0 : recent.last.accuracy;
    if (current < passMark && slope > 0) {
      final days = (passMark - current) / slope;
      final t = last.add(Duration(hours: (days * 24).round()));
      if (!t.isAfter(finish)) reaches = t;
    }
    return ProgressProjection(
      past: points,
      projectedAtFinish: at(finish).toDouble(),
      finishDate: finish,
      remainingExercises: remaining,
      triesPerExercise: tries.toDouble(),
      reachesPassMark: reaches,
    );
  }
}
