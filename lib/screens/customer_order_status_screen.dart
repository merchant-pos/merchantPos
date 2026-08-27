import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../db/order_repository.dart';
import '../models/customer_order.dart';
import '../models/order_type.dart';
import '../providers/auth_provider.dart';
import '../theme.dart';
import '../providers/table_session_provider.dart';
import '../utils/id_time.dart';
import '../widgets/cancel_order_button.dart';
import 'customer_receipt_screen.dart';
import '../widgets/dialog_actions.dart';

/// Lets the customer track their own orders live. Also where they end
/// their session once done.
///
/// Which orders count as "mine" depends on whether they're signed in:
///
///  - **Guest**: the session id assigned when they scanned the table QR.
///    It lives in this device's storage, which is all a guest has.
///  - **Signed in**: everything booked under their email at this resto.
///    Keying off the session there meant a new phone generated a new
///    session id and their orders vanished — even though the server had
///    them all along.
class CustomerOrderStatusScreen extends StatelessWidget {
  const CustomerOrderStatusScreen({super.key});

  static const _kitchenLabels = {
    KitchenStatus.waiting: 'Menunggu Diproses',
    KitchenStatus.onProgress: 'Sedang Dimasak',
    KitchenStatus.done: 'Selesai',
    KitchenStatus.cancelled: 'Dibatalkan',
  };
  static const _kitchenColors = {
    KitchenStatus.waiting: Colors.grey,
    KitchenStatus.onProgress: Colors.orange,
    KitchenStatus.done: Colors.green,
    KitchenStatus.cancelled: Colors.grey,
  };

  Future<void> _confirmEndSession(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Selesaikan Sesi?'),
        content: const Text(
          'Sesi meja ini akan diakhiri. Kalau kamu mau pesan lagi nanti, '
          'scan ulang QR meja yang sama untuk melanjutkan riwayat pesanan ini.',
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          DialogActions(
            confirmLabel: 'Ya, Selesai',
            onConfirm: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await context.read<TableSessionProvider>().endSession();
    if (!context.mounted) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<TableSessionProvider>();
    final currency = NumberFormat.currency(
      locale: 'id_ID',
      symbol: 'Rp ',
      decimalDigits: 0,
    );
    final dateFmt = DateFormat('HH:mm', 'id_ID');

    if (!session.hasActiveResto) {
      return Scaffold(
        appBar: AppBar(title: const Text('Pesanan Saya')),
        body: const Center(child: Text('Belum ada sesi aktif.')),
      );
    }

    final repo = OrderRepository();
    final auth = context.watch<AuthProvider>();
    final email = auth.isLoggedIn && !auth.isEmployee ? auth.user?.email : null;
    final restoId = session.restoId;

    return Scaffold(
      // Judulnya cukup "Pesanan Saya". Meja/Take Away dulu ditempel di
      // sini, padahal itu milik masing-masing pesanan, bukan milik
      // layarnya: daftar ini bisa memuat pesanan Dine In dan Take Away
      // sekaligus, jadi satu label di header pasti salah untuk sebagian
      // isinya.
      appBar: AppBar(title: const Text('Pesanan Saya')),
      body: StreamBuilder<List<CustomerOrder>>(
        stream: email != null
            ? repo.watchByCustomerEmail(email)
            : repo.watchBySession(session.sessionId!),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Text('Gagal memuat pesanan.\n${snapshot.error}',
                  textAlign: TextAlign.center),
            );
          }
          var orders = snapshot.data ?? [];
          // The email stream spans every resto they've ever ordered from;
          // this screen is about the place they're sitting in right now.
          // (Supabase streams only take one equality filter, so the resto
          // narrowing has to happen here.)
          if (email != null && restoId != null) {
            orders = orders.where((o) => o.restoId == restoId).toList();
          }
          if (orders.isEmpty) {
            return const Center(child: Text('Belum ada pesanan di sesi ini.'));
          }
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: orders.length,
            itemBuilder: (context, index) {
              final order = orders[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // Nomor antrean harian kalau ada; potongan
                          // UUID hanya untuk pesanan lama yang terbit
                          // sebelum penomoran ini dipasang.
                          Text(
                              order.punyaNomor
                                  ? 'Pesanan ${order.nomorTampil}'
                                  : 'Pesanan #${order.id.substring(0, 6).toUpperCase()}',
                              style: const TextStyle(fontWeight: FontWeight.bold)),
                          Row(
                            children: [
                              Text(dateFmt.format(order.createdAt.toWib()),
                                  style: const TextStyle(color: Colors.grey, fontSize: 12)),
                              // Tombol yang membuka penjelasan "tidak ada
                              // struk" tetap tombol yang mengecewakan.
                              // Yang batal tidak ditawari sama sekali.
                              if (!order.dibatalkan)
                              IconButton(
                                icon: const Icon(Icons.receipt_long_outlined, size: 20),
                                tooltip: 'Struk Pembayaran',
                                visualDensity: VisualDensity.compact,
                                onPressed: () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => CustomerReceiptScreen(order: order),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      _OrderPlaceLine(order: order),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          // Pesanan yang batal berhenti punya status
                          // dapur.
                          //
                          // Kolom kitchen_status-nya memang berhenti di
                          // nilai terakhirnya — jurnal dan riwayat butuh
                          // itu — tapi menampilkannya apa adanya berarti
                          // layar menyebut "Sedang Dimasak" untuk
                          // pesanan yang sudah dibatalkan, dan pelanggan
                          // menunggu makanan yang tidak akan datang.
                          Icon(Icons.circle,
                              size: 10,
                              color: order.dibatalkan
                                  ? MerchantPosTheme.mutedOf(context)
                                  : _kitchenColors[order.kitchenStatus]),
                          const SizedBox(width: 6),
                          Text(
                            order.dibatalkan
                                ? 'Dibatalkan'
                                : _kitchenLabels[order.kitchenStatus]!,
                            style: TextStyle(
                              color: order.dibatalkan
                                  ? MerchantPosTheme.mutedOf(context)
                                  : _kitchenColors[order.kitchenStatus],
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            switch (order.paymentStatus) {
                              OrderPaymentStatus.paid => 'Sudah Dibayar',
                              // Sudah disebut di sebelah kiri; diulang
                              // dua kali berdampingan malah terbaca
                              // seperti dua hal berbeda.
                              OrderPaymentStatus.cancelled => '',
                              OrderPaymentStatus.expired => 'Hangus, tidak dibayar',
                              OrderPaymentStatus.pending => 'Menunggu Pembayaran',
                            },
                            style: TextStyle(
                              color: switch (order.paymentStatus) {
                                OrderPaymentStatus.paid => Colors.green,
                                OrderPaymentStatus.pending => Colors.orange,
                                _ => MerchantPosTheme.mutedOf(context),
                              },
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 16),
                      ...order.items.map(
                        (item) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(child: Text('${item.productName} x${item.quantity}')),
                                  Text(currency.format(item.subtotal)),
                                ],
                              ),
                              if (item.notes != null && item.notes!.isNotEmpty)
                                Text(
                                  item.notes!,
                                  style: TextStyle(fontSize: 12, color: MerchantPosTheme.mutedOf(context)),
                                ),
                            ],
                          ),
                        ),
                      ),
                      const Divider(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Total', style: TextStyle(fontWeight: FontWeight.bold)),
                          Text(currency.format(order.total),
                              style: const TextStyle(fontWeight: FontWeight.bold)),
                        ],
                      ),
                      // Di sinilah pelanggan berada saat berubah pikiran:
                      // beberapa menit setelah memesan, masih duduk di
                      // restonya. Riwayat baru dibuka jauh sesudahnya.
                      if (order.canBeCancelledByCustomer) ...[
                        const SizedBox(height: 10),
                        CancelOrderButton(order: order),
                      ],
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: OutlinedButton.icon(
            icon: const Icon(Icons.check_circle_outline),
            label: const Text('Pesanan Sudah Semua • Selesai'),
            onPressed: () => _confirmEndSession(context),
          ),
        ),
      ),
    );
  }
}

/// Tempat pesanan ini diantar: nomor meja untuk Dine In, atau nama yang
/// akan dipanggil untuk Take Away.
///
/// Sebelumnya keterangan ini menempel di judul layar, yang membuatnya
/// berlaku untuk semua pesanan sekaligus — padahal satu orang bisa punya
/// pesanan Dine In dan Take Away berdampingan di daftar yang sama.
class _OrderPlaceLine extends StatelessWidget {
  final CustomerOrder order;

  const _OrderPlaceLine({required this.order});

  @override
  Widget build(BuildContext context) {
    final takeAway = order.orderType == OrderType.takeAway;
    final name = order.customerName?.trim();

    final label = takeAway
        ? 'Take Away'
        : (order.tableNumber != null && order.tableNumber!.isNotEmpty
            ? 'Meja ${order.tableNumber}'
            : 'Dine In');

    return Wrap(
      spacing: 6,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _chip(
          icon: takeAway ? Icons.shopping_bag_outlined : Icons.table_restaurant_outlined,
          text: label,
          color: takeAway ? const Color(0xFFF59E0B) : MerchantPosTheme.brand,
        ),
        if (name != null && name.isNotEmpty)
          _chip(
            icon: Icons.person_outline,
            text: name,
            color: MerchantPosTheme.mutedOf(context),
          ),
      ],
    );
  }

  Widget _chip({required IconData icon, required String text, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: color.withOpacity(0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: color),
          ),
        ],
      ),
    );
  }
}
