import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/petty_cash_entry.dart';

class PettyCashRepository {
  final _client = Supabase.instance.client;

  Future<List<PettyCashEntry>> getForResto(String restoId) async {
    final rows = await _client
        .from('petty_cash_entries')
        .select()
        .eq('resto_id', restoId)
        .order('created_at', ascending: false);
    return rows.map((r) => PettyCashEntry.fromMap(r)).toList();
  }

  /// Aliran langsung top up petty cash resto ini, terbaru di atas.
  Stream<List<PettyCashEntry>> watchForResto(String restoId) {
    return _client
        .from('petty_cash_entries')
        .stream(primaryKey: ['id'])
        .eq('resto_id', restoId)
        .order('created_at', ascending: false)
        .map((rows) => rows.map((r) => PettyCashEntry.fromMap(r)).toList());
  }

  /// Berapa pengajuan top up yang masih menunggu keputusan Finance.
  Future<int> pendingCount(String restoId) async {
    return await _client
        .from('petty_cash_entries')
        .count(CountOption.exact)
        .eq('resto_id', restoId)
        .eq('status', 'pending');
  }

  Future<void> create(PettyCashEntry entry) async {
    await _client.from('petty_cash_entries').insert(entry.toMap());
  }

  Future<void> delete(String id) async {
    await _client.from('petty_cash_entries').delete().eq('id', id);
  }

  /// Menyetujui atau menolak satu pengajuan top up.
  ///
  /// Hanya baris ini yang disentuh, dan trigger jurnalnya pun bekerja per
  /// baris — jadi menyetujui satu pengajuan tidak akan ikut melepas
  /// pengajuan lain yang masih menunggu.
  Future<void> review(
    String id, {
    required PettyCashStatus status,
    required String reviewedBy,
    String? note,
  }) async {
    await _client.from('petty_cash_entries').update({
      'status': status.dbValue,
      'reviewed_by': reviewedBy,
      'reviewed_at': DateTime.now().toUtc().toIso8601String(),
      if (note != null && note.trim().isNotEmpty) 'review_note': note.trim(),
    }).eq('id', id);
  }
}
