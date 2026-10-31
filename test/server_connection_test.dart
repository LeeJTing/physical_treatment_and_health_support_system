import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:physical_treatment_and_health_support_system/device_platform/local_settings/local_settings.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/server_connection_service/server_connection_service.dart';
import 'package:physical_treatment_and_health_support_system/model/result.dart';
import 'package:physical_treatment_and_health_support_system/shared_client/api_client/api_client.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/server_settings_view_model/server_settings_view_model.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/ui_state.dart';

/// The app reaches the AI server on the laptop at an address that can change (Wi-Fi IP or tunnel).
void main() {
  group('ServerConnectionService.normalise', () {
    test('a bare laptop IP becomes http, a name becomes https', () {
      expect(ServerConnectionService.normalise('192.168.1.20:8000'), 'http://192.168.1.20:8000');
      expect(ServerConnectionService.normalise(' abc-def.trycloudflare.com/ '), 'https://abc-def.trycloudflare.com');
      expect(ServerConnectionService.normalise('http://10.0.2.2:8000/health'), 'http://10.0.2.2:8000');
      expect(ServerConnectionService.normalise('https://x.example.com/api/'), 'https://x.example.com/api');
    });

    test('rejects what cannot be an address', () {
      expect(ServerConnectionService.normalise(''), isNull);
      expect(ServerConnectionService.normalise('not an address'), isNull);
      expect(ServerConnectionService.normalise('ftp://host'), isNull);
    });
  });

  group('ServerConnectionService', () {
    late List<Uri> calls;
    late ApiClient api;
    late MemoryLocalSettings store;
    late ServerConnectionService service;

    MockClient laptop({bool up = true}) => MockClient((req) async {
      calls.add(req.url);
      if (!up) throw http.ClientException('Connection refused');
      if (req.url.path == '/health') {
        return http.Response(
          jsonEncode({
            'status': 'ok',
            'version': '0.1.0',
            'modules': {'food_recognition': 'ready', 'analysis': 'loading'},
          }),
          200,
        );
      }
      return http.Response(jsonEncode({'ok': true}), 200);
    });

    void build({bool up = true, Map<String, String>? saved}) {
      calls = [];
      store = MemoryLocalSettings(saved);
      api = ApiClient(baseUrl: 'http://10.0.2.2:8000', tokenProvider: () => 'dev-token', httpClient: laptop(up: up));
      service = ServerConnectionService(api, store, defaultAddress: 'http://10.0.2.2:8000');
    }

    test('restore uses the address saved on the phone', () async {
      build(saved: {ServerConnectionService.settingsKey: 'https://saved.trycloudflare.com'});
      await service.restore();
      expect(api.baseUrl, 'https://saved.trycloudflare.com');
      await api.post('/plan', const {});
      expect(calls.single.toString(), 'https://saved.trycloudflare.com/plan');
    });

    test('test reports version, latency and module readiness without changing the address', () async {
      build();
      final res = await service.test('192.168.1.20:8000');
      expect(res, isA<Success>());
      final s = res.dataOrNull!;
      expect(s.address, 'http://192.168.1.20:8000');
      expect(s.version, '0.1.0');
      expect(s.modules['analysis'], 'loading');
      expect(s.allReady, isFalse);
      expect(calls.single.toString(), 'http://192.168.1.20:8000/health');
      expect(api.baseUrl, 'http://10.0.2.2:8000');
    });

    test('an unreachable laptop gives advice, not a crash', () async {
      build(up: false);
      final res = await service.test('http://192.168.1.20:8000');
      expect(res, isA<Failure>());
      expect((res as Failure).message, contains('same Wi-Fi'));
      final tunnel = await service.test('https://gone.trycloudflare.com');
      expect((tunnel as Failure).message, contains('run_tunnel.ps1'));
    });

    test('save points every AI call at the new address and remembers it; reset goes back', () async {
      build();
      await service.save('192.168.1.20:8000');
      expect(api.baseUrl, 'http://192.168.1.20:8000');
      expect(store.values[ServerConnectionService.settingsKey], 'http://192.168.1.20:8000');
      await service.reset();
      expect(api.baseUrl, 'http://10.0.2.2:8000');
      expect(store.values, isEmpty);
    });

    test('ServerSettingsViewModel: save tests first and says when the server is not up yet', () async {
      build(up: false);
      final vm = ServerSettingsViewModel(service);
      await vm.save('192.168.1.20:8000');
      expect(vm.status, isA<UiError>());
      expect(vm.notice, contains('did not answer yet'));
      expect(vm.address, 'http://192.168.1.20:8000');
    });
  });
}
