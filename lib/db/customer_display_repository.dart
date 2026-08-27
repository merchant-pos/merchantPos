import 'package:supabase_flutter/supabase_flutter.dart';

/// Apa yang sedang ditampilkan layar depan sebuah resto.
enum StatusLayar { menganggur, menunggu, lunas }

class TampilanLayar {
  final StatusLayar status;
  final int? amount;
  final String? qrString;
  final String? label;

  const TampilanLayar({
    this.status = StatusLayar.menganggur,
    this.amount,
    this.qrString,
    this.label,
  });

  bool get adaQr => qrString != null && qrString!.isNotEmpty;

  factory TampilanLayar.fromMap(Map<String, dynamic> map) => TampilanLayar(
        status: switch (map['status']) {
          'awaiting' => StatusLayar.menunggu,
          'paid' => StatusLayar.lunas,
          _ => StatusLayar.menganggur,
        },
        amount: (map['amount'] as num?)?.toInt(),
        qrString: map['qr_string'] as String?,
        label: map['label'] as String?,
      );
}

/// Layar pelanggan di meja kasir.
///
/// Barisnya membawa isi tampilannya, bukan penunjuk ke pesanan: di alur
/// kasir, pesanannya baru dibuat sesudah pembayaran dikonfirmasi — saat
/// QR-nya tampil, belum ada baris pesanan untuk ditunjuk.
class CustomerDisplayRepository {
  final _client = Supabase.instance.client;

  Future<void> _tulis(
    String restoId,
    String status, {
    int? amount,
    String? qrString,
    String? label,
  }) async {
    await _client.rpc('set_customer_display', params: {
      'p_resto_id': restoId,
      'p_status': status,
      'p_amount': amount,
      'p_qr_string': qrString,
      'p_label': label,
    });
  }

  /// Menampilkan tagihan yang menunggu dibayar.
  Future<void> tampilkan(
    String restoId, {
    required int amount,
    String? qrString,
    String? label,
  }) =>
      _tulis(restoId, 'awaiting',
          amount: amount, qrString: qrString, label: label);

  /// Menyatakan lunas — tampil sebentar sebagai konfirmasi.
  Future<void> lunas(String restoId, {required int amount, String? label}) =>
      _tulis(restoId, 'paid', amount: amount, label: label);

  /// Mengembalikannya ke keadaan menganggur.
  ///
  /// Dipanggil saat kasir menutup layar pembayarannya. Tanpa ini,
  /// tagihan orang sebelumnya tetap terpampang di depan pelanggan
  /// berikutnya — termasuk nominalnya dan QR-nya, yang masih bisa
  /// dipindai.
  Future<void> kosongkan(String restoId) => _tulis(restoId, 'idle');

  /// Berubah seketika, tanpa perlu dimuat ulang.
  Stream<TampilanLayar> watch(String restoId) {
    return _client
        .from('customer_displays')
        .stream(primaryKey: ['resto_id'])
        .eq('resto_id', restoId)
        .map((rows) => rows.isEmpty
            ? const TampilanLayar()
            : TampilanLayar.fromMap(rows.first));
  }
}
