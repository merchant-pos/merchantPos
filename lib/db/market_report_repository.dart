import 'package:supabase_flutter/supabase_flutter.dart';

/// Sebaris peringkat: siapa/apa, berapa transaksinya, berapa nilainya.
class ReportRow {
  final String id;
  final String label;
  final String? sublabel;
  final int count;
  final int amount;

  const ReportRow({
    required this.id,
    required this.label,
    this.sublabel,
    this.count = 0,
    this.amount = 0,
  });
}

/// Angka pasar MerchantPOS — hanya untuk Super Admin.
///
/// Seluruh perhitungannya di server. Mengunduh pesanan seluruh resto ke
/// sebuah HP lalu menjumlahkannya di sini berarti batas 1.000 baris
/// PostgREST memotongnya diam-diam, dan yang tampil adalah peringkat
/// yang salah tanpa satu pun tanda ada yang hilang.
class MarketReportRepository {
  final _client = Supabase.instance.client;

  Future<List<ReportRow>> topCustomers({int limit = 5}) async =>
      _rows('report_top_customers', limit, (r) => ReportRow(
            id: r['customer_label'] as String? ?? '',
            label: r['customer_name'] as String? ?? '',
            sublabel: r['customer_label'] as String?,
            count: (r['orders_count'] as num?)?.toInt() ?? 0,
            amount: (r['total_amount'] as num?)?.toInt() ?? 0,
          ));

  Future<List<ReportRow>> idleCustomers({int limit = 100}) async =>
      _rows('report_idle_customers', limit, (r) => ReportRow(
            id: r['email'] as String? ?? '',
            label: r['customer_name'] as String? ?? '',
            sublabel: r['email'] as String?,
          ));

  Future<List<ReportRow>> topRestos({int limit = 5}) async =>
      _rows('report_top_restos', limit, (r) => ReportRow(
            id: r['resto_id'] as String? ?? '',
            label: r['resto_name'] as String? ?? '',
            count: (r['orders_count'] as num?)?.toInt() ?? 0,
            amount: (r['total_amount'] as num?)?.toInt() ?? 0,
          ));

  Future<List<ReportRow>> idleRestos({int limit = 200}) async =>
      _rows('report_idle_restos', limit, (r) => ReportRow(
            id: r['resto_id'] as String? ?? '',
            label: r['resto_name'] as String? ?? '',
            count: (r['orders_count'] as num?)?.toInt() ?? 0,
          ));

  Future<List<ReportRow>> _rows(
    String fn,
    int limit,
    ReportRow Function(Map<String, dynamic>) bentuk,
  ) async {
    final rows = await _client.rpc(fn, params: {'p_limit': limit});
    return [
      for (final r in (rows as List? ?? const []))
        bentuk(Map<String, dynamic>.from(r as Map)),
    ];
  }
}
