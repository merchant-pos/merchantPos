import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merchant_pos/widgets/side_cart_dialog.dart';

/// Popup tidak boleh menutupi panel keranjang.
///
/// Kasir membacakan pesanan sambil pelanggan menyebutkannya, dan
/// keranjang di kanan itu yang sedang dibaca.
void main() {
  Future<void> buka(WidgetTester tester, Size layar) async {
    tester.view.physicalSize = layar;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showDialogBesideCart<void>(
                context: context,
                builder: (_) => const AlertDialog(
                  key: Key('popup'),
                  title: Text('Bakmi Goreng Sapi'),
                  content: SizedBox(height: 200),
                ),
              ),
              child: const Text('buka'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('buka'));
    await tester.pumpAndSettle();
  }

  testWidgets('di tablet lebar, popup berhenti sebelum panel keranjang',
      (tester) async {
    await buka(tester, const Size(1280, 800));

    final kotak = tester.getRect(find.byKey(const Key('popup')));
    const batasKeranjang = 1280 - kSideCartWidth;

    expect(kotak.right, lessThanOrEqualTo(batasKeranjang),
        reason: 'popup masuk ke wilayah keranjang');
    expect(kotak.left, lessThan(batasKeranjang / 2),
        reason: 'popup harus condong ke kiri, bukan tetap di tengah');
  });

  testWidgets('di HP, popup tetap di tengah seperti biasa', (tester) async {
    await buka(tester, const Size(400, 800));

    final kotak = tester.getRect(find.byKey(const Key('popup')));
    const tengahLayar = 200.0;
    final tengahPopup = kotak.center.dx;

    // Tidak ada keranjang berdampingan di HP, jadi tidak ada yang perlu
    // dihindari.
    expect((tengahPopup - tengahLayar).abs(), lessThan(2));
  });

  testWidgets('popupnya tetap cukup lebar untuk dibaca', (tester) async {
    await buka(tester, const Size(1280, 800));
    final kotak = tester.getRect(find.byKey(const Key('popup')));
    expect(kotak.width, greaterThan(300));
  });

  group('panel keranjang di layar lebar', () {
    final kasir = File('lib/screens/pos_home_screen.dart').readAsStringSync();
    final pelanggan =
        File('lib/screens/customer_home_screen.dart').readAsStringSync();
    final keranjang =
        File('lib/screens/customer_cart_screen.dart').readAsStringSync();

    test('keduanya memakai lebar panel yang sama', () {
      // Dua angka terpisah akan berpisah, dan yang terlihat adalah
      // popup yang menutupi keranjang sedikit — persis cukup untuk
      // menyembunyikan baris terakhirnya.
      expect(kasir, contains('width: kSideCartWidth,'));
      expect(pelanggan, contains('width: kSideCartWidth,'));
      expect(kasir, isNot(contains('width: 360,')));
    });

    test('popup keduanya menghindari panelnya', () {
      expect(kasir, contains('showDialogBesideCart<QuantityDialogResult>('));
      expect(pelanggan, contains('showDialogBesideCart<QuantityDialogResult>('));
      expect(kasir, isNot(contains('showDialog<QuantityDialogResult>(')));
      expect(pelanggan, isNot(contains('showDialog<QuantityDialogResult>(')));
    });

    test('panel pelanggan memakai halaman keranjang yang sama', () {
      // Menyalinnya berarti dua tempat yang harus diingat berbarengan
      // tiap kali aturan pembayarannya berubah, dan yang kedua selalu
      // ketinggalan.
      expect(pelanggan, contains('CustomerCartScreen(embedded: true)'));
      expect(keranjang, contains('if (widget.embedded) return isi;'));
    });

    test('yang ditanam tidak membawa Scaffold sendiri', () {
      // Scaffold di dalam Scaffold membawa AppBar kedua dan latar yang
      // menimpa panelnya.
      final blok = keranjang.substring(keranjang.indexOf('if (widget.embedded)'));
      expect(blok.indexOf('return isi;'), lessThan(blok.indexOf('Scaffold(')));
    });

    test('bar bawah menghilang saat panelnya tampil', () {
      // Bar yang menawarkan jalan ke tempat yang sedang terbuka.
      expect(pelanggan, contains('bottomNavigationBar: Breakpoints.isWide(context)'));
      expect(kasir, contains('bottomNavigationBar: Breakpoints.isWide(context)'));
    });
  });
}
