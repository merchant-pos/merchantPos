import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../db/order_repository.dart';
import '../models/customer_order.dart';
import '../services/payment_gateway_service.dart';
import '../theme.dart';
import '../utils/qris_image.dart';
import '../widgets/app_toast.dart';
import '../widgets/merchantpos_qr_card.dart';
import '../utils/id_time.dart';

/// Layar pembayaran QRIS untuk pesanan mandiri.
///
/// Dua keadaan yang sangat berbeda, dan layar ini melayani keduanya:
///
/// - **Gateway terpasang.** QR-nya terbit di penyedia pembayaran, punya
///   masa berlaku, dan yang menyatakan lunas adalah webhook penyedia.
///   Tidak ada tombol apa pun yang bisa ditekan untuk mengaku sudah
///   membayar — apa pun yang bisa ditekan orang yang belum membayar
///   bukan bukti pembayaran.
///
/// - **Belum terpasang.** Kembali ke QR simulasi seperti sebelumnya,
///   lengkap dengan tombol konfirmasinya. Resto yang belum punya akun
///   gateway tetap harus bisa menerima pesanan, dan layar pembayaran
///   yang gagal terbuka jauh lebih merugikan daripada yang jatuh ke cara
///   lama.
class CustomerQrisScreen extends StatefulWidget {
  final String orderId;
  final int amount;
  final String restoId;

  const CustomerQrisScreen({
    super.key,
    required this.orderId,
    required this.amount,
    required this.restoId,
  });

  @override
  State<CustomerQrisScreen> createState() => _CustomerQrisScreenState();
}

class _CustomerQrisScreenState extends State<CustomerQrisScreen> {
  final _orderRepo = OrderRepository();
  final _gateway = PaymentGatewayService();

  QrisCharge? _charge;
  bool _loadingCharge = true;
  bool _confirming = false;
  bool _downloading = false;
  bool _simulating = false;

  StreamSubscription<CustomerOrder?>? _orderSub;
  Timer? _ticker;
  Timer? _poller;

  /// Layar suksesnya sudah dibuka.
  ///
  /// Sekarang ada dua sumber yang bisa memicunya — aliran realtime dan
  /// penjaga tiga detik — dan keduanya bisa datang nyaris bersamaan.
  /// Tanpa penanda ini, layar suksesnya ditumpuk dua kali, dan yang
  /// menekan Selesai akan menemukan salinannya lagi di baliknya.
  bool _navigated = false;
  Duration _remaining = Duration.zero;

  /// Nominal yang ditampilkan. Angka dari server dipakai begitu ada —
  /// itu yang sama dengan yang dituntut QR-nya.
  int get _amount => _charge?.amount ?? widget.amount;

  bool get _gatewayActive => _charge != null;

  @override
  void initState() {
    super.initState();
    _createCharge();
    _watchOrder();
  }

  @override
  void dispose() {
    _orderSub?.cancel();
    _ticker?.cancel();
    _poller?.cancel();
    super.dispose();
  }

  Future<void> _createCharge() async {
    final charge = await _gateway.createQris(widget.orderId);
    if (!mounted) return;
    setState(() {
      _charge = charge;
      _loadingCharge = false;
    });
    if (charge != null) _startTicker();
  }

  void _startTicker() {
    _ticker?.cancel();
    setState(() => _remaining = _charge!.remaining);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _remaining = _charge!.remaining);
      if (_remaining.isNegative) _ticker?.cancel();
    });
  }

  /// Menunggu kabar dari server bahwa pesanannya lunas.
  ///
  /// Ini satu-satunya jalan pindah layar saat gateway terpasang: yang
  /// menggerakkan statusnya adalah webhook penyedia, dan HP-nya hanya
  /// menonton.
  void _watchOrder() {
    _orderSub = _orderRepo.watchOne(widget.orderId).listen((order) {
      if (!mounted || order == null) return;
      if (order.paymentStatus == OrderPaymentStatus.paid) _goToSuccess();
    });

    // Penjaga kalau aliran realtime-nya tersendat.
    //
    // Layar ini menunggu kabar yang datangnya dari luar HP, dan sinyal
    // yang putus sebentar di tengah resto sudah cukup membuat kabarnya
    // tidak pernah sampai. Yang menunggu di depan kasir tidak tahu itu —
    // yang dia lihat cuma layar yang diam padahal uangnya sudah keluar.
    //
    // Tiga detik: cukup rapat supaya perpindahannya terasa seketika,
    // cukup jarang supaya menunggu setengah jam tidak berarti ribuan
    // permintaan.
    _poller = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (!mounted) return;
      try {
        final rows = await _orderRepo.getByIds([widget.orderId]);
        if (!mounted || rows.isEmpty) return;
        if (rows.first.paymentStatus == OrderPaymentStatus.paid) _goToSuccess();
      } catch (_) {
        // Sedang luring. Percobaan berikutnya tiga detik lagi.
      }
    });
  }

  void _goToSuccess() {
    if (_navigated) return;
    _navigated = true;
    _orderSub?.cancel();
    _poller?.cancel();
    _ticker?.cancel();
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => _OrderPlacedScreen(orderId: widget.orderId)),
      (route) => route.isFirst,
    );
  }

  Future<void> _downloadQr({required String qrData, required String merchantName}) async {
    setState(() => _downloading = true);
    await saveQrisToGallery(
      context,
      qrData: qrData,
      merchantName: merchantName,
      amount: _amount,
      orderId: widget.orderId,
    );
    if (mounted) setState(() => _downloading = false);
  }

  /// Hanya dipakai saat gateway belum terpasang.
  Future<void> _confirmPaid() async {
    setState(() => _confirming = true);
    try {
      await _orderRepo.markPaid(widget.orderId);
      // Perpindahan layarnya ditangani pemantau pesanan.
    } catch (e) {
      if (!mounted) return;
      showAppToast(context, 'Gagal konfirmasi pembayaran: $e', isError: true);
      setState(() => _confirming = false);
    }
  }

  /// Hanya muncul saat penyedianya memakai kunci uji.
  ///
  /// Yang dipanggil endpoint simulasi milik penyedia — pelunasannya
  /// tetap datang lewat webhook, sama seperti pembayaran sungguhan.
  /// Jadi yang diuji tetap rantai yang sebenarnya, bukan jalan pintas
  /// yang cuma ada saat pengujian.
  Future<void> _simulate() async {
    setState(() => _simulating = true);
    final error = await _gateway.simulatePayment(orderId: widget.orderId);
    if (!mounted) return;
    setState(() => _simulating = false);
    if (error != null) showAppToast(context, error, isError: true);
    // Perpindahan layarnya ditangani pemantau pesanan, sama seperti
    // pembayaran sungguhan.
  }

  Future<void> _renewCharge() async {
    setState(() => _loadingCharge = true);
    await _createCharge();
  }

  @override
  Widget build(BuildContext context) {
    final currency =
        NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bayar dengan QRIS'),
        automaticallyImplyLeading: false,
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: Supabase.instance.client
            .from('settings')
            .stream(primaryKey: ['resto_id']).eq('resto_id', widget.restoId),
        builder: (context, snapshot) {
          final data = snapshot.data?.isNotEmpty == true ? snapshot.data!.first : null;
          final merchantName = data?['merchant_name'] as String? ?? 'Toko';
          final qrisId = data?['qris_id'] as String? ?? '-';

          final qrData = _charge?.qrString ??
              'DUMMY-QRIS|MERCHANT:$merchantName|ID:$qrisId'
                  '|AMOUNT:$_amount|ORDER:${widget.orderId}';
          final expired = _gatewayActive && _remaining.isNegative;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Text(merchantName,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(
                  currency.format(_amount),
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 20),
                if (_loadingCharge)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 80),
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
                    title: merchantName,
                    kicker: 'BAYAR DENGAN QRIS',
                    subtitle: 'Scan pakai aplikasi bank atau e-wallet',
                    badge: currency.format(_amount),
                    footer: 'Nomor pesanan #${refOf(widget.orderId)}',
                    overlayText: expired ? 'Kedaluwarsa' : null,
                  ),
                  const SizedBox(height: 14),
                  if (_gatewayActive)
                    _StatusLine(remaining: _remaining)
                  else
                    const Text(
                      '(QR simulasi — payment gateway belum dipasang di merchant ini)',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  const SizedBox(height: 22),
                  if (expired)
                    FilledButton.icon(
                      onPressed: _renewCharge,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Buat QR Baru'),
                    )
                  else ...[
                    // Membayar biasanya berarti berpindah ke aplikasi
                    // bank, yang membuat layar ini hilang dari pandangan
                    // — jadi biarkan mereka menyimpan salinannya.
                    OutlinedButton.icon(
                      onPressed: _downloading
                          ? null
                          : () => _downloadQr(qrData: qrData, merchantName: merchantName),
                      icon: _downloading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.download_outlined),
                      label: const Text('Simpan QR ke Galeri'),
                    ),
                    // Mode uji: QR-nya bukan QRIS asli, jadi tidak ada
                    // yang bisa memindainya. Tombol ini menggantikan
                    // tindakan memindai itu — bukan menggantikan
                    // webhooknya, yang tetap yang menyatakan lunas.
                    //
                    // Muncul karena servernya bilang ini kunci uji,
                    // bukan karena penanda saat build. Ganti ke kunci
                    // produksi dan tombolnya hilang tanpa build ulang.
                    if (_charge?.testMode == true) ...[
                      const SizedBox(height: 12),
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
                      const SizedBox(height: 4),
                      Text(
                        'Mode uji — QR ini bukan QRIS asli dan tidak bisa dipindai',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 11, color: Colors.orange.shade800),
                      ),
                    ],
                    // Tombol "sudah bayar" hanya ada saat belum ada
                    // gateway. Dengan gateway terpasang, satu-satunya
                    // yang boleh menyatakan lunas adalah penyedianya.
                    if (!_gatewayActive) ...[
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: _confirming ? null : _confirmPaid,
                        child: _confirming
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2))
                            : const Text('Simulasikan: Sudah Dibayar'),
                      ),
                    ],
                  ],
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Baris keadaan saat gateway terpasang: menunggu, berikut sisa waktunya.
class _StatusLine extends StatelessWidget {
  final Duration remaining;

  const _StatusLine({required this.remaining});

  @override
  Widget build(BuildContext context) {
    if (remaining.isNegative) {
      return Text(
        'Waktu pembayaran habis. Buat QR baru untuk melanjutkan.',
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.red.shade700, fontSize: 12.5),
      );
    }

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
        const SizedBox(height: 6),
        Text(
          'Berlaku $m:$s',
          style: const TextStyle(
              fontSize: 13, fontWeight: FontWeight.bold, color: MerchantPosTheme.brandDark),
        ),
        const SizedBox(height: 4),
        Text(
          'Layar ini berpindah sendiri begitu pembayaranmu diterima.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11.5, color: MerchantPosTheme.mutedOf(context)),
        ),
      ],
    );
  }
}

class _OrderPlacedScreen extends StatelessWidget {
  final String orderId;

  const _OrderPlacedScreen({required this.orderId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pesanan Diterima'),
        automaticallyImplyLeading: false,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 84,
                height: 84,
                decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle),
                child: const Icon(Icons.check, color: Colors.white, size: 48),
              ),
              const SizedBox(height: 16),
              const Text('Pembayaran Berhasil',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text('Nomor pesanan: ${orderId.substring(0, 8).toUpperCase()}',
                  style: const TextStyle(color: Colors.grey)),
              const SizedBox(height: 4),
              const Text(
                'Pesanan kamu sudah masuk ke kasir dan sedang diproses.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
                child: const Text('Selesai'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
