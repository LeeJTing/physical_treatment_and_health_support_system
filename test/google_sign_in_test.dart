import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:physical_treatment_and_health_support_system/core/constants/app_constants.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/auth_repository/supabase_auth_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/result.dart';
import 'package:physical_treatment_and_health_support_system/shared_client/supabase_provider/supabase_provider.dart';

/// Continue with Google (FR100_018) asks the Supabase project first whether the Google provider is
/// switched on, so a project without it explains instead of opening a browser error page.
void main() {
  const url = 'https://demo-ref.supabase.co';
  late List<http.Request> calls;

  SupabaseProvider provider({bool google = true, int status = 200, bool offline = false}) {
    calls = [];
    final mock = MockClient((req) async {
      calls.add(req);
      if (offline) throw http.ClientException('Failed host lookup');
      return http.Response(
        jsonEncode({
          'external': {'email': true, 'google': google, 'github': false},
          'disable_signup': false,
        }),
        status,
      );
    });
    return SupabaseProvider(
      SupabaseClient(url, 'sb_publishable_test'),
      url: '$url/',
      publishableKey: 'sb_publishable_test',
      httpClient: mock,
    );
  }

  test('reads which providers the project has switched on, with the publishable key only', () async {
    final p = provider();
    final providers = await p.enabledProviders();
    expect(providers['google'], isTrue);
    expect(providers['github'], isFalse);
    expect(calls.single.url.toString(), '$url/auth/v1/settings');
    expect(calls.single.headers['apikey'], 'sb_publishable_test');
    expect(calls.single.headers.containsKey('Authorization'), isFalse);
  });

  test('Google switched off in the project: the app explains instead of opening the browser', () async {
    final res = await SupabaseAuthRepository(provider(google: false)).signInWithGoogle();
    expect(res, isA<Failure>());
    expect((res as Failure).code, 'unsupported');
    expect(res.message, Messages.googleNotAvailable);
  });

  test('project unreachable: the usual offline message, no browser', () async {
    final res = await SupabaseAuthRepository(provider(offline: true)).signInWithGoogle();
    expect((res as Failure).code, 'offline');
  });

  test('the return link is the one registered in AndroidManifest and Supabase Redirect URLs', () {
    expect(SupabaseAuthRepository.oauthRedirect, 'my.edu.tarumt.apths://login-callback');
  });
}
