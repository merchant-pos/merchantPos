/// Supabase project credentials. The anon/publishable key is safe to
/// ship in the client — it's designed for that, and every table is
/// still gated by Row Level Security policies (see supabase/schema.sql).
class SupabaseConfig {
  static const url = 'https://pekjbgjmeayxdcaiwhsk.supabase.co';
  static const anonKey = 'sb_publishable_6hengTSXtx6qhpbVngH22g_vU98MWmh';

  /// OAuth client milik proyek Google "Merchant-POS" sendiri.
  ///
  /// Tidak dipakai jalur web — di sana login lewat pengalihan Supabase,
  /// dan yang memegang client id-nya Supabase, bukan aplikasi ini.
  /// Ditulis di sini supaya nilainya tidak lagi menunjuk client KaataGo:
  /// nilai warisan yang kebetulan tidak terpakai adalah yang paling
  /// lama bertahan salah, karena tidak pernah ada yang gagal karenanya.
  static const googleWebClientId =
      '511761298857-9drjm9q4umsd64jee05sip4m3ftj496s.apps.googleusercontent.com';
}
