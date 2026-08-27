import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../db/restaurant_repository.dart';
import '../models/order_type.dart';
import '../models/receipt_data.dart';
import '../models/restaurant.dart';
import '../models/transaction.dart';
import '../providers/auth_provider.dart';
import '../utils/receipt_image.dart';
import '../widgets/receipt_view.dart';

/// Shown right after a Kasir/Admin checkout: a success beat, then the
/// printed receipt itself.
class ReceiptScreen extends StatefulWidget {
  final PosTransaction transaction;

  const ReceiptScreen({super.key, required this.transaction});

  @override
  State<ReceiptScreen> createState() => _ReceiptScreenState();
}

class _ReceiptScreenState extends State<ReceiptScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;
  late final Animation<double> _fade;

  final _restoRepo = RestaurantRepository();
  Restaurant? _resto;
  bool _printing = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _scale = CurvedAnimation(parent: _controller, curve: Curves.elasticOut);
    _fade = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.4, 1.0, curve: Curves.easeIn),
    );
    _controller.forward();
    _loadResto();
  }

  /// Name, address and logo come from the resto record — the receipt
  /// header is the customer-facing part, so it shows the shop, not the
  /// app. Failing to load just leaves those blank rather than blocking
  /// the receipt.
  Future<void> _loadResto() async {
    final restoId = context.read<AuthProvider>().restoId;
    if (restoId == null) return;
    try {
      final resto = await _restoRepo.getOnce(restoId);
      if (mounted) setState(() => _resto = resto);
    } catch (_) {
      // Offline — the receipt still prints, just without shop details.
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _paymentLabel(PaymentMethod m) {
    switch (m) {
      case PaymentMethod.cash:
        return 'Tunai';
      case PaymentMethod.qris:
        return 'QRIS';
      case PaymentMethod.transfer:
        return 'Transfer';
    }
  }

  ReceiptData get _data {
    final tx = widget.transaction;
    final dateFmt = DateFormat('dd MMM yyyy, HH:mm', 'id_ID');

    return ReceiptData(
      restoName: _resto?.name ?? 'Merchant',
      restoAddress: _resto?.address,
      restoPhone: _resto?.phone,
      restoLogoBase64: _resto?.logoBase64,
      reference: '#${tx.id.substring(0, 8).toUpperCase()}',
      // Kasir transactions are stamped with the device's own clock at
      // checkout, so this is already local time — no WIB shift here.
      dateTime: tx.createdAt,
      headerRows: [
        if (tx.punyaNomor) ('No. Pesanan', tx.nomorTampil),
        ('No.', '#${tx.id.substring(0, 8).toUpperCase()}'),
        if (tx.cashierName != null && tx.cashierName!.isNotEmpty) ('Kasir', tx.cashierName!),
        ('Tipe', kOrderTypeLabels[tx.orderType]!),
        if (tx.customerName != null && tx.customerName!.isNotEmpty) ('Nama', tx.customerName!),
      ],
      lines: tx.items
          .map((i) => ReceiptLine(
                name: i.productName,
                quantity: i.quantity,
                unitPrice: i.price,
                subtotal: i.subtotal,
                note: i.notes,
              ))
          .toList(),
      total: tx.total,
      serviceAmount: tx.serviceAmount,
      ppnAmount: tx.ppnAmount,
      cashReceived: tx.cashReceived,
      footerRows: [
        ('Metode', _paymentLabel(tx.paymentMethod)),
        ('Dibayar', dateFmt.format(tx.createdAt)),
      ],
    );
  }

  Future<void> _print() async {
    setState(() => _printing = true);
    await printReceipt(context, _data);
    if (mounted) setState(() => _printing = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Struk'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 16),
            ScaleTransition(
              scale: _scale,
              child: Container(
                width: 72,
                height: 72,
                decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle),
                child: const Icon(Icons.check, color: Colors.white, size: 42),
              ),
            ),
            const SizedBox(height: 10),
            FadeTransition(
              opacity: _fade,
              child: const Text(
                'Pembayaran Berhasil',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.10),
                        blurRadius: 12,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: ReceiptView(data: _data),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      icon: _printing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.print_outlined),
                      label: const Text('Cetak Struk'),
                      onPressed: _printing ? null : _print,
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst),
                      child: const Text('Selesai'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
