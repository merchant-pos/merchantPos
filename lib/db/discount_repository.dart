import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/discount.dart';

class DiscountRepository {
  final _client = Supabase.instance.client;

  Future<List<Discount>> getForResto(String restoId) async {
    final rows = await _client
        .from('discounts')
        .select()
        .eq('resto_id', restoId)
        .order('created_at', ascending: false);
    return rows.map((r) => Discount.fromMap(r)).toList();
  }

  /// Diskon yang sedang berlaku hari ini.
  ///
  /// Disaring di aplikasi, bukan lewat `where` tanggal di server.
  /// Daftarnya pendek, dan aturannya — termasuk hari terakhir yang ikut
  /// berlaku penuh — sudah tertulis satu kali di [PromoPeriod]. Menulis
  /// ulang aturan yang sama sebagai SQL berarti dua tempat yang harus
  /// selalu sepakat.
  Future<List<Discount>> liveForResto(String restoId) async {
    final all = await getForResto(restoId);
    return all.where((d) => d.isLive()).toList();
  }

  Future<void> save(Discount discount) async {
    await _client.from('discounts').upsert(discount.toMap());
  }

  Future<void> delete(String id) async {
    await _client.from('discounts').delete().eq('id', id);
  }

  Future<void> setActive(String id, bool active) async {
    await _client.from('discounts').update({'active': active}).eq('id', id);
  }
}
