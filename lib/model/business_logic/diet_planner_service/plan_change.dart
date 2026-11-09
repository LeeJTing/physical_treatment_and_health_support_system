import 'package:physical_treatment_and_health_support_system/model/entity/diet_plan.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/food_item.dart';

/// What the patient is about to do to the plan (UC900 A5.1, A5.3).
enum PlanChangeKind { add, remove, replace, portion }

/// A change to the plan worked out before it is made, so the patient can see its effect and
/// confirm it (UC900 A5.1 step 3): the day's totals before and after, what it means in words, and
/// health warnings and any invalid input. Health warnings do not block the patient's choices.
class PlanChange {
  final PlanChangeKind kind;
  final DateTime day;
  final MealSlot slot;

  /// The question the confirmation asks, e.g. "Add Pisang to your snack?".
  final String title;

  /// What will happen, in plain words: the energy, sodium and free sugars of the day before and
  /// after, needs reached or lost, an empty slot, a locked food. Lines that warn of too much, too
  /// little or something not good for the body are marked [PlanNote.warn].
  final List<PlanNote> effects;

  /// The day's totals (with what was eaten today outside the plan) before and after the change.
  final Nutrients before;
  final Nutrients after;

  /// Invalid portions or dates that prevent persistence. Health warnings are in [effects].
  final List<String> problems;

  /// The plan the change was worked out from, and the plan after it.
  final DietPlan basePlan;
  final DietPlan plan;

  /// Shown once the change is made, e.g. "Pisang added to your snack.".
  final String doneMessage;

  const PlanChange({
    required this.kind,
    required this.day,
    required this.slot,
    required this.title,
    required this.effects,
    required this.before,
    required this.after,
    required this.problems,
    required this.basePlan,
    required this.plan,
    required this.doneMessage,
  });

  bool get allowed => problems.isEmpty;
  Nutrients get delta => after - before;

  /// The lines that warn (shown in red).
  List<PlanNote> get warnings => effects.where((e) => e.warn).toList();
}

/// One line of an explanation or an effect. [warn] marks too much, too little or something not
/// good for the body, with what it does to the body; the screens show it in red.
class PlanNote {
  final String text;
  final bool warn;
  const PlanNote(this.text, {this.warn = false});

  @override
  String toString() => text;
}

/// One reason in the explanation of a plan (UC900 A5; DC700_06): [kind] picks the picture
/// (energy, plate, limits, profile, preference, needs, lock).
class PlanReason {
  final String kind;
  final String title;
  final String text;

  /// False when the reason is a warning (a need the day does not reach).
  final bool ok;

  const PlanReason(this.kind, this.title, this.text, {this.ok = true});
}

/// A "follow your diet plan" alert (UC900 with M600): a planned main meal not logged by its time,
/// or a logged meal that is not the planned one. Shown on the phone at [at] and in the app.
class PlanAlert {
  final MealSlot slot;
  final DateTime at;
  final String title;
  final String body;

  /// The rest of the day would go over a limit if nothing changes (shown in red).
  final bool overLimit;

  const PlanAlert({
    required this.slot,
    required this.at,
    required this.title,
    required this.body,
    this.overLimit = false,
  });
}

/// How closely the plan has been followed so far: the planned meals whose time has passed (or that
/// were logged), and how many were eaten as planned, eaten differently or missed.
class PlanFollow {
  final int due;
  final int followed;
  final int different;
  final int missed;
  const PlanFollow({this.due = 0, this.followed = 0, this.different = 0, this.missed = 0});

  double get share => due == 0 ? 1 : followed / due;

  /// Not following the plan: at least two planned meals due and fewer than 60 % eaten as planned.
  bool get notFollowing => due >= 2 && share < 0.6;
}
