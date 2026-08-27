import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Halaman checkout harus tetap utuh di layar yang pendek.
///
/// Blok rincian di bawahnya — jenis pesanan, nomor meja, nama, tagihan,
/// voucher, cara bayar — lebih tinggi daripada layar tablet melintang.
void main() {
  const tinggiRincian = 900.0;

  Widget polaLama() => MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              Expanded(
                child: ListView(
                  children: [
                    for (var i = 0; i < 3; i++)
                      SizedBox(height: 80, key: Key('item$i')),
                  ],
                ),
              ),
              const SizedBox(
                height: tinggiRincian,
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: SizedBox(height: 48, key: Key('tombol')),
                ),
              ),
            ],
          ),
        ),
      );

  Widget polaBaru() => MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              for (var i = 0; i < 3; i++)
                SizedBox(height: 80, key: Key('item$i')),
              const SizedBox(
                height: tinggiRincian,
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: SizedBox(height: 48, key: Key('tombol')),
                ),
              ),
            ],
          ),
        ),
      );

  Future<void> pasang(WidgetTester tester, Widget w) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(w);
  }

  testWidgets('pola lama: daftar item terperas dan tombolnya terpotong',
      (tester) async {
    await pasang(tester, polaLama());

    // Inilah yang terlihat di tablet: bagian bawahnya melimpah keluar
    // layar, dan tombol bayarnya ikut terpotong di sana.
    expect(tester.takeException().toString(), contains('overflowed'));

    // Dan daftar itemnya tidak dibangun sama sekali: ruangnya nol,
    // jadi tidak ada satu baris pun yang pernah muncul di layar.
    expect(find.byKey(const Key('item0')), findsNothing);
  });

  testWidgets('pola baru: itemnya utuh dan tombolnya bisa dicapai',
      (tester) async {
    await pasang(tester, polaBaru());

    expect(tester.getSize(find.byKey(const Key('item0'))).height, 80);

    // Tidak terlihat sejak awal — memang harus digulir, dan sekarang
    // bisa.
    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pumpAndSettle();

    final tombol = tester.getRect(find.byKey(const Key('tombol')));
    expect(tombol.bottom, lessThanOrEqualTo(800));
    expect(tester.takeException(), isNull);
  });

  group('sumbernya', () {
    test('kedua halaman checkout memakai satu gulungan', () {
      // Kasir, Admin, dan Owner lewat CheckoutScreen; Pelanggan lewat
      // CustomerCartScreen. Keduanya harus diperbaiki, bukan salah
      // satunya.
      for (final f in [
        'lib/screens/checkout_screen.dart',
        'lib/screens/customer_cart_screen.dart',
      ]) {
        final isi = File(f).readAsStringSync();
        expect(isi, contains('for (final item in cart.items)'), reason: f);
        expect(isi, isNot(contains('Expanded(\n                child: ListView.builder(')),
            reason: f);
      }
    });
  });
}
