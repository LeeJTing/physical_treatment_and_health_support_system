/// Body regions of the tappable body map in the planning questionnaire, and
/// the mapping from the regions a patient taps to the one affected body area
/// the recommender understands (FR500_03, RehabInfo.bodyAreas).
///
/// Pure Dart (no Flutter) so the mapping is unit-tested on its own. UI-only:
/// these classes are not in the Chapter 4 class diagram (PROJECT_STATE §11).
library;

enum BodyView { front, back }

/// The PERSON's side, not the screen's. In the front view the person's right
/// is on the screen's left; in the back view it is on the screen's right.
enum BodySide { left, right, centre }

/// Groups that decide the affected body area.
enum BodyGroup { arm, leg, core }

class BodyRegion {
  /// Unique id, e.g. 'front_right_knee'.
  final String id;

  /// Shape drawn for this region; `shape` + the screen side picks the path.
  final String shape;
  final BodyView view;
  final BodySide side;
  final BodyGroup group;

  /// Label with a `{side}` placeholder, e.g. '{Side} knee', 'Back of {side} thigh'.
  final String _template;

  /// Why the region cannot be chosen, or null when it can. Such a region is
  /// drawn greyed out and a tap shows this note instead of selecting it.
  final String? unavailableNote;

  const BodyRegion(
    this.id,
    this._template, {
    required this.shape,
    required this.view,
    required this.side,
    required this.group,
    this.unavailableNote,
  });

  bool get available => unavailableNote == null;

  /// Patient-facing name, always with the person's own side: 'Right knee'.
  String get label => _template
      .replaceAll('{Side}', side == BodySide.left ? 'Left' : 'Right')
      .replaceAll('{side}', side == BodySide.left ? 'left' : 'right');

  /// Whether the region is drawn on the screen's left half.
  bool get onScreenLeft => switch (side) {
    BodySide.centre => false,
    BodySide.right => view == BodyView.front,
    BodySide.left => view == BodyView.back,
  };

  @override
  String toString() => id;
}

/// Regions of both views and the mapping to the recommender's body areas.
class BodyRegions {
  BodyRegions._();

  /// No neck exercises in the catalogue: neck problems are left to a doctor
  /// or physiotherapist (PC review, 9 Oct).
  static const neckNote =
      "Neck problems need a doctor or physiotherapist to guide the exercises, "
      "so this app doesn't include neck exercises.";

  static List<BodyRegion> _paired(
    String name,
    String template, {
    required String shape,
    required BodyView view,
    required BodyGroup group,
  }) => [
    for (final side in [BodySide.right, BodySide.left])
      BodyRegion(
        '${view.name}_${side.name}_$name',
        template,
        shape: shape,
        view: view,
        side: side,
        group: group,
      ),
  ];

  static final List<BodyRegion> front = [
    const BodyRegion(
      'front_neck',
      'Neck',
      shape: 'neck',
      view: BodyView.front,
      side: BodySide.centre,
      group: BodyGroup.core,
      unavailableNote: BodyRegions.neckNote,
    ),
    const BodyRegion(
      'front_chest',
      'Chest',
      shape: 'torsoUpper',
      view: BodyView.front,
      side: BodySide.centre,
      group: BodyGroup.core,
    ),
    const BodyRegion(
      'front_abdomen',
      'Abdomen',
      shape: 'torsoLower',
      view: BodyView.front,
      side: BodySide.centre,
      group: BodyGroup.core,
    ),
    ..._paired(
      'shoulder',
      '{Side} shoulder',
      shape: 'shoulder',
      view: BodyView.front,
      group: BodyGroup.arm,
    ),
    ..._paired(
      'upper_arm',
      '{Side} upper arm',
      shape: 'upperArm',
      view: BodyView.front,
      group: BodyGroup.arm,
    ),
    ..._paired(
      'elbow',
      '{Side} elbow',
      shape: 'elbow',
      view: BodyView.front,
      group: BodyGroup.arm,
    ),
    ..._paired(
      'forearm',
      '{Side} forearm',
      shape: 'forearm',
      view: BodyView.front,
      group: BodyGroup.arm,
    ),
    ..._paired(
      'hand',
      '{Side} wrist and hand',
      shape: 'hand',
      view: BodyView.front,
      group: BodyGroup.arm,
    ),
    ..._paired(
      'hip',
      '{Side} hip',
      shape: 'hip',
      view: BodyView.front,
      group: BodyGroup.leg,
    ),
    ..._paired(
      'thigh',
      '{Side} thigh',
      shape: 'thigh',
      view: BodyView.front,
      group: BodyGroup.leg,
    ),
    ..._paired(
      'knee',
      '{Side} knee',
      shape: 'knee',
      view: BodyView.front,
      group: BodyGroup.leg,
    ),
    ..._paired(
      'shin',
      '{Side} shin',
      shape: 'shin',
      view: BodyView.front,
      group: BodyGroup.leg,
    ),
    ..._paired(
      'foot',
      '{Side} ankle and foot',
      shape: 'foot',
      view: BodyView.front,
      group: BodyGroup.leg,
    ),
  ];

  static final List<BodyRegion> back = [
    const BodyRegion(
      'back_neck',
      'Back of the neck',
      shape: 'neck',
      view: BodyView.back,
      side: BodySide.centre,
      group: BodyGroup.core,
      unavailableNote: BodyRegions.neckNote,
    ),
    const BodyRegion(
      'back_upper_back',
      'Upper back',
      shape: 'torsoUpper',
      view: BodyView.back,
      side: BodySide.centre,
      group: BodyGroup.core,
    ),
    const BodyRegion(
      'back_lower_back',
      'Lower back',
      shape: 'torsoLower',
      view: BodyView.back,
      side: BodySide.centre,
      group: BodyGroup.core,
    ),
    ..._paired(
      'shoulder',
      'Back of {side} shoulder',
      shape: 'shoulder',
      view: BodyView.back,
      group: BodyGroup.arm,
    ),
    ..._paired(
      'upper_arm',
      'Back of {side} upper arm',
      shape: 'upperArm',
      view: BodyView.back,
      group: BodyGroup.arm,
    ),
    ..._paired(
      'elbow',
      'Back of {side} elbow',
      shape: 'elbow',
      view: BodyView.back,
      group: BodyGroup.arm,
    ),
    ..._paired(
      'buttock',
      '{Side} buttock',
      shape: 'hip',
      view: BodyView.back,
      group: BodyGroup.leg,
    ),
    ..._paired(
      'thigh',
      'Back of {side} thigh',
      shape: 'thigh',
      view: BodyView.back,
      group: BodyGroup.leg,
    ),
    ..._paired(
      'knee',
      'Back of {side} knee',
      shape: 'knee',
      view: BodyView.back,
      group: BodyGroup.leg,
    ),
    ..._paired(
      'calf',
      '{Side} calf',
      shape: 'shin',
      view: BodyView.back,
      group: BodyGroup.leg,
    ),
    ..._paired(
      'heel',
      '{Side} heel and ankle',
      shape: 'foot',
      view: BodyView.back,
      group: BodyGroup.leg,
    ),
  ];

  static List<BodyRegion> of(BodyView view) =>
      view == BodyView.front ? front : back;

  static final Map<String, BodyRegion> byId = {
    for (final r in [...front, ...back]) r.id: r,
  };

  /// The one affected body area for the selected regions (RehabInfo.bodyAreas),
  /// or null when nothing is selected.
  ///  - arms only: LEFT_ARM, RIGHT_ARM or BOTH_ARMS
  ///  - legs only: LEFT_LEG, RIGHT_LEG or BOTH_LEGS
  ///  - core only: CORE
  ///  - two or more of arms, legs and core: FULL_BODY
  /// Regions that cannot be chosen (the neck) are ignored.
  static String? areaFor(Iterable<BodyRegion> regions) {
    regions = [
      for (final r in regions)
        if (r.available) r,
    ];
    final groups = {for (final r in regions) r.group};
    if (groups.isEmpty) return null;
    if (groups.length > 1) return 'FULL_BODY';
    final group = groups.single;
    if (group == BodyGroup.core) return 'CORE';
    final sides = {for (final r in regions) r.side};
    final limb = group == BodyGroup.arm ? 'ARM' : 'LEG';
    if (sides.length > 1) return 'BOTH_${limb}S';
    return '${sides.single == BodySide.left ? 'LEFT' : 'RIGHT'}_$limb';
  }

  /// Body parts of a region shape, as the recommender's focus block names
  /// them (ai_server engine.FOCUS_PARTS). A segment between two joints
  /// counts for both; the neck has none.
  static const _shapeParts = {
    'shoulder': ['shoulder'],
    'upperArm': ['shoulder', 'elbow'],
    'elbow': ['elbow'],
    'forearm': ['wrist_hand'],
    'hand': ['wrist_hand'],
    'torsoUpper': ['back'],
    'torsoLower': ['back'],
    'hip': ['hip'],
    'thigh': ['hip', 'knee'],
    'knee': ['knee'],
    'shin': ['ankle_foot'],
    'foot': ['ankle_foot'],
  };

  /// The finer body parts of the tapped regions, sent as focus_parts to
  /// /recommend so it can tell, e.g., a shoulder plan from a hand plan that
  /// share the same body area. Sorted; empty when nothing usable is chosen.
  static List<String> focusParts(Iterable<BodyRegion> regions) => [
    ...{
      for (final r in regions)
        if (r.available) ...?_shapeParts[r.shape],
    },
  ]..sort();

  /// Regions of [view] that a plan for [area] targets, for the plan card.
  static Set<BodyRegion> forArea(String area, BodyView view) {
    bool wanted(BodyRegion r) => switch (area) {
      'LEFT_ARM' => r.group == BodyGroup.arm && r.side == BodySide.left,
      'RIGHT_ARM' => r.group == BodyGroup.arm && r.side == BodySide.right,
      'BOTH_ARMS' => r.group == BodyGroup.arm,
      'LEFT_LEG' => r.group == BodyGroup.leg && r.side == BodySide.left,
      'RIGHT_LEG' => r.group == BodyGroup.leg && r.side == BodySide.right,
      'BOTH_LEGS' => r.group == BodyGroup.leg,
      'CORE' => r.group == BodyGroup.core,
      'FULL_BODY' => true,
      _ => false,
    };
    return {
      for (final r in of(view))
        if (r.available && wanted(r)) r,
    };
  }
}
