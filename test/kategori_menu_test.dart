import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Kategori menu harus mengingat keadaannya saat digulir.
///
/// ListView.builder membuang widget yang keluar layar lalu
/// membangunnya lagi saat kembali terlihat. Tanpa kunci, ExpansionTile
/// kehilangan ingatannya dan memakai `initiallyExpanded` lagi — lalu
/// memainkan animasi bukanya dari awal.
void main() {
  Widget daftar({required bool pakaiKunci}) => MaterialApp(
        home: Scaffold(
          body: ListView.builder(
            itemCount: 12,
            itemBuilder: (context, i) => ExpansionTile(
              key: pakaiKunci ? PageStorageKey<String>('kategori$i') : null,
              initiallyExpanded: true,
              title: Text('Kategori $i'),
              children: [SizedBox(height: 300, key: Key('isi$i'))],
            ),
          ),
        ),
      );

  Future<void> lipatLaluGulir(WidgetTester tester, Widget w) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(w);

    // Lipat kategori pertama.
    await tester.tap(find.text('Kategori 0'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('isi0')), findsNothing);

    // Gulir jauh sampai kategori itu dibuang, lalu kembali.
    await tester.drag(find.byType(ListView), const Offset(0, -2500));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, 2500));
    await tester.pumpAndSettle();
  }

  testWidgets('tanpa kunci: yang sudah dilipat membuka sendiri',
      (tester) async {
    await lipatLaluGulir(tester, daftar(pakaiKunci: false));
    // Inilah kedipannya: kategori kembali terbuka, animasinya diputar
    // ulang tiap kali menggulir.
    expect(find.byKey(const Key('isi0')), findsOneWidget);
  });

  testWidgets('dengan kunci: keadaannya diingat', (tester) async {
    await lipatLaluGulir(tester, daftar(pakaiKunci: true));
    expect(find.byKey(const Key('isi0')), findsNothing);
  });

  testWidgets('stream yang dibuat ulang tiap build memaksa layar memuat lagi',
      (tester) async {
    // Inilah kedipan yang kedua: StreamBuilder menilai stream dari
    // identitasnya. Stream baru berarti kembali ke keadaan menunggu,
    // dan daftarnya berganti jadi lingkaran memuat.
    var bangun = 0;
    late StateSetter paksaBangun;

    Stream<int> buatStream() => Stream<int>.value(1);

    await tester.pumpWidget(MaterialApp(
      home: StatefulBuilder(
        builder: (context, setState) {
          paksaBangun = setState;
          bangun++;
          return StreamBuilder<int>(
            stream: buatStream(),
            builder: (context, snap) => Text(
              snap.connectionState == ConnectionState.waiting
                  ? 'memuat'
                  : 'siap',
            ),
          );
        },
      ),
    ));

    await tester.pumpAndSettle();
    expect(find.text('siap'), findsOneWidget);

    paksaBangun(() {});
    await tester.pump();
    expect(find.text('memuat'), findsOneWidget,
        reason: 'stream baru mengembalikan layar ke keadaan memuat');
    expect(bangun, 2);
  });

  group('sumbernya', () {
    final berkas =
        File('lib/widgets/product_category_list.dart').readAsStringSync();

    test('tiap kategori punya kunci sendiri', () {
      // Kuncinya ValueKey, bukan PageStorageKey — yang terakhir itu
      // beradu ember penyimpanan dengan GridView di dalamnya.
      expect(berkas, contains('key: ValueKey<String>(category),'));
    });

    test('layar pelanggan tidak berlangganan ulang tiap build', () {
      final layar =
          File('lib/screens/customer_home_screen.dart').readAsStringSync();
      expect(layar, contains('void _siapkanStream(String restoId)'));
      // Yang lama: repo dibuat di dalam build, lalu stream barunya
      // dibuat tiap kali layar dibangun ulang.
      expect(layar,
          isNot(contains('stream: repo.watchAll(session.restoId!),')));
      expect(layar,
          isNot(contains('final repo = FirestoreProductRepository();')));
      // Dan sekarang tidak lewat StreamBuilder sama sekali: langganannya
      // dipegang layar ini supaya hidupnya seumur layar.
      expect(layar, isNot(contains('StreamBuilder<List<Product>>')));
    });

    test('langganannya dibuat ulang hanya kalau restonya berganti', () {
      final layar =
          File('lib/screens/customer_home_screen.dart').readAsStringSync();
      expect(layar,
          contains('if (_streamRestoId == restoId && _produkSub != null) return;'));
    });

    test('berlaku untuk semua yang menampilkan menu', () {
      // Kasir, Admin, dan Owner lewat PosHomeScreen; Pelanggan lewat
      // layarnya sendiri. Semuanya memakai widget yang sama ini.
      for (final f in [
        'lib/screens/pos_home_screen.dart',
        'lib/screens/customer_home_screen.dart',
      ]) {
        expect(File(f).readAsStringSync(), contains('ProductCategoryList('),
            reason: f);
      }
    });
  });
}
