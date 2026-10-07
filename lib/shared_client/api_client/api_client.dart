import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'package:physical_treatment_and_health_support_system/core/constants/app_constants.dart';
import 'package:physical_treatment_and_health_support_system/model/result.dart';

/// Single HTTP entry point to the FastAPI AI server (Table 4.32). Attaches
/// the Supabase access token as a bearer token, applies the per-call
/// timeout, and converts transport errors into a [Failure].
class ApiClient {
  final String baseUrl;
  final String? Function() _token;
  final http.Client _http;

  ApiClient({
    required this.baseUrl,
    required String? Function() tokenProvider,
    http.Client? httpClient,
  }) : _token = tokenProvider,
       _http = httpClient ?? http.Client();

  Map<String, String> _headers({bool json = true}) => {
    if (json) 'Content-Type': 'application/json',
    if (_token() != null) 'Authorization': 'Bearer ${_token()}',
  };

  Future<Result<Map<String, dynamic>>> post(
    String path,
    Map<String, dynamic> body, {
    Duration timeout = AppConstants.defaultTimeout,
  }) => _send(
    () => _http
        .post(
          Uri.parse('$baseUrl$path'),
          headers: _headers(),
          body: jsonEncode(body),
        )
        .timeout(timeout),
  );

  Future<Result<Map<String, dynamic>>> get(
    String path, {
    Map<String, String>? query,
    Duration timeout = AppConstants.defaultTimeout,
  }) => _send(
    () => _http
        .get(
          Uri.parse('$baseUrl$path').replace(queryParameters: query),
          headers: _headers(),
        )
        .timeout(timeout),
  );

  /// Multipart upload for an exercise clip (or a meal photo).
  Future<Result<Map<String, dynamic>>> postFile(
    String path,
    File file, {
    Map<String, String> fields = const {},
    Duration timeout = AppConstants.poseTimeout,
  }) => _send(() async {
    final req = http.MultipartRequest('POST', Uri.parse('$baseUrl$path'))
      ..headers.addAll(_headers(json: false))
      ..fields.addAll(fields)
      ..files.add(await http.MultipartFile.fromPath('file', file.path));
    final streamed = await _http.send(req).timeout(timeout);
    return http.Response.fromStream(streamed);
  });

  Future<Result<Map<String, dynamic>>> _send(
    Future<http.Response> Function() call,
  ) async {
    try {
      final res = await call();
      Map<String, dynamic> body;
      try {
        body = res.body.isEmpty
            ? <String, dynamic>{}
            : jsonDecode(res.body) as Map<String, dynamic>;
      } catch (_) {
        body = {'detail': res.body};
      }
      if (res.statusCode == 401) {
        return const Failure(
          'Your session has expired. Please log in again.',
          code: 'unauthorised',
        );
      }
      if (res.statusCode >= 400) {
        final err = body['error'];
        final code = err is Map ? err['code']?.toString() : null;
        final msg = err is Map
            ? err['message']?.toString()
            : body['detail']?.toString();
        return Failure(
          msg ?? 'Server error (${res.statusCode}).',
          code: code ?? 'http_${res.statusCode}',
        );
      }
      return Success(body);
    } on TimeoutException catch (e) {
      return Failure(
        'The service is temporarily unavailable. Please try again later.',
        code: 'timeout',
        cause: e,
      );
    } on SocketException catch (e) {
      return Failure(
        'No connection to the server. Please check your internet connection.',
        code: 'offline',
        cause: e,
      );
    } catch (e) {
      return Failure(
        'The service is temporarily unavailable. Please try again later.',
        code: 'unknown',
        cause: e,
      );
    }
  }
}
