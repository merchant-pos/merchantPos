import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merchant_pos/models/product.dart';
import 'package:merchant_pos/theme.dart';
import 'package:merchant_pos/widgets/product_category_list.dart';

/// Melipat kategori lalu membukanya lagi harus mengembalikan menunya.
///
/// `PageStorageKey` di ExpansionTile dipakai bersama oleh dua penghuni
/// yang tidak saling tahu: keadaan buka/tutup disimpan sebagai bool,
/// posisi gulir GridView di dalamnya sebagai double — di ember yang
/// sama. Grid membaca bool itu sebagai double, melempar, dan
/// menyisakan blok kosong di tempat menunya.
void main() {
  List<Product> menu() => [
        for (var i = 0; i < 4; i++)
          Product(
            id: 'p$i',
            name: 'Menu $i',
            category: i < 2 ? 'Makanan' : 'Minuman',
            price: 25000,
            stock: 10,
          ),
      ];

  Future<void> pasang(WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: MerchantPosTheme.dark(),
      home: Scaffold(
        body: ProductCategoryList(
          products: menu(),
          quantityOf: (_) => 0,
          ppnPercent: 11,
          onTapProduct: (_) {},
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('buka → lipat → buka lagi mengembalikan menunya',
      (tester) async {
    await pasang(tester);
    expect(find.text('Menu 0'), findsOneWidget);

    await tester.tap(find.text('Makanan'));
    await tester.pumpAndSettle();
    expect(find.text('Menu 0'), findsNothing);

    await tester.tap(find.text('Makanan'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull,
        reason: 'inilah yang dulu melempar bool-sebagai-double');
    expect(find.text('Menu 0'), findsOneWidget,
        reason: 'menunya harus kembali, bukan blok kosong');
  });

  testWidgets('kategori lain tidak ikut terpengaruh', (tester) async {
    await pasang(tester);
    await tester.tap(find.text('Makanan'));
    await tester.pumpAndSettle();
    expect(find.text('Menu 2'), findsOneWidget,
        reason: 'Minuman tetap terbuka');
  });

  testWidgets('yang dilipat tetap terlipat, tidak membuka sendiri',
      (tester) async {
    await pasang(tester);
    await tester.tap(find.text('Makanan'));
    await tester.pumpAndSettle();
    // Rebuild dipicu dengan mengetuk kategori lain.
    await tester.tap(find.text('Minuman'));
    await tester.pumpAndSettle();
    expect(find.text('Menu 0'), findsNothing);
  });

  group('sumbernya', () {
    final berkas =
        File('lib/widgets/product_category_list.dart').readAsStringSync();

    test('tidak memakai PageStorageKey', () {
      // Namanya masih disebut di komentar, sebagai catatan kenapa cara
      // itu ditinggalkan. Yang tidak boleh kembali pemakaiannya.
      expect(berkas, isNot(contains('key: PageStorageKey')));
      expect(berkas, contains('key: ValueKey<String>(category),'));
    });

    test('keadaannya dipegang widgetnya sendiri', () {
      // Selamat dari daur ulang ListView — alasan kunci itu dipasang
      // sejak awal — tanpa menumpang ember PageStorage.
      expect(berkas, contains('final Set<String> _terlipat'));
      expect(berkas, contains('mencari || !_terlipat.contains(category)'));
      expect(berkas, contains('onExpansionChanged:'));
    });
  });
}
