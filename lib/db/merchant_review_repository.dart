import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/merchant_review.dart';

class MerchantReviewRepository {
  final _client = Supabase.instance.client;

  Future<List<MerchantReview>> forResto(String restoId) async {
    final rows = await _client
        .from('merchant_reviews')
        .select()
        .eq('resto_id', restoId)
        .order('created_at', ascending: false);
    return rows.map((r) => MerchantReview.fromMap(r)).toList();
  }

  /// Penilaian yang sudah pernah ditulis orang ini, kalau ada.
  Future<MerchantReview?> mine(String restoId) async {
    final email = _client.auth.currentUser?.email;
    if (email == null) return null;
    final rows = await _client
        .from('merchant_reviews')
        .select()
        .eq('resto_id', restoId)
        .eq('customer_email', email)
        .limit(1);
    return rows.isEmpty ? null : MerchantReview.fromMap(rows.first);
  }

  /// Menyimpan penilaian, menimpa punyanya sendiri kalau sudah ada.
  ///
  /// Yang berubah pikiran mengubah penilaiannya, bukan menambah yang
  /// kedua — tanpa itu, satu orang yang kecewa bisa menenggelamkan
  /// rata-ratanya sendirian.
  Future<void> simpan({
    required String restoId,
    required String customerName,
    required int rating,
    String? comment,
    List<String> photos = const [],
  }) async {
    final email = _client.auth.currentUser?.email;
    if (email == null) return;
    await _client.from('merchant_reviews').upsert({
      'resto_id': restoId,
      'customer_email': email,
      'customer_name': customerName,
      'rating': rating,
      'comment': (comment ?? '').trim().isEmpty ? null : comment!.trim(),
      'photos': photos,
      'updated_at': DateTime.now().toIso8601String(),
    }, onConflict: 'resto_id,customer_email');
  }

  /// Rata-rata bintang seluruh merchant sekaligus.
  ///
  /// Dihitung server. Daftar merchant menampilkan puluhan baris; menarik
  /// seluruh ulasan tiap merchant untuk satu angka bintang berarti layar
  /// pilih merchant mengunduh ribuan baris tiap kali dibuka.
  Future<Map<String, RatingRingkas>> ringkasan() async {
    final rows = await _client.rpc('merchant_rating_summary');
    final hasil = <String, RatingRingkas>{};
    for (final r in (rows as List? ?? const [])) {
      final m = Map<String, dynamic>.from(r as Map);
      hasil[m['resto_id'] as String] = RatingRingkas(
        rata: (m['rata'] as num?)?.toDouble() ?? 0,
        jumlah: (m['jumlah'] as num?)?.toInt() ?? 0,
      );
    }
    return hasil;
  }
}
