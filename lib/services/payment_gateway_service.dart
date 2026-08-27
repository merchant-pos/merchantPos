import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Tagihan QRIS yang sudah terbit di penyedia pembayaran.
class QrisCharge {
  /// Isi kode QR-nya, apa adanya dari penyedia.
  final String qrString;

  /// Nominal yang benar-benar ditagihkan, dibaca dari pesanan di server.
  ///
  /// Ditampilkan dari sini, bukan dari hitungan di HP: yang dibayar
  /// orang harus berasal dari sumber yang sama dengan yang dituntut
  /// QR-nya. Dua tempat menghitung angka yang sama adalah dua tempat
  /// yang bisa berbeda.
  final int amount;

  final DateTime expiresAt;

  /// Pengenal tagihannya di server, untuk menanyakan statusnya nanti.
  final String referenceId;

  /// Penyedianya sedang memakai kunci uji.
  ///
  /// Ditentukan server, bukan aplikasi. Aplikasi tidak punya cara
  /// mengetahuinya sendiri, dan menitipkannya ke penanda saat build
  /// berarti mengandalkan seseorang ingat mematikannya sebelum rilis —
  /// yang selalu gagal tepat pada rilis yang paling sibuk. Dengan cara
  /// ini, mengganti kunci ke produksi sudah cukup untuk melenyapkan
  /// seluruh perkakas ujinya, tanpa build ulang.
  final bool testMode;

  QrisCharge({
    required this.qrString,
    required this.amount,
    required this.expiresAt,
    this.referenceId = '',
    this.testMode = false,
  });

  Duration get remaining => expiresAt.difference(DateTime.now());
  bool get isExpired => remaining.isNegative;
}

/// Meminta tagihan QRIS ke penyedia lewat Edge Function.
///
/// Aplikasi hanya menyebut nomor pesanannya. Nominalnya sengaja tidak
/// ikut dikirim — server yang membacanya sendiri dari pesanan itu.
/// Nominal yang datang dari HP bisa diubah siapa pun yang mau membayar
/// seratus ribu dengan seribu rupiah.
class PaymentGatewayService {
  final _client = Supabase.instance.client;

  /// Membuat (atau memakai ulang) tagihan untuk sebuah pesanan.
  ///
  /// Mengembalikan null kalau penyedia pembayarannya belum dipasang di
  /// resto ini — dan itu bukan kegagalan: layar pemanggilnya kembali ke
  /// QR simulasi seperti sebelumnya. Resto yang belum punya akun
  /// gateway tetap harus bisa menerima pesanan.
  Future<QrisCharge?> createQris(String orderId) async {
    try {
      final res = await _client.functions.invoke(
        'create-qris',
        body: {'order_id': orderId},
      );

      final data = res.data;
      if (data is! Map || data['qr_string'] == null) {
        debugPrint('[QRIS] jawaban tidak terduga: $data');
        return null;
      }

      return _parse(data);
    } catch (e) {
      // Termasuk saat kuncinya belum dipasang. Dicatat, tapi tidak
      // dilempar ke atas: layar pembayaran yang gagal terbuka jauh lebih
      // merugikan daripada layar pembayaran yang jatuh ke cara lama.
      debugPrint('[QRIS] gagal membuat tagihan: $e');
      return null;
    }
  }

  /// Tagihan untuk pembayaran di meja kasir, tanpa pesanan.
  ///
  /// Pesanan yang diinput kasir baru dibuat setelah pembayarannya
  /// diterima, jadi saat QR-nya harus terbit belum ada pesanan yang bisa
  /// disebut. Yang menghubungkan keduanya nanti adalah transaksi yang
  /// tercatat sesudahnya.
  Future<QrisCharge?> createCounterQris({
    required String restoId,
    required int amount,
  }) async {
    try {
      final res = await _client.functions.invoke(
        'create-qris',
        body: {'resto_id': restoId, 'amount': amount},
      );
      final data = res.data;
      if (data is! Map || data['qr_string'] == null) return null;
      return _parse(data);
    } catch (e) {
      debugPrint('[QRIS] gagal membuat tagihan kasir: $e');
      return null;
    }
  }

  QrisCharge _parse(Map data) => QrisCharge(
        qrString: data['qr_string'] as String,
        amount: (data['amount'] as num).toInt(),
        expiresAt: DateTime.parse(data['expires_at'] as String).toLocal(),
        referenceId: data['reference_id'] as String? ?? '',
        testMode: data['test_mode'] == true,
      );

  /// Menanyakan apakah sebuah tagihan sudah dibayar.
  ///
  /// Dipakai layar kasir, yang tagihannya tidak menempel pada pesanan
  /// mana pun — jadi tidak ada baris yang bisa dipantau realtime seperti
  /// di jalur pelanggan.
  Future<bool> isPaid(String referenceId) async {
    if (referenceId.isEmpty) return false;
    try {
      final status = await _client.rpc(
        'gateway_charge_status',
        params: {'p_reference_id': referenceId},
      );
      return status == 'paid';
    } catch (_) {
      return false;
    }
  }

  /// Memalsukan pembayaran, hanya berlaku saat penyedianya memakai kunci
  /// uji.
  ///
  /// Bukan jalan pintas untuk menandai pesanan lunas: yang dipanggil
  /// adalah endpoint simulasi milik penyedia, dan pelunasannya tetap
  /// datang lewat webhook seperti pembayaran sungguhan. Yang digantikan
  /// cuma satu hal — tindakan pelanggan memindai QR-nya, yang di mode
  /// uji memang mustahil karena kodenya bukan QRIS asli.
  ///
  /// Ditolak server kalau kuncinya bukan kunci uji.
  Future<String?> simulatePayment({String? orderId, String? referenceId}) async {
    try {
      final res = await _client.functions.invoke(
        'create-qris',
        body: {
          if (orderId != null) 'order_id': orderId,
          if (referenceId != null) 'reference_id': referenceId,
          'simulate': true,
        },
      );
      final data = res.data;
      if (data is Map && data['simulated'] == true) return null;
      return 'Simulasi ditolak: ${data is Map ? data['error'] ?? data : data}';
    } catch (e) {
      return 'Simulasi gagal: $e';
    }
  }
}
