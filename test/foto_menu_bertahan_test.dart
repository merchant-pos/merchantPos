import 'package:flutter_test/flutter_test.dart';
import 'package:merchant_pos/models/product.dart';
import 'package:merchant_pos/utils/foto_menu_bertahan.dart';

Product menu(String id, {String? foto}) =>
    Product(id: id, name: id, category: 'Makanan', price: 1000, photoBase64: foto);

void main() {
  group('foto menu bertahan dari pembaruan stok', () {
    test('yang belum pernah berfoto tidak dicurigai', () {
      final ingatan = IngatanFotoMenu();
      ingatan.catat([menu('a')]);
      expect(ingatan.curiga([menu('a')]), isEmpty);
    });

    // Inilah kejadiannya: menu yang barusan dipesan stoknya berkurang,
    // barisnya terkirim ulang lewat realtime tanpa foto, dan fotonya
    // hilang dari layar pemesan.
    test('yang tadinya berfoto lalu datang tanpa foto dicurigai', () {
      final ingatan = IngatanFotoMenu();
      ingatan.catat([menu('a', foto: 'abc')]);
      expect(ingatan.curiga([menu('a')]), ['a']);
    });

    test('yang tetap berfoto tidak dicurigai', () {
      final ingatan = IngatanFotoMenu();
      ingatan.catat([menu('a', foto: 'abc')]);
      expect(ingatan.curiga([menu('a', foto: 'abc')]), isEmpty);
    });

    test('foto lama dipasang sementara sambil menunggu jawaban server', () {
      final ingatan = IngatanFotoMenu();
      ingatan.catat([menu('a', foto: 'abc')]);
      final pulih = ingatan.pulihkan([menu('a')], ['a']);
      expect(pulih.single.photoBase64, 'abc');
    });

    test('menu lain tidak ikut disentuh', () {
      final ingatan = IngatanFotoMenu();
      ingatan.catat([menu('a', foto: 'abc'), menu('b', foto: 'xyz')]);
      final pulih = ingatan.pulihkan([menu('a'), menu('b')], ['a']);
      expect(pulih[0].photoBase64, 'abc');
      expect(pulih[1].photoBase64, isNull);
    });

    // Merchant berhak menghapus foto menunya. Menolak mengakuinya sama
    // salahnya dengan menghilangkan fotonya sendiri.
    test('penghapusan yang dipastikan server benar-benar dilupakan', () {
      final ingatan = IngatanFotoMenu();
      ingatan.catat([menu('a', foto: 'abc')]);
      ingatan.lupakan('a');
      expect(ingatan.punya('a'), isFalse);
      expect(ingatan.curiga([menu('a')]), isEmpty);
    });

    test('foto yang berganti dicatat yang terbaru', () {
      final ingatan = IngatanFotoMenu();
      ingatan.catat([menu('a', foto: 'lama')]);
      ingatan.catat([menu('a', foto: 'baru')]);
      expect(ingatan.pulihkan([menu('a')], ['a']).single.photoBase64, 'baru');
    });

    test('foto kosong tidak dianggap foto', () {
      final ingatan = IngatanFotoMenu();
      ingatan.catat([menu('a', foto: '')]);
      expect(ingatan.punya('a'), isFalse);
    });
  });
}
