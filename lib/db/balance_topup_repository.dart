import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/balance_topup.dart';

class BalanceTopupRepository {
  final _client = Supabase.instance.client;

  Future<List<BalanceTopup>> getForResto(String restoId) async {
    final rows = await _client
        .from('balance_topups')
        .select()
        .eq('resto_id', restoId)
        .order('created_at', ascending: false);
    return rows.map((r) => BalanceTopup.fromMap(r)).toList();
  }

  /// Mencatat setoran. Jurnalnya ditulis pemicu di basis data, bukan di
  /// sini — dua baris jurnal yang dikirim aplikasi bisa sampai satu dan
  /// gagal satu, dan pembukuan yang timpang sebelah lebih sulit
  /// ditemukan daripada pembukuan yang kosong.
  Future<void> add({
    required String restoId,
    required int amount,
    required String source,
    String? note,
    String? proofBase64,
  }) async {
    await _client.from('balance_topups').insert({
      'resto_id': restoId,
      'amount': amount,
      'source': source,
      if (note != null && note.isNotEmpty) 'note': note,
      if (proofBase64 != null && proofBase64.isNotEmpty)
        'proof_base64': proofBase64,
      'created_by': _client.auth.currentUser?.email,
    });
  }
}
