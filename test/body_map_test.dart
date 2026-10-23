import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:physical_treatment_and_health_support_system/core/utils/body_regions.dart';
import 'package:physical_treatment_and_health_support_system/view/common/choice_card.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/rehab_info.dart';
import 'package:physical_treatment_and_health_support_system/view/planning_view/rehab_questionnaire_sheet.dart';
import 'package:physical_treatment_and_health_support_system/view/planning_view/widgets/body_map.dart';

BodyRegion r(String id) => BodyRegions.byId[id]!;

String? area(List<String> ids) =>
    BodyRegions.areaFor([for (final id in ids) r(id)]);

/// A 360 x 800 phone screen, optionally with large text.
void phone(WidgetTester t, {double textScale = 1}) {
  t.view.physicalSize = const Size(1080, 2400);
  t.view.devicePixelRatio = 3;
  t.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(t.view.reset);
  addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
}

/// Hosts a BodyMap and keeps its selection, like the questionnaire does.
Widget host(Set<String> Function() get, void Function(Set<String>) set) =>
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: StatefulBuilder(
            builder: (context, setState) => BodyMap(
              selected: get(),
              onChanged: (s) => setState(() => set(s)),
            ),
          ),
        ),
      ),
    );

Future<void> tapRegion(
  WidgetTester t,
  String id, {
  Offset shift = Offset.zero,
}) async {
  final canvas = find.byKey(BodyMap.canvasKey);
  final layout = BodyMapLayout(t.getSize(canvas));
  await t.tapAt(
    t.getTopLeft(canvas) + layout.toScreen(BodyShapes.centreOf(r(id))) + shift,
  );
  await t.pump();
}

/// Scrolls the questionnaire's own list until [f] is built and on screen.
Future<void> reveal(WidgetTester t, Finder f) async {
  await t.scrollUntilVisible(
    f,
    150,
    scrollable: find
        .descendant(
          of: find.byType(ListView),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await t.pumpAndSettle();
}

void main() {
  group('mapping regions to the affected body area', () {
    test('arms only', () {
      expect(area(['front_left_elbow']), 'LEFT_ARM');
      expect(
        area(['front_right_shoulder', 'back_right_upper_arm']),
        'RIGHT_ARM',
      );
      expect(area(['front_left_hand', 'front_right_forearm']), 'BOTH_ARMS');
    });
    test('legs only, buttocks and hips count as legs', () {
      expect(area(['front_left_knee']), 'LEFT_LEG');
      expect(area(['back_right_buttock', 'back_right_calf']), 'RIGHT_LEG');
      expect(area(['front_left_hip', 'back_right_heel']), 'BOTH_LEGS');
    });
    test('core only', () {
      expect(area(['back_lower_back', 'front_chest']), 'CORE');
    });
    test('the neck is never part of the area', () {
      expect(r('front_neck').available, isFalse);
      expect(r('back_neck').available, isFalse);
      expect(r('front_neck').unavailableNote, BodyRegions.neckNote);
      expect(area(['front_neck']), isNull);
      expect(area(['front_neck', 'back_neck']), isNull);
      expect(area(['back_neck', 'front_left_knee']), 'LEFT_LEG');
      // Neck + an arm is the arm alone, not full body.
      expect(area(['front_neck', 'front_right_elbow']), 'RIGHT_ARM');
      expect(area(['front_neck', 'back_upper_back']), 'CORE');
    });
    test('only the two neck regions are unavailable', () {
      expect([
        for (final x in BodyRegions.byId.values)
          if (!x.available) x.id,
      ], unorderedEquals(['front_neck', 'back_neck']));
    });
    test('two or more groups give full body', () {
      expect(area(['front_left_knee', 'front_left_elbow']), 'FULL_BODY');
      expect(area(['back_upper_back', 'front_right_knee']), 'FULL_BODY');
      expect(
        area(['front_abdomen', 'front_left_hand', 'back_left_calf']),
        'FULL_BODY',
      );
    });
    test('nothing selected', () => expect(area([]), isNull));
    test('every available region maps to one of the eight areas', () {
      for (final reg in BodyRegions.byId.values.where((x) => x.available)) {
        expect(RehabInfo.bodyAreas, contains(BodyRegions.areaFor([reg])));
      }
    });
    test('about twenty regions per view, unique ids', () {
      expect(BodyRegions.front.length, inInclusiveRange(18, 24));
      expect(BodyRegions.back.length, inInclusiveRange(18, 24));
      expect(
        BodyRegions.byId.length,
        BodyRegions.front.length + BodyRegions.back.length,
      );
    });
  });

  group('focus parts for the recommender', () {
    List<String> parts(List<String> ids) =>
        BodyRegions.focusParts([for (final id in ids) r(id)]);
    test('each region gives its body parts', () {
      expect(parts(['front_right_hand']), ['wrist_hand']);
      expect(parts(['front_left_forearm']), ['wrist_hand']);
      expect(parts(['back_right_shoulder']), ['shoulder']);
      expect(parts(['front_left_upper_arm']), ['elbow', 'shoulder']);
      expect(parts(['back_left_heel', 'front_right_knee']), [
        'ankle_foot',
        'knee',
      ]);
      expect(parts(['back_lower_back', 'front_abdomen']), ['back']);
    });
    test('the neck adds nothing, both sides count once', () {
      expect(parts(['front_neck', 'back_neck']), isEmpty);
      expect(parts(['front_left_hand', 'front_right_hand']), ['wrist_hand']);
    });
    test('every available region has at least one known part', () {
      const known = {
        'shoulder',
        'elbow',
        'wrist_hand',
        'hip',
        'knee',
        'ankle_foot',
        'back',
      };
      for (final x in BodyRegions.byId.values.where((x) => x.available)) {
        expect(BodyRegions.focusParts([x]), isNotEmpty, reason: x.id);
        expect(known.containsAll(BodyRegions.focusParts([x])), isTrue);
      }
    });
  });

  group('grouping by limb (Elwin, 9 Oct)', () {
    List<RegionCluster> groups(List<String> ids) =>
        BodyRegions.clusters([for (final id in ids) r(id)]);
    const rightArm = [
      'front_right_shoulder',
      'front_right_upper_arm',
      'front_right_elbow',
      'front_right_forearm',
      'front_right_hand',
    ];
    test('places on one limb form one group, in a fixed order', () {
      final g = groups([...rightArm, 'front_left_knee', 'front_chest']);
      expect([for (final c in g) c.title], ['Right arm', 'Trunk', 'Left leg']);
      expect(g.first.regions, hasLength(5));
    });
    test('chip text names the parts, or the region when alone', () {
      expect(groups(['front_left_knee']).single.summary, 'Left knee');
      expect(
        groups(['front_right_elbow', 'back_right_elbow']).single.summary,
        'Right arm: elbow, back of elbow',
      );
      expect(
        groups(rightArm).single.summary,
        'Right arm: shoulder, upper arm and 3 more',
      );
    });
    test('map label: own name, two trunk names, or a count', () {
      String label(List<String> ids) =>
          RegionCluster.mapLabel(groups(ids).single);
      expect(label(['front_left_shoulder']), 'Left shoulder');
      expect(label(['front_chest', 'front_abdomen']), 'Chest, abdomen');
      expect(label(rightArm), 'Right arm (5)');
    });
    test('the neck never forms a group', () {
      expect(groups(['front_neck', 'back_neck']), isEmpty);
    });
  });

  group('person\'s side vs screen side', () {
    test('front: the person\'s right is on the screen\'s left', () {
      expect(r('front_right_knee').onScreenLeft, isTrue);
      expect(r('front_left_knee').onScreenLeft, isFalse);
    });
    test('back: the person\'s right is on the screen\'s right', () {
      expect(r('back_right_knee').onScreenLeft, isFalse);
      expect(r('back_left_knee').onScreenLeft, isTrue);
    });
    test('labels say the person\'s side', () {
      expect(r('front_right_knee').label, 'Right knee');
      expect(r('back_left_thigh').label, 'Back of left thigh');
      expect(r('back_upper_back').label, 'Upper back');
    });
    test('every region\'s centre hits that region', () {
      const size = Size(328, 380);
      final layout = BodyMapLayout(size);
      for (final view in BodyView.values) {
        for (final reg in BodyRegions.of(view)) {
          final hit = bodyRegionAt(
            view,
            size,
            layout.toScreen(BodyShapes.centreOf(reg)),
          );
          expect(hit?.id, reg.id);
        }
      }
    });
  });

  group('BodyMap widget', () {
    testWidgets('tap selects with a label and chip, tap again deselects', (
      t,
    ) async {
      phone(t);
      var sel = <String>{};
      await t.pumpWidget(host(() => sel, (s) => sel = s));
      await tapRegion(t, 'front_right_knee');
      expect(sel, {'front_right_knee'});
      expect(find.text('Right knee'), findsNWidgets(2)); // label + chip
      expect(find.text('Your plan will focus on: Right leg'), findsOneWidget);
      await tapRegion(t, 'front_right_knee');
      expect(sel, isEmpty);
      expect(find.text('Right knee'), findsNothing);
    });

    testWidgets(
      'screen left in the front view is the right side, in the back view the left',
      (t) async {
        phone(t);
        var sel = <String>{};
        await t.pumpWidget(host(() => sel, (s) => sel = s));
        final canvas = find.byKey(BodyMap.canvasKey);
        final layout = BodyMapLayout(t.getSize(canvas));
        // The same screen point (screen-left knee) in both views.
        final point =
            t.getTopLeft(canvas) +
            layout.toScreen(BodyShapes.centreOf(r('front_right_knee')));
        await t.tapAt(point);
        await t.pump();
        expect(sel, {'front_right_knee'});
        await t.tap(find.text('Back'));
        await t.pumpAndSettle();
        await t.tapAt(point);
        await t.pump();
        expect(sel, {'front_right_knee', 'back_left_knee'});
        expect(find.text('Back of left knee'), findsNWidgets(2));
        expect(find.text('Your plan will focus on: Both legs'), findsOneWidget);
      },
    );

    testWidgets('switching front and back keeps the selection', (t) async {
      phone(t);
      var sel = <String>{};
      await t.pumpWidget(host(() => sel, (s) => sel = s));
      await tapRegion(t, 'front_left_elbow');
      await t.tap(find.text('Back'));
      await t.pumpAndSettle();
      await tapRegion(t, 'back_lower_back');
      await t.tap(find.text('Front'));
      await t.pumpAndSettle();
      expect(sel, {'front_left_elbow', 'back_lower_back'});
      expect(
        find.text('Left elbow'),
        findsNWidgets(2),
      ); // label shown again in front
      expect(find.text('Lower back'), findsOneWidget); // chip only (other view)
      expect(find.text('Your plan will focus on: Full body'), findsOneWidget);
    });

    testWidgets('small parts have an enlarged hit area', (t) async {
      phone(t);
      var sel = <String>{};
      await t.pumpWidget(host(() => sel, (s) => sel = s));
      // 15 logical px below the hand centre is outside the drawn hand at this scale.
      await tapRegion(t, 'front_right_hand', shift: const Offset(0, 15));
      expect(sel, {'front_right_hand'});
    });

    testWidgets('chips remove a part and Clear removes all', (t) async {
      phone(t);
      var sel = <String>{};
      await t.pumpWidget(host(() => sel, (s) => sel = s));
      await tapRegion(t, 'front_left_knee');
      await tapRegion(t, 'front_chest');
      await t.tap(find.byTooltip('Remove Chest'));
      await t.pump();
      expect(sel, {'front_left_knee'});
      await t.tap(find.text('Clear'));
      await t.pump();
      expect(sel, isEmpty);
    });

    testWidgets('every region has a semantics label and selected state', (
      t,
    ) async {
      phone(t);
      final handle = t.ensureSemantics();
      var sel = <String>{'front_right_knee'};
      await t.pumpWidget(host(() => sel, (s) => sel = s));
      // The regions are semantics nodes of the painter, so search the tree.
      for (final reg in BodyRegions.front.where((x) => x.available)) {
        expect(
          find.semantics.byLabel(reg.label),
          findsAtLeast(1),
          reason: reg.label,
        );
      }
      // 'Right knee' is also the chip's label; the figure's node is the
      // selectable button.
      expect(
        find.semantics.byLabel('Right knee').evaluate(),
        contains(
          isSemantics(
            label: 'Right knee',
            isButton: true,
            hasSelectedState: true,
            isSelected: true,
            hasTapAction: true,
          ),
        ),
      );
      expect(
        find.semantics.byLabel('Right shin').evaluate().single,
        isSemantics(isButton: true, isSelected: false),
      );
      // A screen reader's double-tap selects the region too.
      t.semantics.tap(find.semantics.byLabel('Right shin'));
      await t.pump();
      expect(sel, {'front_right_knee', 'front_right_shin'});
      handle.dispose();
    });

    testWidgets('tapping the neck shows the note and selects nothing', (
      t,
    ) async {
      phone(t);
      var sel = <String>{};
      await t.pumpWidget(host(() => sel, (s) => sel = s));
      await tapRegion(t, 'front_neck');
      expect(sel, isEmpty);
      expect(find.text(BodyRegions.neckNote), findsOneWidget);
      expect(find.textContaining('Your plan will focus on'), findsNothing);
      // The back of the neck too.
      await t.tap(find.text('Back'));
      await t.pumpAndSettle();
      await tapRegion(t, 'back_neck');
      expect(sel, isEmpty);
      expect(find.text(BodyRegions.neckNote), findsOneWidget);
      // Choosing an available region hides the note.
      await tapRegion(t, 'back_upper_back');
      expect(sel, {'back_upper_back'});
      expect(find.text(BodyRegions.neckNote), findsNothing);
    });

    testWidgets('the neck says not available to screen readers', (t) async {
      phone(t);
      final handle = t.ensureSemantics();
      var sel = <String>{};
      await t.pumpWidget(host(() => sel, (s) => sel = s));
      final neck = find.semantics.byLabel('Neck, not available');
      expect(
        neck.evaluate().single,
        isSemantics(
          hint: BodyRegions.neckNote,
          hasEnabledState: true,
          isEnabled: false,
          hasSelectedState: false,
        ),
      );
      t.semantics.tap(neck);
      await t.pump();
      expect(sel, isEmpty);
      expect(find.text(BodyRegions.neckNote), findsOneWidget);
      handle.dispose();
    });

    testWidgets('a neck id left in the selection is not shown as chosen', (
      t,
    ) async {
      phone(t);
      var sel = <String>{'front_neck', 'front_left_knee'};
      await t.pumpWidget(host(() => sel, (s) => sel = s));
      expect(find.byType(InputChip), findsOneWidget);
      expect(find.text('Your plan will focus on: Left leg'), findsOneWidget);
    });

    testWidgets(
      'everything selected: a few grouped labels, none cut or overlapping',
      (t) async {
        phone(t);
        var sel = {
          for (final x in BodyRegions.front)
            if (x.available) x.id,
        };
        await t.pumpWidget(host(() => sel, (s) => sel = s));
        await t.pumpAndSettle();
        final labels = [
          for (final text in [
            'Right arm (5)',
            'Left arm (5)',
            'Chest, abdomen',
            'Right leg (5)',
            'Left leg (5)',
          ])
            find.text(text),
        ];
        for (final l in labels) {
          expect(l, findsOneWidget);
        }
        // Every label's text fits its box (the 'Left' for 'Left shoulder' bug).
        for (final e in find.byType(Text).evaluate()) {
          final para = e.renderObject;
          if (para is RenderParagraph && para.didExceedMaxLines) {
            fail('cut text: ${para.text.toPlainText()}');
          }
        }
        final rects = [for (final l in labels) t.getRect(l)];
        for (var i = 0; i < rects.length; i++) {
          for (var j = i + 1; j < rects.length; j++) {
            expect(rects[i].overlaps(rects[j]), isFalse);
          }
        }
        // One chip per group, not one per place.
        expect(find.byType(InputChip), findsNWidgets(5));
      },
    );

    testWidgets('a single long label is shown whole', (t) async {
      phone(t);
      var sel = <String>{'front_left_shoulder'};
      await t.pumpWidget(host(() => sel, (s) => sel = s));
      await t.pumpAndSettle();
      for (final e in find.text('Left shoulder').evaluate()) {
        expect((e.renderObject! as RenderParagraph).didExceedMaxLines, isFalse);
      }
    });

    testWidgets('a limb chip removes the whole limb', (t) async {
      phone(t);
      var sel = <String>{
        'front_right_shoulder',
        'front_right_elbow',
        'back_right_elbow',
        'front_left_knee',
      };
      await t.pumpWidget(host(() => sel, (s) => sel = s));
      await t.tap(find.byTooltip('Remove Right arm'));
      await t.pump();
      expect(sel, {'front_left_knee'});
    });

    testWidgets('no overflow with 2x text on 360x800', (t) async {
      phone(t, textScale: 2);
      var sel = <String>{};
      await t.pumpWidget(host(() => sel, (s) => sel = s));
      for (final id in [
        'front_right_shoulder',
        'front_right_knee',
        'front_left_hand',
        'front_chest',
        'front_left_foot',
      ]) {
        await tapRegion(t, id);
      }
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    });
  });

  group('questionnaire', () {
    Future<RehabInfo?> answer(
      WidgetTester t,
      Future<void> Function() pickArea, {
      Future<void> Function()? then,
    }) async {
      RehabInfo? result;
      await t.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async =>
                    result = await showRehabQuestionnaire(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      await pickArea();
      for (final option in ['Early', 'Low', 'Move more freely']) {
        await reveal(t, find.text(option));
        await t.tap(find.text(option));
        await t.pump();
      }
      await then?.call();
      await t.tap(find.text('Find my plans'));
      await t.pumpAndSettle();
      return result;
    }

    testWidgets('returns the area mapped from the body map', (t) async {
      phone(t);
      final rehab = await answer(t, () async {
        await tapRegion(t, 'front_right_knee');
        await tapRegion(t, 'front_left_knee');
      });
      expect(rehab?.affectedBodyArea, 'BOTH_LEGS');
      expect(rehab?.focusParts, ['knee']);
    });

    Future<RehabInfo?> withPaceTaps(WidgetTester t, List<String> taps) =>
        answer(
          t,
          () => tapRegion(t, 'front_left_knee'),
          then: () async {
            for (final label in taps) {
              await reveal(t, find.text(label));
              await t.tap(find.text(label));
              await t.pump();
            }
          },
        );

    testWidgets('the pace is optional', (t) async {
      phone(t);
      expect((await withPaceTaps(t, []))?.pace, isNull);
    });

    testWidgets('the chosen pace is returned', (t) async {
      phone(t);
      expect((await withPaceTaps(t, ['Faster', 'Steady']))?.pace, 'MEDIUM');
    });

    testWidgets('tapping the chosen pace again clears it', (t) async {
      phone(t);
      expect((await withPaceTaps(t, ['Faster', 'Faster']))?.pace, isNull);
    });

    testWidgets('answer cards say which one is chosen', (t) async {
      phone(t);
      final handle = t.ensureSemantics();
      await t.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showRehabQuestionnaire(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      await reveal(t, find.text('Early'));
      await t.tap(find.text('Early'));
      await t.pump();
      expect(
        t.getSemantics(
          find
              .ancestor(
                of: find.text('Early'),
                matching: find.byType(Semantics),
              )
              .first,
        ),
        isSemantics(isSelected: true, hasSelectedState: true, isButton: true),
      );
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
      handle.dispose();
    });

    testWidgets('Find my plans stays disabled until a part is chosen', (
      t,
    ) async {
      phone(t);
      final rehab = await answer(t, () async {});
      expect(rehab, isNull); // button disabled, sheet still open
      expect(find.text('Find my plans'), findsOneWidget);
    });

    testWidgets('the list fallback still offers the eight options', (t) async {
      phone(t);
      final rehab = await answer(t, () async {
        await reveal(t, find.text("Can't find it? Choose from a list"));
        await t.tap(find.text("Can't find it? Choose from a list"));
        await t.pumpAndSettle();
        expect(find.text('Full body'), findsOneWidget);
        await t.tap(find.text('Core and back'));
        await t.pumpAndSettle();
      });
      expect(rehab?.affectedBodyArea, 'CORE');
    });

    testWidgets('sheet has no overflow with 2x text on 360x800', (t) async {
      phone(t, textScale: 2);
      await t.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showRehabQuestionnaire(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      await tapRegion(t, 'front_left_knee');
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    });
  });

  testWidgets(
    'a sheet closed by mistake opens again with the answers given (emulator, 24 Oct)',
    (t) async {
      final draft = RehabDraft();
      await t.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showRehabQuestionnaire(context, draft: draft),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      await reveal(t, find.text('Early'));
      await t.tap(find.text('Early'));
      await t.pump();
      await t.tapAt(const Offset(10, 10)); // outside the sheet: it closes
      await t.pumpAndSettle();
      expect(find.text('Early'), findsNothing);

      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      await reveal(t, find.text('Early'));
      final early = t.widget<ChoiceCard>(
        find.ancestor(of: find.text('Early'), matching: find.byType(ChoiceCard)),
      );
      expect(early.selected, isTrue); // before: a new, empty questionnaire
    },
  );

  group('plan card thumbnail', () {
    const expected = {
      'LEFT_ARM': (BodyGroup.arm, {BodySide.left}),
      'RIGHT_ARM': (BodyGroup.arm, {BodySide.right}),
      'BOTH_ARMS': (BodyGroup.arm, {BodySide.left, BodySide.right}),
      'LEFT_LEG': (BodyGroup.leg, {BodySide.left}),
      'RIGHT_LEG': (BodyGroup.leg, {BodySide.right}),
      'BOTH_LEGS': (BodyGroup.leg, {BodySide.left, BodySide.right}),
      'CORE': (BodyGroup.core, {BodySide.centre}),
    };

    test('highlights the right regions for all eight areas', () {
      for (final e in expected.entries) {
        final got = BodyMapThumbnail(area: e.key).highlighted;
        expect(got, isNotEmpty, reason: e.key);
        expect(
          got.every(
            (x) => x.group == e.value.$1 && e.value.$2.contains(x.side),
          ),
          isTrue,
          reason: e.key,
        );
        expect({for (final x in got) x.side}, e.value.$2, reason: e.key);
        // and the highlighted area maps back to the same code
        expect(BodyRegions.areaFor(got), e.key);
      }
      final full = BodyMapThumbnail(area: 'FULL_BODY').highlighted;
      // Everything but the neck.
      expect(full.length, BodyRegions.front.length - 1);
      for (final a in [...expected.keys, 'FULL_BODY']) {
        for (final v in BodyView.values) {
          expect(
            BodyRegions.forArea(a, v).where((x) => !x.available),
            isEmpty,
            reason: '$a $v',
          );
        }
      }
      expect(BodyRegions.areaFor(full), 'FULL_BODY');
    });

    testWidgets('has a readable label for screen readers', (t) async {
      final handle = t.ensureSemantics();
      await t.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: BodyMapThumbnail(area: 'LEFT_LEG')),
        ),
      );
      expect(find.bySemanticsLabel('Target area: Left leg'), findsOneWidget);
      handle.dispose();
    });
  });

  // The parts the map sends as focus_parts must be the ones the server knows (FOCUS_PARTS in
  // ai_server/app/recommend/engine.py); this reads that file (audit, 24 Oct).
  test('every focus part of the map is one the server recommender knows', () {
    final py = File('ai_server/app/recommend/engine.py').readAsStringSync();
    final line = RegExp(
      r'^FOCUS_PARTS = \(([^)]*)\)',
      multiLine: true,
    ).firstMatch(py)!;
    final server = {
      for (final m in RegExp(r'"(\w+)"').allMatches(line[1]!)) m[1]!,
    };
    final sent = BodyRegions.focusParts([
      ...BodyRegions.front,
      ...BodyRegions.back,
    ]);
    expect(sent.toSet(), server);
  });
}
