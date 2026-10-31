import 'package:physical_treatment_and_health_support_system/device_platform/local_settings/local_settings.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/server_connection_service/server_status.dart';
import 'package:physical_treatment_and_health_support_system/model/result.dart';
import 'package:physical_treatment_and_health_support_system/shared_client/api_client/api_client.dart';

/// Which AI server the app talks to. The server runs on the team's laptop, so its address changes:
/// `http://<laptop IP>:8000` on the same Wi-Fi, or a https://….trycloudflare.com tunnel address that is
/// new each time the tunnel starts. The patient (or the tester) can change it in Profile > AI server
/// without rebuilding the app; the build-time AI_BASE_URL stays the default.
class ServerConnectionService {
  static const String settingsKey = 'ai_server_address';

  final ApiClient _api;
  final LocalSettings _settings;

  /// The build-time address (AI_BASE_URL).
  final String defaultAddress;

  ServerConnectionService(this._api, this._settings, {required this.defaultAddress});

  /// The address every AI call goes to now.
  String get address => _api.baseUrl;

  bool get usingDefault => address == defaultAddress;

  /// At start-up: use the address saved on this phone, if any.
  Future<void> restore() async {
    final saved = normalise(await _settings.read(settingsKey) ?? '');
    if (saved != null) _api.baseUrl = saved;
  }

  /// Turns what was typed into a base URL, or null when it cannot be one.
  /// "192.168.1.20:8000" → http://192.168.1.20:8000 (a laptop on the same Wi-Fi: plain http);
  /// "abc.trycloudflare.com" → https://abc.trycloudflare.com (anything with a name: https).
  /// A trailing slash or /health is removed.
  static String? normalise(String input) {
    var s = input.trim();
    if (s.isEmpty || s.contains(' ')) return null;
    if (!s.contains('://')) {
      final host = s.split('/').first.split(':').first;
      final isIp = RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(host) || host == 'localhost';
      s = '${isIp ? 'http' : 'https'}://$s';
    }
    final uri = Uri.tryParse(s);
    if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https') || uri.host.isEmpty) {
      return null;
    }
    var path = uri.path;
    if (path.endsWith('/health')) path = path.substring(0, path.length - '/health'.length);
    while (path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    return '${uri.scheme}://${uri.authority}$path';
  }

  /// Checks [input] (or the current address) with GET /health.
  Future<Result<ServerStatus>> test([String? input]) async {
    final url = input == null ? address : normalise(input);
    if (url == null) {
      return const Failure(
        'Enter an address such as http://192.168.1.20:8000 or https://xxxx.trycloudflare.com.',
        code: 'invalid_address',
      );
    }
    final watch = Stopwatch()..start();
    final res = await _api.health(url);
    watch.stop();
    return switch (res) {
      Success(:final data) when data['status'] == 'ok' =>
        Success(ServerStatus.fromHealth(url, data, watch.elapsedMilliseconds)),
      Success() => Failure('$url answered, but it is not the HealthGuide AI server.', code: 'not_ai_server'),
      Failure(:final code) => Failure(_hint(url, code), code: code),
    };
  }

  /// Points the app at [input] and remembers it on this phone.
  Future<Result<String>> save(String input) async {
    final url = normalise(input);
    if (url == null) {
      return const Failure('That is not a valid server address.', code: 'invalid_address');
    }
    _api.baseUrl = url;
    await _settings.write(settingsKey, url);
    return Success(url);
  }

  /// Back to the build-time address.
  Future<void> reset() async {
    _api.baseUrl = defaultAddress;
    await _settings.remove(settingsKey);
  }

  static String _hint(String url, String? code) {
    final local = Uri.tryParse(url)?.scheme == 'http';
    final where = local
        ? 'Check that the server is running on the laptop (run_server.ps1 -Lan), that the phone and the '
              'laptop are on the same Wi-Fi, and that the address is the laptop\'s IP shown by the script.'
        : 'Check that the server and the tunnel are running on the laptop (run_server.ps1 and '
              'run_tunnel.ps1) and that this is the address the tunnel printed this time.';
    return switch (code) {
      'timeout' => 'The AI server did not answer in time. $where',
      _ => 'Cannot reach the AI server at $url. $where',
    };
  }
}
