import 'package:flutter_test/flutter_test.dart';

import 'package:physical_treatment_and_health_support_system/device_platform/local_settings/local_settings.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/user_guide_service/user_guide_service.dart';
import 'package:physical_treatment_and_health_support_system/view/common/user_guide.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/user_guide_view_model/user_guide_view_model.dart';

void main() {
  test('a picture guide opens by itself once per phone, and again after "show the guides again"', () async {
    final settings = MemoryLocalSettings();
    final vm = UserGuideViewModel(UserGuideService(settings));
    expect(await vm.shouldShow('diet'), isTrue);
    await vm.markSeen('diet');
    expect(await vm.shouldShow('diet'), isFalse); // the same visit
    final later = UserGuideViewModel(UserGuideService(settings)); // the app opened again
    expect(await later.shouldShow('diet'), isFalse);
    expect(await later.shouldShow('tracking'), isTrue);
    await later.showAllAgain(Guides.all.map((g) => g.key));
    expect(await later.shouldShow('diet'), isTrue);
  });

  test('every guide has a title and 3 or 4 short steps', () {
    expect(Guides.all.map((g) => g.key).toSet(), hasLength(Guides.all.length));
    for (final g in Guides.all) {
      expect(g.title, isNotEmpty);
      expect(g.steps.length, inInclusiveRange(3, 4));
      for (final s in g.steps) {
        expect(s.text.split(' ').length, lessThanOrEqualTo(40), reason: s.title);
      }
    }
  });
}
