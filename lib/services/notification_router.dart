import '../screens/merchant_review_form.dart';
import '../screens/support_chat_screen.dart';
import '../db/restaurant_repository.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../screens/cash_deposit_screen.dart';
import '../screens/customer_inbox_screen.dart';
import '../screens/customer_order_status_screen.dart';
import '../screens/employee_orders_screen.dart';
import '../screens/finance_balance_screen.dart';
import '../screens/inbox_screen.dart';
import '../screens/pending_payment_screen.dart';

/// Kunci navigator aplikasi.
///
/// Notifikasi tiba di luar pohon widget — tidak ada `context` yang bisa
/// dipakai dari sana. Tanpa kunci ini, satu-satunya yang bisa dilakukan
/// saat notifikasi diketuk adalah membuka aplikasi di halaman mana pun
/// yang kebetulan terakhir dibuka, dan orangnya harus mencari sendiri
/// apa yang tadi dikabarkan.
final navigatorKey = GlobalKey<NavigatorState>();

/// Membuka halaman yang dimaksud sebuah notifikasi.
///
/// Ketukan pada notifikasi adalah pernyataan niat: orangnya ingin
/// melihat hal itu, sekarang. Membuang niat itu ke beranda berarti dia
/// harus mengingat sendiri apa yang barusan dikabarkan lalu mencarinya
/// lewat tiga ketukan lagi — dan yang paling sering hilang di jalan
/// justru yang paling mendesak: permintaan top up yang menunggu
/// persetujuan.
class NotificationRouter {
  const NotificationRouter._();

  /// Membuka halaman untuk sebuah kejadian push.
  ///
  /// Kejadian yang tidak dikenal sengaja tidak melakukan apa-apa.
  /// Aplikasinya tetap terbuka seperti biasa — itu lebih baik daripada
  /// melempar orangnya ke halaman yang salah karena nama kejadiannya
  /// berubah di server dan aplikasinya belum diperbarui.
  static Future<void> buka(String? event, {Map<String, dynamic>? data}) async {
    final nav = navigatorKey.currentState;
    if (nav == null || event == null) return;

    final context = nav.context;
    final auth = context.read<AuthProvider>();

    // Ajakan menilai butuh merchant-nya, dan merchant-nya harus dibaca
    // dulu — jadi ia ditangani terpisah dari tabel tujuan yang serba
    // langsung di bawah.
    if (event == 'review_prompt') {
      final restoId = data?['resto_id'] as String?;
      if (restoId == null) return;
      final m = await RestaurantRepository().getOnce(restoId);
      if (m == null) return;
      nav.push(MaterialPageRoute(
        builder: (_) => MerchantReviewForm(merchant: m),
      ));
      return;
    }

    // Percakapan support butuh id tiketnya, dan sisi mana yang membuka
    // menentukan apa yang boleh ditekan di sana — jadi ia juga
    // ditangani terpisah dari tabel tujuan yang serba langsung.
    if (event == 'support_message') {
      final ticketId = data?['ticket_id'] as String?;
      if (ticketId == null) return;
      nav.push(MaterialPageRoute(
        builder: (_) => SupportChatScreen(
          ticketId: ticketId,
          sebagaiAdmin: auth.isSuperAdmin,
          namaSaya: auth.employeeName,
        ),
      ));
      return;
    }

    final tujuan = _tujuanUntuk(event, auth);
    if (tujuan == null) return;

    nav.push(MaterialPageRoute(builder: (_) => tujuan));
  }

  static Widget? _tujuanUntuk(String event, AuthProvider auth) {
    switch (event) {
      // Kabar versi baru dan pengumuman resto sama-sama mendarat di
      // kotak masuk — yang berbeda hanya kotak masuk siapa.
      case 'announcement':
        return auth.isEmployee ? const InboxScreen() : const InboxTujuanPelanggan();

      // Top up petty cash: yang dikabari Owner dan Finance, dan yang
      // mereka butuhkan halaman persetujuannya — bukan berandanya.
      case 'petty_pending':
      case 'petty_reviewed':
        return const FinanceBalanceScreen();

      // Setoran tunai, alurnya sama: menunggu diperiksa.
      case 'deposit_pending':
      case 'deposit_reviewed':
        return const CashDepositScreen();

      // Pesanan dari HP pelanggan yang memilih bayar di kasir.
      case 'pending_payment':
        return const PendingPaymentScreen();

      // Pesanan baru dan yang berpindah status: daftar pesanan
      // pegawainya.
      case 'order_new':
      case 'order_cooking':
        return const EmployeeOrdersScreen();

      // "Pesanan kamu siap" — ini satu-satunya yang menyasar pelanggan.
      case 'order_ready':
        return auth.isEmployee
            ? const EmployeeOrdersScreen()
            : const CustomerOrderStatusScreen();

      default:
        return null;
    }
  }
}

/// Kotak masuk pelanggan.
///
/// Dibungkus supaya berkas ini tidak perlu tahu bagaimana layar itu
/// dibangun — namanya saja yang dipakai di tabel tujuan di atas.
class InboxTujuanPelanggan extends StatelessWidget {
  const InboxTujuanPelanggan({super.key});

  @override
  Widget build(BuildContext context) => const CustomerInboxScreen();
}
