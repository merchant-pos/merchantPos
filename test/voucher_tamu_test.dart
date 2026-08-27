import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Voucher menempel pada akun, bukan pada perangkat.
///
/// Tamu yang belum masuk tidak punya tempat menyimpannya — menawarkan
/// voucher kepadanya cuma menjanjikan daftar yang selalu kosong, dan
/// yang menekannya akan mengira vouchernya hilang.
void main() {
  final beranda =
      File('lib/screens/customer_home_screen.dart').readAsStringSync();
  final keranjang =
      File('lib/screens/customer_cart_screen.dart').readAsStringSync();
  final voucherSaya =
      File('lib/screens/my_vouchers_screen.dart').readAsStringSync();

  group('menu Voucher Saya', () {
    test('hanya ada di hub, dan hub hanya untuk yang sudah masuk', () {
      // Tamu tidak pernah sampai ke _hubView: cabangnya menuntut
      // loggedInAsCustomer.
      expect(beranda, contains('MyVouchersScreen()'));
      expect(
          beranda,
          contains('if (!session.hasActiveResto && loggedInAsCustomer && '
              '!_showChooser) {'));

      final hub = beranda.substring(beranda.indexOf('Widget _hubView'));
      expect(hub.indexOf('MyVouchersScreen()'), greaterThan(0),
          reason: 'menunya harus berada di dalam _hubView');
    });

    test('layar tamu tidak menawarkannya', () {
      // Yang ada di layar tamu cuma Scan QR, Pilih Resto, dan riwayat.
      final tamu = beranda.substring(
          beranda.indexOf("title: Text(loggedInAsCustomer ? 'Mau Pesan Di Mana?'"),
          beranda.indexOf('// Sesudah titik ini restonya sudah pasti'));
      expect(tamu, isNot(contains('MyVouchersScreen')));
    });
  });

  group('Pakai Voucher di keranjang', () {
    test('disembunyikan dari tamu', () {
      expect(keranjang, contains('if (_bisaPakaiVoucher) ...['));
      expect(keranjang,
          contains('return auth.isLoggedIn && !auth.isEmployee;'));
    });

    test('barisnya benar-benar di dalam penjagaannya', () {
      final i = keranjang.indexOf('if (_bisaPakaiVoucher) ...[');
      final j = keranjang.indexOf('_BarisVoucher(');
      expect(i, lessThan(j));
      expect(j - i, lessThan(400), reason: 'harus baris berikutnya, bukan jauh');
    });

    test('nilai vouchernya tetap nol saat tidak dipakai', () {
      // Tanpa baris ini, tamu tetap tidak bisa memasang voucher — tapi
      // yang dikirim ke server harus jelas kosong, bukan sisa keadaan.
      expect(keranjang, contains('voucherClaimId: _voucher?.id,'));
      expect(keranjang, contains('voucherAmount: _voucher?.amount ?? 0,'));
    });
  });

  group('kalau tamu tetap sampai ke layar voucher', () {
    test('layarnya sendiri menolak dengan ajakan masuk', () {
      // Pertahanan berlapis: server juga menolak menebus tanpa email.
      expect(voucherSaya.toLowerCase(), contains('masuk'));
    });
  });
}
