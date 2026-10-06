import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:physical_treatment_and_health_support_system/core/base/result.dart';
import 'package:physical_treatment_and_health_support_system/core/constants/app_constants.dart';

/// Message shown when the phone cannot reach Supabase.
const String offlineMessage =
    'No connection to the server. Please check your internet connection.';

/// Runs one Supabase call and turns every exception into a [Failure], so the
/// Supabase repositories never throw (same contract as the fakes).
///
/// Codes: 'offline' (no network), 'timeout', the Supabase error code for
/// Auth and database errors (the ViewModels map those to the report's
/// messages), 'unknown' otherwise. Raw database messages are never shown to
/// the patient; they stay in [Failure.cause] for debugging.
Future<Result<T>> supabaseGuard<T>(
  Future<T> Function() body, {
  String failMessage = Messages.dbUnavailable,
}) async {
  try {
    return Success<T>(await body().timeout(AppConstants.defaultTimeout));
  } on TimeoutException catch (e) {
    return Failure<T>(failMessage, code: 'timeout', cause: e);
  } on SocketException catch (e) {
    return Failure<T>(offlineMessage, code: 'offline', cause: e);
  } on http.ClientException catch (e) {
    return Failure<T>(offlineMessage, code: 'offline', cause: e);
  } on AuthRetryableFetchException catch (e) {
    return Failure<T>(offlineMessage, code: 'offline', cause: e);
  } on AuthException catch (e) {
    return Failure<T>(e.message, code: e.code ?? e.statusCode, cause: e);
  } on PostgrestException catch (e) {
    return Failure<T>(failMessage, code: e.code, cause: e);
  } catch (e) {
    return Failure<T>(failMessage, code: 'unknown', cause: e);
  }
}
