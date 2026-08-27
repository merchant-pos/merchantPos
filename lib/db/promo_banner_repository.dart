import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/promo_banner.dart';

class PromoBannerRepository {
  final _client = Supabase.instance.client;

  /// Seluruh banner resto — untuk layar admin dan owner.
  ///
  /// Tidak disaring sama sekali: yang nonaktif maupun yang masa
  /// berlakunya sudah lewat tetap ikut. Banner yang menghilang sendiri
  /// dari layar pengelolanya adalah banner yang tidak bisa dihapus,
  /// tidak bisa dipakai ulang tahun depan, dan tidak bisa diperiksa
  /// kenapa dulu berhenti tampil — yang tersisa cuma barisnya di
  /// database yang tidak pernah dilihat siapa pun lagi.
  ///
  /// Menghapusnya keputusan orangnya, bukan keputusan tanggal.
  Future<List<PromoBanner>> getForResto(String restoId) async {
    final rows = await _client
        .from('promo_banners')
        .select()
        .eq('resto_id', restoId)
        .order('sort_order')
        .order('created_at');
    return rows.map((r) => PromoBanner.fromMap(r)).toList();
  }

  /// Hanya yang benar-benar sedang tayang — untuk customer.
  ///
  /// Saklar aktifnya saja tidak cukup: banner yang saklarnya masih
  /// menyala tapi masa berlakunya sudah lewat tetap tampil ke
  /// pelanggan, dan promo yang sudah berakhir tapi masih terpampang
  /// adalah janji yang akan ditagih di kasir.
  ///
  /// Masa berlakunya disaring di sini, bukan lewat `where` tanggal:
  /// aturan "hari terakhir ikut berlaku penuh" sudah tertulis satu kali
  /// di PromoPeriod, dan menulis ulang aturan yang sama sebagai SQL
  /// berarti dua tempat yang harus selalu sepakat.
  Future<List<PromoBanner>> activeForResto(String restoId) async {
    final rows = await _client
        .from('promo_banners')
        .select()
        .eq('resto_id', restoId)
        .eq('active', true)
        .order('sort_order')
        .order('created_at');
    return rows
        .map((r) => PromoBanner.fromMap(r))
        .where((b) => b.isLive())
        .toList();
  }

  Future<void> create(PromoBanner banner) async {
    await _client.from('promo_banners').insert(banner.toMap());
  }

  Future<void> update(PromoBanner banner) async {
    await _client.from('promo_banners').update(banner.toMap()).eq('id', banner.id);
  }

  Future<void> setActive(String id, bool active) async {
    await _client.from('promo_banners').update({'active': active}).eq('id', id);
  }

  /// Menyimpan urutan baru sekaligus, supaya daftar tidak sempat berada
  /// dalam keadaan setengah tersusun kalau salah satu penulisan gagal.
  Future<void> reorder(List<PromoBanner> ordered) async {
    for (var i = 0; i < ordered.length; i++) {
      await _client.from('promo_banners').update({'sort_order': i}).eq('id', ordered[i].id);
    }
  }

  Future<void> delete(String id) async {
    await _client.from('promo_banners').delete().eq('id', id);
  }
}
