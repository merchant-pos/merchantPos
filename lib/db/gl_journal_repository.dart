import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/billing.dart';
import '../models/gl_journal_entry.dart';

class GlJournalRepository {
  final _client = Supabase.instance.client;

  /// Jurnal seluruh resto — hanya Super Admin yang bisa membacanya, dan
  /// hanya membaca: tidak ada kebijakan tulis untuk siapa pun.
  ///
  /// Pembukuan Merchant-POS sendiri disaring keluar. Ia memang tersimpan di
  /// tabel yang sama — penyewa platform memakai mesin pembukuan yang
  /// sama persis dengan resto — tapi mencampurnya di satu layar membuat
  /// total debit/kredit menjumlahkan dua pembukuan yang tidak punya
  /// hubungan satu sama lain: penjualan resto, dan tagihan yang kami
  /// terbitkan kepada mereka.
  ///
  /// Pembukuan Merchant-POS punya layarnya sendiri, Jurnal GL Merchant-POS.
  ///
  /// Disaring di kueri, bukan sesudah data sampai: baris platform yang
  /// ikut terangkut memakan jatah batas 1.000 baris, dan yang terpotong
  /// justru jurnal resto yang dicari.
  Future<List<GlJournalEntry>> getAll({int limit = 1000}) async {
    final rows = await _client
        .from('gl_journal_entries')
        .select()
        .neq('resto_id', kPlatformRestoId)
        .order('entry_date', ascending: false)
        .order('entry_time', ascending: false)
        .limit(limit);
    return rows.map((r) => GlJournalEntry.fromMap(r)).toList();
  }

  Future<List<GlJournalEntry>> getForResto(String restoId) async {
    final rows = await _client
        .from('gl_journal_entries')
        .select()
        .eq('resto_id', restoId)
        .order('created_at', ascending: false);
    return rows.map((r) => GlJournalEntry.fromMap(r)).toList();
  }
}
