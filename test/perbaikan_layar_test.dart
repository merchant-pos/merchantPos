import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:merchant_pos/models/customer_order.dart';

void main() {
  CustomerOrder pesanan(OrderPaymentStatus bayar, KitchenStatus dapur) =>
      CustomerOrder(
        id: 'x',
        createdAt: DateTime(2026, 8, 20),
        items: const [],
        total: 1000,
        paymentStatus: bayar,
        customerLabel: 'Tamu',
        restoId: 'r1',
        kitchenStatus: dapur,
      );

  group('pesanan yang batal', () {
    test('dikenali batal walau status dapurnya masih berjalan', () {
      // Kolom kitchen_status memang berhenti di nilai terakhirnya —
      // riwayat butuh itu — tapi bagi yang memesan artinya sama:
      // makanannya tidak akan datang.
      expect(
          pesanan(OrderPaymentStatus.cancelled, KitchenStatus.onProgress)
              .dibatalkan,
          isTrue);
      expect(
          pesanan(OrderPaymentStatus.expired, KitchenStatus.waiting).dibatalkan,
          isTrue);
    });

    test('yang berjalan tidak ikut terhitung batal', () {
      expect(
          pesanan(OrderPaymentStatus.paid, KitchenStatus.onProgress).dibatalkan,
          isFalse);
      expect(
          pesanan(OrderPaymentStatus.pending, KitchenStatus.waiting).dibatalkan,
          isFalse);
    });

    test('layar pelanggan menyebut Dibatalkan, bukan Sedang Dimasak', () {
      final layar = File('lib/screens/customer_order_status_screen.dart')
          .readAsStringSync();
      expect(layar, contains("order.dibatalkan\n                                ? 'Dibatalkan'"));
    });

    test('keluar dari antrean dapur', () {
      // Membiarkannya di tab "Sedang Dimasak" berarti dapur memasak
      // pesanan yang sudah dibatalkan.
      final chef = File('lib/screens/chef_home_screen.dart').readAsStringSync();
      expect(chef, contains('!o.dibatalkan'));
    });
  });

  group('kolom topping', () {
    final form = File('lib/screens/product_form_screen.dart').readAsStringSync();

    test('harganya berlabel dan Rp-nya selalu terlihat', () {
      // prefixText hanya muncul saat kolomnya disentuh — kotak kosong
      // tanpa label membuat yang mengisinya menebak mana yang mana.
      expect(form, contains("labelText: 'Harga',"));
      expect(form, contains("child: Text(\n                                'Rp',"));
      expect(form, isNot(contains("prefixText: 'Rp ',\n                            border")));
    });

    test('label namanya tidak menghilang saat diisi', () {
      expect(form, contains('floatingLabelBehavior: FloatingLabelBehavior.always'));
    });
  });

  group('yang disembunyikan', () {
    test('tombol tes notifikasi tidak lagi dipasang', () {
      final beranda =
          File('lib/screens/customer_home_screen.dart').readAsStringSync();
      expect(beranda, isNot(contains('const NotificationTestTile()')));
    });

    test('QRIS hilang dari Info Pembayaran dan penyuntingannya', () {
      final info =
          File('lib/screens/payment_info_screen.dart').readAsStringSync();
      final setelan =
          File('lib/screens/settings_screen.dart').readAsStringSync();
      expect(info, isNot(contains("title: 'QRIS',")));
      expect(setelan, isNot(contains("_decoration('ID QRIS Merchant')")));
    });

    test('nilai QRIS lama tetap disimpan, bukan dihapus', () {
      // Kolomnya tidak lagi tampil; datanya tidak ikut hilang.
      final setelan =
          File('lib/screens/settings_screen.dart').readAsStringSync();
      expect(setelan, contains('qrisId: _qrisIdCtrl.text.trim()'));
    });
  });

  group('popup unduhan', () {
    final tombol =
        File('lib/widgets/update_download_button.dart').readAsStringSync();
    final bulir =
        File('lib/widgets/update_download_banner.dart').readAsStringSync();

    test('tidak membuka dirinya saat unduhan dimulai', () {
      // Orang yang baru menekan Unduh sudah tahu unduhannya berjalan.
      expect(tombol, isNot(contains('showUpdateDownloadDialog(context)')));
    });

    test('dibuka lewat bulir kemajuannya', () {
      expect(bulir, contains('onTap: notice != null ? null : () => showUpdateDownloadDialog(context)'));
    });
  });

  group('nomor antrean di struk kasir', () {
    test('diambil dari baris pesanan yang dicerminkan ke server', () {
      final repo = File('lib/db/order_repository.dart').readAsStringSync();
      expect(repo, contains('createReturningNo'));
      expect(repo, contains("(row['order_no'] as num?)?.toInt()"));
    });

    test('ditunggu sebentar, dan kegagalannya tidak menahan kasir', () {
      // Kasir yang menunggu jaringan untuk mencetak struk adalah antrean
      // yang berhenti.
      final cart = File('lib/providers/cart_provider.dart').readAsStringSync();
      expect(cart, contains('.timeout(const Duration(seconds: 4))'));
      expect(cart, contains('.catchError((_) => null)'));
    });

    test('tersimpan juga di penyimpanan lokal', () {
      final db = File('lib/db/database_helper.dart').readAsStringSync();
      // Yang diperiksa migrasinya, bukan nomor versinya. Versi basis
      // data lokal naik tiap kali ada kolom baru untuk hal lain, dan
      // tes yang memakukan angkanya cuma gagal karena fitur yang tidak
      // ada hubungannya.
      expect(db, contains('if (oldVersion < 14)'));
      expect(db, contains('ALTER TABLE transactions ADD COLUMN orderNo INTEGER'));
    });

    test('dibaca dari kedua nama kolom', () {
      // sqflite memakai `orderNo`, Supabase memakai `order_no`.
      final tx = File('lib/models/transaction.dart').readAsStringSync();
      expect(tx, contains("map['orderNo']"));
      expect(tx, contains("map['order_no']"));
    });
  });
}
