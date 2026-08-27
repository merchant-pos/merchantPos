import 'dart:async';

import 'package:flutter/material.dart';

import '../theme.dart';
import 'package:intl/intl.dart';

import '../models/customer_order.dart';

/// Layar penutup untuk pesanan yang dipilih dibayar tunai di kasir.
///
/// Pesanannya sudah selesai dibuat — dapur menerimanya sekarang juga.
/// Yang belum terjadi cuma pembayarannya, dan itu terjadi di meja kasir.
/// Karena itu tidak ada tombol "sudah bayar" di sini: pelanggan tidak
/// bisa menyatakan uangnya sudah berpindah, hanya kasir yang bisa.
///
/// Nada layarnya sengaja bukan peringatan. Ini alur yang sah dan
/// disediakan sendiri oleh resto — yang perlu dibawa pulang pelanggan
/// cuma dua hal: pesanannya sudah masuk, dan nomor pesanannya harus
/// disebutkan di kasir.
class CustomerCashPendingScreen extends StatefulWidget {
  final String orderId;
  final int amount;

  /// Kapan pesanannya dibuat — titik nol hitungan mundurnya. Boleh
  /// kosong untuk pemanggil lama; dianggap baru saja dibuat.
  final DateTime? createdAt;

  const CustomerCashPendingScreen({
    super.key,
    required this.orderId,
    required this.amount,
    this.createdAt,
  });

  @override
  State<CustomerCashPendingScreen> createState() =>
      _CustomerCashPendingScreenState();
}

class _CustomerCashPendingScreenState extends State<CustomerCashPendingScreen> {
  late final DateTime _deadline =
      (widget.createdAt ?? DateTime.now()).add(CustomerOrder.paymentWindow);
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final orderId = widget.orderId;
    final amount = widget.amount;
    final remaining = _deadline.difference(DateTime.now());
    final habis = remaining.isNegative;
    final currency = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
    final ref = orderId.length >= 8
        ? orderId.substring(0, 8).toUpperCase()
        : orderId.toUpperCase();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pesanan Diterima'),
        automaticallyImplyLeading: false,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 84,
                height: 84,
                decoration: const BoxDecoration(
                  color: Color(0xFFF59E0B),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.storefront_outlined, color: Colors.white, size: 44),
              ),
              const SizedBox(height: 16),
              const Text('Pesanan Kamu Sudah Masuk',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              const Text(
                'Status: Menunggu Pembayaran',
                style: TextStyle(color: Color(0xFFB45309), fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: MerchantPosTheme.tintOf(context, Colors.amber),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFF59E0B).withOpacity(0.4)),
                ),
                child: Column(
                  children: [
                    const Text(
                      'Silakan ke kasir dulu untuk menyelesaikan pembayaran',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    const SizedBox(height: 10),
                    // Nomor pesanan ditaruh sebesar ini karena inilah satu-
                    // satunya hal yang harus dibaca ulang orangnya beberapa
                    // menit lagi, sambil berdiri di depan kasir.
                    Text('Nomor Pesanan',
                        style: TextStyle(fontSize: 11.5, color: MerchantPosTheme.onTintOf(context, Colors.brown))),
                    Text(
                      ref,
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                        color: Color(0xFF92400E),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text('Yang harus dibayar',
                        style: TextStyle(fontSize: 11.5, color: MerchantPosTheme.onTintOf(context, Colors.brown))),
                    Text(
                      currency.format(amount),
                      style: const TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF92400E),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              // Hitungan mundurnya ditaruh persis di bawah nomor pesanan,
              // bukan di sudut layar sebagai catatan kaki. Batas waktu
              // yang baru terbaca setelah lewat sama saja dengan tidak
              // pernah diberitahukan.
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: habis ? MerchantPosTheme.tintOf(context, Colors.red) : MerchantPosTheme.softFillOf(context),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  children: [
                    Icon(
                      habis ? Icons.cancel_outlined : Icons.timer_outlined,
                      size: 20,
                      color: habis ? MerchantPosTheme.onTintOf(context, Colors.red) : MerchantPosTheme.mutedOf(context),
                    ),
                    const SizedBox(height: 6),
                    if (habis)
                      const Text(
                        'Batas waktu pembayaran sudah lewat.\n'
                        'Pesanan ini dibatalkan — silakan pesan ulang.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFB91C1C),
                        ),
                      )
                    else ...[
                      Text(
                        'Bayar dalam ${_clock(remaining)}',
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Kalau belum dibayar sampai waktunya habis, pesanan '
                        'ini otomatis dibatalkan.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, color: MerchantPosTheme.mutedOf(context)),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Pesanan kamu sudah diteruskan ke dapur. Sebutkan nomor pesanan '
                'di atas saat membayar di kasir.',
                textAlign: TextAlign.center,
                style: TextStyle(color: MerchantPosTheme.mutedOf(context), fontSize: 13),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
                  child: const Text('Selesai'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _clock(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}
