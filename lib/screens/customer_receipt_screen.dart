import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme.dart';
import '../db/restaurant_repository.dart';
import '../models/customer_order.dart';
import '../models/order_type.dart';
import '../models/receipt_data.dart';
import '../models/restaurant.dart';
import '../utils/id_time.dart';
import '../utils/receipt_image.dart';
import '../widgets/receipt_view.dart';

/// Itemized receipt for one customer order, which can be saved to the
/// gallery or shared out through the phone's own share sheet. Reachable
/// from "Pesanan Saya" and the customer's own order history.
class CustomerReceiptScreen extends StatefulWidget {
  final CustomerOrder order;

  /// Dibuka dari Riwayat Transaksi oleh kasir/admin, bukan oleh
  /// customer. Yang mereka butuhkan mencetak ulang, bukan menyimpan
  /// struk orang lain ke galeri HP-nya sendiri.
  final bool forStaff;

  const CustomerReceiptScreen({
    super.key,
    required this.order,
    this.forStaff = false,
  });

  @override
  State<CustomerReceiptScreen> createState() => _CustomerReceiptScreenState();
}

class _CustomerReceiptScreenState extends State<CustomerReceiptScreen> {
  final _restoRepo = RestaurantRepository();
  Restaurant? _resto;
  bool _sharing = false;
  bool _downloading = false;

  @override
  void initState() {
    super.initState();
    _loadResto();
  }

  Future<void> _loadResto() async {
    try {
      final resto = await _restoRepo.getOnce(widget.order.restoId);
      if (mounted) setState(() => _resto = resto);
    } catch (_) {
      // Offline — the receipt still prints, just without shop details.
    }
  }

  String _paymentLabel(CustomerOrder order) {
    if (order.source == OrderSource.kasir) return order.paymentMethod ?? '-';
    return 'QRIS';
  }

  ReceiptData get _data {
    final order = widget.order;
    final dateFmt = DateFormat('dd MMM yyyy, HH:mm', 'id_ID');
    final paidAt = order.createdAt.toWib();

    return ReceiptData(
      restoName: _resto?.name ?? 'Merchant',
      restoAddress: _resto?.address,
      restoPhone: _resto?.phone,
      restoLogoBase64: _resto?.logoBase64,
      reference: '#${order.id.substring(0, 8).toUpperCase()}',
      dateTime: paidAt,
      headerRows: [
        if (order.punyaNomor) ('No. Pesanan', order.nomorTampil),
        ('No.', '#${order.id.substring(0, 8).toUpperCase()}'),
        if (order.cashierName != null && order.cashierName!.isNotEmpty)
          ('Diinput oleh', order.cashierName!),
        (
          'Tipe',
          order.tableNumber != null
              ? '${kOrderTypeLabels[order.orderType]!} · Meja ${order.tableNumber}'
              : kOrderTypeLabels[order.orderType]!
        ),
        if (order.customerName != null && order.customerName!.isNotEmpty)
          ('Nama', order.customerName!),
      ],
      lines: order.items
          .map((i) => ReceiptLine(
                name: i.productName,
                quantity: i.quantity,
                unitPrice: i.price,
                subtotal: i.subtotal,
                note: i.notes,
              ))
          .toList(),
      total: order.total,
      serviceAmount: order.serviceAmount,
      ppnAmount: order.ppnAmount,
      footerRows: [
        ('Metode', _paymentLabel(order)),
        ('Dibayar', dateFmt.format(paidAt)),
      ],
      paid: order.paymentStatus == OrderPaymentStatus.paid,
    );
  }

  bool _printing = false;

  Future<void> _print() async {
    setState(() => _printing = true);
    await printReceipt(context, _data);
    if (mounted) setState(() => _printing = false);
  }

  Future<void> _downloadToGallery() async {
    setState(() => _downloading = true);
    await saveReceiptToGallery(context, _data);
    if (mounted) setState(() => _downloading = false);
  }

  Future<void> _share() async {
    setState(() => _sharing = true);
    await shareReceipt(context, _data);
    if (mounted) setState(() => _sharing = false);
  }

  @override
  Widget build(BuildContext context) {
    // Pesanan yang batal tidak punya struk, dan tidak boleh punya.
    //
    // Struk adalah bukti pembayaran. Menerbitkannya untuk pesanan yang
    // uangnya tidak pernah berpindah berarti membuat bukti atas sesuatu
    // yang tidak terjadi — dan yang memegangnya bisa memakainya untuk
    // menagih, mengklaim ke kantor, atau menuntut barangnya.
    //
    // Penjaganya di sini, bukan di tiap tombol yang membukanya. Ada tiga
    // pintu menuju layar ini hari ini, dan pintu keempat yang dibuat
    // nanti tidak akan ingat memasang penjaganya sendiri.
    if (widget.order.dibatalkan) {
      return const _TanpaStruk();
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.forStaff ? 'Cetak Ulang Struk' : 'Struk Pembayaran'),
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
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
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: widget.forStaff
                ? SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      icon: _printing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.print_outlined),
                      label: const Text('Cetak Ulang Struk'),
                      onPressed: _printing ? null : _print,
                    ),
                  )
                : Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: _downloading
                        ? const SizedBox(
                            width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.download_outlined),
                    label: const Text('Simpan'),
                    onPressed: _downloading ? null : _downloadToGallery,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: _sharing
                        ? const SizedBox(
                            width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.share_outlined),
                    label: const Text('Bagikan'),
                    onPressed: _sharing ? null : _share,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Yang ditampilkan menggantikan struk pesanan yang batal.
class _TanpaStruk extends StatelessWidget {
  const _TanpaStruk();

  @override
  Widget build(BuildContext context) {
    final muted = MerchantPosTheme.mutedOf(context);
    return Scaffold(
      backgroundColor: MerchantPosTheme.backgroundOf(context),
      appBar: AppBar(title: const Text('Struk Pembayaran')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.receipt_long_outlined, size: 46, color: muted),
              const SizedBox(height: 14),
              const Text(
                'Pesanan ini tidak punya struk',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 8),
              Text(
                'Pesanannya dibatalkan atau hangus sebelum dibayar, jadi '
                'tidak ada pembayaran yang bisa dibuktikan.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: muted, height: 1.4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
