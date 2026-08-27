import '../widgets/penilaian_tile.dart';
import 'package:flutter/material.dart';

import '../theme.dart';

import '../widgets/language_theme_toggle.dart';
import 'package:provider/provider.dart';

import '../db/order_repository.dart';
import '../models/customer_order.dart';
import '../providers/auth_provider.dart';
import '../widgets/inbox_icon_button.dart';
import '../widgets/kitchen_checklist_dialog.dart';
import '../utils/logout_confirm.dart';
import '../widgets/grouped_order_list.dart';
import '../widgets/app_toast.dart';

/// Chef's entire app: a live, tabbed feed of incoming orders — from both
/// Employee Kasir sales and customer self-orders — with full item detail.
/// Chef can advance an order from "Baru" → "Diproses" → "Selesai"; the
/// status updates live for the customer to see too. No product
/// management, no cashier access, no settings.
class ChefHomeScreen extends StatefulWidget {
  const ChefHomeScreen({super.key});

  @override
  State<ChefHomeScreen> createState() => _ChefHomeScreenState();
}

class _ChefHomeScreenState extends State<ChefHomeScreen> {
  final _repo = OrderRepository();

  /// Status null berarti tab "Menunggu Pembayaran": isinya dipilih dari
  /// status bayarnya, bukan status dapurnya.
  static const _tabs = <(KitchenStatus?, String)>[
    (null, 'Menunggu Bayar'),
    (KitchenStatus.waiting, 'Baru'),
    (KitchenStatus.onProgress, 'Diproses'),
    (KitchenStatus.done, 'Selesai'),
  ];

  /// Pesanan yang uangnya belum diterima ditarik keluar dari tiga tab
  /// kerja dan dikumpulkan di tab pertama.
  ///
  /// Semua yang belum lunas, bukan hanya yang memilih bayar tunai:
  /// pesanan QRIS yang ditinggal tanpa dibayar sama belum lunasnya, dan
  /// penanda yang lebih sempit membuatnya jatuh ke antrean "Baru"
  /// seolah sudah beres — persis yang tidak boleh terjadi.
  bool _awaitingPayment(CustomerOrder o) => o.isAwaitingPayment;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final restoId = auth.restoId!;
    final employeeName = auth.employeeName?.isNotEmpty == true ? auth.employeeName! : 'Chef';

    return DefaultTabController(
      length: _tabs.length,
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: 60,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(employeeName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              Text(
                '${auth.roleLabel ?? 'Chef'} • ${auth.user?.email ?? ''}',
                style: const TextStyle(fontSize: 11, color: Colors.white70),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
          // Bisa digeser, tapi ditaruh di tengah.
          //
          // Empat tab dengan satu label dua kata tidak muat dibagi rata
          // di layar HP, jadi tetap harus bisa digeser. Yang berubah cuma
          // perataannya: rata kiri menyisakan ruang kosong menganggur di
          // kanan dan membuat barisnya terlihat terpotong — seolah ada
          // tab kelima yang gagal dimuat.
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.center,
            tabs: _tabs.map((t) => Tab(text: t.$2)).toList(),
          ),
          actions: [
            // Owner membuka layar ini dari hub-nya sendiri, dan hub itu
            // sudah punya Kotak Masuk, Tes Notifikasi, Tampilan, dan
            // Keluar. Menampilkannya lagi di sini bukan cuma
            // mengulang — ia menawarkan pengaturan aplikasi di layar
            // yang dia buka untuk satu hal saja: mengintip dapur.
            if (!auth.isOwner) ...[
              const AppearanceIconButton(),
              const InboxIconButton(),
              // Tombol Tes Notifikasi dibuang: push-nya sudah berjalan,
              // dan tombol uji yang tertinggal di layar pemakai
              // akhirnya ditekan seseorang yang mengira itu fitur.
              //
              // Penilaian pelanggan menggantikannya di sini. Layar ini
              // berupa tab, bukan daftar menu, jadi pintunya berupa
              // ikon — chef yang menerima keluhan di meja juga yang
              // paling perlu tahu apa yang ditulis orang setelah pulang.
              IconButton(
                icon: const Icon(Icons.star_outline),
                tooltip: 'Penilaian Pelanggan',
                onPressed: () => bukaPenilaian(context),
              ),
            ],
            // Owner membuka layar ini dari hub-nya, dan hub itu sudah
            // punya menu Keluar sendiri. Tombol logout di sini akan
            // mengeluarkannya dari aplikasi hanya karena dia mengintip
            // dapur — sesuatu yang tidak pernah dia maksud.
            if (!auth.isOwner)
              IconButton(
                icon: const Icon(Icons.logout),
                tooltip: 'Keluar',
                onPressed: () async {
                  if (!await confirmLogout(context)) return;
                  if (!context.mounted) return;
                  await context.read<AuthProvider>().signOut();
                },
              ),
          ],
        ),
        body: StreamBuilder<List<CustomerOrder>>(
          stream: _repo.watchAll(restoId),
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
            // Pesanan yang hangus atau ditarik pelanggannya tidak muncul
            // di mana pun di dapur. Membiarkannya jatuh kembali ke "Baru"
            // hanya karena status bayarnya bukan lagi 'pending' adalah
            // cara paling pasti memasak pesanan yang sudah dibatalkan.
            final allOrders =
                (snapshot.data ?? []).where((o) => !o.isVoid).toList();

            return TabBarView(
              children: _tabs.map((tab) {
                final orders = tab.$1 == null
                    ? allOrders.where(_awaitingPayment).toList()
                    : allOrders
                        // Yang batal keluar dari antrean dapur. Kolom
                        // kitchen_status-nya berhenti di nilai
                        // terakhirnya — riwayat butuh itu — tapi
                        // membiarkannya di tab "Sedang Dimasak" berarti
                        // dapur memasak pesanan yang sudah dibatalkan.
                        .where((o) =>
                            o.kitchenStatus == tab.$1 &&
                            !_awaitingPayment(o) &&
                            !o.dibatalkan)
                        .toList();
                if (orders.isEmpty) {
                  return Center(
                    child: Text(tab.$1 == null
                        ? 'Tidak ada pesanan yang menunggu pembayaran.'
                        : 'Tidak ada pesanan "${tab.$2}".'),
                  );
                }
                // Tab Selesai menumpuk tanpa batas — pesanan kemarin,
                // minggu lalu, bulan lalu — dan yang dicari hampir selalu
                // satu hari tertentu. Dua tab lainnya adalah antrean
                // kerja yang harus terbaca sekaligus.
                final done = tab.$1 == KitchenStatus.done;
                return GroupedOrderList(
                  // Kunci yang ikut berganti saat temanya berganti.
                  //
                  // Warna kartunya dibaca sekali saat dibangun. Kalau
                  // subtree-nya bertahan melewati pergantian tema —
                  // dan di layar ini itu memang terjadi, meninggalkan
                  // kartu gelap di halaman terang — warnanya tidak
                  // pernah dihitung ulang. Kunci baru memaksa daftarnya
                  // dibangun dari nol.
                  key: ValueKey(Theme.of(context).brightness),
                  orders: orders,
                  actionsFor: _buildActions,
                  collapsibleDays: done,
                  expandItems: !done,
                );
              }).toList(),
            );
          },
        ),
      ),
    );
  }

  /// Menutup pesanan lewat daftar centang, bukan satu tombol.
  ///
  /// Centang separuh tetap disimpan dan pesanannya bertahan di "Sedang
  /// Dimasak" — dapur yang mengerjakan lima menu sekaligus jarang
  /// menyelesaikan semuanya dalam satu waktu, dan memaksanya sekali klik
  /// hanya akan membuat daftar centangnya diabaikan.
  Future<void> _openChecklist(CustomerOrder order) async {
    final result = await showDialog<Set<int>>(
      context: context,
      builder: (_) => KitchenChecklistDialog(order: order),
    );
    if (result == null) return;

    final allDone = result.length >= order.items.length;
    try {
      await _repo.updateChecklist(
        order.id,
        itemsDone: result,
        status: allDone ? KitchenStatus.done : KitchenStatus.onProgress,
      );
    } catch (e) {
      if (!mounted) return;
      showAppToast(context, 'Gagal menyimpan: $e', isError: true);
    }
  }

  Widget? _buildActions(CustomerOrder order) {
    // Belum dibayar berarti belum boleh dimasak.
    //
    // Sebelumnya tombolnya tetap ada di sini, dengan alasan supaya
    // pelanggan tidak menunggu dua kali. Tapi tombol yang tersedia akan
    // ditekan — dan yang menanggung bahan yang terlanjur terpakai saat
    // pesanannya batal adalah resto, bukan orang yang menekannya.
    // Kalau memang mau dimasak duluan, kasir tinggal menerima
    // pembayarannya lebih dulu.
    if (order.isAwaitingPayment) return const _AwaitingPaymentNote();

    switch (order.kitchenStatus) {
      case KitchenStatus.waiting:
        return SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            icon: const Icon(Icons.soup_kitchen_outlined, size: 18),
            label: const Text('Mulai Masak'),
            onPressed: () =>
                _repo.updateKitchenStatus(order.id, KitchenStatus.onProgress),
          ),
        );
      case KitchenStatus.onProgress:
        final done = order.itemsDone.length;
        final total = order.items.length;
        final partial = done > 0 && done < total;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (partial) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.pending_actions, size: 14, color: Color(0xFF92400E)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Sebagian selesai — $done dari $total menu',
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF92400E),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
            FilledButton.icon(
              icon: const Icon(Icons.checklist_rtl, size: 18),
              label: Text(partial ? 'Lanjutkan Cek Menu' : 'Cek Menu & Selesai'),
              onPressed: () => _openChecklist(order),
            ),
          ],
        );
      case KitchenStatus.done:
      // Yang batal tidak punya tombol apa pun: tidak ada yang perlu
      // dikerjakan dapur, dan barisnya pun sudah disaring keluar dari
      // tab mana pun. Dicantumkan di sini supaya penambahan nilai baru
      // pada KitchenStatus tidak lolos diam-diam.
      case KitchenStatus.cancelled:
        return null;
    }
  }
}

/// Keterangan pengganti tombol untuk pesanan yang belum dibayar.
///
/// Dituliskan, bukan dibiarkan kosong: baris tanpa tombol dan tanpa
/// keterangan terbaca sebagai layar yang rusak, dan yang membacanya
/// sedang berdiri di dapur menunggu pekerjaan.
class _AwaitingPaymentNote extends StatelessWidget {
  const _AwaitingPaymentNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: MerchantPosTheme.tintOf(context, Colors.orange),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.hourglass_empty,
              size: 14, color: MerchantPosTheme.onTintOf(context, Colors.orange)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Menunggu pembayaran — mulai masak setelah kasir menerima '
              'pembayarannya.',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: MerchantPosTheme.onTintOf(context, Colors.orange),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
