import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/billing.dart';

class BillingRepository {
  final _client = Supabase.instance.client;

  /// Keadaan langganan sebuah resto.
  ///
  /// Dibaca dari fungsi server, bukan disusun dari tabelnya di sini.
  /// Aturan "terkunci" dipakai juga oleh kebijakan RLS; kalau aplikasi
  /// menghitungnya sendiri, dua perhitungan itu akan berpisah suatu
  /// hari — dan yang terlihat adalah layar yang mengaku aman sementara
  /// database menolak menyimpan apa pun.
  Future<BillingState> stateOf(String restoId) async {
    final rows = await _client.rpc(
      'resto_billing_state',
      params: {'p_resto_id': restoId},
    );
    final list = (rows as List?) ?? const [];
    if (list.isEmpty) return BillingState.tenang;
    return BillingState.fromMap(Map<String, dynamic>.from(list.first as Map));
  }

  Future<RestoBilling?> settingsOf(String restoId) async {
    final rows = await _client
        .from('resto_billing')
        .select()
        .eq('resto_id', restoId)
        .limit(1);
    if (rows.isEmpty) return null;
    return RestoBilling.fromMap(rows.first);
  }

  /// Setelan seluruh resto, untuk layar Super Admin.
  Future<Map<String, RestoBilling>> allSettings() async {
    final rows = await _client.from('resto_billing').select();
    return {
      for (final r in rows) r['resto_id'] as String: RestoBilling.fromMap(r),
    };
  }

  Future<void> saveSettings(RestoBilling billing) async {
    await _client.from('resto_billing').upsert({
      ...billing.toMap(),
      'updated_at': DateTime.now().toIso8601String(),
    });
  }

  Future<List<BillingInvoice>> invoicesOf(String restoId) async {
    final rows = await _client
        .from('billing_invoices')
        .select()
        .eq('resto_id', restoId)
        .order('due_date', ascending: false);
    return rows.map((r) => BillingInvoice.fromMap(r)).toList();
  }

  /// Tagihan lintas resto — hanya Super Admin yang bisa membacanya.
  Future<List<BillingInvoice>> allInvoices({bool onlyOpen = false}) async {
    var q = _client
        .from('billing_invoices')
        .select('*, restaurants(name)');
    if (onlyOpen) {
      q = q.inFilter('status', ['unpaid', 'review']);
    }
    final rows = await q.order('due_date', ascending: false).limit(300);
    return rows.map((r) => BillingInvoice.fromMap(r)).toList();
  }

  /// Resto mengunggah bukti bayar.
  ///
  /// Lewat RPC, bukan UPDATE langsung: kalau langsung, tidak ada yang
  /// mencegah restonya menulis status 'paid' untuk dirinya sendiri.
  Future<void> submitPayment(
    String invoiceId, {
    String? proofBase64,
    String? note,
  }) async {
    await _client.rpc('submit_billing_payment', params: {
      'p_invoice_id': invoiceId,
      'p_proof_base64': proofBase64,
      'p_note': note,
    });
  }

  /// Merchant-POS menerima atau menolak bukti bayar.
  Future<void> review(String invoiceId,
      {required bool accept, String? reason}) async {
    await _client.rpc('review_billing_payment', params: {
      'p_invoice_id': invoiceId,
      'p_accept': accept,
      'p_reason': reason,
    });
  }

  /// Meminta nomor Virtual Account untuk sebuah tagihan.
  ///
  /// Nominalnya tidak dikirim dari sini — fungsi edge membacanya sendiri
  /// dari tabel tagihan. Nominal yang datang dari aplikasi bisa diubah
  /// siapa pun yang ingin melunasi tagihan sejuta rupiah dengan seribu.
  Future<Map<String, dynamic>> requestVa(String invoiceId,
      {String bank = 'BCA'}) async {
    try {
      final res = await _client.functions.invoke('create-billing-va', body: {
        'invoice_id': invoiceId,
        'bank': bank,
      });
      final data = Map<String, dynamic>.from(res.data as Map);
      if (data['error'] != null) throw Exception(data['error']);
      return data;
    } on FunctionException catch (e) {
      // Jawaban selain 2xx dilempar sebagai FunctionException, jadi
      // pemeriksaan data['error'] di atas tidak pernah sampai. Tanpa ini
      // yang tampil di layar adalah seluruh bungkusnya — status, detail
      // bersarang, reasonPhrase — dan orang resto yang membacanya tidak
      // punya cara menemukan kalimat yang sebenarnya menjelaskan apa
      // yang salah.
      throw Exception(_pesanGalat(e.details) ?? 'Penyedia pembayaran menolak permintaan');
    }
  }

  /// Kalimat penjelas dari dalam jawaban Xendit, sedalam apa pun ia
  /// dibungkus.
  static String? _pesanGalat(Object? details) {
    if (details is Map) {
      for (final kunci in ['error', 'message', 'detail']) {
        final nilai = details[kunci];
        if (nilai is String && nilai.isNotEmpty) return nilai;
        if (nilai is Map) {
          final dalam = _pesanGalat(nilai);
          if (dalam != null) return dalam;
        }
      }
    }
    if (details is String && details.isNotEmpty) return details;
    return null;
  }

  // ── Diskon langganan ───────────────────────────────────────────────

  Future<List<BillingDiscount>> discounts() async {
    final rows = await _client
        .from('billing_discounts')
        .select()
        .order('created_at', ascending: false);
    return rows.map((r) => BillingDiscount.fromMap(r)).toList();
  }

  Future<void> saveDiscount(BillingDiscount d) async {
    await _client.from('billing_discounts').upsert(d.toMap());
  }

  Future<void> deleteDiscount(String id) async {
    await _client.from('billing_discounts').delete().eq('id', id);
  }

  /// Tagihan yang sudah lunas — riwayat pendapatan langganan.
  Future<List<BillingInvoice>> paidInvoices() async {
    final rows = await _client
        .from('billing_invoices')
        .select('*, restaurants(name)')
        .inFilter('status', ['paid', 'waived'])
        .order('confirmed_at', ascending: false)
        .limit(500);
    return rows.map((r) => BillingInvoice.fromMap(r)).toList();
  }

  /// Menyuruh Xendit berlaku seolah uangnya sudah ditransfer.
  ///
  /// Hanya bekerja dengan kunci development — ditolak Xendit sendiri
  /// pada kunci produksi, jadi tidak ada penanda yang bisa tertinggal
  /// menyala di rilis.
  Future<void> simulateVaPayment(String invoiceId) async {
    try {
      final res = await _client.functions.invoke('create-billing-va', body: {
        'invoice_id': invoiceId,
        'simulate': true,
      });
      final data = Map<String, dynamic>.from(res.data as Map);
      if (data['error'] != null) throw Exception(data['error']);
    } on FunctionException catch (e) {
      throw Exception(_pesanGalat(e.details) ?? 'Simulasi ditolak');
    }
  }

  /// Menghitung ulang satu tagihan mengikuti diskon yang berlaku
  /// sekarang.
  ///
  /// Menunggu penjadwal harian berarti resto melihat tagihan penuh
  /// sampai besok, dan yang menjelaskan selisihnya adalah orang yang
  /// menerima telepon.
  Future<int> refreshInvoice(String invoiceId) async {
    final n = await _client.rpc('refresh_billing_invoice', params: {
      'p_invoice_id': invoiceId,
    });
    return (n as num?)?.toInt() ?? 0;
  }

  /// Menerbitkan tagihan sekarang juga, tanpa menunggu penjadwal.
  Future<int> generateNow() async {
    final n = await _client.rpc('generate_billing_invoices');
    return (n as num?)?.toInt() ?? 0;
  }
}
