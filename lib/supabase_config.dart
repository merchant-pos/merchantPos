/// Supabase project credentials. The anon/publishable key is safe to
/// ship in the client — it's designed for that, and every table is
/// still gated by Row Level Security policies (see supabase/schema.sql).
class SupabaseConfig {
  static const url = 'https://xizpwtycczigjhzxegen.supabase.co';
  static const anonKey = 'sb_publishable_uhDdS0WTVvW7L7RMkLwz4w_boNWr7ye';

  /// Web OAuth client id (reused from the earlier Firebase project setup)
  /// — required as GoogleSignIn's serverClientId so the id token it
  /// returns has the right audience for Supabase to verify.
  static const googleWebClientId =
      '1015088896093-5k1bi18rhsifjd67bduvu58hhd9s7sv3.apps.googleusercontent.com';
}
