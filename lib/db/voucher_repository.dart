import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/voucher.dart';

class VoucherRepository {
  final _client = Supabase.instance.client;

  /// Seluruh batch berikut jumlah penebusnya — untuk Super Admin.
  ///
  /// Penebusnya dihitung dari tabel penebusan, bukan disimpan sebagai
  /// angka di baris batch-nya. Angka yang disimpan terpisah akan
  /// berpisah dari kenyataannya suatu hari, dan yang menemukannya adalah
  /// pelanggan yang ditolak padahal kuotanya masih ada.
  Future<List<Voucher>> all() async {
    final rows = await _client
        .from('vouchers')
        .select()
        .order('created_at', ascending: false);
    final klaim =
        await _client.from('voucher_claims').select('voucher_id, status');

    // Dua hitungan, karena keduanya menjawab pertanyaan berbeda:
    // berapa jatah yang sudah diserahkan, dan berapa yang benar-benar
    // masih tertahan di tangan orang.
    final hitung = <String, int>{};
    final gantung = <String, int>{};
    for (final r in klaim) {
      final id = r['voucher_id'] as String;
      hitung[id] = (hitung[id] ?? 0) + 1;
      // Yang sudah dipakai maupun hangus tidak menggantung lagi —
      // dananya sudah berpindah, masing-masing ke GL restonya dan ke
      // GL Total Saldo.
      if (r['status'] == 'claimed') {
        gantung[id] = (gantung[id] ?? 0) + 1;
      }
    }
    return [
      for (final r in rows)
        voucherFromMap(
          r,
          claimed: hitung[r['id'] as String] ?? 0,
          menggantung: gantung[r['id'] as String] ?? 0,
        ),
    ];
  }

  /// Menerbitkan satu batch: nominalnya dipecah jadi beberapa voucher,
  /// dan dananya berpindah dari saldo bebas ke kantong voucher.
  Future<String> generate({
    required String code,
    required String name,
    required int totalAmount,
    required int quantity,
    required DateTime expiresOn,
    int minPurchase = 0,
    List<String> restoIds = const [],
    String? banner,
    bool newCustomersOnly = false,
  }) async {
    final id = await _client.rpc('generate_voucher_batch', params: {
      'p_code': code,
      'p_name': name,
      'p_total': totalAmount,
      'p_quantity': quantity,
      'p_expires_on': expiresOn.toIso8601String().split('T').first,
      'p_min_purchase': minPurchase,
      'p_resto_ids': restoIds,
      'p_banner': banner,
      'p_new_customers_only': newCustomersOnly,
    });
    return id?.toString() ?? '';
  }

  /// Membuang batch yang tidak jadi.
  ///
  /// Syaratnya ditegakkan server: harus sudah ditutup, dan belum ada
  /// yang menebus. Dananya dikembalikan ke saldo di sana juga.
  Future<void> delete(String id) async {
    await _client.rpc('delete_voucher_batch', params: {'p_id': id});
  }

  /// Siapa saja yang sudah menebus sebuah batch.
  Future<List<VoucherClaim>> claimsOf(String voucherId) async {
    final rows = await _client
        .from('voucher_claims')
        .select('*, vouchers(code, name, expires_on, min_purchase, resto_ids)')
        .eq('voucher_id', voucherId)
        .order('created_at', ascending: false);
    return rows.map((r) => VoucherClaim.fromMap(r)).toList();
  }

  Future<void> setActive(String id, bool active) async {
    await _client.from('vouchers').update({'active': active}).eq('id', id);
  }

  /// Pelanggan menebus sebuah kode.
  ///
  /// Kuotanya ditegakkan server. Menghitungnya di aplikasi berarti dua
  /// orang yang menekan tombol di detik yang sama sama-sama lolos
  /// sebagai penebus terakhir.
  Future<ClaimResult> claim(String code) async {
    final rows = await _client.rpc('claim_voucher', params: {'p_code': code});
    final list = (rows as List?) ?? const [];
    if (list.isEmpty) {
      return const ClaimResult(reason: 'Kode voucher tidak ditemukan');
    }
    return ClaimResult.fromMap(Map<String, dynamic>.from(list.first as Map));
  }

  /// Voucher milik pelanggan yang sedang masuk.
  Future<List<VoucherClaim>> mine() async {
    final email = _client.auth.currentUser?.email;
    if (email == null) return const [];
    final rows = await _client
        .from('voucher_claims')
        .select('*, vouchers(code, name, expires_on, min_purchase, resto_ids)')
        .eq('customer_label', email)
        .order('created_at', ascending: false);
    return rows.map((r) => VoucherClaim.fromMap(r)).toList();
  }

  /// Voucher yang siap dipakai di sebuah resto untuk tagihan sebesar ini.
  Future<List<VoucherClaim>> usableAt(String restoId, int total) async {
    final semua = await mine();
    return [
      for (final c in semua)
        if (c.bisaDipakaiDi(restoId, total)) c,
    ];
  }
}
