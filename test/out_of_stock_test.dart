import 'package:flutter_test/flutter_test.dart';
import 'package:merchant_pos/models/product.dart';

Product _p({int stock = 0, bool outOfStock = false}) => Product(
      id: 'p1',
      name: 'Nasi Goreng',
      category: 'Makanan',
      price: 25000,
      stock: stock,
      outOfStock: outOfStock,
    );

void main() {
  group('ketersediaan produk', () {
    test('stok 0 tidak lagi berarti habis', () {
      // Ini inti perubahannya. Resto yang tidak menghitung porsi
      // membiarkan stoknya 0, dan dulu itu menyembunyikan seluruh
      // menunya tanpa ada yang tahu kenapa.
      expect(_p(stock: 0).available, isTrue);
    });

    test('yang menentukan cuma penanda habis', () {
      expect(_p(stock: 100, outOfStock: true).available, isFalse);
      expect(_p(stock: 0, outOfStock: false).available, isTrue);
    });

    test('produk lama tanpa kolomnya dianggap tersedia', () {
      final lama = Product.fromMap({
        'id': 'p1',
        'name': 'Nasi Goreng',
        'category': 'Makanan',
        'price': 25000,
      });

      expect(lama.stock, 0);
      expect(lama.outOfStock, isFalse);
      expect(lama.available, isTrue);
    });

    test('penandanya ikut tersimpan dan terbaca kembali', () {
      final ulang = Product.fromMap({
        ..._p(outOfStock: true).toMap(),
        'price': 25000,
      });

      expect(ulang.outOfStock, isTrue);
      expect(ulang.available, isFalse);
    });

    test('copyWith bisa membalik penandanya tanpa menyentuh yang lain', () {
      final habis = _p(stock: 7).copyWith(outOfStock: true);

      expect(habis.outOfStock, isTrue);
      expect(habis.stock, 7);
      expect(habis.name, 'Nasi Goreng');
      expect(habis.copyWith(outOfStock: false).available, isTrue);
    });
  });
}
