import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Notifikasi yang diketuk harus membuka halaman yang dimaksudnya.
///
/// Ketukan adalah pernyataan niat: orangnya ingin melihat hal itu,
/// sekarang. Membuangnya ke halaman terakhir berarti dia harus
/// mengingat sendiri apa yang barusan dikabarkan.
void main() {
  final router =
      File('lib/services/notification_router.dart').readAsStringSync();
  final push = File('lib/services/push_service.dart').readAsStringSync();
  final notif =
      File('lib/services/notification_service.dart').readAsStringSync();
  final main_ = File('lib/main.dart').readAsStringSync();

  group('tujuan tiap kejadian', () {
    const tujuan = {
      'announcement': 'InboxScreen',
      'petty_pending': 'FinanceBalanceScreen',
      'petty_reviewed': 'FinanceBalanceScreen',
      'deposit_pending': 'CashDepositScreen',
      'deposit_reviewed': 'CashDepositScreen',
      'pending_payment': 'PendingPaymentScreen',
      'order_new': 'EmployeeOrdersScreen',
      'order_cooking': 'EmployeeOrdersScreen',
      'order_ready': 'CustomerOrderStatusScreen',
    };

    for (final e in tujuan.entries) {
      test('${e.key} → ${e.value}', () {
        expect(router, contains("case '${e.key}':"), reason: e.key);
        expect(router, contains(e.value), reason: e.value);
      });
    }

    test('kejadian tak dikenal tidak melempar orangnya ke mana-mana', () {
      // Nama kejadian bisa berubah di server sebelum aplikasinya
      // diperbarui.
      expect(router, contains('default:\n        return null;'));
    });

    test('kotak masuknya mengikuti siapa yang membukanya', () {
      expect(router, contains('auth.isEmployee ? const InboxScreen()'));
    });

    test('pesanan siap menyasar pelanggan, bukan pegawai', () {
      final blok = router.substring(router.indexOf("case 'order_ready':"));
      expect(blok.substring(0, 250), contains('CustomerOrderStatusScreen'));
    });
  });

  group('dari mana ketukannya datang', () {
    test('saat aplikasi di latar belakang', () {
      expect(push, contains('FirebaseMessaging.onMessageOpenedApp.listen(_onTap)'));
    });

    test('saat aplikasi sedang tertutup sama sekali', () {
      // Yang paling sering diketuk dari layar kunci justru yang paling
      // mendesak.
      expect(push, contains('getInitialMessage()'));
    });

    test('yang dari layar kunci ditunda satu frame', () {
      // Navigator-nya belum terpasang saat itu; mendorong halaman ke
      // navigator yang belum ada hanya menghilangkan niat orangnya.
      expect(push, contains('addPostFrameCallback((_) => _onTap(awal))'));
    });

    test('saat aplikasi sedang dibuka', () {
      // Notifikasi yang ditampilkan sendiri oleh aplikasi membawa nama
      // kejadiannya di payload.
      expect(push, contains('event: event,'));
      expect(notif, contains("'event:\$event\${restoId == null ? '' : '?resto_id=\$restoId'}'"));
    });
  });

  group('satu payload, dua kegunaan', () {
    test('dibedakan awalannya, bukan ditebak dari bentuknya', () {
      // Kolom yang sama dipakai pemasang APK, yang isinya jalur berkas.
      expect(main_, contains("payload.startsWith('event:')"));
      expect(main_, contains("final isi = payload.substring(6);"));
      expect(main_, contains('NotificationRouter.buka(isi)'));
    });

    test('pemasang APK tetap jalan', () {
      expect(main_, contains('OpenFilex.open(payload'));
    });
  });

  test('navigator-nya terpasang di aplikasinya', () {
    // Notifikasi tiba di luar pohon widget — tanpa kunci ini tidak ada
    // context yang bisa dipakai bernavigasi.
    expect(main_, contains('navigatorKey: navigatorKey,'));
    expect(router, contains('final navigatorKey = GlobalKey<NavigatorState>()'));
  });
}
