import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:merchant_pos/utils/gallery_saver.dart';

/// Peramban tidak punya galeri foto, dan tidak ada izin yang bisa
/// diminta untuk menulis ke sana.
void main() {
  final penyimpan = File('lib/utils/gallery_saver.dart').readAsStringSync();

  group('menyimpan gambar di web', () {
    // Sebelumnya jalur ini tetap menanyakan izin galeri lewat Gal, yang
    // di web menjawab dengan galat — jadi tombolnya berhenti sebagai
    // "gagal memeriksa izin galeri" pada perangkat yang memang tidak
    // punya galeri sama sekali.
    test('tidak menanyakan izin galeri', () {
      final blok = penyimpan.substring(
          penyimpan.indexOf('Future<bool> ensureGalleryAccess'));
      final sampaiTry = blok.substring(0, blok.indexOf('try {'));
      expect(sampaiTry, contains('if (kIsWeb) return true;'));
    });

    test('menyerahkannya ke peramban sebagai unduhan', () {
      expect(penyimpan, contains('unduhPngWeb(bytes, namaBerkas)'));
      final pintu = File('lib/utils/unduh_web.dart').readAsStringSync();
      expect(pintu, contains("if (dart.library.html) 'unduh_web_html.dart'"));
      // Sisi bukan-web harus ada, kalau tidak Android gagal dibangun.
      expect(File('lib/utils/unduh_web_kosong.dart').existsSync(), isTrue);
    });

    // Bytes-nya menetap di memori tab sampai halamannya ditutup kalau
    // tidak dilepas — dan pada layar yang menyimpan puluhan QR meja
    // sekaligus, itu puluhan salinan yang tidak pernah dipakai lagi.
    // Melepasnya tepat sesudah click() membatalkan unduhannya sendiri
    // di sebagian peramban: tautannya sudah diklik, tapi berkasnya
    // belum sempat dibaca.
    test('object URL-nya dilepas belakangan, bukan seketika', () {
      final html = File('lib/utils/unduh_web_html.dart').readAsStringSync();
      expect(html, contains('revokeObjectUrl'));
      expect(html, isNot(contains('finally {')));
      expect(html, contains('Future<void>.delayed('));
    });
  });

  group('nama berkas unduhan', () {
    // Nomor meja bebas bentuk, dan garis miring di dalamnya membuat
    // peramban memperlakukannya sebagai folder.
    test('membuang tanda yang merusak jalur berkas', () {
      expect(namaBerkasAman('A/01'), 'A-01');
      expect(namaBerkasAman('Meja 3 (pojok)'), 'Meja 3 -pojok');
      expect(namaBerkasAman('VIP-2'), 'VIP-2');
    });

    // "///" sempat lolos sebagai "---": bukan kosong, jadi penjaganya
    // tidak berbunyi, dan berkasnya terunduh bernama tiga setrip.
    test('tidak pernah kosong, dan tidak pernah cuma setrip', () {
      expect(namaBerkasAman('///'), 'Merchant-POS');
      expect(namaBerkasAman(''), 'Merchant-POS');
      expect(namaBerkasAman('   '), 'Merchant-POS');
    });
  });

  test('tiap pemanggil memberi nama berkasnya sendiri', () {
    for (final f in ['table_qr_image', 'qris_image', 'receipt_image']) {
      final isi = File('lib/utils/$f.dart').readAsStringSync();
      expect(isi, contains('namaBerkas:'), reason: f);
    }
  });

  // Di web, memanggil Printing.raster lagi sebelum yang sebelumnya
  // tuntas membuat keduanya saling menunggu: yang pertama selesai,
  // yang kedua tidak pernah kembali, dan layarnya berhenti di
  // "Menyimpan 1/10..." selamanya.
  test('QR meja massal dirender sekali, bukan sekali per kartu', () {
    final qr = File('lib/utils/table_qr_image.dart').readAsStringSync();
    final blok = qr.substring(qr.indexOf('Future<int> saveTableQrBatchToGallery'));
    // Penutup fungsinya '\n}\n' — bukan '\n}', yang lebih dulu cocok
    // dengan '})' penutup daftar parameternya.
    final badan = blok.substring(0, blok.indexOf('\n}\n'));
    expect('Printing.raster('.allMatches(badan).length, 1);
    expect(badan, contains('await for (final page in'));
    // Halaman yang tidak pernah keluar dari alirannya tetap dihitung
    // gagal, kalau tidak angkanya berhenti di tengah tanpa penjelasan.
    expect(badan, contains('for (; i < cards.length; i++)'));
  });

  // Paket printing memuat pdf.js sendiri dari unpkg, lalu mengambil
  // `pdfjsLib` dari window. Kalau CDN-nya tidak terjangkau — atau
  // skripnya termuat tanpa memasang globalnya — dereference itu jatuh
  // ke null, dan yang terlihat orang cuma "Null check operator used on
  // a null value" saat menyimpan QR meja.
  group('pdf.js dilayani sendiri', () {
    final index = File('web/index.html').readAsStringSync();

    test('dimuat sebelum Flutter, bukan dari CDN', () {
      expect(index, contains('<script src="pdf.min.js"></script>'));
      expect(index, isNot(contains('unpkg.com')));
      expect(index.indexOf('pdf.min.js'),
          lessThan(index.indexOf('flutter_bootstrap.js')));
    });

    // Plugin melewati pemuatannya sendiri hanya kalau KEDUANYA ada:
    // globalnya terpasang, dan workerSrc sudah diisi.
    test('workerSrc ikut diisi', () {
      expect(index, contains("workerSrc = 'pdf.worker.min.js'"));
    });

    test('berkasnya benar-benar ikut terkirim', () {
      for (final f in ['web/pdf.min.js', 'web/pdf.worker.min.js']) {
        final b = File(f);
        expect(b.existsSync(), isTrue, reason: f);
        expect(b.lengthSync(), greaterThan(100000), reason: f);
      }
    });
  });
}
