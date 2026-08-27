import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../db/guest_order_store.dart';
import '../db/order_repository.dart';
import '../db/product_review_repository.dart';
import '../db/restaurant_repository.dart';
import '../models/customer_order.dart';
import '../providers/auth_provider.dart';
import '../theme.dart';
import '../widgets/cancel_order_button.dart';
import '../utils/id_time.dart';
import 'customer_receipt_screen.dart';
import 'product_review_form.dart';

/// Cross-restaurant order history, in two flavours:
///
///  - **Logged in**: streamed live by email, so it follows the account to
///    any device and updates as the kitchen progresses.
///  - **Guest**: fetched by the order ids this device saved locally (see
///    [GuestOrderStore]). The orders themselves still come from the
///    server, so status stays accurate — but the *list of which orders
///    were mine* only exists on this phone.
///
/// Unlike "Pesanan Saya" (which only covers the current table session),
/// this spans every resto and session.
class CustomerHistoryScreen extends StatefulWidget {
  const CustomerHistoryScreen({super.key});

  @override
  State<CustomerHistoryScreen> createState() => _CustomerHistoryScreenState();
}

class _CustomerHistoryScreenState extends State<CustomerHistoryScreen> {
  final _restoRepo = RestaurantRepository();
  final _orderRepo = OrderRepository();
  final Map<String, String> _restoNameCache = {};

  // Guest mode only — recreated on pull-to-refresh to re-run the fetch.
  Future<List<CustomerOrder>>? _guestFuture;

  final _reviewRepo = ProductReviewRepository();

  /// Menu yang sudah dinilai, per pesanan.
  ///
  /// Dipakai dua hal: menyembunyikan ajakan menilai pada pesanan yang
  /// seluruh menunya sudah dinilai, dan menandai menu yang sudah dinilai
  /// di dalam daftarnya.
  Map<String, Set<String>> _dinilai = const {};

  /// Pesanan yang sudah pernah ditanyakan, supaya tidak ditanyakan lagi
  /// tiap kali aliran realtime menggerakkan daftarnya.
  final Set<String> _sudahDitanya = {};

  /// Menanyakan penilaian untuk pesanan yang belum pernah ditanyakan.
  ///
  /// Dipanggil dari build lewat post-frame — daftar pesanannya sendiri
  /// datang dari StreamBuilder, jadi tidak ada satu titik pun di
  /// initState tempat idnya sudah diketahui.
  Future<void> _muatPenilaian([List<CustomerOrder>? orders]) async {
    final ids = orders == null
        ? _sudahDitanya.toList()
        : [
            for (final o in orders)
              if (o.paymentStatus == OrderPaymentStatus.paid) o.id,
          ];
    if (ids.isEmpty) return;
    if (orders != null) {
      final baru = ids.where((id) => !_sudahDitanya.contains(id)).toList();
      if (baru.isEmpty) return;
      _sudahDitanya.addAll(baru);
    }
    try {
      final hasil = await _reviewRepo.sudahDinilai(_sudahDitanya.toList());
      if (!mounted) return;
      setState(() => _dinilai = hasil);
    } catch (_) {
      // Gagal menanyakan berarti ajakannya tetap muncul. Mengajak orang
      // menilai yang sudah dinilai jauh lebih ringan daripada
      // menyembunyikan ajakan yang seharusnya ada.
    }
  }

  /// Seluruh menu di pesanan ini sudah dinilai.
  bool _semuaDinilai(CustomerOrder order) {
    final sudah = _dinilai[order.id];
    if (sudah == null || sudah.isEmpty) return false;
    return order.items.every((i) => sudah.contains(i.productId));
  }

  Future<String> _restoName(String restoId) async {
    if (_restoNameCache.containsKey(restoId)) return _restoNameCache[restoId]!;
    final resto = await _restoRepo.getOnce(restoId);
    final name = resto?.name ?? restoId;
    _restoNameCache[restoId] = name;
    return name;
  }

  Future<List<CustomerOrder>> _loadGuestOrders() async {
    final ids = await GuestOrderStore().ids();
    return _orderRepo.getByIds(ids);
  }

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

  void _refresh() {
    // Yang login memakai aliran realtime — barisnya berubah sendiri.
    // Yang tamu memakai sekali ambil, jadi harus diminta ulang.
    if (context.read<AuthProvider>().user?.email == null) {
      setState(() => _guestFuture = _loadGuestOrders());
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = context.watch<AuthProvider>().user?.email;

    return Scaffold(
      appBar: AppBar(title: const Text('Riwayat Saya')),
      body: email != null ? _loggedInBody(email) : _guestBody(),
    );
  }

  Widget _loggedInBody(String email) {
    return StreamBuilder<List<CustomerOrder>>(
      stream: _orderRepo.watchByCustomerEmail(email),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Text('Gagal memuat riwayat.\n${snapshot.error}',
                textAlign: TextAlign.center),
          );
        }
        return _orderList(snapshot.data ?? []);
      },
    );
  }

  Widget _guestBody() {
    _guestFuture ??= _loadGuestOrders();

    return FutureBuilder<List<CustomerOrder>>(
      future: _guestFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Text('Gagal memuat riwayat.\n${snapshot.error}',
                textAlign: TextAlign.center),
          );
        }
        return RefreshIndicator(
          // One-shot fetch, so status only moves on an explicit refresh —
          // unlike the logged-in stream, which updates on its own.
          onRefresh: () async {
            setState(() => _guestFuture = _loadGuestOrders());
            await _guestFuture;
          },
          child: _orderList(snapshot.data ?? [], guestNotice: true),
        );
      },
    );
  }

  /// Memilih menu mana dari pesanan itu yang mau dinilai.
  ///
  /// Satu pesanan bisa berisi lima menu, dan yang mengecewakan biasanya
  /// cuma satu. Melompat langsung ke formulir menu pertama berarti
  /// penilaian yang salah sasaran.
  Future<void> _nilaiMenu(CustomerOrder order) async {
    // Menu yang sama bisa muncul beberapa baris dengan pilihan berbeda.
    // Yang dinilai menunya, bukan barisnya.
    final unik = <String, String>{};
    for (final i in order.items) {
      unik.putIfAbsent(i.productId, () => i.productName);
    }
    final sudah = _dinilai[order.id] ?? const <String>{};

    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 18, 20, 6),
              child: Text('Menu mana yang mau dinilai?',
                  style:
                      TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            ),
            for (final e in unik.entries)
              ListTile(
                leading: Icon(
                  sudah.contains(e.key)
                      ? Icons.star_rounded
                      : Icons.restaurant_menu,
                  size: 20,
                  color: sudah.contains(e.key)
                      ? const Color(0xFFF59E0B)
                      : null,
                ),
                title: Text(e.value),
                // Yang sudah dinilai tetap ditampilkan, dengan tanda.
                // Menyembunyikannya membuat orang mengira menunya hilang
                // — dan mengubah penilaian yang barusan ditulis jadi
                // tidak mungkin.
                subtitle: sudah.contains(e.key)
                    ? const Text('Sudah dinilai — ketuk untuk mengubah',
                        style: TextStyle(fontSize: 11.5))
                    : null,
                trailing: const Icon(Icons.chevron_right, size: 20),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  final tersimpan = await Navigator.of(context).push<bool>(
                    MaterialPageRoute(
                      builder: (_) => ProductReviewForm(
                        restoId: order.restoId,
                        orderId: order.id,
                        productId: e.key,
                        productName: e.value,
                      ),
                    ),
                  );
                  if (tersimpan == true) await _muatPenilaian();
                },
              ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  Widget _orderList(List<CustomerOrder> orders, {bool guestNotice = false}) {
    final currency = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
    final dateFmt = DateFormat('dd MMM yyyy, HH:mm', 'id_ID');

    WidgetsBinding.instance
        .addPostFrameCallback((_) => _muatPenilaian(orders));

    if (orders.isEmpty) {
      // Still a scrollable, so pull-to-refresh keeps working when empty.
      return ListView(
        children: [
          if (guestNotice) const _GuestNotice(),
          const Padding(
            padding: EdgeInsets.only(top: 60),
            child: Center(child: Text('Belum ada riwayat pesanan.')),
          ),
        ],
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: orders.length + (guestNotice ? 1 : 0),
      itemBuilder: (context, index) {
        if (guestNotice && index == 0) return const _GuestNotice();
        final order = orders[index - (guestNotice ? 1 : 0)];
        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: Column(
            children: [
              ListTile(
            title: FutureBuilder<String>(
              future: _restoName(order.restoId),
              builder: (context, snap) => Text(
                snap.data ?? order.restoId,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${order.tableNumber != null ? 'Meja ${order.tableNumber} • ' : ''}'
                  '${dateFmt.format(order.createdAt.toWib())}',
                  style: const TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    // Pesanan yang batal berhenti punya status dapur.
                    //
                    // Datanya sudah dibetulkan pemicu di basis data,
                    // tapi baris lama yang terbit sebelum itu masih
                    // membawa nilai lamanya — dan riwayat memang tempat
                    // baris lama berkumpul.
                    Icon(Icons.circle,
                        size: 8,
                        color: order.dibatalkan
                            ? Colors.grey
                            : _kitchenColors[order.kitchenStatus]),
                    const SizedBox(width: 4),
                    Text(
                      order.dibatalkan
                          ? 'Dibatalkan'
                          : _kitchenLabels[order.kitchenStatus]!,
                      style: TextStyle(
                        fontSize: 11,
                        color: order.dibatalkan
                            ? Colors.grey
                            : _kitchenColors[order.kitchenStatus],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      switch (order.paymentStatus) {
                        OrderPaymentStatus.paid => 'Sudah Dibayar',
                        // Sudah disebut di sebelah kiri; diulang dua
                        // kali berdampingan malah terbaca seperti dua
                        // hal berbeda.
                        OrderPaymentStatus.cancelled => '',
                        OrderPaymentStatus.expired => 'Hangus, tidak dibayar',
                        OrderPaymentStatus.pending => 'Menunggu Pembayaran',
                      },
                      style: TextStyle(
                        fontSize: 11,
                        color: switch (order.paymentStatus) {
                          OrderPaymentStatus.paid => Colors.green,
                          OrderPaymentStatus.pending => Colors.orange,
                          _ => MerchantPosTheme.mutedOf(context),
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
            trailing: Text(
              currency.format(order.total),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
                // Pesanan yang batal tidak bisa dibuka strukmya —
                // barisnya tetap ada di riwayat, tapi tidak menawarkan
                // bukti pembayaran yang memang tidak pernah ada.
                onTap: order.dibatalkan
                    ? null
                    : () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) =>
                                  CustomerReceiptScreen(order: order)),
                        ),
              ),
              // Tombolnya hanya muncul selagi benar-benar bisa dipakai.
              // Tombol yang selalu ada lalu menolak saat ditekan membuat
              // orang mengira aplikasinya rusak — padahal yang terjadi
              // cuma dapur sudah mulai memasak.
              // Menilai menu hanya ditawarkan pada pesanan yang lunas,
              // dan hanya kepada yang punya akun.
              //
              // Bukan sekadar aturan tampilan: basis data menolak
              // penilaian atas menu yang tidak pernah dibeli orang itu.
              // Tombol yang muncul di tempat lain cuma akan berakhir
              // sebagai pesan galat.
              // Hilang begitu seluruh menunya sudah dinilai. Tombol yang
              // tetap ada setelah semuanya selesai adalah ajakan yang
              // tidak punya isi — dan yang menekannya menemukan daftar
              // yang seluruhnya sudah bertanda.
              if (order.paymentStatus == OrderPaymentStatus.paid &&
                  context.read<AuthProvider>().user != null &&
                  order.items.isNotEmpty &&
                  !_semuaDinilai(order))
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 12, 6),
                    child: TextButton.icon(
                      icon: const Icon(Icons.star_border, size: 18),
                      label: const Text('Boleh bantu rating pesanannya yaa'),
                      onPressed: () => _nilaiMenu(order),
                    ),
                  ),
                ),
              if (order.canBeCancelledByCustomer)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                  child: CancelOrderButton(
                    order: order,
                    onCancelled: _refresh,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Sets expectations about what a guest's history actually is, so nobody
/// assumes it'll survive a reinstall or follow them to a new phone.
class _GuestNotice extends StatelessWidget {
  const _GuestNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          Icon(Icons.phone_android, size: 18, color: Colors.orange.shade800),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              kIsWeb
                  ? 'Riwayat ini tersimpan di peramban ini saja, dan hilang '
                      'kalau data situsnya dibersihkan. Pasang aplikasi '
                      'Merchant-POS untuk menyimpannya di akunmu.'
                  : 'Riwayat ini tersimpan di HP ini saja. Login dengan Gmail '
                      'supaya riwayatmu tetap ada walau ganti HP.',
              style: TextStyle(fontSize: 12, color: Colors.orange.shade900),
            ),
          ),
        ],
      ),
    );
  }
}
