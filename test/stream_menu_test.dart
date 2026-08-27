import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Layar menu pelanggan harus tetap memuat sesudah ditutup dan dibuka
/// lagi.
void main() {
  test('pendengar kedua tidak pernah menerima potret awalnya', () async {
    // Stream realtime mengirim potret pertamanya sekali, saat mulai
    // didengarkan. Dibungkus asBroadcastStream lalu disimpan, pendengar
    // yang datang belakangan melewatkan potret itu dan cuma menunggu
    // perubahan berikutnya — tidak ada data, tidak ada galat, dan
    // lingkarannya berputar selamanya.
    var kaliDidengar = 0;
    final sumber = Stream<List<int>>.multi((pengontrol) {
      kaliDidengar++;
      // Potret awal hanya untuk pendengar pertama, seperti langganan
      // realtime yang sudah terlanjur berjalan.
      if (kaliDidengar == 1) pengontrol.add([1, 2, 3]);
    });
    final siaran = sumber.asBroadcastStream();

    final pertama = siaran.listen((_) {});
    await Future<void>.delayed(Duration.zero);
    await pertama.cancel();

    List<int>? diterima;
    siaran.listen((v) => diterima = v);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(diterima, isNull,
        reason: 'inilah lingkaran memuat yang tidak pernah berhenti');
  });

  test('langganan yang dipegang sendiri tetap hidup lintas rebuild',
      () async {
    // Yang dipakai sekarang: satu langganan seumur layar, datanya
    // disimpan, dan dibatalkan di dispose.
    final sumber = StreamController<int>.broadcast();
    int? terakhir;
    final sub = sumber.stream.listen((v) => terakhir = v);

    sumber.add(1);
    await Future<void>.delayed(Duration.zero);
    expect(terakhir, 1);

    sumber.add(2);
    await Future<void>.delayed(Duration.zero);
    expect(terakhir, 2, reason: 'tetap menerima tanpa berlangganan ulang');

    await sub.cancel();
    await sumber.close();
  });

  group('sumbernya', () {
    final layar =
        File('lib/screens/customer_home_screen.dart').readAsStringSync();

    test('tidak lagi menyimpan stream siaran', () {
      // Yang tersisa cuma catatan kenapa cara itu ditinggalkan.
      expect(layar, isNot(contains('.asBroadcastStream();')));
      expect(layar, contains('Sempat dicoba dengan `asBroadcastStream()`'));
    });

    test('langganannya dipegang layar dan dibatalkan di dispose', () {
      expect(layar, contains('StreamSubscription<List<Product>>? _produkSub;'));
      expect(layar, contains('StreamSubscription<Restaurant?>? _restoSub;'));
      final blok = layar.substring(layar.indexOf('void dispose()'));
      expect(blok.substring(0, 300), contains('_produkSub?.cancel();'));
      expect(blok.substring(0, 300), contains('_restoSub?.cancel();'));
    });

    test('langganan lama dibatalkan saat restonya berganti', () {
      // Tanpa ini, berpindah resto meninggalkan langganan yang terus
      // menulis menu resto sebelumnya ke layar.
      final blok = layar.substring(layar.indexOf('void _siapkanStream('));
      expect(blok.indexOf('_produkSub?.cancel();'),
          lessThan(blok.indexOf('_produkSub = _productRepo')));
    });

    test('datanya disimpan, jadi kembali ke layar ini tidak memuat ulang', () {
      expect(layar, contains('List<Product>? _produk;'));
      expect(layar, contains('if (_produk == null)'));
    });

    test('galatnya punya jalurnya sendiri', () {
      expect(layar, contains('onError: (Object e)'));
      expect(layar, contains('if (_galatProduk != null)'));
    });
  });

  group('banner', () {
    final banner =
        File('lib/widgets/promo_banner_carousel.dart').readAsStringSync();

    test('ukurannya dibaca sebelum bannernya tampil', () {
      // Dua perubahan tata letak untuk satu banner, dan yang kedua
      // terjadi tepat saat orangnya mulai membaca.
      final blok = banner.substring(banner.indexOf('Future<void> _load()'));
      expect(blok.indexOf('await _hitungRasio(items)'),
          lessThan(blok.indexOf('_banners = items;')));
    });

    test('rasionya tidak lagi diisi belakangan lewat setState kedua', () {
      expect(banner, isNot(contains('unawaited(_bacaRasio(')));
      expect(banner, contains('return paling?.clamp(1.6, 3.2);'));
    });
  });
}
