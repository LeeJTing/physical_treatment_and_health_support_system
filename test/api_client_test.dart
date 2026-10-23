// ApiClient (Table 4.32): every transport problem becomes a Failure with a code the services map
// to the report's messages (audit, 24 Oct).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:physical_treatment_and_health_support_system/model/result.dart';
import 'package:physical_treatment_and_health_support_system/shared_client/api_client/api_client.dart';

ApiClient _client(MockClientHandler handler, {String? token = 't'}) =>
    ApiClient(
      baseUrl: 'http://ai',
      tokenProvider: () => token,
      httpClient: MockClient(handler),
    );

Future<String?> _code(Future<Result<Map<String, dynamic>>> call) async =>
    switch (await call) {
      Failure(:final code) => code,
      Success() => null,
    };

void main() {
  test('the token goes as a bearer token; a 200 body comes back', () async {
    String? auth;
    final c = _client((r) async {
      auth = r.headers['Authorization'];
      return http.Response(jsonEncode({'ok': true}), 200);
    });
    final res = await c.get('/health');
    expect(auth, 'Bearer t');
    expect(res.dataOrNull, {'ok': true});
  });

  test(
    '401 is unauthorised; the server error contract keeps its code',
    () async {
      expect(
        await _code(_client((_) async => http.Response('', 401)).get('/x')),
        'unauthorised',
      );
      final body = jsonEncode({
        'error': {'code': 'invalid_video', 'message': 'Too short'},
      });
      expect(
        await _code(_client((_) async => http.Response(body, 422)).get('/x')),
        'invalid_video',
      );
    },
  );

  test(
    'a non-JSON error page (tunnel down) is a failure with the status',
    () async {
      final c = _client(
        (_) async => http.Response('<html>Bad gateway</html>', 502),
      );
      expect(await _code(c.get('/x')), 'http_502');
    },
  );

  test('no connection is offline, also as an http ClientException', () async {
    expect(
      await _code(
        _client((_) async => throw const SocketException('down')).get('/x'),
      ),
      'offline',
    );
    expect(
      await _code(
        _client(
          (_) async => throw http.ClientException('Connection closed'),
        ).get('/x'),
      ),
      'offline',
    );
  });

  test('too slow is timeout', () async {
    final c = _client((_) => Completer<http.Response>().future);
    expect(
      await _code(
        c.post('/x', const {}, timeout: const Duration(milliseconds: 10)),
      ),
      'timeout',
    );
  });
}
