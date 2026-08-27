import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/table_session_provider.dart';
import '../services/notification_service.dart';
import '../services/fund_request_notifier.dart';
import '../services/order_notifier.dart';
import '../services/push_service.dart';

/// Menyalakan notifikasi pesanan sesuai siapa yang sedang memakai
/// aplikasi, dan mematikannya begitu perannya berubah.
///
/// Ditaruh membungkus seluruh isi aplikasi, bukan di layar tertentu,
/// karena kabar pesanan harus tetap sampai walaupun orangnya sedang
/// membuka layar lain — kasir yang sedang mengetik pesanan berikutnya
/// tetap perlu tahu pesanan sebelumnya sudah siap.
class OrderNotificationBinder extends StatefulWidget {
  final Widget child;

  const OrderNotificationBinder({super.key, required this.child});

  @override
  State<OrderNotificationBinder> createState() => _OrderNotificationBinderState();
}

class _OrderNotificationBinderState extends State<OrderNotificationBinder> {
  OrderNotifier? _notifier;
  FundRequestNotifier? _fundNotifier;

  /// Penanda terpisah untuk kabar setoran/petty cash. Yang menentukannya
  /// cuma "resto mana, email siapa", jadi berganti layar atau berganti
  /// meja tidak boleh ikut membangun ulang aliran ini.
  String? _activeFundKey;

  /// Penanda konfigurasi yang sedang berjalan. Dibandingkan setiap
  /// rebuild supaya stream-nya tidak dibangun ulang terus-menerus —
  /// hanya saat yang menonton benar-benar berganti.
  String? _activeKey;

  bool _askedPermission = false;

  @override
  void dispose() {
    _notifier?.stop();
    _fundNotifier?.stop();
    super.dispose();
  }

  /// Menerjemahkan keadaan login dan sesi meja jadi "siapa yang
  /// mendengarkan apa", atau null kalau memang tidak ada yang perlu
  /// diberitahu (belum login dan belum memilih resto).
  OrderNotifier? _buildNotifier(AuthProvider auth, TableSessionProvider session) {
    if (auth.isChef && auth.restoId != null) {
      return OrderNotifier(role: OrderWatchRole.chef, restoId: auth.restoId!);
    }
    if ((auth.isKasir || auth.isAdmin) && auth.restoId != null) {
      return OrderNotifier(
        role: OrderWatchRole.cashier,
        restoId: auth.restoId!,
        cashierEmail: auth.user?.email,
      );
    }
    // Customer — baik yang login maupun tamu — dikenali dari resto yang
    // sedang dia buka. Tanpa sesi resto tidak ada yang bisa diikuti.
    if (!auth.isEmployee && session.hasActiveResto && session.restoId != null) {
      return OrderNotifier(
        role: OrderWatchRole.customer,
        restoId: session.restoId!,
        customerEmail: auth.isLoggedIn ? auth.user?.email : null,
        sessionId: session.sessionId,
      );
    }
    return null;
  }

  /// Menyalakan kabar hasil pengajuan untuk yang mengajukan — kasir dan
  /// admin. Finance dan Owner tidak ikut: merekalah yang memutuskan, dan
  /// diberi tahu soal keputusannya sendiri hanya jadi gema.
  void _syncFundNotifier(AuthProvider auth) {
    final email = auth.user?.email;
    final eligible =
        (auth.isKasir || auth.isAdmin) && auth.restoId != null && email != null;
    final nextKey = eligible ? '${auth.restoId}|$email' : null;
    if (nextKey == _activeFundKey) return;

    _activeFundKey = nextKey;
    _fundNotifier?.stop();
    _fundNotifier = nextKey == null
        ? null
        : FundRequestNotifier(restoId: auth.restoId!, employeeEmail: email!);
    _fundNotifier?.start();
  }

  /// Mendaftarkan perangkat ini ke server supaya tetap bisa dikabari
  /// walau aplikasinya ditutup.
  ///
  /// Ditaruh di sini, bukan di layar login, karena pemiliknya bisa
  /// berganti tanpa login ulang: pelanggan tamu berpindah resto, owner
  /// menukar cabang. Yang dicatat harus selalu keadaan sekarang, bukan
  /// keadaan saat terakhir kali seseorang mengetuk tombol masuk.
  void _syncPushToken(AuthProvider auth, TableSessionProvider session) {
    // Karyawan didaftarkan walau belum punya resto.
    //
    // Syarat `restoId != null` dulu ada di sini, dan akibatnya Super
    // Admin tidak pernah mendaftar sama sekali — ia memang tidak
    // terikat resto mana pun. Pengumuman versi baru masuk ke kotak
    // masuknya, tapi notifikasinya tidak pernah sampai, karena
    // perangkatnya tidak dikenal server.
    //
    // Owner yang belum memilih cabang kena hal yang sama.
    //
    // Baris tanpa resto tidak ikut terjaring pengumuman milik sebuah
    // resto — penyaringnya memang `resto_id`, dan itu benar: Super
    // Admin tidak perlu menerima promo tiap resto.
    if (auth.isEmployee) {
      PushService.instance.register(
        email: auth.user?.email,
        restoId: auth.restoId,
        role: auth.role?.dbValue,
      );
      return;
    }

    // Pelanggan yang sudah masuk didaftarkan walau belum membuka resto
    // mana pun.
    //
    // Voucher dan kabar versi baru menyasar emailnya, bukan restonya —
    // dan sebelum ini, pelanggan yang cuma membuka aplikasinya tanpa
    // masuk ke menu resto tidak punya baris token sama sekali. Yang
    // paling dirugikan justru yang ditunggu kabarnya: pemberitahuan
    // voucher baru.
    if (auth.isLoggedIn) {
      PushService.instance.register(
        email: auth.user?.email,
        restoId: session.hasActiveResto ? session.restoId : null,
        role: 'customer',
        sessionId: session.hasActiveResto ? session.sessionId : null,
      );
      return;
    }

    // Tamu hanya dikenal lewat sesi mejanya. Tanpa resto aktif, tidak
    // ada satu pun penanda yang bisa dipakai memanggilnya kembali.
    if (session.hasActiveResto && session.restoId != null) {
      PushService.instance.register(
        restoId: session.restoId,
        role: 'customer',
        sessionId: session.sessionId,
      );
    }
  }

  String? _keyFor(OrderNotifier? n) => n == null
      ? null
      : '${n.role}|${n.restoId}|${n.customerEmail}|${n.sessionId}|${n.cashierEmail}';

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final session = context.watch<TableSessionProvider>();

    final next = _buildNotifier(auth, session);
    final nextKey = _keyFor(next);

    if (nextKey != _activeKey) {
      _activeKey = nextKey;
      _notifier?.stop();
      _notifier = next;

      if (next != null) {
        // Izinnya diminta sekali, saat pertama kali benar-benar ada yang
        // perlu diberitahu — bukan saat aplikasi dibuka, di mana orang
        // belum punya alasan untuk mengizinkannya.
        if (!_askedPermission) {
          _askedPermission = true;
          NotificationService.instance.requestPermission();
        }
        next.start();
      }
    }

    _syncFundNotifier(auth);
    _syncPushToken(auth, session);

    return widget.child;
  }
}
