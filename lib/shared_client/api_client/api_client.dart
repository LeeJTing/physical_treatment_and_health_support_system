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
  /// Address of the AI server, e.g. https://xxxx.trycloudflare.com or http://192.168.1.20:8000
  /// (the laptop). Starts as the build-time AI_BASE_URL; ServerConnectionService changes it when
  /// the patient saves another address in Profile > AI server.
  String baseUrl;
  final String? Function() _token;
  final http.Client _http;

  ApiClient({
    required this.baseUrl,
    required String? Function() tokenProvider,
    http.Client? httpClient,
  }) : _token = tokenProvider,
       _http = httpClient ?? http.Client();

  /// GET [url]/health without the login token (the endpoint is public). Used to test an address
  /// before it is saved, so it takes the full address instead of [baseUrl].
  Future<Result<Map<String, dynamic>>> health(
    String url, {
    Duration timeout = const Duration(seconds: 8),
  }) => _send(() => _http.get(Uri.parse('$url/health')).timeout(timeout));

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

  /// Multipart upload for an exercise clip (or a meal photo). Without [timeout], the analysis time
  /// plus the time to upload the file at [AppConstants.slowestUploadBytesPerSecond].
  Future<Result<Map<String, dynamic>>> postFile(
    String path,
    File file, {
    Map<String, String> fields = const {},
    Duration? timeout,
  }) => _send(() async {
    final req = http.MultipartRequest('POST', Uri.parse('$baseUrl$path'))
      ..headers.addAll(_headers(json: false))
      ..fields.addAll(fields)
      ..files.add(await http.MultipartFile.fromPath('file', file.path));
    final limit = timeout ?? uploadTimeout(await file.length());
    // The reply is read inside the limit too (bug list #6): a connection that stalled after the
    // headers left the analysing screen waiting for ever.
    return _http.send(req).then(http.Response.fromStream).timeout(limit);
  });

  /// How long an upload of [bytes] may take, analysis included.
  static Duration uploadTimeout(int bytes) =>
      AppConstants.poseTimeout +
      Duration(
        milliseconds: bytes * 1000 ~/ AppConstants.slowestUploadBytesPerSecond,
      );

  /// Multipart upload of bytes already in memory, e.g. a meal photo reduced on the phone
  /// (UC800 C4), as the form field "file".
  Future<Result<Map<String, dynamic>>> postBytes(
    String path,
    List<int> bytes, {
    String filename = 'upload.jpg',
    Map<String, String> fields = const {},
    Duration timeout = AppConstants.defaultTimeout,
  }) => _send(() async {
    final req = http.MultipartRequest('POST', Uri.parse('$baseUrl$path'))
      ..headers.addAll(_headers(json: false))
      ..fields.addAll(fields)
      ..files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
    final streamed = await _http.send(req).timeout(timeout);
    return http.Response.fromStream(streamed).timeout(timeout);
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
    } on http.ClientException catch (e) {
      // A connection that dropped or could not be made, as supabaseGuard treats it (audit, 24 Oct).
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
