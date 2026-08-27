import '../db/customer_display_repository.dart';
import 'dart:async';

import 'package:flutter/material.dart';

import '../theme.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/settings_provider.dart';
import '../services/payment_gateway_service.dart';
import '../utils/table_qr_image.dart';
import '../widgets/app_toast.dart';
import '../widgets/merchantpos_qr_card.dart';

/// Layar QRIS di meja kasir.
///
/// Bentuknya sama dengan layar pembayaran pelanggan, dan alasannya sama
/// pula: yang menyatakan lunas adalah penyedia pembayaran, bukan
/// ketukan di layar. Bedanya cuma satu — di sini tagihannya berdiri
/// tanpa pesanan, karena pesanan kasir baru dibuat setelah uangnya
/// diterima.
///
/// Kalau penyedianya belum terpasang, kembali ke QR simulasi seperti
/// sebelumnya. Resto yang belum punya akun gateway tetap harus bisa
/// menerima pembayaran QRIS dengan cara lamanya.
class PaymentQrisScreen extends StatefulWidget {
  final int amount;

  const PaymentQrisScreen({super.key, required this.amount});

  @override
  State<PaymentQrisScreen> createState() => _PaymentQrisScreenState();
}

class _PaymentQrisScreenState extends State<PaymentQrisScreen> {
  final _gateway = PaymentGatewayService();
  final _layar = CustomerDisplayRepository();

  /// Resto ini, disimpan saat layar dibuka.
  ///
  /// Dibaca sekali di initState, bukan di dispose: saat dispose berjalan
  /// context-nya sudah tidak boleh dipakai membaca provider, dan tanpa
  /// ini layar depannya tidak pernah dipadamkan — tagihan orang
  /// sebelumnya tetap terpampang beserta QR-nya, yang masih bisa
  /// dipindai orang lain.
  String? _restoId;

  QrisCharge? _charge;
  bool _loading = true;
  bool _simulating = false;
  Timer? _poller;
  Timer? _ticker;
  Duration _remaining = Duration.zero;

  bool get _gatewayActive => _charge != null;

  @override
  void initState() {
    super.initState();
    _restoId = context.read<AuthProvider>().restoId;
    _createCharge();
  }

  /// Menyalakan layar pelanggan, kalau restonya memakainya.
  ///
  /// Kegagalannya diabaikan dengan sengaja: layar depan adalah pelengkap.
  /// Kasir yang tidak bisa menyelesaikan pembayaran karena perangkat
  /// kedua sedang mati adalah kerugian yang jauh lebih besar daripada
  /// pelanggan yang harus melihat QR di layar kasir.
  Future<void> _tampilkanDiLayarDepan() async {
    final resto = _restoId;
    if (resto == null) return;
    try {
      await _layar.tampilkan(
        resto,
        amount: widget.amount,
        qrString: _charge?.qrString,
      );
    } catch (_) {}
  }

  Future<void> _padamkanLayarDepan() async {
    final resto = _restoId;
    if (resto == null) return;
    try {
      await _layar.kosongkan(resto);
    } catch (_) {}
  }

  @override
  void dispose() {
    _poller?.cancel();
    _ticker?.cancel();
    // Tanpa menunggu hasilnya: layar ini sudah ditutup, dan menahan
    // penutupannya demi satu panggilan jaringan membuat kasir menunggu
    // untuk sesuatu yang tidak dia lihat.
    _padamkanLayarDepan();
    super.dispose();
  }

  Future<void> _createCharge() async {
    final restoId = context.read<AuthProvider>().restoId;
    final charge = restoId == null
        ? null
        : await _gateway.createCounterQris(restoId: restoId, amount: widget.amount);
    if (!mounted) return;
    setState(() {
      _charge = charge;
      _loading = false;
    });

    // Dinyalakan walau tagihannya gagal dibuat: nominalnya tetap perlu
    // dibaca pelanggan, dan tanpa QR layarnya menyuruh membayar di
    // kasir — yang memang jadi jalan keluarnya saat QRIS bermasalah.
    unawaited(_tampilkanDiLayarDepan());
    if (charge == null) return;

    _remaining = charge.remaining;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _remaining = charge.remaining);
    });

    // Ditanyakan berulang, bukan ditunggu lewat aliran realtime:
    // tagihannya tidak menempel pada baris pesanan mana pun, jadi tidak
    // ada yang bisa dipantau. Tiga detik cukup rapat supaya kasir tidak
    // merasa menunggu lebih lama daripada pelanggannya.
    _poller = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (!mounted) return;
      if (await _gateway.isPaid(charge.referenceId)) _confirm();
    });
  }

  void _confirm() {
    _poller?.cancel();
    _ticker?.cancel();
    // Layar depan menyatakan lunas lebih dulu, baru layar kasirnya
    // ditutup. Pelanggan yang baru saja memindai butuh satu tanda bahwa
    // pembayarannya sampai — dan tanda itu paling berguna di layar yang
    // sedang dia lihat, bukan di layar kasir yang membelakanginya.
    final resto = _restoId;
    if (resto != null) {
      unawaited(_layar
          .lunas(resto, amount: widget.amount)
          .catchError((_) {}));
    }
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _simulate() async {
    setState(() => _simulating = true);
    final error =
        await _gateway.simulatePayment(referenceId: _charge?.referenceId);
    if (!mounted) return;
    setState(() => _simulating = false);
    if (error != null) showAppToast(context, error, isError: true);
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final currency =
        NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

    final qrData = _charge?.qrString ??
        'DUMMY-QRIS|MERCHANT:${settings.merchantName}'
            '|ID:${settings.qrisId}|AMOUNT:${widget.amount}';
    final expired = _gatewayActive && _remaining.isNegative;

    return Scaffold(
      appBar: AppBar(title: const Text('Bayar dengan QRIS')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 100),
                child: Column(
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 14),
                    Text('Menyiapkan kode pembayaran…',
                        style: TextStyle(color: Colors.grey)),
                  ],
                ),
              )
            else ...[
              MerchantPosQrCard(
                data: qrData,
                title: settings.merchantName,
                kicker: 'BAYAR DENGAN QRIS',
                subtitle: 'Scan pakai aplikasi bank atau e-wallet',
                badge: currency.format(_charge?.amount ?? widget.amount),
                footer: _gatewayActive
                    ? 'Layar ini lanjut sendiri setelah pembayaran diterima'
                    : 'Konfirmasi manual setelah pelanggan membayar',
                overlayText: expired ? 'Kedaluwarsa' : null,
              ),
              const SizedBox(height: 16),
              if (_gatewayActive && !expired)
                _WaitingLine(remaining: _remaining)
              else if (!_gatewayActive)
                const Text(
                  '(QR simulasi — payment gateway belum dipasang di merchant ini)',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
              const SizedBox(height: 16),
              // Dicetak, bukan cuma ditunjukkan.
              //
              // Layar kasir menghadap kasirnya, dan menyodorkannya ke
              // pelanggan berarti tabletnya berpindah tangan — di
              // tengah antrean, sambil terbuka di halaman transaksi.
              // Selembar kertas bisa dibawa ke mejanya dan dipindai
              // tanpa terburu-buru.
              OutlinedButton.icon(
                onPressed: () => printTableQrs(
                  context,
                  [
                    TableQrCard.payment(
                      restoName: settings.merchantName,
                      amount: currency.format(_charge?.amount ?? widget.amount),
                      payload: qrData,
                    ),
                  ],
                  name: 'qris-bayar',
                ),
                icon: const Icon(Icons.print_outlined, size: 18),
                label: const Text('Cetak QR untuk Customer'),
              ),
              const SizedBox(height: 16),
              if (_charge?.testMode == true) ...[
                OutlinedButton.icon(
                  onPressed: _simulating ? null : _simulate,
                  icon: _simulating
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.science_outlined, size: 18),
                  label: const Text('Simulasikan Pembayaran'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.orange.shade800,
                    side: BorderSide(color: Colors.orange.shade300),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Mode uji — QR ini bukan QRIS asli dan tidak bisa dipindai',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, color: Colors.orange.shade800),
                ),
                const SizedBox(height: 14),
              ],
              // Tombol konfirmasi manual hanya ada saat tidak ada
              // penyedia. Dengan gateway terpasang, kasir yang menekan
              // "sudah dibayar" untuk pembayaran yang belum masuk
              // menciptakan selisih yang baru ketahuan saat tutup buku.
              if (!_gatewayActive)
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Simulasikan: Sudah Dibayar'),
                ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Batal'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _WaitingLine extends StatelessWidget {
  final Duration remaining;

  const _WaitingLine({required this.remaining});

  @override
  Widget build(BuildContext context) {
    final m = remaining.inMinutes.toString().padLeft(2, '0');
    final s = (remaining.inSeconds % 60).toString().padLeft(2, '0');

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 13,
              height: 13,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 8),
            Text('Menunggu pembayaran…',
                style: TextStyle(fontSize: 12.5, color: MerchantPosTheme.mutedOf(context))),
          ],
        ),
        const SizedBox(height: 4),
        Text('Berlaku $m:$s',
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
      ],
    );
  }
}
