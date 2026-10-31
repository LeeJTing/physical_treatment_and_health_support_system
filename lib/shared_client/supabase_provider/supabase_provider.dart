import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Wraps the Supabase client and exposes the signed-in account (Table 4.34).
/// The only component that holds the session token. RLS scopes every query
/// to auth.uid(), so repositories never filter by account by hand.
class SupabaseProvider {
  final SupabaseClient client;

  /// Project URL and publishable key, kept for the public Auth settings endpoint.
  final String url;
  final String publishableKey;
  final http.Client _http;

  SupabaseProvider(
    this.client, {
    this.url = '',
    this.publishableKey = '',
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  static Future<SupabaseProvider> initialise({
    required String url,
    required String publishableKey,
  }) async {
    await Supabase.initialize(url: url, publishableKey: publishableKey);
    return SupabaseProvider(
      Supabase.instance.client,
      url: url,
      publishableKey: publishableKey,
    );
  }

  String? get currentAccountId => client.auth.currentUser?.id;

  String? get accessToken => client.auth.currentSession?.accessToken;

  SupabaseQueryBuilder from(String table) => client.from(table);

  Stream<AuthState> onAuthChange() => client.auth.onAuthStateChange;

  /// Which sign-in providers are switched on in this Supabase project (GET /auth/v1/settings,
  /// public, needs only the publishable key), e.g. {"google": true, "email": true}.
  /// Throws when the project cannot be reached; callers wrap it in supabaseGuard.
  Future<Map<String, bool>> enabledProviders({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final res = await _http
        .get(
          Uri.parse('${url.replaceAll(RegExp(r'/+$'), '')}/auth/v1/settings'),
          headers: {'apikey': publishableKey},
        )
        .timeout(timeout);
    if (res.statusCode != 200) {
      throw http.ClientException('Auth settings: HTTP ${res.statusCode}');
    }
    final external = (jsonDecode(res.body) as Map)['external'] as Map? ?? const {};
    return {for (final e in external.entries) e.key.toString(): e.value == true};
  }
}
