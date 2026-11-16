import 'package:physical_treatment_and_health_support_system/device_platform/link_opener/link_opener.dart';
import 'package:physical_treatment_and_health_support_system/model/result.dart';

/// Opens a study in the phone's browser (Elwin, 10 Nov: "should the hyperlink of the research
/// paper"). Not in the report's service list (PROJECT_STATE section 11). Like every service it
/// never throws: a phone without a browser gives a Failure with the address to copy.
class LinkService {
  final LinkOpener _opener;

  LinkService([LinkOpener? opener]) : _opener = opener ?? PluginLinkOpener();

  Future<Result<void>> open(String address) async {
    final failed = Failure<void>(
      'Could not open the link: $address',
      code: 'link_not_opened',
    );
    final uri = Uri.tryParse(address);
    if (uri == null || !uri.hasScheme) return failed;
    final res = await guard(() => _opener.open(uri), code: 'link_not_opened');
    return switch (res) {
      Success(data: true) => const Success<void>(null),
      _ => failed,
    };
  }
}
