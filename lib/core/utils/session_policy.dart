/// How long a signed-in session lasts without being used (FR100_034): the patient must log in
/// again once it has not been renewed for this long. "Renewed" = the app was opened or used while
/// signed in. Shared by the Supabase and fake auth repositories so both behave the same.
class SessionPolicy {
  SessionPolicy._();

  static const Duration lifetime = Duration(days: 3);

  /// True when the session was last renewed more than [lifetime] before [now]. No record (first
  /// use after this rule was added) counts as fresh.
  static bool expired(DateTime? lastRenewed, DateTime now) =>
      lastRenewed != null && now.difference(lastRenewed) > lifetime;
}
