import 'package:url_launcher/url_launcher.dart';

/// Opens a web address in the phone's browser (Elwin, 10 Nov: the research links on the posture
/// result). Behind an interface so tests use a fake and no view calls the plugin directly.
abstract interface class LinkOpener {
  /// True when a browser took the address.
  Future<bool> open(Uri address);
}

/// [LinkOpener] on url_launcher: the address opens outside the app, in the browser.
class PluginLinkOpener implements LinkOpener {
  @override
  Future<bool> open(Uri address) =>
      launchUrl(address, mode: LaunchMode.externalApplication);
}
