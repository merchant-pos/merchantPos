import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Banner promo tidak boleh mengambil alih halaman menu.
///
/// Di tablet, 16:9 selebar layar berarti banner ratusan piksel
/// tingginya — menunya sendiri terdorong keluar layar sebelum sempat
/// terlihat.
void main() {
  const maxLebar = 560.0;

  Widget kotak(double rasio) => MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: maxLebar),
                  child: AspectRatio(
                    aspectRatio: rasio,
                    child: Container(key: const Key('banner'), color: Colors.blue),
                  ),
                ),
              ),
            ],
          ),
        ),
      );

  Future<Size> ukur(WidgetTester tester, Size layar, double rasio) async {
    tester.view.physicalSize = layar;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(kotak(rasio));
    return tester.getSize(find.byKey(const Key('banner')));
  }

  testWidgets('di tablet, tingginya berhenti jauh di bawah setengah layar',
      (tester) async {
    final s = await ukur(tester, const Size(1280, 800), 16 / 9);
    expect(s.width, maxLebar);
    expect(s.height, lessThan(800 * 0.45),
        reason: 'banner memakan terlalu banyak tinggi layar');
  });

  testWidgets('di HP, batas lebarnya tidak berpengaruh', (tester) async {
    final s = await ukur(tester, const Size(400, 800), 16 / 9);
    expect(s.width, 400, reason: 'di HP banner tetap selebar layar');
  });

  testWidgets('banner jangkung tetap tidak menghabiskan layar',
      (tester) async {
    // Rasio terkecil yang diizinkan sesudah dijepit.
    final s = await ukur(tester, const Size(400, 800), 1.6);
    expect(s.height, lessThan(800 * 0.45));
  });

  group('tidak ada pita di tepi gambarnya', () {
    // Pita itu latar kabur yang menyembul: kotaknya lebih tinggi
    // daripada gambarnya, dan yang mengisi sisanya jadi berbeda warna.
    Widget susunan({required bool paddingDiDalam}) {
      const rasio = 1200 / 628;
      final halaman = Container(key: const Key('gambar'), color: Colors.red);
      return MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              if (paddingDiDalam)
                AspectRatio(
                  aspectRatio: rasio,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: halaman,
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: AspectRatio(aspectRatio: rasio, child: halaman),
                ),
            ],
          ),
        ),
      );
    }

    Future<void> pasang(WidgetTester tester, Widget w) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(w);
    }

    testWidgets('padding di dalam rasio menyisakan pita', (tester) async {
      await pasang(tester, susunan(paddingDiDalam: true));
      final g = tester.getSize(find.byKey(const Key('gambar')));
      // Lebarnya menyusut 28 tapi tingginya tetap — bentuknya jadi
      // lebih jangkung daripada gambarnya, dan selisihnya jadi pita.
      expect(g.width, 400 - 28);
      expect(g.width / g.height, lessThan(1200 / 628));
    });

    testWidgets('padding di luar rasio membuatnya pas', (tester) async {
      await pasang(tester, susunan(paddingDiDalam: false));
      final g = tester.getSize(find.byKey(const Key('gambar')));
      expect(g.width, 400 - 28);
      expect(g.width / g.height, closeTo(1200 / 628, 0.001),
          reason: 'kotaknya harus sebentuk gambarnya');
    });

    test('yang dipakai versi yang di luar', () {
      final berkas =
          File('lib/widgets/promo_banner_carousel.dart').readAsStringSync();
      final i = berkas.indexOf("padding: const EdgeInsets.symmetric(horizontal: 14)");
      final j = berkas.indexOf('aspectRatio: _rasio');
      expect(i, lessThan(j), reason: 'paddingnya harus membungkus rasionya');
      // Dan tidak ada lagi padding per halaman di dalam PageView.
      final blokHalaman = berkas.substring(berkas.indexOf('itemBuilder:'));
      expect(blokHalaman.substring(0, 300),
          isNot(contains('EdgeInsets.symmetric(horizontal: 14)')));
    });
  });

  group('kategori menu', () {
    final daftar =
        File('lib/widgets/product_category_list.dart').readAsStringSync();

    test('terbuka sejak awal', () {
      // Menu yang bersembunyi di balik judul kategori adalah menu yang
      // tidak ditemukan — dan halaman berisi tiga baris judul terbaca
      // seperti resto yang belum mengisi menunya.
      // Bawaannya terbuka: yang belum pernah dilipat orangnya tidak ada
      // di daftar `_terlipat`.
      expect(daftar,
          contains('mencari || !_terlipat.contains(category)'));
      expect(daftar, isNot(contains('initiallyExpanded: false,')));
    });

    test('masih bisa dilipat', () {
      // Yang sudah tahu isinya boleh merapikan layarnya sendiri.
      expect(daftar, contains('ExpansionTile('));
    });

    test('berlaku untuk kasir maupun pelanggan', () {
      for (final f in [
        'lib/screens/pos_home_screen.dart',
        'lib/screens/customer_home_screen.dart',
      ]) {
        expect(File(f).readAsStringSync(), contains('ProductCategoryList('),
            reason: f);
      }
    });

    test('admin dan owner memakai layar input pesanan yang sama', () {
      // Bukan salinan layar kasir. Kalau salinan, tiap perbaikan tata
      // letak harus diingat tiga kali dan yang ketiga selalu
      // ketinggalan.
      for (final f in [
        'lib/screens/admin_home_screen.dart',
        'lib/screens/owner_home_screen.dart',
        'lib/screens/kasir_home_screen.dart',
      ]) {
        expect(File(f).readAsStringSync(), contains('PosHomeScreen()'),
            reason: f);
      }
    });
  });

  group('sumbernya', () {
    final berkas =
        File('lib/widgets/promo_banner_carousel.dart').readAsStringSync();

    test('rasionya dibaca dari gambarnya, bukan dipatok', () {
      expect(berkas, contains('decodeImageFromList'));
      expect(berkas, contains('aspectRatio: _rasio ?? 16 / 9,'));
    });

    test('memakai bentuk paling jangkung di antara bannernya', () {
      // Kotak yang lebih pendek dari salah satu gambarnya menyisakan
      // pita untuk gambar itu.
      expect(berkas, contains('if (paling == null || r < paling) paling = r;'));
    });

    test('dijepit supaya banner salah ukuran tidak mengambil alih', () {
      expect(berkas, contains('.clamp(1.6, 3.2)'));
    });

    test('lebarnya dibatasi dan ditengahkan', () {
      expect(berkas, contains('maxWidth: 560'));
      expect(berkas, contains('Center('));
    });

    test('gambarnya tetap utuh, tidak dipotong', () {
      // Yang terpotong biasanya justru nominal diskon atau tanggal
      // berlakunya, yang ditaruh perancangnya di tepi gambar.
      expect(berkas, contains('fit: BoxFit.contain,'));
    });

    test('satu banner rusak tidak menghentikan pembacaan yang lain', () {
      expect(berkas, contains('} catch (_) {'));
    });
  });
}
