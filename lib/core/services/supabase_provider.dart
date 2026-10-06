import 'package:supabase_flutter/supabase_flutter.dart';

/// Wraps the Supabase client and exposes the signed-in account (Table 4.34).
/// The only component that holds the session token. RLS scopes every query
/// to auth.uid(), so repositories never filter by account by hand.
class SupabaseProvider {
  final SupabaseClient client;

  SupabaseProvider(this.client);

  static Future<SupabaseProvider> initialise({required String url, required String publishableKey}) async {
    await Supabase.initialize(url: url, publishableKey: publishableKey);
    return SupabaseProvider(Supabase.instance.client);
  }

  String? get currentAccountId => client.auth.currentUser?.id;

  String? get accessToken => client.auth.currentSession?.accessToken;

  SupabaseQueryBuilder from(String table) => client.from(table);

  Stream<AuthState> onAuthChange() => client.auth.onAuthStateChange;
}
